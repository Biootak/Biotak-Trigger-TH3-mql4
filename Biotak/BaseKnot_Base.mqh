// BaseKnot_Base.mqh - BaseKnotTool split 2026-09-29: exact lines 223-1333 of BaseKnotTool.mqh, byte-identical, zero renames.
#ifndef BASE_KNOT_BASE_MQH
#define BASE_KNOT_BASE_MQH

#property strict

//--- session states
// P-UI-34: nominal (design) point sizes for this module's own chrome, routed through
// PnlPt so a scaled display draws the design's px instead of +25% (the same exposure
// P-UI-30 fixed inside the settings cards). g_bkTextSize stays a user setting.
#define BK_PT_HINT   9    // the bottom-corner hint line
// P-BK-27 (2026-09-15): the INFO readout's frozen nominal is RETIRED IN PLACE —
// the size is a user setting now (`inpBKInfoFontSize`; 0 = follow the Base Box
// text size). Restoring the old look = BKInfoFontPt() returning PnlPt(BK_PT_INFO).
#define BK_PT_INFO   8    // the box' [H Pips | R:R] readout (P-BK-27: retired size)
#define BK_PT_BADGE  8    // the retired badge (one-line restorable)
#define BK_IDLE    0
#define BK_ARMED   1   // menu hidden, waiting for the first corner click
#define BK_PREVIEW 2   // first corner set, rubber-band follows the cursor

//--- geometry / UX tuning
// BKTPR-OFF (P-BK-50): THE R-MULTIPLE TARGET IS RETIRED IN PLACE. The target a
// Base-Knot box draws is the TRADE PLAN's own TP1..TP3 now (BaseKnotTPLevel — the
// very numbers the label's `#SL:-n #TP1+n #TP2+n #TP3+n` row prints for the knot's
// TF). Restore the old one by uncommenting the two `BKTPR-OFF` lines in
// BaseKnotCalcLevels (the `TARGET R` state itself never moved: the SAME number now
// says HOW MANY plan legs are drawn, BaseKnotTPCount).
#define BK_TP_R_MULT      2.0    // retired (BKTPR-OFF): the old N in TP = Entry +/- N x R —
                                 //          R = EngSL of the knot's own TF (P-BK-46)
// BK_TP_PLAN_MAX (the plan's own targets — TP1..TP3) is declared in ConstantsAndEnums:
// the setting's 1..3 clamp is owned one layer BELOW this module and must read it too.
//--- P-BK-50 (user: «خط ها یکم ورود و استاپ لاس بزرگتر و ضخیم تر بشه»): the ENTRY
//--- and STOP rays draw at this width. At 1px a ray over a busy candle body read
//--- as part of the price action instead of as a level (the same lesson the TP
//--- tick below already learned).
#define BK_LEVEL_WIDTH    2
#define BK_ARM_GUARD      500    // ms — ignore the arming click's own release (CLICK fallback path)
#define BK_BADGE_W        46   // NOBKDEL: retired with the X badge (kept for one-line restore)
#define BK_BADGE_H        18   // NOBKDEL: retired with the X badge (kept for one-line restore)
#define BK_DIR_LOOKBACK   128   // bars scanned for the entry-side resolve
#define BK_INFO_GRACE_MS  4000  // Auto INFO: label stays this long after commit, then hides (chart stays clean)
//--- P-BK-58 (2026-09-16) — THE NOTE'S THIRD HOME. The Base Box card's INFO row grew a third
//--- rung (0 = Auto on the box, 1 = Always on the box, 2 = the label family's corner column —
//--- «تا کاربر بتواند بین «چسبیده به باکس» و «گوشهٔ ثابت» یکی را انتخاب کند»). The rung is the
//--- user's own setting (`inpBKShowInfo` / `g_bkShowInfo`), so it is NOT owned here: this module
//--- only reads it. `BK_NOTE_CORNER` is the corner row's own tag — it hangs off the chart's
//--- prefix, never off a box' (a box' `ObjectsDeleteAll(pfx)` must not wipe the shared row).
#define BK_NOTE_CHART     2    // the rung that means "the family's corner, not the box"
#define BK_NOTE_CORNER "NOTE_CORNER"
//--- P-BK-86 (2026-09-18) — THE BOX-SIDE NOTE WEARS ITS OWN PLATE.
//--- The user, on his own screenshot: «این اطلاعات میره داخل کندل ها خونده نمیشه اینو باید
//--- چیکارش کنیم که هیچ تداخل نداشته باشه و همیشه بتونه خونده بشه». Two things were wrong
//--- with the old box-side note, and they have ONE cause: it was a CHART-SPACE `OBJ_TEXT`.
//---   1. MT4 paints the chart's own art in that same layer, so the candles the note sits
//---      among — and the level lines that cross it — came out ON TOP of its glyphs (his
//---      screenshot: a red level line straight through "16 bars");
//---   2. no `OBJ_TEXT` can carry a background, so there was nothing to read the ink against.
//--- The fix is one move that answers both: the box-side note becomes a SCREEN pair — the
//--- text as an `OBJ_LABEL` (the panel layer MT4 draws ABOVE every chart-space object, so
//--- no candle, zone edge or level line can ever reach it again) plus a PLATE behind it
//--- (`OBJ_RECTANGLE_LABEL`) filled with the CHART'S OWN background colour. Over an empty
//--- chart the plate is invisible; where the candles are it is an honest cut-out — exactly
//--- how MetaTrader's own price label reads. The corner row (rung 2) is UNCHANGED: it is the
//--- label family's column, over the panel's own margin, and P-BK-56's look stays as it was.
//--- The plate's size is MEASURED, never guessed: `PnlRawTextW` / `PnlRawLineH` are the chart
//--- label family's own owners of that arithmetic (the note hands MT4 `inpFontName` at
//--- `BKInfoFontPt()` RAW, P-BK-56 / P-UI-42), so the plate is the ink plus this padding.
//--- And the plate's ink and the note's own foreground are the SAME measurement: both read
//--- `CHART_COLOR_BACKGROUND` (the plate's fill directly, the ink through `BaseKnotFgForBg`),
//--- so the pair can never disagree about which way round they are — a dark plate under dark
//--- ink is the one failure mode a background has to be unable to produce.
#define BK_NOTE_PLATE  "_BG"   // the plate's name IS the note's name + this (ONE owner below)
#define BK_NOTE_PAD_X    4     // px of plate on each side of the ink
#define BK_NOTE_PAD_Y    2     // px of plate above and below the ink
#define BK_NOTE_LIFT     2     // px between the plate's bottom edge and the box' top edge
//--- P-BK-87 (2026-09-18) — THE PAIR IS KEPT INSIDE THE WINDOW.
//--- Going screen-space (P-BK-86) traded one collision for another: a chart-space object
//--- is clipped by the chart, but a SCREEN object is not — it is simply projected to
//--- whatever pixel the box' corner lands on, and off-window pixels do not paint. So a box
//--- scrolled to the top edge, or to the right one, took the note with it: the user's own
//--- words for the whole line of work are «همیشه بتونه خونده بشه» — ALWAYS readable — and a
//--- note that vanishes at the window edge is not. The chart's four edges are therefore the
//--- one boundary the plate is pulled back inside, by the SAME rule the label family's own
//--- countdown tag already uses (`LabelFunctions.mqh`: `cw - MathMax(8, inpLabelsMarginLeft)`
//--- on the right — beyond that sits the price scale — and a bottom reserve for the
//--- date-scale bar). The bottom reserve is spelled HERE rather than reused from the panel
//--- half's `PNL_BOTTOM_SAFE`: `BiotakPanels.mqh` is the UI half, which the Lite entry does
//--- not compile, so a domain-half module that read it would break Lite (P-BUILD-01).
#define BK_NOTE_EDGE_MARGIN  4     // px the plate keeps from the window's top and left edges
#define BK_NOTE_BOTTOM_SAFE 20     // px the plate keeps from the bottom edge (the date-scale bar)
//--- BKNODERUNG-OFF (P-BK-75, 2026-09-17): P-BK-47 below IS RETIRED. It named the type
//--- by a RUNG DISTANCE, which was a DURATION in disguise; the user replaced it with the
//--- box' own HEIGHT against the movement abilities (that TF's own TH) — see the
//--- P-BK-75 block above the ability table
//--- further down, which owns the type now. Kept here because the user's words and the
//--- old reasoning are the restore path's own context (restore = uncomment the pair below
//--- and re-teach the audit, never rewrite).
//---
//--- P-BK-47 (2026-09-15, RETIRED): THE NOTE'S NODE TYPE IS THE NODE'S LENGTH. The user's
//--- own rule, word for word: «دسته بندی گره های معاملاتی براساس طول گره: FTR گرهی که طولش
//--- مساوی تایم تریگر تایمی باشد که گره در آن دیده میشود سه کندل · ETR گرهی که طولش
//--- مساوی تایم پترن باشد · CTR گرهی که طولش مساوی تایم ساختار باشد · OTR گرهی که
//--- طولش بیشتر از تایم ساختار باشد». The length was read on the PROJECT'S ladder
//--- (M1 · M5 · M15 · H1 · H4 · D1 · W1 · MN1 — the same eight the base's size class
//--- walks, P-BK-43) as a count of rungs the class sat above the node's TF:
//---   * 0 rungs up  -> FTR;  1 rung up -> ETR;  2 rungs up -> CTR;  3+ -> OTR.
//--- A node whose class was unmeasurable claimed nothing (BK_NODE_NONE).
//--- The pairs the course lists beside the names (ABO/EBO/CBO/OBO) describe the
//--- BREAK's story («بیس … برگشت»), which still decides the SIDE the trade comes in on
//--- (BaseKnotNodeDir, P-BK-46) and is still shown beside the type — it never names
//--- the type. Numbers never renumber: NONE/FTR/ETR/CTR/OTR stay 0..4.
//--- BKNODERUNG-OFF (P-BK-75, 2026-09-17): the three defines below are the RETIRED rung
//--- read's own vocabulary (how many ladder rungs the class sat above the node's TF).
//--- Nothing compares against them any more — the type is the box' HEIGHT against the
//--- movement abilities (ATR) — but they stay, because the retired pair below is written in them
//--- and the restore path is "uncomment, re-teach", never "rewrite".
#define BK_NODE_RUNG_FTR  0   // (retired) the TRIGGER length — the node's own TF
#define BK_NODE_RUNG_ETR  1   // (retired) the PATTERN time — one rung above the node's TF
#define BK_NODE_RUNG_CTR  2   // (retired) the STRUCTURE time — two rungs above the node's TF
                              // ... 3 or more rungs up was OTR (past the structure time)
#define BK_NODE_NONE   0   // nothing claimed (no height / that TF's TH not warm yet)
#define BK_NODE_FTR    1   // as long as the TRIGGER ability (TH)
#define BK_NODE_ETR    2   // as long as the PATTERN ability (TH)
#define BK_NODE_CTR    3   // as long as the STRUCTURE ability (TH)
#define BK_NODE_OTR    4   // LONGER than the structure ability (TH)
//--- P-BK-38: the BREAK's story — the side, never the type any more — is read on the
//--- BASE'S OWN TF's candles (below), so this window is a count of THAT TF's bars,
//--- never of the chart's: 1500 D1 bars are the same years on every chart.
//---
//--- P-BK-48 (2026-09-15) — AND IT READS THE WHOLE PAST MARKET OF THAT NODE: «من با این
//--- گره ها و طول حرکت کار دارم … حتما گره های گذشته مارکت هم بررسی می شود برای تحلیل
//--- لایو سطوح و واکنش ها، چون هنوز ممکن است سفارش داخل گره معاملاتی گذشته مارکت باشد».
//--- 128 bars was ~32 hours on M15, so a base the market later traded THROUGH read as if
//--- nothing had happened to it (the user's own BUY box that the market had already
//--- consumed). The window is now the node's own LIFE measured to the newest CLOSED bar,
//--- capped by BK_BIAS_MAX bars of the class' TF — the tradeoff is read cost, and the
//--- read is closed-bar data, memoised per box per newest closed bar (P-BK-36 pattern).
#define BK_BIAS_MAX 3000       // bars of the STORY's TF from the base's right side to now
                               // (M15 ~ 31 days, H1 ~ 4 months, M5 ~ 10 days) — the READ'S
                               // HORIZON is printed in the hover, so a node older than it is
                               // never silently called fresh. Past-market testing is the case
                               // this number exists for: «این ابزار شاید در گذشته مارکت هم
                               // تست کنمش».
//--- P-BK-48: the node's LIFE STATE — what the MARKET did with it since it formed. The
//--- course reads a zone by its DEPARTURE (which side it was left on) and by how much of
//--- that interest is still unspent: every revisit eats it, and a close cleanly THROUGH
//--- the far edge spends it (the methodology's own words: «each revisit consumes the
//--- resting interest» / a zone is «consumed once price trades cleanly through it»).
#define BK_STATE_UNKNOWN  0   // nothing measured (no departure yet / series not ready)
#define BK_STATE_FRESH    1   // left and never revisited — the strongest reading
#define BK_STATE_TESTED   2   // the market came back at least once (partly spent)
#define BK_STATE_CONSUMED 3   // closed cleanly THROUGH the far edge — the orders are spent
//--- P-BK-48: WHICH RUNG OF THE BIAS LADDER answered (published for the tooltip's "why"
//--- and compared by the pump, so the note can never show a side the evidence dropped).
#define BK_SIDE_NONE     0   // no evidence: the LIVE price decides (P-BK-13's own rule)
#define BK_SIDE_ZONE     1   // the node's own life answered (departure + state)
#define BK_SIDE_CTX      2   // (reserved) the class rung's own drift was the tie-breaker
#define BK_BIAS_CTX_BARS 24   // the class rung's bars the context drift is measured over
//--- P-BK-81 (2026-09-17) — THE DIRECTION IS ONE BIT, AND IT IS THE BASE'S OWN EXIT
//--- CANDLE'S. The user: «چرا جهت درست تشخیص نمیده rbr , dbd rbd … بهترین راه چیه که کلا
//--- از شر این rbr , dbd rbd خلاص بشیم و جهت سل و بای به صورت صدردصدی درست تشخیص داده
//--- بشه». The four names were never a direction: the standard definitions make RBR and
//--- DBR BOTH Buy and RBD and DBD BOTH Sell — «the move OUT of the base decides the
//--- direction, because the move into it only shows past direction while the exit shows
//--- current intent» (alphaexcapital.com/forex/price-action/rally-base-rally). So the
//--- approach leg could only ever split continuation from reversal, it could never name a
//--- side, and the four names carried NO directional information the exit leg did not
//--- already carry. They are GONE:
//---   * the DIRECTION is `nd.side` — the close of the base's OWN EXIT CANDLE (`sp.tExit`,
//---     the very candle the note's number is counted to) against the band: above the
//---     ceiling -> +1 Buy, below the floor -> -1 Sell, inside -> 0 (no direction claimed,
//---     and the live price decides, exactly as before P-BK-46).
//---   * NOTHING ELSE may name it. Not the box' right edge (dragging it used to move the
//---     story walk's start and flip the side — «کمی که جابجا میکن نوع گره عوض میشه»),
//---     not a later return, not a second break, not a close through the far edge. Those
//---     are FACTS about the node's life (`state`, `depBars`, `revisits`) and they are
//---     reported; none of them is a direction.
//---   * ONE CANDLE, ONE ANSWER, ON EVERY CHART: the exit candle is the base's own (P-BK-44
//---     reads it off the RUN, never off the drawn rectangle), so the same box answers the
//---     same side on every timeframe and on the past market alike.
//--- BKPAT-OFF (P-BK-81): the four names lived here — `BK_PAT_NONE/RBR/RBD/DBR/DBD`,
//--- `BK_APPROACH_MAX`, the struct's `approach`/`pattern`, the approach walk, the two
//--- assignment sites, `BaseKnotPatternName/Tag/Line` and the note/hover clauses that
//--- printed them. Restoring them means putting all of that back AND re-teaching the
//--- audit's `check_node` gates named "the four names are GONE" — never by rewriting the
//--- exit-candle read, which owns the direction now.

//--- object-name tag: "<prefix>_BK_<id>_<KIND>"
#define BK_TAG "_BK_"

//--- committed-box registry (parent ↔ children share one id prefix)
struct BaseKnotBox
{
   string id;      // "<commitTFmin>_<tick>[rNNN]" (legacy: bare tick)
   int    dir;     // +1 Buy / -1 Sell — decided at commit, then follows the live price (P-BK-13)
   int    tfMin;   // chart Period() minutes at commit (0 = legacy = all TFs)
   uint   commitMs; // GetTickCount at commit — drives the Auto INFO grace (0 = long ago)
   bool   locked;  // mini LOCK row — locked boxes are unselectable (no drag)
   int    nodeKind; // P-BK-29/47: the type LAST published to the note (0 = none yet) — the pump's shadow
   int    baseTFMin; // P-BK-36/38: the class LAST published (0 = legacy/unset) — the TF the
                     //              note names, the TF the node's LENGTH is classed by AND the
                     //              TF the break's story is read on
   int    nodeSide;  // P-BK-47/46: the SIDE the break's story names (0 = none) — published so
                     //              the live-price follow leaves a named trade alone. (The node's
                     //              TIME is not kept here: P-BK-77 finds it from the box' own
                     //              geometry on every read, so there is no second copy to drift.)
   int    biasState; // P-BK-48: the node's LIFE STATE LAST published (FRESH/TESTED/
                     //              CONSUMED) — the pump compares it and the trade lines obey
                     //              it: a CONSUMED node draws no Entry/SL/TP at all
   datetime exitT;   // P-BK-81: the base's OWN EXIT candle (the candle that CLOSED OUTSIDE
                     //              the band) — the ONE candle the direction is read from,
                     //              published so the pump reads the same direction the note
                     //              does. (P-BK-49's `baseT`, the base's own ENTRY, is gone
                     //              with the approach leg it anchored — BKPAT-OFF.)
   datetime storyT;  // P-BK-41: the base's OWN right side (its last stand-still candle) —
                     //              the shift the story is read FROM, published so the pump
                     //              reads the same story the note does
};
//--- P-BK-41: ONE SPAN — the base's own story, shared by the number, the class, the
//--- node's read and the note, so no two of them can describe different objects.
//--- `life`  = the candles the base lasted (its first candle .. the candle that
//---             CLOSED OUTSIDE the band — «از جای که وارد بیس شده تا جایی که ازش
//---             خارج شده و شکسه و کلوز کرده»);
//--- `still` = how many of them STOOD STILL (P-BK-28/40: the size class's input);
//--- `tStart`/`tLast` = the base's own two ends, `tExit` = the knot's formation.
struct BaseKnotSpan
{
   int      life;     // the note's number — the candles the base lasted (start..exit)
   int      still;    // ... of them, the ones that STOOD STILL (body inside the band)
   datetime tStart;   // the base's first candle — where price entered the base
   datetime tLast;    // its last stand-still candle (the base's own right side)
   datetime tExit;    // the candle that closed OUTSIDE the band — the knot's formation
};
void BaseKnotSpanClear(BaseKnotSpan &sp)
{
   sp.life = 0; sp.still = 0; sp.tStart = 0; sp.tLast = 0; sp.tExit = 0;
}
//+------------------------------------------------------------------+
//| P-BK-84 (2026-09-18) — THE CLASS' SPAN IS THE BASE'S OWN, AND THE  |
//| BOX IS ONLY A FLOOR.                                              |
//|                                                                  |
//| The user: «این قانون شمارش کندل ها باید اضافه بشه … از روی همون که |
//| الان هستش میشه برای ۵ دقیقه دیگه» — a 17-bar M1 base IS 17 minutes |
//| of base, so three M5 candles (15 minutes) fit inside it and the    |
//| node's time is M5.                                                 |
//|                                                                  |
//| P-BK-80 had moved the class' span onto the BOX' two anchors to kill |
//| the `+ chartMin` term — and that half was RIGHT and stays. But it   |
//| also moved the span OFF THE BASE, and the user draws with the       |
//| MEASURING tool: the rectangle is routinely NARROWER than the base   |
//| it points at (P-BK-44: the run is walked on BOTH sides of the box'  |
//| right edge). An 11-minute box around a 17-minute base then refused  |
//| M5 on `3 * 5 > 11` and the whole box fell back to M1.               |
//|                                                                  |
//| The span is the UNION: the box' own two anchors (chart-free, stored |
//| on the object — P-BK-80's floor, so a box dragged WIDE can never    |
//| shrink the reading) and the base's own entry..exit (P-BK-41's own   |
//| ends, so a box drawn NARROW can never shrink it either).            |
//| `b1`/`b2` stand in only while no base was measured at all.          |
//+------------------------------------------------------------------+
void BaseKnotClassSpan(BaseKnotSpan &sp, const datetime b1, const datetime b2,
                       datetime &c1, datetime &c2)
{
   c1 = b1; c2 = b2;
   if(sp.tStart > 0 && (c1 == 0 || sp.tStart < c1)) c1 = sp.tStart;
   if(sp.tExit  > 0 && sp.tExit > c2)               c2 = sp.tExit;
}
//--- P-BK-47/77/78/81: what the note's node read measures — ONE record per read, and it
//--- answers TWO different questions (never the same one twice):
//---   * the TYPE (`kind`) is the node's LENGTH — the box' own HEIGHT against the TH of the
//---     NODE'S OWN TIME (`nodeTF` = the class P-BK-77 found on the whole ladder, one rung
//---     above it for the pattern time, two for the structure time, P-BK-78) — and NOTHING
//---     price did, and no chart TF, can move it;
//---   * the SIDE (`side`) is ONE BIT off the base's OWN EXIT CANDLE (P-BK-81), read on the
//---     story TF's own candles exactly as P-BK-29/38 read the story — it names the edge the
//---     trade comes in on (P-BK-46). The story's other facts (`returned`/`rebreaks`/
//---     `crossed`) are the node's LIFE and they are reported; none of them is a direction.
//---     The step numbers beside it SIZE that read and can never move it.
struct BaseKnotNode
{
   int    kind;       // BK_NODE_* — BK_NODE_NONE = nothing claimable
   int    rungs;      // P-BK-47: retired with the rung-count read (BKNODERUNG-OFF) — always -1
   int    nodeTF;     // P-BK-77: the NODE'S OWN TIME — the rung whose three candles stood still
   int    baseTF;     // P-BK-78: the same TF (one read, two names — kept so no caller breaks)
   int    side;       // P-BK-81: THE DIRECTION — the base's own EXIT CANDLE's close vs the
                      //          band: +1 it closed ABOVE the ceiling (Buy), -1 BELOW the
                      //          floor (Sell), 0 inside / no exit read (nothing claimed)
   int    barsAgo;    // bars since that exit candle (the break's own bar)
   int    rebreaks;   // closes back beyond the same edge AFTER a return (the second break)
   double baseStep;   // the base's own height, in movement steps
   double breakStep;  // how far the break' close went past the edge, in steps
   double retStep;    // the deepest close back inside the base, in steps (0 = never returned)
   bool   returned;   // a close came back INSIDE the base after that first break
   bool   crossed;    // P-BK-35: the return's closes ran past the FAR edge — the far-side
                      //          story's own test is a LEVEL of the box, never a step count
   int    storyTF;    // P-BK-38: the TF whose candles the story was read on (the base's own)
   //--- P-BK-48: THE PAST MARKET OF THIS NODE — what happened to it AFTER it formed.
   //--- The floor under the side: a base the market has already traded cleanly through
   //--- claims nothing, however strong its departure was.
   int    state;      // BK_STATE_* — FRESH / TESTED / CONSUMED
   int    depBars;    // the DEPARTURE's length in candles («طول حرکت»): the leg that left
                      // the base, counted until price came back inside (or until now)
   double depStep;    // ... and that leg's reach past the edge, in movement steps (TH)
   //--- P-BK-75/78: the box' HEIGHT (the length the user's rule compares) and the THREE
   //--- MOVEMENT ABILITIES of the node's own TIME it was compared against - the THs of
   //--- that rung, of the rung one step above it (the pattern time) and of the rung two
   //--- above (the structure time), in price units; 0 = the pump never pushed that row, or
   //--- pushed it while the TH was not warm. Published on the record so the tooltip can
   //--- spell the comparison without a second read.
   double   height;   // top - bot — «طول گره» is «ارتفاع باکس»
   double   abTrig;   // the node's own time's TH - the trigger ability
   double   abPat;    // the pattern time's TH - one rung above
   double   abStr;    // the structure time's TH - two rungs above
   //--- P-BK-79: THE BAR ALL OF THE ABOVE WAS READ AT — the box' own story end (`storyT`),
   //--- or 0 for the live sizing preview, which has no base yet and asks for the live row.
   //--- Published for the same reason the abilities are: the tooltip prints the bands off
   //--- the SAME anchor the type was decided by, never another bar's.
   datetime anchor;
   int    revisits;   // how many times the market came back INSIDE after leaving
   int    lastSide;   // the side of the NEWEST close outside the band (0 = inside now)
   int    lifeBars;   // bars from the base's right side to the newest closed candle (age)
   int    ctxAlign;   // +1/-1 = the class rung's own drift AGREES with the trade's side /
                      //         runs AGAINST it, 0 = unknown (the L4 label, never a decider)
   int    sideLevel;  // BK_SIDE_* — which rung of the bias ladder answered
};
static BaseKnotBox g_bkBoxes[];
static int         g_bkState      = BK_IDLE;
static datetime    g_bkT1         = 0;
static double      g_bkP1         = 0.0;
static uint        g_bkArmedMs    = 0;
static bool        g_bkLeftPrev   = false;
static bool        g_bkHeld       = false;   // left button held down inside our gesture (press without release yet)
static datetime    g_bkLiveT      = 0;       // last rubber-band cursor point (off-chart release fallback)
static double      g_bkLiveP      = 0.0;
static bool        g_bkInitDone   = false;
//--- P-BK-29: THE MOVEMENT STEP the note's node read is measured with. The
//--- course measures every one of the four types in movement STEPS;
//--- P-BK-92: the step is the rung's own TH points now (was ATR). TH lives in
//--- THCalculations below this module - the layer law, so this module never
//--- reads it: the pump layers PUSH (BiotakKit / EventHandlers). 0 = unknown, and
//--- everything that needs it then stays QUIET instead of guessing: a wrong
//--- size is a wrong knot type (the course's own entry rule — «فاصله ی یک ATR
//--- یا APR» — has no distance without it). `s_bkNodeBar` is the bar the last
//--- node read ran for: the read is CLOSED-BAR data, so a new bar (or a fresh
//--- step) is the only thing that can move a type, and the pump compares that
//--- once per round, not once per box.
static double      s_bkStepTH    = 0.0;
static datetime    s_bkNodeBar    = 0;
//--- P-BK-46 (2026-09-15) — THE KNOT'S TRADE IS MEASURED IN EngSL OF ITS OWN TF, and
//--- EngSL is TRADE-PLAN MATH (TradePlanFormulas), which sits ABOVE this module: the
//--- same layer law the movement step above obeys, so it is PUSHED IN the same way.
//--- The pump layers ASK which TFs the live boxes call their own (BaseKnotEngNeeds),
//--- compute ONE value per TF (TradePlanEngOf — the very number the TRex card's Eng.SL
//--- row shows, rounded to whole pips exactly as that row is) and push the pairs back
//--- (BaseKnotEngPush). A TF the table does not carry answers 0, which is an ABSENCE
//--- and never a guess: the knot then keeps the box' own height for its risk and its
//--- own text SAYS which of the two it is showing. `s_bkEngEpoch` moves only when a
//--- stored pair really changed — the pump's "the levels must be rebuilt" signal,
//--- exactly like the step's own gate above.
//--- P-BK-79 (2026-09-17) — A ROW IS (TF, ANCHOR), NOT A TF. The user: «مثلا atr یک دقیقه
//--- زمان گره بوده مثلا 20 … با گذشت زمان ممکن 40 بشه یا 10 بشه که اینطوری نمیشه نوع گره
//--- دقیق مشخص کرد». Two boxes on the SAME TF whose bases ended on DIFFERENT bars need
//--- DIFFERENT EngSL/HuntSL/TP — and different ladder THs for their types — so a TF-keyed
//--- table can only ever answer one of them. The anchor is the box' own `storyT` (the bar
//--- its story ended on), and 0 means "no anchor": the LIVE row, which is what the sizing
//--- preview asks for before it has a base.
//--- The bound is ROWS now, not TFs: the old 10 was sized for eight timeframes, and one
//--- box alone asks up to four of them, each on its own anchor.
#define BK_ENG_ROW_MAX 48
static int      s_bkEngTF[BK_ENG_ROW_MAX];
static datetime s_bkEngAnchor[BK_ENG_ROW_MAX];   // P-BK-79: the bar this row was read at
static double   s_bkEngPips[BK_ENG_ROW_MAX];
//--- P-BK-51 (2026-09-15) — THE HUNTER LEG RIDES THE SAME TABLE. The user's own rule
//--- («و برای گره etr میشه به اندازه huntsl محل ورود») sizes an ETR/CTR/OTR entry by ONE
//--- HuntSL of penetration, so the SAME ask / push pair carries it: HuntSL is the number
//--- the TRex card's `Hunter SL:` row prints (TradePlanFormulas — round(8/3 x Eng), or
//--- TR/1.66666 under the alt triple), pushed per TF exactly like EngSL, so the box and
//--- that row can never disagree about it. 0 = NOT pushed for that TF (an absence).
static double s_bkEngHunt[BK_ENG_ROW_MAX];
//--- P-BK-50 — THE PLAN'S OWN TARGET LEGS ride the SAME table, so ONE pump round
//--- answers everything a box draws: the risk (EngSL of its TF) AND the plan's
//--- TP1..TP3 in pips — the numbers the label's `#SL:-n #TP1+n #TP2+n #TP3+n` row
//--- prints for that TF. The plan engine computes them (TradePlanFormulas, above
//--- this module); this module only reads them back, so the box and the row beside
//--- it can never disagree about a target.
static double s_bkEngTP1[BK_ENG_ROW_MAX];
static double s_bkEngTP2[BK_ENG_ROW_MAX];
static double s_bkEngTP3[BK_ENG_ROW_MAX];
static int    s_bkEngN     = 0;
static uint   s_bkEngEpoch = 0;
static uint   s_bkEngSeen  = 0;
//--- IDLE box-drag follow (unified lean follow, P-BK-07): the press latches
//--- the drag candidate + its anchor cache; per-step moves go through
//--- BaseKnotFollowDrag ONLY, and that function now has ONE owner path: the
//--- terminal's own native drag (anchor-exact, unbudgeted, pixel-locked with the
//--- fill). The cursor-delta fallback that used to write the BOX itself while the
//--- anchors sat frozen is RETIRED dead-by-construction (BKCURSOR-OFF — the user's
//--- «اونی که لایو نیست» call: a 30 ms-budgeted second writer is exactly what reads
//--- as stepped, and the live path covers every build that drags a box at all);
//--- release re-syncs authoritatively and the 500 ms pump settles a lost gesture
//--- end (P-BK-18).
static string      s_bkDragId = "";
static datetime    s_bkDragT0 = 0;
static double      s_bkDragP0 = 0.0;
static int         s_bkDragX0 = 0;
static int         s_bkDragY0 = 0;
static datetime    s_bkDragBT1 = 0;
static datetime    s_bkDragBT2 = 0;
static double      s_bkDragBP1 = 0.0;
static double      s_bkDragBP2 = 0.0;
static bool        s_bkDragMoved = false;
static uint        s_bkDragMs = 0;        // single follow budget: moves + paint (30ms)
static uint        s_bkDragPaintMs = 0;   // shared drag-paint budget (all painters)
static uint        s_bkDragActMs = 0;     // last drag activity — the stuck-lock watchdog (below) only fires when silent
static datetime    s_bkFolT1 = 0;         // last-followed BOX anchors — anchor-exact
static datetime    s_bkFolT2 = 0;         // source wins while the terminal moves them
static double      s_bkFolP1 = 0.0;
static double      s_bkFolP2 = 0.0;
// Press slop for drag-vs-hold/tap (mirrors the UI BK_HOLD_MOVE/BK_CLICK_SLOP
// language; defined HERE because Lite compiles this module without Panels).
#define BK_DRAG_SLOP 8
// P-BK-24: THE PRESS IS MEASURED IN PIXELS. The user aims at the VISIBLE border
// — a line `inpBoxBorderWidth` px wide sitting exactly ON the boundary — so half
// of that line is already outside the rectangle, and the inside-only test that
// used to guard the press rejected a third of the gestures the TERMINAL accepted
// (the user's own ledger, 68 gestures in one day: 42 `drag latch` / 26 `drag
// adopt … (the press missed it)`). ~4-6 px is the terminal's own hit tolerance.
#define BK_PRESS_SLOP_PX 5
// P-BK-18: the CURSOR-DELTA fallback is the only follow path that writes the BOX
// itself, so it keeps a 30 ms budget. The anchor path (children only) is
// CHANGE-driven and needs no budget: it writes exactly when the terminal moved
// the box, which is what MT4 already repaints for the box on the same frame.
#define BK_DRAG_CURSOR_MS 30
//--- P-BK-19 — WHO owns a box gesture, and WHAT the press grabbed. Two
//--- independent lessons, one per field below:
//---  (a) OWNERSHIP — kept as the LAW a restore must obey. Its consumer, the
//---      cursor-delta fallback, is RETIRED dead-by-construction (BKCURSOR-OFF:
//---      «دوتا درگ فعال داشتیم، اونی که لایو نیست حذف شود») — the defines and the
//---      statics below stay compiled so the restore is one word. While it WAS
//---      live: the cursor fallback was the ONE path that writes the BOX,
//---      and a native drag is the TERMINAL's gesture: it announces itself with
//---      CHARTEVENT_OBJECT_DRAG (and by moving the anchors), and MT4 CANCELS an
//---      in-progress native drag whose object is rewritten mid-flight (P-BK-15).
//---      So the fallback may only ever write a box the terminal has NOT claimed
//---      — two writers on one box is the P-BK-07 fight one layer down — and the
//---      terminal is asked FIRST (BK_DRAG_OWNER_MS): on a healthy build the
//---      first OBJECT_DRAG lands within the first travelled pixels, long before
//---      this window closes, so a real drag is never touched.
//---  (b) THE GRAB. The fallback used to translate BOTH anchors whatever the
//---      press had grabbed, so dragging one EDGE also moved the far side —
//---      «من یک طرف درگ میکنم طرف دیگه تکون میخوره». The press point is now
//---      MEASURED in pixels against the box's two corners (ChartTimePriceToXY —
//---      the same call the placement rule and this module's own preview already
//---      place objects with) into a 4-bit selection over {t1,p1,t2,p2}:
//---      a body grab moves all four (offsets kept), an edge/corner grab resizes
//---      exactly the grabbed side and leaves the opposite one where it is.
#define BK_GRAB_T1  1     // the box's first anchor TIME is the grabbed value
#define BK_GRAB_P1  2     // ...its first anchor PRICE
#define BK_GRAB_T2  4     // ...its second anchor TIME
#define BK_GRAB_P2  8     // ...its second anchor PRICE
#define BK_GRAB_ALL (BK_GRAB_T1 | BK_GRAB_P1 | BK_GRAB_T2 | BK_GRAB_P2)
#define BK_GRAB_CORNER_PX 8   // press this close to a corner grabs BOTH of its values
#define BK_GRAB_EDGE_PX   6   // ...this close to one edge grabs that edge only
#define BK_GRAB_MIN_SPAN_PX 24 // a box this small has no targetable edge: every press
                               // inside it is within the band, so the body grab stands
#define BK_DRAG_OWNER_MS  250 // the terminal's first refusal: a native drag speaks
                              // with its own OBJECT_DRAG this soon after the press
static int         s_bkGrabSel     = BK_GRAB_ALL;  // what this gesture may write
static bool        s_bkNativeClaim = false;        // the TERMINAL owns this gesture
// P-BK-25: is the press-time anchor snapshot (s_bkDragBP1/BP2) TRUSTWORTHY?  It
// is only when OUR press hit test latched the box: the adopt path below takes
// its snapshot AFTER the terminal has already moved the box, and the release
// magnet decides "did ONE side move?" by comparing against exactly that
// snapshot — so an untrusted baseline can read a whole-box MOVE as a one-side
// resize and snap it. A role that cannot be measured must not invent
// (P-BK-19b's rule, one layer up).
static bool        s_bkSnapTrusted = false;
static uint        s_bkOwnerMs     = 0;            // press moment — the settle window above
static bool        s_bkFallLogged  = false;        // one ledger line per gesture
//--- P-BK-61 — THE HANDLE GESTURE, in two statics (the same shape every other
//--- gesture of this module keeps): WHICH SIDE the hand is dragging right now
//--- (0 = none — the keeper's `skip`, the one chip that may never be written
//--- mid-gesture, P-BK-15), and whether this gesture's single ledger line was
//--- already written. Both are cleared on the press edge and on the release, so
//--- a missed release can only ever lose one line, never a box.
//+------------------------------------------------------------------+
//| P-BK-65 (2026-09-16) — ONE FIELD, ONE QUESTION: "IS A CHIP HELD"  |
//| IS NOT "WAS THIS GESTURE A RESIZE".                               |
//|                                                                  |
//| Reported: «چرا باکس ری‌سایز می‌کنم برمی‌گرده سر جای خودش یا لبه دیگه |
//| سمت دیگه میرن» — a handle resize SNAPPED BACK to the press-time     |
//| size, and the OPPOSITE edge jumped. The only writer that can do     |
//| that is `BaseKnotBodySizeHeal` (P-BK-61b: it re-imposes the press-  |
//| time WIDTH/HEIGHT around the box' left/top corner), so the resize   |
//| was being read as a BODY drag on the release. WHY: the release      |
//| decided "was this a resize" from `s_bkGripLive` — the keeper's own  |
//| skip field — and EVERY press edge of the mouse channel cleared it   |
//| ("a fresh press is a fresh gesture"). A press edge lands DURING a   |
//| live chip drag (the terminal's spurious down-flicker, the same       |
//| KEYSTATE family P-BK-03/P-UI-73 record), and the moment it does,     |
//| the resize loses its identity twice over:                          |
//|   * the RELEASE reads `bkGripWas == 0` → the body-size heal fires   |
//|     → the box springs back to its old size and the far edge jumps;  |
//|   * the KEEPER's skip goes to 0 → `BaseKnotGripsFollow` rewrites    |
//|     the very chip the hand is dragging, and MT4 CANCELS the native  |
//|     drag it is running (P-BK-15).                                   |
//|                                                                  |
//| SO the two questions get two fields:                                |
//|   * `s_bkGripLive`  — WHICH chip the hand holds RIGHT NOW (the       |
//|     keeper's `skip`). Correctly follows the press edge: at a real    |
//|     press nothing is held.                                          |
//|   * `s_bkGripGesture` — THE KIND OF THIS PRESS (the side of the chip|
//|     the TERMINAL named). Latched on the first OBJECT_DRAG of a chip  |
//|     and cleared ONLY by a witness that cannot lie: the release, the  |
//|     pump's silence watchdog, an OBJECT_DRAG that names the BOX itself|
//|     (the terminal says which object it drags — that IS the ground    |
//|     truth), or teardown.                                            |
//|   * `s_bkBoxNamed` — did the terminal name the BOX in this press?    |
//|     The body-size heal's own precondition (a magnet-enlarged FILL is |
//|     fixed only for a gesture the terminal moved the BOX on; a chip   |
//|     gesture can never run it), so the heal has TWO independent gates |
//|     and a lost latch can no longer spring the box back.             |
//|                                                                  |
//| COST: two int/bool stores on a gesture's FIRST event, one compare on |
//| the press edge and one at the release. Nothing per tick, nothing per |
//| step, no new terminal read anywhere.                                |
//+------------------------------------------------------------------+
static int         s_bkGripLive    = 0;            // the side being dragged (0 = none)
static int         s_bkGripGesture = 0;            // P-BK-65: this PRESS is a RESIZE (the chip's side)
static bool        s_bkBoxNamed    = false;        // P-BK-65: the terminal named the BOX in this press
static bool        s_bkGripLogged  = false;        // one "grip resize" line per gesture
static bool        s_bkMagnetLogged = false;       // P-BK-64: one "magnet" line per gesture —
                                                   // it carries the px distance the snap used, so
                                                   // the next «مگنت کار نمی‌کنه» is a number in the
                                                   // log instead of another guess
//--- P-PERF-42 — ONE child-existence probe per GESTURE, never per child per step.
//--- The per-step move used to ask `ObjectFind` for EVERY child before every
//--- `ObjectMove` (~10 terminal calls per drag event, at event rate), yet the
//--- child set is a property of the BOX: a drag never creates or deletes one
//--- (`BaseKnotMoveChildren` only moves), so the answer cannot change mid-gesture.
//--- It is now one 9-bit mask built on the first move of a gesture and keyed on
//--- the id it was built for, so the overlap-adopt path (the press latched one
//--- box and the terminal drags another) rebuilds instead of trusting it; the
//--- press clears the key so the SAME box dragged twice probes twice. A missing
//--- child is skipped exactly as before, and any child that really did vanish is
//--- recreated by the release `BaseKnotSync` / the pump's missing-edge heal.
#define BK_CH_EDGE_T 1
#define BK_CH_EDGE_B 2
#define BK_CH_EDGE_L 4
#define BK_CH_EDGE_R 8
#define BK_CH_ENTRY  16
#define BK_CH_SL     32
#define BK_CH_TP     64    // P-BK-50: bit 6 names TP1 now — the mask is private to this
#define BK_CH_TP2    512   //           module, so the address is kept; TP2/TP3 take the
#define BK_CH_TP3    1024  //           next free bits
#define BK_CH_ENTRY2 8192  // BKE2-OFF: retired bits — kept so the mask still compiles
#define BK_CH_SL2    16384 //           ... Sync purges these names instead of drawing them
#define BK_CH_E2TP1  32768 //           ... and its three plan ticks, measured from entry 2
#define BK_CH_E2TP2  65536
#define BK_CH_E2TP3  131072
#define BK_CH_INFO   128
#define BK_CH_TEXT   256
#define BK_CH_DOT    2048  // P-BK-59: the centre grip — a SCREEN object, so the drag step
                           //           cannot move it with ObjectMove (see the mover below)
#define BK_CH_GRIP   4096  // P-BK-61: the HANDLE family — ONE bit for the whole set (the corner
                           //           chips of BK_GRIP_COUNT are created, retired and carried
                           //           together, and the keeper re-measures each one itself)
static int         s_bkChildMask   = 0;            // which children existed at the gesture's start
static string      s_bkChildMaskId = "";           // the box that mask was built for ("" = probe on the next move)
//--- P-PERF-43 — the BOX drag measures ITSELF (P-PERF-15 pattern). The gesture
//--- ledger (P-BK-19) says WHO owned the drag; these two numbers say what it
//--- COST, split by phase (children/box writes vs the throttled repaint), so the
//--- next "the drag lags" is attributed from the log instead of guessed at.
//--- Cost on the fast path: a GetTickCount around each phase that already ran.
static uint        s_bkPerfMoveWorst  = 0;         // worst children/box write pass, ms
static uint        s_bkPerfPaintWorst = 0;         // worst repaint, ms
static uint        s_bkPerfPasses     = 0;         // move passes applied this gesture
static bool        g_bkRestoreReq = false;  // UI side: re-show the menu once
static bool        g_bkTouched    = false;  // Arm ran → OnDeinit must restore chart props
static bool        g_bkAutoWas    = true;    // CHART_AUTOSCROLL before a gesture (ticks slide the view mid-drag)
// P-UI-90: scroll + context menu are NO LONGER captured here. Four owners each
// saved "what the user had" and wrote it back themselves, and a pair read while
// another owner already held the lock recorded our own `false` as the user's -
// the one-way ratchet that left the chart scroll-locked for the life of the
// terminal (and after Remove). `ChartViewLock*` (GlobalVariables) is the single
// owner of that capture/restore now. AUTOSCROLL stays per-owner on purpose: it
// is not part of that pair, and the two writers that need it (a box gesture, the
// line drag) only ever RESTORE what they saw, so they cannot ratchet each other.
static bool        s_bkChartLocked = false;  // a gesture currently holds the chart props below
static bool        s_bkDragLock    = false;  // holder is the IDLE box-drag (not the draw session)

//+------------------------------------------------------------------+
//| Naming: every structure shares ONE id — parent/child by suffix.  |
//| Dragging/deleting the BOX cascades to its ENTRY/SL/TP/badges.     |
//+------------------------------------------------------------------+
string BaseKnotPrefix(const string id)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + id + "_";
}
string BaseKnotBoxName(const string pfx)   { return pfx + "BOX"; }
string BaseKnotEntryName(const string pfx) { return pfx + "ENTRY"; }
string BaseKnotSLName(const string pfx)    { return pfx + "SL"; }
// BKE2-OFF: the 2nd entry's names — kept so the purge deletes them, never drawn.
// Underscore-free suffixes: the OBJECT_DELETE heal splits at the LAST
// underscore, so a suffixed tick must not carry one of its own.
string BaseKnotEntry2Name(const string pfx) { return pfx + "ENTRY2"; }
string BaseKnotSL2Name(const string pfx)    { return pfx + "SL2"; }
string BaseKnotTPTick2Name(const string pfx, const int k) { return pfx + "E2TP" + IntegerToString(k); }
string BaseKnotTPName(const string pfx)    { return pfx + "TP"; }   // BKTPR-OFF: the retired single tick — kept as the name the purge deletes
string BaseKnotTPTickName(const string pfx, const int k) { return pfx + "TP" + IntegerToString(k); }   // P-BK-50: TP1..TP3, one tick each
string BaseKnotBuyName(const string pfx)   { return pfx + "BUY"; }
string BaseKnotDelName(const string pfx)   { return pfx + "DEL"; }
string BaseKnotInfoName(const string pfx)  { return pfx + "INFO"; }
// P-BK-86: the note's PLATE — the opaque background the box-side note is read on. It is
// spelled off the NOTE'S OWN NAME (never off a box prefix), so the writer — which only ever
// holds the note's name — spells it exactly as the wipe sites that hold a prefix. ONE owner
// of the suffix, so a rename can never leave an orphan bar on the chart.
string BaseKnotInfoPlateName(const string infoName) { return infoName + BK_NOTE_PLATE; }
// P-BK-86: ONE wipe for the PAIR. A note without its plate is the unreadable text this change
// exists for; a plate without its note is an empty bar over the candles. They are one readout,
// so every delete site goes through here instead of deleting half of it.
void BaseKnotInfoWipe(const string pfx)
{
   string in = BaseKnotInfoName(pfx);
   ObjectDelete(0, in);
   ObjectDelete(0, BaseKnotInfoPlateName(in));
}
// P-BK-92: the HALF-wipe the visibility rule needs. The ink keeps itself (a LABEL obeys the
// TF mask), so hiding a note's TF deletes the PLATE only — the pair's own name owner answers
// it, never a box prefix (the writer holds the note's name, not the box').
bool BaseKnotNotePlateDrop(const string infoName)
{
   string pn = BaseKnotInfoPlateName(infoName);
   if(ObjectFind(0, pn) < 0) return false;
   ObjectDelete(0, pn);
   return true;
}
// User TEXT (TV-parity 2026-09-07, Text tab): one OBJ_TEXT child per box,
// content edited via the full card's edit field. Lives in the chart object
// itself (no GV — strings don't fit doubles); delete = clear (Sync never
// resurrects a deleted TEXT, it only moves/restyles an existing one).
string BaseKnotTextName(const string pfx)  { return pfx + "TEXT"; }
string BaseKnotGetText(const string pfx)
{
   string tn = BaseKnotTextName(pfx);
   if(ObjectFind(0, tn) < 0) return "";
   return ObjectGetString(0, tn, OBJPROP_TEXT);
}
void BaseKnotSetText(const string id, const string txt)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string tn = BaseKnotTextName(pfx);
   string t = txt;
   StringTrimLeft(t); StringTrimRight(t);
   if(StringLen(t) == 0) { ObjectDelete(0, tn); ChartRedraw(); return; }   // empty = clear
   if(ObjectFind(0, tn) < 0)
   {
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) return;
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      double top = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      if(!ObjectCreate(0, tn, OBJ_TEXT, 0, t2, top)) return;
   }
   ObjectSetString(0, tn, OBJPROP_TEXT, t);
   BaseKnotSync(id);   // placement + font follow the box + mirrors
   ChartRedraw();
}
// Text anchor geometry — single source of truth for PlaceText (full restyle)
// and the drag mover below (position only). TV Text-tab alignment: horizontal
// (Left|Center|Right) picks the corner, vertical (Top|Inside/Bottom) picks
// above / inside-top / below the box (TV default Inside).
void BaseKnotTextPlace(const datetime t1, const datetime t2,
                       const double top, const double bot,
                       datetime &tx, double &px, int &anchor)
{
   int al = ClampSettingInt(g_bkAlign, 0, 2);
   int va = ClampSettingInt(g_bkVAlign, 0, 2);
   tx = (al == 0 ? t1 : (al == 1 ? t1 + (t2 - t1) / 2 : t2));
   px = top;
   anchor = ANCHOR_UPPER;
   if(va == 0)         // Top — text sits ABOVE the box top edge
      anchor = (al == 0 ? ANCHOR_LEFT_LOWER : (al == 1 ? ANCHOR_LOWER : ANCHOR_RIGHT_LOWER));
   else if(va == 2)    // Bottom — text sits BELOW the box bottom edge
   {
      px = bot;
      anchor = (al == 0 ? ANCHOR_LEFT_UPPER : (al == 1 ? ANCHOR_UPPER : ANCHOR_RIGHT_UPPER));
   }
   else                // Inside — text hangs from the box top edge
      anchor = (al == 0 ? ANCHOR_LEFT_UPPER : (al == 1 ? ANCHOR_UPPER : ANCHOR_RIGHT_UPPER));
}
// (Re)place + restyle an EXISTING text object (geometry via BaseKnotTextPlace).
void BaseKnotPlaceText(const string pfx, const datetime t1, const datetime t2,
                       const double top, const double bot, const long tfMask, const string tip)
{
   string tn = BaseKnotTextName(pfx);
   if(ObjectFind(0, tn) < 0) return;   // no text — never resurrect (delete = clear)
   datetime tx; double px; int anchor;
   BaseKnotTextPlace(t1, t2, top, bot, tx, px, anchor);
   ObjectSetInteger(0, tn, OBJPROP_TIME, 0, tx);
   ObjectSetDouble(0, tn, OBJPROP_PRICE, 0, px);
   ObjectSetString(0, tn, OBJPROP_FONT, BKTextFont());
   ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, ClampSettingInt(g_bkTextSize, 8, 24));
   ObjectSetInteger(0, tn, OBJPROP_COLOR, GetBKTextRenderColor());
   ObjectSetInteger(0, tn, OBJPROP_ANCHOR, anchor);
   if(StringLen(tip) > 0) ObjectSetString(0, tn, OBJPROP_TOOLTIP, tip);   // hover = full numbers, like box/edges
   ObjectSetInteger(0, tn, OBJPROP_BACK, false);
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, tn, OBJPROP_ZORDER, Z_BOX_TEXT);
   ObjectSetInteger(0, tn, OBJPROP_TIMEFRAMES, tfMask);
}
// Short TF name for tooltips / risk text (P-BK-60: the box is on every TF, so a
// name here means the box' OWN commit TF — "M5" — and never a scope).
string BaseKnotTFName(const int tfMin)
{
   if(tfMin <= 0) return "all TFs";
   if(tfMin == 1) return "M1"; if(tfMin == 5) return "M5";
   if(tfMin == 15) return "M15"; if(tfMin == 30) return "M30";
   if(tfMin == 60) return "H1"; if(tfMin == 240) return "H4";
   if(tfMin == 1440) return "D1"; if(tfMin == 10080) return "W1";
   if(tfMin == 43200) return "MN1";
   return IntegerToString(tfMin) + "m";
}
// ONE live tooltip language for box + edges (TV Coordinates/Visibility tabs
// live here in MT4: drag edits coords natively, visibility is automatic).
// Coords · TF-scope · user text · risk numbers — nothing unreachable.
// P-BK-29/47: the node's own sentence arrives READY-BUILT (`nodeLine`) — the
// read belongs to Sync (one bar scan per box per rebuild), never to the
// tooltip, and a string keeps this signature free of the node record.
// P-BK-46: `riskTag` arrives the same way — the first number is the trade's RISK,
// so the hover says whether it is EngSL of the knot's own TF or the box' height.
// P-BK-50: so do the PLAN's targets (`tpTip`, ready-built by BaseKnotTPPlanTip —
// the retired `TARGET R` x R field is gone, and the plan's own legs take its place).
string BaseKnotBoxTooltip(const string id, const datetime t1, const datetime t2,
                          const double top, const double bot, const string side,
                          const double hPips, const string tpTip, BaseKnotSpan &sp,
                          const string riskTag, const string nodeLine, const string entryLine,
                          const string entryLine2)
{
   int k = BaseKnotFind(id);
   int tfMin = (k >= 0 ? g_bkBoxes[k].tfMin : 0);
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);
   // P-BK-51: the first line states the STOP's own two facts (its size and where it sits),
   // and `entryLine` — the SAME sentence the note's hover reads — states the entry's.
   string tt = "Base box " + side + " · " + DoubleToString(hPips, 1) + " pips (the STOP: one " + riskTag +
               " behind the entry, INSIDE the box) · BOTH legs sit INSIDE the box" + entryLine +
               (sp.life > 0 ? " · " + IntegerToString(sp.life) + " bars" : "");
    tt += entryLine2;   // BKE2-OFF: always "" now (kept so the signature still compiles)
   tt += "\n" + TimeToString(t1, TIME_DATE|TIME_MINUTES) + " -> " + TimeToString(t2, TIME_DATE|TIME_MINUTES);
   datetime cs1, cs2;                                    // P-BK-84: the class' span — box ∪ base
   BaseKnotClassSpan(sp, t1, t2, cs1, cs2);
   tt += BaseKnotBaseLine(sp.still, cs1, cs2, top, bot);   // P-BK-84: the class, off the BASE'S OWN entry..exit (the node's own time, the same on every chart)
   if(sp.life > 0)   // P-BK-40/41/42: what the note's number is MADE OF, and HOW it is counted
      tt += "\n     " + IntegerToString(sp.life) + " bars = the candles between the ENTRY candle " +
            "and the EXIT candle (entry not counted, exit counted) · " + IntegerToString(sp.still) +
            " of them stood still inside the band (the base's own length — P-BK-84 reads the class"
            " on the base's own span ∪ the box', so neither a narrow box nor the chart can move it)";
   if(sp.life > 0 && sp.tStart > 0 && sp.tExit > 0)   // P-BK-41/42: band, entry, exit, then the number
   {
      int dg = GetCachedDigits();
      tt += "\n     band " + DoubleToString(bot, dg) + ".." + DoubleToString(top, dg) +
            " -> entry candle " + TimeToString(sp.tStart, TIME_DATE|TIME_MINUTES) + " (not counted)" +
            (sp.tExit > sp.tLast
             ? " -> exit candle " + TimeToString(sp.tExit, TIME_DATE|TIME_MINUTES) + " (counted)"
             : " -> no exit yet: the newest closed candle is still holding the band") +
            (sp.tExit > 0 && t2 > sp.tExit
             ? " · the box reaches past the exit (those candles are not the base)"
             : (sp.tLast > 0 && t2 < sp.tLast
                ? " · the box' right edge is INSIDE the base: the story runs on to the exit"
                : ""));
   }
   tt += nodeLine;                 // P-BK-29/47 — the node type (its length) + the story's numbers
   tt += tpTip;                    // P-BK-50 — the plan's own targets, leg by leg
   // P-BK-60: the box is on every timeframe — the hover says so ONCE (the commit TF
   // still rides the note and the risk text above; it is no longer a scope).
   tt += "\nVisible: every timeframe (drag to move)";
   string ut = (k >= 0 ? BaseKnotGetText(BaseKnotPrefix(id)) : "");
   if(StringLen(ut) > 0) tt += "\n\"" + ut + "\"";
   if(k >= 0 && g_bkBoxes[k].locked) tt += "\nLOCKED (hold to unlock)";
   else tt += "\nclick: info badge · select + Delete key removes all";
   return tt;
}
string BaseKnotPrevTag()   // sizing-preview edges live under this tag (4 segments)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "PREVIEW";
}
void BaseKnotWipePreview()
{
   string tag = BaseKnotPrevTag();
   if(tag != "") ObjectsDeleteAll(0, tag);
}
string BaseKnotHintName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "HINT";
}
string BaseKnotGV(const string id)
{
   return "Biotak_BK_" + id + "_" + GetCachedChartIdStr();
}
//+------------------------------------------------------------------+
//| P-BK-26 — DROP THE TERMINAL'S SELECTION OF A BOX, ONCE, GUARDED.  |
//|                                                                  |
//| `OBJPROP_SELECTABLE` is the DRAG (P-UI-48's lesson: MT4 grabs a     |
//| selectable object exactly once, on the press that lands on it) while|
//| `OBJPROP_SELECTED` is the HIJACK — a selected object is moved by     |
//| MT4 on every LATER drag anywhere on the chart, whatever that drag    |
//| was meant for (P-UI-45's law, fixed for the custom-price line in     |
//| P-UI-48 and never for this handle). ONE owner, read then write only  |
//| while the box really is selected (a gesture that never selected it   |
//| pays one bool read), and never called while the button is down       |
//| (P-BK-15: writing into a live native drag cancels it).               |
//| BKSELECT-KEPT (2026-09-15): currently no callers — both drops are    |
//| retired so the box stays selected like MT4's own; kept for a         |
//| one-line restore.                                                    |
//+------------------------------------------------------------------+
void BaseKnotDropSelection(const string id)
{
   if(id == "") return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED))
      ObjectSetInteger(0, box, OBJPROP_SELECTED, false);
}

//+------------------------------------------------------------------+
//| P-BK-73 — GRANT THE SELECTION, ONCE, GUARDED (the mirror of the    |
//| drop above and the ONE owner of the grant).                        |
//|                                                                   |
//| WHY IT EXISTS: the terminal paints its selection markers — the      |
//| centre square plus one on every control corner, the five the user   |
//| sees on MT4's own rectangle — for a SELECTED object only, and with  |
//| BKGRIP-OFF (P-BK-71) those markers ARE this module's only resize    |
//| handles (`BK_GRAB_CORNER_PX` measures the press against them). An   |
//| unselected box therefore wears nothing and its native resize — the  |
//| gesture P-BK-72 was written for — is unreachable until the user     |
//| clicks it. MT4's own rectangle never has that gap: it is still in   |
//| edit mode the instant the draw is let go, which is what            |
//| `BaseKnotCommit` now answers.                                       |
//|                                                                   |
//| THE GUARDS: a LOCKED box is not selectable, so the terminal draws   |
//| no marker on it and a granted selection would only lie — refused.   |
//| An already-selected box pays ONE read and no repaint (the perf law  |
//| this module follows everywhere: never write a property you would    |
//| not change). The commit is the only caller and both of its call     |
//| sites are a RELEASE (mouse-up) or a CLICK, never a live button — so |
//| the P-BK-15 rule (a write cancels a drag the terminal owns) cannot  |
//| be broken from here.                                                |
//|                                                                    |
//| THIS IS THE DOCS' OWN RECIPE, not a trick of ours. The MQL4         |
//| Reference's OBJ_RECTANGLE page ships a `RectangleCreate()` example  |
//| whose property block is exactly                                    |
//|   ObjectCreate(chart_ID, name, OBJ_RECTANGLE, sub_window,           |
//|                time1, price1, time2, price2);                       |
//|   … OBJPROP_COLOR / STYLE / WIDTH / FILL / BACK …                   |
//|   ObjectSetInteger(chart_ID, name, OBJPROP_SELECTABLE, selection);  |
//|   ObjectSetInteger(chart_ID, name, OBJPROP_SELECTED,  selection);   |
//|   … OBJPROP_HIDDEN / ZORDER …                                       |
//| under the comment «when creating a graphical object using           |
//| ObjectCreate function, the object cannot be highlighted and moved   |
//| by default. Inside this method, selection parameter is true by      |
//| default making it possible to highlight and move the object». So    |
//| the terminal's own way to hand a fresh rectangle its five markers   |
//| is ONE line at creation — the line this function is.               |
//+------------------------------------------------------------------+
void BaseKnotSelectBox(const string id)
{
   if(id == "") return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   if(!(bool)ObjectGetInteger(0, box, OBJPROP_SELECTABLE)) return;   // a locked box wears no markers anyway
   if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED)) return;      // already selected: no write, no repaint
   ObjectSetInteger(0, box, OBJPROP_SELECTED, true);
}

//+------------------------------------------------------------------+
//| Box look — SINGLE source of truth (P-BK-04/06, TV-fill 2026-09-07, |
//| P-BK-74 2026-09-17).                                               |
//| ONE object, and it is the terminal's own rectangle:                |
//|   * HOLLOW (TR=100, the default) → FILL false, BACK false, COLOR =  |
//|     GetBoxBorderRenderColor() with the user's border style/width.   |
//|     That is the Rectangle tool's own look — no fill, not a          |
//|     background object — and the outline the user sees IS the object |
//|     the terminal drags and marks. BKEDGE-OFF (P-BK-74) retired the  |
//|     four OBJ_TREND children that used to draw this border, and with |
//|     them the P-BK-18 settle heal (the border is no longer a COPY of |
//|     the box, so there is nothing left to fall behind).              |
//|   * FILL set → FILL true + GetBoxFillRenderColor() (TV Style-tab    |
//|     bucket, e.g. 36%) and BACK true: the fill belongs BEHIND the    |
//|     candles. That fill IS the object's own pixel, it must not cover |
//|     the bars, and the user asked for that look (16 zones/drag cost  |
//|     is the price of the look).                                      |
//|                                                                    |
//| P-BK-23 (2026-09-15) — THE HOLLOW BOX IS A FOREGROUND OBJECT, LIKE  |
//| MT4'S OWN, and that part of the lesson still stands. «مال خودِ       |
//| متاتریدر راحت درگ میشه ولی این بیس نات یکم سخته»: the saved chart   |
//| records say what the difference was. MT4 stores its own objects     |
//| `background=0`, and a background object forces the terminal to      |
//| repaint the BARS under it on every frame of a native drag, over an  |
//| area exactly the size of the box. That is the «چسبناک» the user     |
//| feels exactly where the candles are and never in the empty part of  |
//| the chart — while our own follow measures `move=0ms paint=0ms` and  |
//| the gesture ledger says `native=1` (the cost is the TERMINAL's).    |
//| P-BK-74 is what makes that free: with the rectangle wearing the     |
//| border ink itself, the grabbable ring IS the ring the user sees —   |
//| no cover, no children to keep in step, and the terminal moves the   |
//| outline with the object it belongs to.                              |
//+------------------------------------------------------------------+
//--- edge suffixes (committed pfx AND preview tag share them)
#define BK_EDGE_T "_T"
#define BK_EDGE_B "_B"
#define BK_EDGE_L "_L"
#define BK_EDGE_R "_R"
void BaseKnotStyleBox(const string box)   // fill layer + drag handle + (P-BK-74) the border itself
{
   if(BoxFillVisible())
   {
      ObjectSetInteger(0, box, OBJPROP_COLOR, GetBoxFillRenderColor());
      ObjectSetInteger(0, box, OBJPROP_FILL, true);
      ObjectSetInteger(0, box, OBJPROP_BACK, true);          // the fill belongs behind the candles (zone-like)
      ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);  // a fill's own edge is flat — the ink that reads is the FILL
      ObjectSetInteger(0, box, OBJPROP_WIDTH, 1);
   }
   else
   {
      // P-BK-74 — THE RECTANGLE **IS** THE BOX, MetaTrader's own way. Its own
      // outline wears the border ink/style/width the user set, so the object the
      // terminal draws is the object the user sees — one object, not a visible
      // cover for four trend-line children (BKEDGE-OFF below).
      // FILL false = HOLLOW and BACK false = FOREGROUND are the terminal's own
      // defaults for its Rectangle tool («باکس پیش فرض بدون fill باشه و
      // بگراندش غیر فعال باشه») and the two properties its OBJ_RECTANGLE example
      // sets as `fill` and `back`; the docs' own `RectangleCreate()` ships them
      // false. Nothing here is a workaround any more: the rectangle renders its
      // border because it IS a rectangle, exactly as the terminal renders its own.
      ObjectSetInteger(0, box, OBJPROP_COLOR, GetBoxBorderRenderColor());
      ObjectSetInteger(0, box, OBJPROP_FILL, false);
      ObjectSetInteger(0, box, OBJPROP_BACK, false);
      ObjectSetInteger(0, box, OBJPROP_STYLE, inpBoxBorderStyle);
      ObjectSetInteger(0, box, OBJPROP_WIDTH, inpBoxBorderWidth);
   }
   ObjectSetInteger(0, box, OBJPROP_ZORDER, Z_BOX_FILL);   // single source — Commit no longer sets it separately
}
// True when the BOX rect currently shows the live look (heal check).
bool BaseKnotFillHealed(const string box)
{
   if(BoxFillVisible())
   {
      if(ObjectGetInteger(0, box, OBJPROP_FILL) == 0) return false;
      if((color)ObjectGetInteger(0, box, OBJPROP_COLOR) != GetBoxFillRenderColor()) return false;
      return true;
   }
   if(ObjectGetInteger(0, box, OBJPROP_FILL) != 0) return false;
   // P-BK-23: a hollow box must also be a FOREGROUND object (MT4's own objects
   // are stored background=0). One extra read per box per pump — and it is what
   // heals the boxes committed before this rule existed.
   if(ObjectGetInteger(0, box, OBJPROP_BACK) != 0) return false;
   // P-BK-74: and the ink is the BORDER's now (it used to be the background
   // colour, because the visible border was four trend edges). This one compare
   // is what heals every box an older build left invisible.
   return ((color)ObjectGetInteger(0, box, OBJPROP_COLOR) == GetBoxBorderRenderColor());
}

bool BaseKnotSessionActive() { return (g_bkState != BK_IDLE); }
// P-BK-62 (2026-09-16) — THE BOX TOOL'S ONE ANSWER TO "DO WE OWN THE VIEW?".
//
// Three gestures of this module take the chart view: the draw session, an IDLE
// body drag and a handle RESIZE (`BaseKnotDragLockOn`). The reconcile watchdog
// (`ChartScrollReconcile`, run from the entry's timer and from every button-up
// finalizer) rebuilds the lock from OWNERSHIP INTENT, and that query only ever
// asked the draw SESSION — so an IDLE drag/resize was invisible to it, the next
// round handed the view back under the user's hand, and the drag's own guard then
// early-returned for the rest of the gesture. The chart scrolled while the user
// was dragging/resizing the box. This is P-UI-53's fix, for the second owner:
// every holder of the lock answers ONE query, and nobody restores it from under
// a live gesture. Two bool reads; no writes of its own.
bool BaseKnotViewOwned() { return (s_bkDragLock || g_bkState != BK_IDLE); }
int  BaseKnotCount()         { return ArraySize(g_bkBoxes); }

// UI side polls this after OnChartEventHandler to re-show the hidden menu.
bool BaseKnotTakeRestoreFlag()
{
   if(!g_bkRestoreReq) return false;
   g_bkRestoreReq = false;
   return true;
}

//+------------------------------------------------------------------+
//| Dynamic point/pip — gold, crypto, JPY and forex all covered via   |
//| the shared asset-aware cache (PerformanceOptimizations.mqh).      |
//+------------------------------------------------------------------+
double BaseKnotPipSize()
{
   double pip = GetCachedPipSize();
   if(pip <= 0) pip = GetCachedPoint();
   if(pip <= 0) pip = _Point;
   return pip;
}
double BaseKnotToPips(const double dist) { return dist / BaseKnotPipSize(); }

//+------------------------------------------------------------------+
//| Id helpers — ids are "<tfMin>_<tick>[rNNN]"; tails split at the   |
//| LAST underscore (StringFind from the right) because the id itself |
//| contains an underscore.                                           |
//+------------------------------------------------------------------+
void BaseKnotSplitTail(const string tail, string &bid, string &kind)
{
   bid = ""; kind = "";
   int last = -1, pos = 0;
   while(true)
   {
      int f = StringFind(tail, "_", pos);
      if(f < 0) break;
      last = f;
      pos = f + 1;
   }
   if(last <= 0) return;   // malformed (PREVIEW/HINT tails land here)
   bid  = StringSubstr(tail, 0, last);
   kind = StringSubstr(tail, last + 1);
}
// Commit-TF minutes encoded in the id head; 0 = legacy bare-tick id.
int BaseKnotIdTF(const string bid)
{
   int us = StringFind(bid, "_");
   if(us <= 0) return 0;
   return (int)StringToInteger(StringSubstr(bid, 0, us));
}
//+------------------------------------------------------------------+
//| P-BK-60 (2026-09-16) — THE BOX LIVES ON EVERY TIMEFRAME.         |
//|                                                                  |
//| «این باکس در تایم های بالاتر هم نمایش داده بشه ... پیش فرض». The  |
//| commit-TF mask (the box' own TF and every LOWER one, P-BK-01's    |
//| hairline rule) is the DEFAULT no longer: the mask is ALL periods, |
//| so a knot drawn on M5 is still on the chart on H1 and D1. The     |
//| box' anchors ARE chart time/price, so it lands exactly where the  |
//| user drew it — the same two candles' worth of time simply covers  |
//| more of the window; it never moves, and nothing re-reads a TF to  |
//| decide whether it may be seen.                                    |
//|                                                                  |
//| ONE MASK, ONE PROBE: every object of the family (the handle, the  |
//| 4 edges, Entry/SL/TP, the note, the user text, the P-BK-59 grip)  |
//| rides THIS function's answer, and the question "is this box on    |
//| the chart here?" is asked through BaseKnotTFVisible — never       |
//| through `Period()` at a call site.                                |
//|                                                                  |
//| BKTFSCOPE-OFF: the retired rule stays in place below, one word    |
//| away; `tfMin` stays a parameter because the RETIRED body is what  |
//| reads it, not the caller (so a restore is: delete the first       |
//| `return`, uncomment, and re-teach nothing else).                  |
//+------------------------------------------------------------------+
long BaseKnotTFMask(const int tfMin)
{
   return OBJ_ALL_PERIODS;   // P-BK-60: on every TF — see the note above
   //--- BKTFSCOPE-OFF: commit TF + every lower TF (restore by deleting the line above) ---
   //if(tfMin <= 0) return OBJ_ALL_PERIODS;   // legacy box — keep old behavior
   //long m = 0;
   //if(tfMin >= 1)     m |= OBJ_PERIOD_M1;
   //if(tfMin >= 5)     m |= OBJ_PERIOD_M5;
   //if(tfMin >= 15)    m |= OBJ_PERIOD_M15;
   //if(tfMin >= 30)    m |= OBJ_PERIOD_M30;
   //if(tfMin >= 60)    m |= OBJ_PERIOD_H1;
   //if(tfMin >= 240)   m |= OBJ_PERIOD_H4;
   //if(tfMin >= 1440)  m |= OBJ_PERIOD_D1;
   //if(tfMin >= 10080) m |= OBJ_PERIOD_W1;
   //if(tfMin >= 43200) m |= OBJ_PERIOD_MN1;
   //if(m == 0) m = OBJ_ALL_PERIODS;
   //return m;
}
// The same question in minutes (no flag mapping, so an exotic chart TF is safe) —
// and the ONE owner the strip, the note row and the TP glue ask (P-BK-60).
bool BaseKnotTFVisible(const int tfMin)
{
   return true;   // P-BK-60: on every TF — see BaseKnotTFMask's note above
   //--- BKTFSCOPE-OFF: the commit-TF floor (restore by deleting the line above) ---
   //if(tfMin <= 0) return true;
   //return (Period() <= tfMin);
}

//+------------------------------------------------------------------+
//| BKMAGNET-OFF (2026-09-06, user decision — corners jumped to candle|
//| shadows and the box never landed where clicked, unlike the native |
//| rectangle tool): NO snapping — a click IS the corner, exactly like |
//| MT4's own box. Body kept (commented) for a one-line restore.      |
//| P-BK-21 (2026-09-15): that decision covers DRAWING only, and it      |
//| stands — this function stays the identity. The magnet lives on the   |
//| ADJUST gesture instead (`BaseKnotMagnetSettle`, called on the drag   |
//| release), because there the user HAS chosen the edge and is asking   |
//| for the exact wick. Do not "restore" the body below: two magnets      |
//| would fight and the draw-time one is the one that was rejected.      |
//+------------------------------------------------------------------+
double BaseKnotSnapPrice(const datetime t, const double price)
{
   return price;   // BKMAGNET-OFF: click = corner, no High/Low pull
   //--- retired snap body (restore by deleting the line above) ---
   //if(!inpEnableMagnet) return price;
   //if(t <= 0 || price <= 0) return price;
   //int shift = iBarShift(_Symbol, 0, t, false);
   //if(shift < 0) return price;
   //double hi = High[shift], lo = Low[shift];
   //if(hi <= 0 || lo <= 0 || hi < lo) return price;
   //double dH = MathAbs(price - hi), dL = MathAbs(price - lo);
   //double gate = (double)inpMagnetSensitivityPips * BaseKnotPipSize();
   //if(gate <= 0) gate = BaseKnotPipSize();   // sensitivity 0 = exact touch only
   //if(MathMin(dH, dL) > gate) return price;  // too far — leave the hand-drawn value
   //return (dH <= dL ? hi : lo);
}
#endif // BASE_KNOT_BASE_MQH
