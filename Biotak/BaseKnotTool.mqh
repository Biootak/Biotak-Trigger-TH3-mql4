//+------------------------------------------------------------------+
//|                                              BaseKnotTool.mqh    |
//|        Base / Knot Measurement Tool — TradingView-style two-click |
//|        base-box drawer with Entry / SL / TP projections.          |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain (no UI deps — compiles in Full AND Lite).   |
//| The Tools-ring button, menu hide/restore and chart-lock watchdog  |
//| hooks live on the UI side (BiotakMenu/BiotakPanels) and call into |
//| this module. Chart scroll is locked directly here (raw Chart*      |
//| calls) so Lite — which has no menu — keeps drag/delete working.   |
//|                                                                   |
//| STATE MACHINE (the ONLY mouse-event consumer while active):       |
//|   NATIVE DRAG (like MT4's own rectangle): press → corner 1,        |
//|   hold + move → live rubber-band + Entry/SL/TP, release → commit.  |
//|   TAP-TAP (TradingView-style): click 1 → corner 1, move (hover      |
//|   preview), click 2 → commit. Single-shot: commit → BK_IDLE.       |
//|   (ESC / right-click / orb → IDLE).                                 |
//| While BK_ARMED/BK_PREVIEW, BaseKnotOnChartEvent() returns true for |
//| consumed events so OnChartEventHandler returns early and nothing   |
//| else (custom-price, TH3, panels) sees the gesture.                 |
//|                                                                   |
//| PRODUCT RULES (2026-09-06 — no Buy/Sell button, fully automatic;     |
//|  2026-09-08 — frozen dir went LIVE: it follows the price, see below):  |
//|  * P-BK-46/47 (2026-09-15) — THE TRADE IS THE KNOT'S OWN, and the    |
//|                                                                      |
//|    [its SIDE half is RETIRED IN PLACE by P-BK-49 below — BKNODEDIR-OFF]|
//|    BREAK'S STORY names the SIDE it rides (P-BK-47 moved the TYPE off |
//|    that story — the type is the node's LENGTH now): the break never   |
//|    came back, or the same edge broke again after a return = the       |
//|    break's own side (entry on the edge that broke); a return into the |
//|    base, or one that ran out the FAR edge = the return's side (entry  |
//|    on that far edge); and the live price only decides for a base with |
//|    no break measured yet. R — the risk every leg is measured in — is  |
//|    EngSL OF THE KNOT'S OWN TF (the base class), pushed in by the pump |
//|    layers because trade-plan math sits above this module. P-BK-51     |
//|    (2026-09-15, user: «برای گره اف تی ار میشه به اندازه engsl محل ورود|
//|    داخل گره و به اندازه engsl از محل ورود استاپ» + «و برای گره etr   |
//|    میشه به اندازه huntsl محل ورود و به اندازه engsl از محل ورود میشه |
//|    استاپ لاسش» + «و برای نوع هی بعدی بای از engsl , huntsl یک تایم   |
//|    بالاتر استفاده کرده») OWNS the three legs: BOTH of them sit INSIDE|
//|    the knot, measured from the edge the side comes in on (top for a  |
//|    Buy, bottom for a Sell) — the ENTRY waits ONE EngSL of penetration|
//|    for an FTR node and ONE HuntSL for ETR/CTR/OTR (and a CTR/OTR knot |
//|    is read ONE TF HIGHER, «یک تایم بالاتر»), while the SL is ALWAYS  |
//|    one EngSL behind the entry. The TARGETS are the trade plan's OWN  |
//|    TP1..TP3 of the knot's TF (the numbers the label's `#SL/-TP` row   |
//|    prints), measured from the entry exactly as that row measures     |
//|    them. The old `TARGET R` x R target stays RETIRED IN PLACE        |
//|    (BKTPR-OFF), and that SAME state picks how many of the plan's     |
//|    legs are drawn (1..3); P-BK-50's `entry ONE R OUTSIDE, stop ON    |
//|    the edge` pair is superseded in place (BKGEOM-OFF). Until the     |
//|    pump pushes a number the box' own height stands in, and EVERY text|
//|    says which of the two it is showing (the hovers, ray tooltips).   |
//|  * P-BK-81 (2026-09-17) — THE DIRECTION IS ONE BIT: THE BASE'S   |
//|    OWN EXIT CANDLE'S. The four names (RBR/RBD/DBR/DBD, P-BK-49)   |
//|    are GONE — RBR and DBR are the SAME direction and RBD and DBD  |
//|    are the same, so they never named a side the exit leg did not  |
//|    already name. The walk starts AT that candle (the candle that   |
//|    CLOSED OUTSIDE the band — the very one the note's number is     |
//|    counted to): above the ceiling -> Buy, below the floor -> Sell, |
//|    inside -> nothing claimed. NOT the box' right edge (dragging it  |
//|    used to move the walk's start and flip the side), and no later   |
//|    return, second break or far-edge close can rewrite it — those   |
//|    are the node's LIFE and are reported, never a direction.        |
//|  * P-BK-82 (2026-09-17) — M1 IS A RUNG OF THE CLASS LADDER. The     |
//|    ladder the class read walks began at M5, so a base whose candles |
//|    stand still on M1 could NEVER be named M1: the read fell past    |
//|    every rung and named the SPAN's own rung instead — the user's    |
//|    17-minute box around a 5-bar M1 base printed «M15 base»          |
//|    («گره که مال یک دقیقه هستش رو مال پانزده دقیقه نشون میده»).      |
//|    The floor is M1 now, and nothing else moves: every other caller  |
//|    hands a tfMin >= 1, where the old first step still answers 5.    |
//|  * Direction is decided at commit, then FOLLOWS the live price — a    |
//|    box below it = demand = Buy (the entry sits INSIDE the top edge — |
//|    see the P-BK-51 bullet above for the measure and the stop); a      |
//|    box above it = supply = Sell (mirrored). The BOX ITSELF is the     |
//|    hysteresis band: outside takes that side, inside keeps the current |
//|    one, so a price vibrating inside the box can never flicker the     |
//|    lines (the reason the dir was frozen before P-BK-13). Flips run in |
//|    the 500 ms pump (BaseKnotSyncBadges, Full + Lite) and instantly on |
//|    drag-release, and persist to the chart-scoped GV. A commit landing |
//|    with the price INSIDE the box resolves by entry side: the most    |
//|    recent close outside the box decides (from below → Buy, from    |
//|    above → Sell), mid-vs-price only as the last fallback.          |
//|  * Multi-instance: box ids are "<commitTFmin>_<tick>" (+ rand on   |
//|    collision), so any number of knots coexist; tails are split at  |
//|    the LAST underscore because ids themselves contain one.         |
//|  * Visibility: a box lives on EVERY timeframe (P-BK-60 —          |
//|    «این باکس در تایم های بالاتر هم نمایش داده بشه ... پیش فرض»).   |
//|    The old commit-TF mask ("that TF and every lower one", P-BK-01) |
//|    is retired in place: the anchors are real chart time/price, so  |
//|    a knot drawn on M5 is still on the chart on H1/D1 — exactly     |
//|    where it was drawn, only longer across the window.              |
//|  * BKMAGNET-OFF: NO magnet — click = corner, exactly like MT4's own |
//|    rectangle (snapping pulled corners to candle shadows).          |
//|  * Info label ("the base note"): chart-anchored, a GLANCE —           |
//|    "[<side> · <EngSL|node EngSL> 17.9 | 26.4 | N bars · M15 base ·    |
//|    FTR]" — the risk and the NAME of its source (P-BK-46/53), then    |
//|    the box' OWN HEIGHT in pips, bare (P-BK-57 — its hover names it,   |
//|    and it stays out when the risk IS that height), never a unit      |
//|    word and never a target list; the plan's legs are the TICKS on    |
//|    the chart (P-BK-50) and every leg's level/pips/R live in the box   |
//|    hover. The old "… 17.9 Pips | TP 12/25/51 …" field is retired in   |
//|    place (BKTAGTP-OFF, P-BK-54). P-BK-28 names the base's SIZE CLASS |
//|    (3 candles = a base, 9..12 = the 3 candles of the TF above; one    |
//|    or two candles = structure) and P-BK-47 names the NODE TYPE from |
//|    the SAME ladder: how many rungs the class stands above the TF the |
//|    node is SEEN ON (0 = FTR, 1 = ETR, 2 = CTR, 3+ = OTR) — the type |
//|    IS the length, so no chart TF can move it, and the movement steps |
//|    (= ATR, pushed in by the pump layers — ATR sits above this      |
//|    module, so it is never read here) only size the break story's    |
//|    numbers (and the side the trade rides, P-BK-46).                |
//|    Auto (default)                                                  |
//|    shows it live while sizing + 4 s after commit, then hides it so  |
//|    the chart stays clean (Base Box card INFO row pins it on); full  |
//|    numbers always ride the box/edge hover tooltips. Its SIZE is the |
//|    user's (P-BK-27: `inpBKInfoFontSize`, 0 = follow the Base Box    |
//|    text size — Base Box > Setup > INFO SIZE).                       |
//|    P-BK-58: the note has TWO HOMES and the user picks one on that   |
//|    same INFO row — the box' corner (rungs 0/1) or the LABEL         |
//|    FAMILY'S OWN COLUMN next to the TRex trade card (rung 2,         |
//|    «گوشهٔ ثابت»). Same text, same writer, ONE object at a time; the  |
//|    corner row answers the SELECTED box (the newest while none is     |
//|    selected, the box being SIZED always), and its slot is PUSHED IN  |
//|    by the label module, which owns that column.                    |
//|    ENTRY and SL are      |
//|    OBJ_TREND rays (RAY_RIGHT, width BK_LEVEL_WIDTH — P-BK-50)       |
//|    anchored at the box right edge; the plan's TARGETS (TP1..TP3,    |
//|    one short thick tick each at the chart's right edge) are the     |
//|    same family without RAY_RIGHT. All BACK + unselectable.          |
//|  * P-BK-59 (2026-09-16) — THE CENTRE GRIP WEARS THE BORDER INK.   |
//|    «این نقطه وسط باکس به رنگ سفید هستش توی پس زمینه سفید به خوبی    |
//|    دیده نمیشه همون رنگ بوردر بگیره»: that dot is not ours — it is  |
//|    MetaTrader's OWN selection marker (a 2x2 WHITE square at the     |
//|    centre of a selected rectangle), and the terminal gives the EA no |
//|    colour for it. The marker is painted WITH the object, so it sits  |
//|    below every rung above it (the amber edges already clip the       |
//|    corner markers), and a SCREEN square of our own, in the box'      |
//|    border ink, covers it whole. The grip mirrors the terminal — it   |
//|    exists exactly while MT4 would draw that marker (box unlocked AND |
//|    SELECTED) — rides the 500 ms pump and the drag's own child step.  |
//|  * Chain cleanup: deleting the BOX wipes every child in one        |
//|    ObjectsDeleteAll(prefix) call; deleting a CHILD self-heals it   |
//|    via BaseKnotSync. The BK layer is independent: HideAllTHObjects,|
//|    the L/F toggles, DeleteAllIndicatorObjects (non-deep), the      |
//|    emergency + incremental cleanups and the generic OBJECT_DELETE   |
//|    redraw trigger all skip "_BK_" names (see P-BK-01).              |
//|  * P-BK-71 (2026-09-17) — THE MARK IS A BOX AGAIN, AND NOTHING     |
//|    ELSE. «به جای ترند لاین باکس بزار بهتره» + «یک باکس خود          |
//|    متاتریدر باشه»: the P-BK-67 diagonal trend line is RETIRED IN    |
//|    PLACE (BKTREND-OFF) and the carrier is MT4's OWN rectangle       |
//|    again — moved and selected natively, exactly like the            |
//|    terminal's own box. Every custom point family goes with it:      |
//|    P-BK-59's centre cover (BKDOT-OFF), P-BK-61's corner chips       |
//|    (BKGRIP-OFF) and the P-BK-69 trendline points (BKPOINT-OFF)       |
//|    have no live call site any more — the keepers refuse to run,     |
//|    the drag carries nothing, the wipe only sweeps. The retired      |
//|    tails (mid chips, corners, G1/G2, DOT, P1/P2) have ONE table     |
//|    both readers walk, so a chart any older build wrote is clean     |
//|    after one re-attach. A trendline carrier a P-BK-67/68/69 build   |
//|    left behind is re-created as the rectangle from its own two      |
//|    anchors (no pixel moves) by the same migration.                  |
//|  * P-BK-72 (2026-09-17) — A NATIVE RESIZE SURVIVES THE RELEASE.     |
//|    «مال خود متاتریدر که اینطوریه»: the docs' own rule (anchor       |
//|    points change the size) means a corner/edge press is a RESIZE,   |
//|    and the P-BK-61b size heal — which fires on every release whose  |
//|    size moved — would spring it back to the press-time size         |
//|    («برمی‌گرده سر جای خودش», now on a native gesture). So the       |
//|    press measures its grab role again (BaseKnotGrabRole — live,      |
//|    but its consumer is the heal, NOT the retired cursor fallback),  |
//|    and the heal only fires when that role IS the body. A body move  |
//|    the magnet enlarged still heals; a resize the user asked for     |
//|    is left exactly where the hand let it go.                        |
//|  * P-BK-73 (2026-09-17) — THE COMMIT HANDS THE BOX ITS OWN MARKERS. |
//|    «این باکس ما مثل متاتریدر نیست» — the user's own screenshot:     |
//|    MT4's rectangle wears FIVE squares (the four corners and the     |
//|    centre, 7x7 px, one white pixel each) and ours wore NONE, so the |
//|    first corner grab — the whole native resize P-BK-72 measures —   |
//|    was one click away instead of zero. The terminal paints those    |
//|    markers for a SELECTED object only, and `BaseKnotCommit` never   |
//|    selected the box it had just built, while MT4's own rectangle is |
//|    still in edit mode the instant the draw is let go. One read-then-|
//|    write call at the commit's end (BaseKnotSelectBox — the mirror   |
//|    of P-BK-26's drop, and the ONE owner of the grant) closes it.    |
//|    The cost is MT4's own (P-UI-45): a selected object is moved by   |
//|    the terminal on any LATER drag anywhere on the chart until a     |
//|    click lands elsewhere — exactly what MT4's own rectangle does in |
//|    edit mode, with P-BK-63's outside-click drop as the way out.     |
//|  * P-BK-74 (2026-09-17) — THE BOX IS METATRADER'S OWN RECTANGLE.    |
//|    «یک باکس متاتریدر چطور ساخته میشه همون میخوام بزاری» +          |
//|    «باکس پیش فرض بدون fill باشه و بگراندش غیر فعال باشه»: the       |
//|    box was ONE OBJ_RECTANGLE painted in the CHART BACKGROUND colour |
//|    with four OBJ_TREND children drawing the border on top of it.    |
//|    That is not what the terminal's own Rectangle tool makes. Now    |
//|    the rectangle wears the border ink/style/width itself, FILL      |
//|    false (hollow) and BACK false (foreground) — the two properties  |
//|    the MQL4 Reference's own OBJ_RECTANGLE example sets as `fill`    |
//|    and `back`. ONE object, and the object the terminal draws IS the |
//|    object the user sees.                                            |
//|    The four trend-line edges (and the P-BK-18 settle heal that      |
//|    existed only because the border was a COPY of the box) are       |
//|    RETIRED IN PLACE — BKEDGE-OFF, six marked sites. The sizing      |
//|    rubber band is one rectangle again too, so what the user sizes   |
//|    is literally what he gets.                                       |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_TOOL_MQH
#define BASE_KNOT_TOOL_MQH
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
//--- BKNODERUNG-OFF (P-BK-75, 2026-09-17): P-BK-47 below IS RETIRED. It named the type
//--- by a RUNG DISTANCE, which was a DURATION in disguise; the user replaced it with the
//--- box' own HEIGHT against the movement abilities (that TF's own ATR) — see the
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
#define BK_NODE_NONE   0   // nothing claimed (no height / that TF's ATR not warm yet)
#define BK_NODE_FTR    1   // as long as the TRIGGER ability   — 0.25 x ATR
#define BK_NODE_ETR    2   // as long as the PATTERN ability   — 0.50 x ATR
#define BK_NODE_CTR    3   // as long as the STRUCTURE ability — 1.00 x ATR
#define BK_NODE_OTR    4   // LONGER than the structure ability (1.00 x ATR)
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
//--- P-BK-47/77/78/81: what the note's node read measures — ONE record per read, and it
//--- answers TWO different questions (never the same one twice):
//---   * the TYPE (`kind`) is the node's LENGTH — the box' own HEIGHT against the ATR of the
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
   double depStep;    // ... and that leg's reach past the edge, in movement steps (ATR)
   //--- P-BK-75/78: the box' HEIGHT (the length the user's rule compares) and the THREE
   //--- MOVEMENT ABILITIES of the node's own TIME it was compared against — the ATRs of
   //--- that rung, of the rung one step above it (the pattern time) and of the rung two
   //--- above (the structure time), in price units; 0 = the pump never pushed that row, or
   //--- pushed it while the ATR was not warm. Published on the record so the tooltip can
   //--- spell the comparison without a second read.
   double   height;   // top - bot — «طول گره» is «ارتفاع باکس»
   double   abTrig;   // the node's own time's ATR — the trigger ability
   double   abPat;    // the pattern time's ATR — one rung above
   double   abStr;    // the structure time's ATR — two rungs above
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
//--- course measures every one of the four types with ATR («گام حرکتی»), and
//--- ATR lives ABOVE this module (ATRCalculations) — the layer law, so this
//--- module never reads it: the pump layers PUSH the current chart TF's step in
//--- (BiotakKit / EventHandlers, both above ATRCalculations). 0 = unknown, and
//--- everything that needs it then stays QUIET instead of guessing: a wrong
//--- size is a wrong knot type (the course's own entry rule — «فاصله ی یک ATR
//--- یا APR» — has no distance without it). `s_bkNodeBar` is the bar the last
//--- node read ran for: the read is CLOSED-BAR data, so a new bar (or a fresh
//--- step) is the only thing that can move a type, and the pump compares that
//--- once per round, not once per box.
static double      s_bkStepATR    = 0.0;
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
//--- DIFFERENT EngSL/HuntSL/TP — and different ladder ATRs for their types — so a TF-keyed
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
string BaseKnotTPName(const string pfx)    { return pfx + "TP"; }   // BKTPR-OFF: the retired single tick — kept as the name the purge deletes
string BaseKnotTPTickName(const string pfx, const int k) { return pfx + "TP" + IntegerToString(k); }   // P-BK-50: TP1..TP3, one tick each
string BaseKnotBuyName(const string pfx)   { return pfx + "BUY"; }
string BaseKnotDelName(const string pfx)   { return pfx + "DEL"; }
string BaseKnotInfoName(const string pfx)  { return pfx + "INFO"; }
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
                          const string riskTag, const string nodeLine, const string entryLine)
{
   int k = BaseKnotFind(id);
   int tfMin = (k >= 0 ? g_bkBoxes[k].tfMin : 0);
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);
   // P-BK-51: the first line states the STOP's own two facts (its size and where it sits),
   // and `entryLine` — the SAME sentence the note's hover reads — states the entry's.
   string tt = "Base box " + side + " · " + DoubleToString(hPips, 1) + " pips (the STOP: one " + riskTag +
               " behind the entry, INSIDE the box) · BOTH legs sit INSIDE the box" + entryLine +
               (sp.life > 0 ? " · " + IntegerToString(sp.life) + " bars" : "");
   tt += "\n" + TimeToString(t1, TIME_DATE|TIME_MINUTES) + " -> " + TimeToString(t2, TIME_DATE|TIME_MINUTES);
   tt += BaseKnotBaseLine(sp.still, t1, t2, top, bot);   // P-BK-80: the class, off the BOX' own two anchors (the node's own time, the same on every chart)
   if(sp.life > 0)   // P-BK-40/41/42: what the note's number is MADE OF, and HOW it is counted
      tt += "\n     " + IntegerToString(sp.life) + " bars = the candles between the ENTRY candle " +
            "and the EXIT candle (entry not counted, exit counted) · " + IntegerToString(sp.still) +
            " of them stood still inside the band (the base's own length — NOT the class' input: "
            "P-BK-80 reads the class on the box' own span, so the chart cannot move it)";
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

//+------------------------------------------------------------------+
//| Direction — decided at commit, then FOLLOWS the live price (see   |
//| the resolver below + BaseKnotRefreshDirection). Positional rule:  |
//| price above the box = Buy, below = Sell. Price INSIDE resolves by |
//| entry side (most recent close outside: from below → Buy, from      |
//| above → Sell); mid-vs-price is the last fallback. Boxes fully     |
//| outside keep following afterwards — the box itself is the          |
//| hysteresis band, so in-box vibration never flickers the lines.    |
//+------------------------------------------------------------------+
int BaseKnotResolveDirection(const double top, const double bot)
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   if(ref > top) return 1;
   if(ref > 0 && ref < bot) return -1;
   if(ref > 0)   // inside the box (or exactly on an edge): entry side decides
   {
      for(int s = 1; s <= BK_DIR_LOOKBACK; s++)
      {
         double c = iClose(_Symbol, 0, s);
         if(c <= 0) continue;
         if(c < bot) return 1;    // rose into the box from below → demand → Buy
         if(c > top) return -1;   // fell into the box from above → supply → Sell
      }
      double mid = (top + bot) / 2.0;
      return (mid <= ref ? 1 : -1);
   }
   return 1;   // no live price at all — harmless default
}

//+------------------------------------------------------------------+
//| Live reference price — forming-bar close first (the freshest      |
//| chart price), g_currentPrice fallback (EventHandlers refreshes it |
//| per tick; the 500 ms pump also runs on the timer path with zero   |
//| ticks). <= 0 = no usable data — the caller must keep, never flip. |
//+------------------------------------------------------------------+
double BaseKnotLiveRef()
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   return ref;
}

//+------------------------------------------------------------------+
//| Auto-follow (P-BK-13): the box itself is the hysteresis band —    |
//| fully outside takes that side, inside (or on an edge) keeps the   |
//| current one. No extra buffer to tune, no new inputs.              |
//+------------------------------------------------------------------+
int BaseKnotFollowDirection(const double top, const double bot, const int curDir, const double ref)
{
   if(ref <= 0) return curDir;   // weekend / data gap — never flip blind
   if(ref > top) return 1;       // box fully below the price = demand = Buy
   if(ref < bot) return -1;      // box fully above it = supply = Sell
   return curDir;                // inside — keep, so vibration can't flicker
}
// Refresh one box's dir from the live price. Returns true on a real flip
// (dir + chart-scoped GV persisted; the caller Syncs to rebuild the
// Entry/SL/TP lines, tooltips and INFO). Lite-safe: Object* + GV only.
bool BaseKnotRefreshDirection(const string id, const double ref)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(p1 <= 0 || p2 <= 0) return false;
   // P-BK-46: A KNOT WHOSE BREAK'S STORY NAMES A SIDE IS NOT THE PRICE'S TO FLIP. The
   // story's answer (BaseKnotNodeDir) is published by Sync, so the live-price follow
   // below speaks only for a base with no break measured yet (P-BK-13's own case).
   // P-BK-47: the TYPE no longer answers this question — it is the node's LENGTH, and a
   // length is not a side. Keeping the retired `nodeKind` gate here (BKNODEDIR-OFF) would
   // freeze every box the moment it was classed.
   if(g_bkBoxes[k].nodeSide != 0) return false;
   int want = BaseKnotFollowDirection(MathMax(p1, p2), MathMin(p1, p2), g_bkBoxes[k].dir, ref);
   if(want == g_bkBoxes[k].dir) return false;
   g_bkBoxes[k].dir = want;
   GlobalVariableSet(BaseKnotGV(id), (double)want);
   return true;
}

//+------------------------------------------------------------------+
//| Registry helpers                                                  |
//+------------------------------------------------------------------+
int BaseKnotFind(const string id)
{
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
      if(g_bkBoxes[i].id == id) return i;
   return -1;
}
//--- BKDOT-OFF/BKGRIP-OFF/BKPOINT-OFF (P-BK-71) — THE RETIRED POINT TAILS: ONE table,
//--- TWO readers (the once-per-attach sweep in BaseKnotLazyInit and the deselect wipe in
//--- BaseKnotSelectionMarkersWipe). Every selectable square this module EVER drew is named
//--- here, so a chart any older build wrote cannot keep one: mid-edge chips (BKMIDGRIP-OFF),
//--- corner chips (BKGRIP2/BKGRIP-OFF), trendline ends (P-BK-68: G1/G2), the centre cover
//--- (P-BK-59/BKDOT-OFF: DOT) and the trendline points (P-BK-69/BKPOINT-OFF: P1/P2).
//--- Lives HERE (above the first reader) because MQL4 needs the define before use.
#define BK_RETIRED_POINTS 13
string BaseKnotRetiredPointName(const int i)
{
   string tails[BK_RETIRED_POINTS] = {"GT", "GB", "GL", "GR", "GTL", "GTR", "GBL", "GBR",
                                      "G1", "G2", "DOT", "P1", "P2"};
   if(i < 0 || i >= BK_RETIRED_POINTS) return "";
   return tails[i];
}
void BaseKnotRegister(const string id, const int dir, const int tfMin)
{
   if(BaseKnotFind(id) >= 0) return;
   int n = ArraySize(g_bkBoxes);
   ArrayResize(g_bkBoxes, n + 1);
   g_bkBoxes[n].id    = id;
   g_bkBoxes[n].dir   = (dir < 0 ? -1 : 1);
   g_bkBoxes[n].tfMin = tfMin;
   g_bkBoxes[n].commitMs = GetTickCount();   // fresh commit → Auto INFO grace starts now
   g_bkBoxes[n].locked = false;              // fresh boxes are always unlocked
   g_bkBoxes[n].nodeKind = BK_NODE_NONE;     // P-BK-29/47: no type published yet
   g_bkBoxes[n].nodeSide = 0;                // P-BK-46/47: no break's side published yet
   g_bkBoxes[n].baseTFMin = 0;               // P-BK-36/49: no class published yet
   g_bkBoxes[n].biasState = BK_STATE_UNKNOWN;   // P-BK-48/49: no life state measured yet
   g_bkBoxes[n].storyT = 0;                  // P-BK-41/49: no story candle published yet
   g_bkBoxes[n].exitT  = 0;                  // P-BK-81: no exit candle published yet
   GlobalVariableSet(BaseKnotGV(id), (double)g_bkBoxes[n].dir);
}
void BaseKnotUnregister(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   for(int i = k; i < ArraySize(g_bkBoxes) - 1; i++) g_bkBoxes[i] = g_bkBoxes[i + 1];
   ArrayResize(g_bkBoxes, ArraySize(g_bkBoxes) - 1);
   GlobalVariableDel(BaseKnotGV(id));
}
// Lock — a locked box is unselectable so it can never be dragged (hold still
// opens the mini strip, so it can always be unlocked). The flag rides the BOX
// handle's own SELECTABLE bit: no GV, survives TF-switches and restarts.
bool BaseKnotLocked(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   return g_bkBoxes[k].locked;
}
void BaseKnotSetLocked(const string id, const bool on)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   g_bkBoxes[k].locked = on;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, !on);
   BaseKnotSync(id);   // rebuild the live tooltip (coords · TF-scope · text · lock)
   ChartRedraw();
}
// Rebuild the registry from chart objects once (TF-switch safe: the box
// anchors ARE the spec, direction rides a chart-scoped GV, TF rides the id).
// Also purges the transient PREVIEW/HINT of a dead session (state resets on
// reload, so a reloaded indicator must never inherit a ghost rubber-band)
// and sweeps orphan direction-GVs of this chart whose boxes are gone.
void BaseKnotLazyInit()
{
   if(g_bkInitDone) return;
   g_bkInitDone = true;
   if(StringLen(inpObjectPrefix) == 0) return;
   string tag = inpObjectPrefix + BK_TAG;
   BaseKnotWipePreview();
   BaseKnotWipeLive();   // dead-session transients — never inherited
   ObjectDelete(0, BaseKnotHintName());
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, tag) != 0) continue;
      if(StringFind(nm, "BOX", StringLen(nm) - 3) < 0) continue;
       string id = StringSubstr(nm, StringLen(tag), StringLen(nm) - StringLen(tag) - 4);
       int dir = 1;
       if(GlobalVariableCheck(BaseKnotGV(id)))
          dir = ((int)GlobalVariableGet(BaseKnotGV(id)) < 0 ? -1 : 1);
       else
       {
          // No frozen value (pre-GV box or a wiped GV): resolve positionally
          // exactly like a fresh commit instead of blindly defaulting to Buy —
          // Register persists it, so the rebuild is stable from here on.
          double iA = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
          double iB = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
          dir = BaseKnotResolveDirection(MathMax(iA, iB), MathMin(iA, iB));
       }
       BaseKnotRegister(id, dir, BaseKnotIdTF(id));
      int q = BaseKnotFind(id);
      if(q >= 0)
      {
         g_bkBoxes[q].commitMs = 0;   // inherited box — long ago, no Auto grace flash
         g_bkBoxes[q].locked = (ObjectGetInteger(0, nm, OBJPROP_SELECTABLE) == 0);   // lock rides the handle itself — no GV, survives TF-switch/restart
      }
   }
   // P-BK-71 MIGRATION — A TRENDLINE CARRIER BECOMES THE BOX, ONCE PER ATTACH.
   // A chart saved by a P-BK-67/68/69 build carries the OBJ_TREND carrier; the carrier IS
   // the box again, so it is re-created as a RECTANGLE from its own two anchors (the
   // very same time/price, so no knot moves a pixel) and the trendline era's point
   // tails are swept — nothing re-creates them any more (BKPOINT-OFF), so without this
   // pass a saved chart would keep squares that no drag, no restyle and no Sync of the
   // new build would ever touch again. Name lookups + Object* only, and the re-sync
   // loop right below repaints the migrated family in the same attach.
   for(int mg = 0; mg < ArraySize(g_bkBoxes); mg++)
   {
      string mgPfx = BaseKnotPrefix(g_bkBoxes[mg].id);
      if(mgPfx == "") continue;
      string mgBox = BaseKnotBoxName(mgPfx);
      if(ObjectFind(0, mgBox) >= 0 &&
         (ENUM_OBJECT)ObjectGetInteger(0, mgBox, OBJPROP_TYPE) != OBJ_RECTANGLE)
      {
         datetime mgT1 = (datetime)ObjectGetInteger(0, mgBox, OBJPROP_TIME, 0);
         datetime mgT2 = (datetime)ObjectGetInteger(0, mgBox, OBJPROP_TIME, 1);
         double   mgP1 = ObjectGetDouble(0, mgBox, OBJPROP_PRICE, 0);
         double   mgP2 = ObjectGetDouble(0, mgBox, OBJPROP_PRICE, 1);
         bool     mgSel = (bool)ObjectGetInteger(0, mgBox, OBJPROP_SELECTED);
         ObjectDelete(0, mgBox);
         if(mgT1 > 0 && mgT2 > 0 && mgP1 > 0 && mgP2 > 0 &&
            ObjectCreate(0, mgBox, OBJ_RECTANGLE, 0, mgT1, mgP1, mgT2, mgP2))
         {
            BaseKnotStyleBox(mgBox);
            ObjectSetInteger(0, mgBox, OBJPROP_SELECTABLE, !g_bkBoxes[mg].locked);
            ObjectSetInteger(0, mgBox, OBJPROP_SELECTED, mgSel);
         }
      }
      for(int m = 0; m < BK_RETIRED_POINTS; m++)
      {
         string mtail = BaseKnotRetiredPointName(m);
         if(mtail == "") continue;
         string robj = mgPfx + mtail;
         if(ObjectFind(0, robj) >= 0) ObjectDelete(0, robj);
      }
   }
   // BKMIDGRIP-OFF (2026-09-16) — RETIRED-PAIR SWEEP, ONCE PER ATTACH.
   // Superseded by the table walk above (P-BK-71): the four mid-edge chips are four
   // of the table's thirteen tails now, swept for every box on the same pass.
   // BKMIDGRIP-OFF: for(int b = 0; b < ArraySize(g_bkBoxes); b++)
   // BKMIDGRIP-OFF: {
   // BKMIDGRIP-OFF:    string midPfx = BaseKnotPrefix(g_bkBoxes[b].id);
   // BKMIDGRIP-OFF:    if(midPfx == "") continue;
   // BKMIDGRIP-OFF:    string midNames[4] = {"GT", "GB", "GL", "GR"};
   // BKMIDGRIP-OFF:    for(int m = 0; m < 4; m++)
   // BKMIDGRIP-OFF:    {
   // BKMIDGRIP-OFF:       string mid = midPfx + midNames[m];
   // BKMIDGRIP-OFF:       if(ObjectFind(0, mid) >= 0) ObjectDelete(0, mid);
   // BKMIDGRIP-OFF:    }
   // BKMIDGRIP-OFF: }
   // P-BK-06 migration: hollow-by-construction (bg handle + edge segments) —
   // every inherited box is re-synced once so pre-edge boxes gain their
   // border edges and lose their visible fill immediately, no drag needed.
   for(int b = 0; b < ArraySize(g_bkBoxes); b++) BaseKnotSync(g_bkBoxes[b].id);
   // Orphan-GV sweep (this chart only — the GV carries the chart id suffix).
   string cid = GetCachedChartIdStr();
   for(int k = GlobalVariablesTotal() - 1; k >= 0; k--)
   {
      string gv = GlobalVariableName(k);
      if(StringFind(gv, "Biotak_BK_") != 0) continue;
      if(StringFind(gv, "_" + cid, StringLen(gv) - StringLen(cid) - 1) < 0) continue;
      string oid = StringSubstr(gv, 10, StringLen(gv) - 10 - StringLen(cid) - 1);
      if(BaseKnotFind(oid) < 0) GlobalVariableDel(gv);
   }
}

//+------------------------------------------------------------------+
//| Hint bar (bottom-left): guidance while sizing, auto-hiding result.|
//| Amber on dark charts is unreadable on light ones — pick the text   |
//| color from the chart background luminance. Result hints ("BASE #N  |
//| set") expire after 4 s so the corner never nags; guidance hints   |
//| stay until the session ends.                                       |
//+------------------------------------------------------------------+
static uint g_bkHintExpireMs = 0;   // 0 = persistent; else GetTickCount deadline
// Readable foreground for chart-anchored texts (hint + INFO label) — amber on
// dark charts, dark brown on light ones (same luminance gate, one place).
color BaseKnotFgForBg()
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int lum = ((((int)bg) & 0xFF) * 299 + ((((int)bg) >> 8) & 0xFF) * 587 +
              ((((int)bg) >> 16) & 0xFF) * 114) / 1000;
   return (lum > 128 ? C'150,70,0' : C'255,171,0');
}
void BaseKnotHintShow(const string text, const int ttlMs = 0)
{
   string hn = BaseKnotHintName();
   if(hn == "") return;
   if(ObjectFind(0, hn) < 0) ObjectCreate(0, hn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hn, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, 44);
   ObjectSetString(0, hn, OBJPROP_TEXT, text);
   ObjectSetString(0, hn, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, hn, OBJPROP_FONTSIZE, PnlPt(BK_PT_HINT));
   ObjectSetInteger(0, hn, OBJPROP_COLOR, BaseKnotFgForBg());
   ObjectSetInteger(0, hn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_BACK, false);
   ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_BOX_HINT);   // P-UI-31: under the settings card
   g_bkHintExpireMs = (ttlMs > 0 ? GetTickCount() + (uint)ttlMs : 0);
   ChartRedraw();
}
void BaseKnotHintHide()
{
   ObjectDelete(0, BaseKnotHintName());
   g_bkHintExpireMs = 0;
   ChartRedraw();
}
// Per-tick expiry pump (called from RefreshUIPerTick's 500 ms block).
void BaseKnotHintTick()
{
   if(g_bkHintExpireMs == 0) return;
   if((int)(GetTickCount() - g_bkHintExpireMs) >= 0) BaseKnotHintHide();
}

//+------------------------------------------------------------------+
//| Chart lock — MT4-like: while a gesture is active (drawing a new   |
//| box OR dragging a committed one) the view must not slide under    |
//| the hand. MOUSE_SCROLL blocks drag-panning, AUTOSCROLL suspend    |
//| stops live ticks from shifting the chart mid-gesture (restoring   |
//| it only re-arms the snap-to-live the ticks would have done        |
//| anyway). First locker saves, nested locks only re-assert, one     |
//| Unlock restores — so session and drag locks can never corrupt     |
//| each other's saved values. ctxToo=false for IDLE drags (the chart |
//| context menu stays available there, unlike in a draw session).    |
//+------------------------------------------------------------------+
void BaseKnotLockChart(const bool ctxToo)
{
   if(!s_bkChartLocked)
   {
      g_bkAutoWas = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
      s_bkChartLocked = true;
      ChartViewLockAcquire();   // P-UI-90: scroll + context menu have ONE owner
   }
   if(g_bkAutoWas && (ChartGetInteger(0, CHART_AUTOSCROLL) != 0))
      ChartSetInteger(0, CHART_AUTOSCROLL, false);
   if(ctxToo && (bool)ChartGetInteger(0, CHART_CONTEXT_MENU))
      ChartSetInteger(0, CHART_CONTEXT_MENU, false);
   g_bkTouched = true;   // OnDeinit must restore, whatever happens
}
void BaseKnotUnlockChart()
{
   if(!s_bkChartLocked) return;
   ChartViewLockRelease();   // P-UI-90: hands the view back only when NO owner is left
   if(g_bkAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, true);
   s_bkChartLocked = false;
}
// Re-assert an OWNED lock (P-BK-14): a one-time lock is not enough — third
// writers (menu modal unlock when a strip/card closes mid-gesture, the panel
// watchdog restore, template/terminal resets) can flip the props back while
// the button is still down, and the chart then pans under the hand for the
// rest of the gesture. While we own it, every throttled step re-forces the
// props. Read-guarded: steady state costs only the reads, writes happen
// solely on drift. ctxToo mirrors the original locker (session=true, drag=false).
void BaseKnotReassertLock(const bool ctxToo)
{
   if(!s_bkChartLocked) return;
   ChartViewLockAssert();   // P-UI-90: read-guarded, one owner for scroll + ctx
   if(g_bkAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
   { ChartSetInteger(0, CHART_AUTOSCROLL, false); g_bkTouched = true; }
   if(ctxToo && ChartGetInteger(0, CHART_CONTEXT_MENU) != 0)
   { ChartSetInteger(0, CHART_CONTEXT_MENU, false); g_bkTouched = true; }
}
// IDLE box-drag holder: lock once a REAL drag starts (past slop — taps never
// flicker the props), release on button-up. The state check keeps a drag
// release from unlocking a draw session's lock in the pathological overlap.
// P-BK-62 (2026-09-16): AN OWNED DRAG LOCK IS RE-ASSERTED ON EVERY STEP — the
// P-BK-14 rule, extended from the draw session to the drag/resize the session is
// NOT running. The one-time lock is not enough for exactly the reasons P-BK-14
// recorded (a panel release, a modal card, a template reset can flip the props
// back while the button is still down), and here it was worse than a leak: the
// guard below early-returns once `s_bkDragLock` is set, so a single third-writer
// flip left the chart panning under the hand for the REST of the gesture with
// nothing left to take the lock back. Read-guarded through `ChartViewLockAssert`
// (the props' ONE owner): steady state is two property reads per throttled step,
// a write only on drift.
void BaseKnotDragLockOn()
{
   if(s_bkDragLock)
   {
      BaseKnotReassertLock(false);   // P-BK-62: owned — re-force, never re-capture
      return;
   }
   if(g_bkState != BK_IDLE) return;   // taps/sessions never take the drag lock
   BaseKnotLockChart(false);
   s_bkDragLock = true;
}
// P-BK-65: THE GESTURE STATE HAS ONE OWNER, and teardown is one of its four callers
// (the others are the release, the watchdog and the terminal-named box drag). Called
// from OnDeinit (every reason) and from BaseKnotCancel: a removed or cancelled instance
// must not hand a stale "this press is a resize" answer to the next attach. No chart
// write, no probe — three stores.
void BaseKnotGestureClear()
{
   s_bkGripGesture = 0;
   s_bkGripLive    = 0;
   s_bkBoxNamed    = false;
   s_bkDragMoved   = false;
}
void BaseKnotDragLockOff()
{
   if(!s_bkDragLock || g_bkState != BK_IDLE) return;
   s_bkDragLock = false;
   BaseKnotUnlockChart();
}

//+------------------------------------------------------------------+
//| Arm / cancel — called from the Tools-ring click (menu side hides  |
//| the ring first). Raw Chart* scroll lock: no menu dependency, so   |
//| Lite compiles and keeps working on committed boxes.               |
//+------------------------------------------------------------------+
void BaseKnotArm()
{
   BaseKnotLazyInit();
   g_bkState   = BK_ARMED;
   g_bkArmedMs = GetTickCount();
   g_bkLeftPrev = true;   // the arming press is still down — never take its release as click 1
   g_bkHeld = false;
   g_bkLiveT = 0; g_bkLiveP = 0.0;
   BaseKnotLockChart(true);   // no chart slide under the hand while drawing
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   // No bottom hint while armed either (user: nothing is written at the
   // bottom — guidance lives in the ring tooltip, errors stay silent).
   // BaseKnotHintShow("BASE TOOL — press + drag (release = done) · or click 2 corners · right-click / ESC: cancel");
   ChartRedraw();
}
void BaseKnotCancel()
{
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   BaseKnotHintHide();
   g_bkState = BK_IDLE;
   g_bkHeld = false;
   BaseKnotGestureClear();   // P-BK-65: a cancelled session leaves no gesture answer behind
   BaseKnotUnlockChart();
   g_bkRestoreReq = true;   // UI side re-shows the hidden ring menu
   ChartRedraw();
}

// Deinit safety (call from OnDeinitHandler, every reason): a remove /
// TF-switch / crash-reload mid-session must never leave the chart scroll
// locked, a ghost rubber-band behind, or a stale restore flag. Committed
// boxes are the independent layer and stay untouched here (REMOVE wipes
// them via DeleteAllIndicatorObjects(true) + the Biotak_BK_* GV sweep).
void BaseKnotOnDeinit(const int reason)
{
   BaseKnotUnlockChart();   // every reason — a stuck lock must never survive a switch/remove
   g_bkTouched = false;
   s_bkDragLock = false;
   s_bkDragId = ""; s_bkDragMoved = false;
   BaseKnotGestureClear();   // P-BK-65: no gesture state outlives the instance either
   g_bkState = BK_IDLE;
   g_bkRestoreReq = false;
   g_bkHeld = false;
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   ObjectDelete(0, BaseKnotHintName());
   BaseKnotCornerWipe();   // P-BK-58: the family's row is the chart's, not a box child — a remove /
                           // TF switch must never leave a ghost note behind (nor a "nothing changed"
                           // marker that would keep the next init from rebuilding it)
   if(reason == REASON_REMOVE) ArrayResize(g_bkBoxes, 0);
}

//+------------------------------------------------------------------+
//| Border edges — the VISIBLE box outline (finite segments, never a |
//| ray). Ensure-create + move + style in one call, so drag-sync,     |
//| restyle-all and child-delete-heal all rebuild missing edges.      |
//+------------------------------------------------------------------+
void BaseKnotMakeEdge(const string name, const datetime t1, const double p1,
                      const datetime t2, const double p2,
                      const color clr, const int style, const int width,
                      const string tooltip, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX rect is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);   // the visible border always reads (like TH lines + MT4 tools)
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_EDGE);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
// Draw/refresh the 4 outline edges under one tag (committed pfx or preview
// tag) — the hollow look on builds that ignore FILL (P-BK-06).
// BKEDGE-OFF (P-BK-74) — DORMANT, DEAD BY CONSTRUCTION: the border is the box'
// OWN outline now (BaseKnotStyleBox wears the border ink), so no call site draws
// this family any more. The body stays compiled and whole so a restore is ONE
// uncomment — the `BaseKnotDrawEdges(pfx, ...)` call in BaseKnotSync.
void BaseKnotDrawEdges(const string tag, datetime t1, const double p1,
                       datetime t2, const double p2,
                       const color clr, const int style, const int width,
                       const string tooltip, const long tfMask)
{
   if(tag == "") return;
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   BaseKnotMakeEdge(tag + BK_EDGE_T, t1, top, t2, top, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_B, t1, bot, t2, bot, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_L, t1, bot, t1, top, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_R, t2, bot, t2, top, clr, style, width, tooltip, tfMask);
}
//+------------------------------------------------------------------+
//| P-BK-74 (2026-09-17) — THE PREVIEW IS ONE RECTANGLE AGAIN.         |
//|                                                                   |
//| The sizing rubber band used to be four OBJ_TREND edges too (the    |
//| "legacy single-rect preview" the two call sites kept deleting).    |
//| With the edges retired it goes back to the family it belongs to:   |
//| ONE OBJ_RECTANGLE, hollow, foreground, wearing the final look —    |
//| the same object the commit will hand over, so what the user sizes  |
//| is literally what he gets. Ensure-create + move + style in one     |
//| call, so a TF switch or a deleted object heals on the next frame.  |
//| It carries NO selection: the terminal marks nothing while sizing,  |
//| and `BaseKnotCommit` is the one place the selection is granted     |
//| (P-BK-73).                                                        |
//+------------------------------------------------------------------+
void BaseKnotDrawPreviewRect(const string tag, const datetime t1, const double p1,
                             const datetime t2, const double p2,
                             const color clr, const int style, const int width,
                             const string tooltip, const long tfMask)
{
   if(tag == "") return;
   if(ObjectFind(0, tag) < 0) ObjectCreate(0, tag, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectMove(0, tag, 0, t1, p1);
   ObjectMove(0, tag, 1, t2, p2);
   ObjectSetInteger(0, tag, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, tag, OBJPROP_STYLE, style);
   ObjectSetInteger(0, tag, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, tag, OBJPROP_FILL, false);        // hollow — the user's own default
   ObjectSetInteger(0, tag, OBJPROP_BACK, false);        // foreground
   ObjectSetInteger(0, tag, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetInteger(0, tag, OBJPROP_SELECTABLE, false);  // nothing is selected until the commit
   ObjectSetInteger(0, tag, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, tag, OBJPROP_ZORDER, Z_BOX_EDGE);
   ObjectSetString(0, tag, OBJPROP_TOOLTIP, tooltip);
}
//+------------------------------------------------------------------+
//| Children geometry — single source of truth for commit / drag-sync.|
//| P-BK-51 (2026-09-15) — BOTH LEGS SIT INSIDE THE KNOT, and the      |
//| PENETRATION the entry waits for is named by the node's own TYPE.   |
//| The user's rule, word for word: «برای گره اف تی ار میشه به اندازه    |
//| engsl محل ورود داخل گره و به اندازه engsl از محل ورود استاپ» +      |
//| «و برای گره etr میشه به اندازه huntsl محل ورود و به اندازه engsl از|
//| محل ورود میشه استاپ لاسش» + «و برای نوع هی بعدی بای از engsl ,     |
//| huntsl یک تایم بالاتر استفاده کرده». So:                            |
//|   * THE EDGE IS THE SIDE'S OWN EDGE — the one the departure left   |
//|     by (BaseKnotNodeDir / P-BK-49; top for a Buy, bottom for a     |
//|     Sell: WHICH side that is is the PATTERN's call, never a type). |
//|   * BOTH LEGS ARE INSIDE, measured from it:                        |
//|       Buy : Entry = top - offset, SL = Entry - EngSL               |
//|       Sell: Entry = bot + offset, SL = Entry + EngSL               |
//|   * THE OFFSET (the penetration the entry waits for) follows the   |
//|     node's TYPE:                                                   |
//|       FTR (and the live preview, which has no type yet) = ONE      |
//|           EngSL («به اندازه engsl ... داخل گره»);                  |
//|       ETR / CTR / OTR = ONE HuntSL («به اندازه huntsl محل ورود»);   |
//|   * THE STOP IS ALWAYS ONE EngSL BEHIND THE ENTRY, whichever of    |
//|     the two sized the entry («به اندازه engsl از محل ورود استاپ»);  |
//|   * A CTR/OTR NODE IS MEASURED ONE TF HIGHER than its own TF        |
//|     («برای نوع هی بعدی … یک تایم بالاتر») — BaseKnotMeasureTFMin    |
//|     owns that hop and is the only place it exists.                 |
//| Both numbers are PUSHED IN (EngSL / HuntSL per TF — trade-plan math|
//| sits ABOVE this module, the P-BK-46/50 ask / push pair), and a TF  |
//| the table cannot answer is NO LONGER the box' whole height: the     |
//| node's OWN power caps it (P-BK-52, BaseKnotLegPair) — the ABSENCE  |
//| never a guess. P-BK-50's geometry (entry ONE R OUTSIDE the edge,   |
//| the stop ON that edge) is SUPERSEDED IN PLACE by the two lines     |
//| below — the pair it replaced is kept verbatim under BKGEOM-OFF, one |
//| uncomment away. The TARGETS are the TRADE PLAN's own legs          |
//| (BaseKnotTPLevel — the TP1/TP2/TP3 the label's `#SL/-TP` row       |
//| prints for the same TF), measured from the entry exactly as that   |
//| row measures them; the old `TARGET R`-multiple target stays        |
//| RETIRED IN PLACE (BKTPR-OFF) and the SAME state picks how many of   |
//| the plan's legs are drawn (BaseKnotTPCount).                       |
//+------------------------------------------------------------------+
// P-BK-51 — WHICH TF'S NUMBERS SIZE THE TRADE. The knot's own TF is the class the note
// names (P-BK-46); a CTR/OTR knot — as long as the structure time or longer — is read
// ONE RUNG ABOVE that TF (the user's «یک تایم بالاتر»). One owner: the geometry, the
// pump's own TF list (BaseKnotEngNeeds) and every text that names the source ask HERE.
int BaseKnotMeasureTFMin(const int kind, const int tfMin)
{
   if(kind != BK_NODE_CTR && kind != BK_NODE_OTR) return tfMin;   // FTR/ETR: its own TF
   int up = BaseKnotNextTFMin(tfMin > 0 ? tfMin : Period());
   return (up > 0 ? up : tfMin);   // already at the ladder's top — the own TF stands
}
// P-BK-51 — DID THE ENTRY'S PENETRATION COME FROM THE HUNTER LEG? The TYPE asks (ETR and
// the longer CTR/OTR want HuntSL), the TABLE answers: a TF whose HuntSL was never pushed
// falls back to EngSL instead of inventing a size, and every text says so
// (BaseKnotEntryWhy). The FTR node and the box being SIZED are EngSL reads.
// P-BK-79: AND AT ONE ANCHOR. Every reader below takes the bar the row was pushed at
// (`anchor` — the box' own story end, 0 = the live row), because a TF-keyed read could only
// ever answer ONE of two boxes whose bases ended on different bars («با گذشت زمان ممکن 40
// بشه یا 10 بشه»). The default keeps the live callers byte-identical.
bool BaseKnotOffsetIsHunt(const int kind, const int tfMin, const datetime anchor = 0)
{
   if(kind == BK_NODE_FTR || kind == BK_NODE_NONE) return false;
   return (BaseKnotHuntPips(tfMin, anchor) > 0.0);
}
string BaseKnotEntryOffsetTag(const bool isHunt) { return (isHunt ? "HuntSL" : "EngSL"); }
// The penetration itself, in PIPS. 0 = nothing pushed for that (TF, anchor) — an ABSENCE
// the caller turns into the box' own height, exactly like the risk below.
double BaseKnotEntryOffsetPips(const int kind, const int tfMin, const datetime anchor = 0)
{
   if(BaseKnotOffsetIsHunt(kind, tfMin, anchor)) return BaseKnotHuntPips(tfMin, anchor);
   return BaseKnotEngPips(tfMin, anchor);
}
// P-BK-51 — WHY THE ENTRY WAITS THAT DEEP: the node's TYPE names the measure, and the
// number is never shown without the TF it was read on. ONE owner, so the box hover, the
// entry ray and the note's hover can never describe two different measurements.
string BaseKnotEntryWhy(const int kind, const int measureTF, const bool isHunt,
                        const double top, const double bot, const datetime anchor = 0)
{
   string what = BaseKnotEntryOffsetTag(isHunt);
   string tf   = BaseKnotTFName(measureTF > 0 ? measureTF : Period());
   string why;
   if(kind == BK_NODE_FTR)      why = "FTR — the node is the TRIGGER length: " + what + " of " + tf;
   else if(kind == BK_NODE_ETR) why = "ETR — the node is the PATTERN length: " + what + " of " + tf;
   else if(kind == BK_NODE_CTR) why = "CTR — the node is the STRUCTURE length: " + what + " of " + tf + ", one TF above the base";
   else if(kind == BK_NODE_OTR) why = "OTR — longer than the structure time: " + what + " of " + tf + ", one TF above the base";
   else                         why = "no type yet (the box is being sized): " + what + " of " + tf;
   if(!isHunt && kind != BK_NODE_FTR && kind != BK_NODE_NONE)
      why += " — no HuntSL pushed for " + tf + " yet, so EngSL stands in";
   why += BaseKnotCapClause(measureTF, isHunt, top, bot, anchor);   // P-BK-52: ... and the ceiling, when it spoke
   return why;
}
// ... and the SHORT form of the same fact — the box hover's first line and the note's
// own hover read THIS sentence, so "how deep" is answered once.
string BaseKnotEntryLine(const int kind, const int measureTF, const bool isHunt, const int dir,
                         const double top, const double bot, const datetime anchor = 0)
{
   return " · the entry waits ONE " + BaseKnotEntryOffsetTag(isHunt) + " INSIDE the box' " +
          (dir >= 0 ? "top" : "bottom") + " edge (" +
          BaseKnotEntryWhy(kind, measureTF, isHunt, top, bot, anchor) + ")";
}
// P-BK-52 (2026-09-16) — THE NODE'S OWN POWER IS THE CEILING OF BOTH LEGS.
// WHY: P-BK-46/51 push the plan's EngSL / HuntSL in, and a plan leg can be DEEPER than the
// node it is drawn in — a 9-pip node measured with EngSL(M15) = 17 pips put the entry 8 pips
// BEYOND the box' opposite edge while the hover still said «ONE EngSL INSIDE the box' top
// edge» (the user's «برای محل های ورود میگم که دقیق باشه»), and a TF the pump had never
// pushed fell back to the box' WHOLE height, putting the stop a whole box past the entry.
// WHAT: the node's OWN power is its height over the SAME divisor the plan divides its
// composite TR by (64/15), so the ceiling is the same UNIT as the leg it bounds — only
// sourced from the node instead of the market:
//   EngSL_node  = H / 4.266666                    (BK_NODE_POWER_DIV)
//   HuntSL_node = 8/3 x EngSL_node = H x 5/8      (BK_NODE_HUNT_NUM / BK_NODE_HUNT_DEN)
//   leg = min(planLeg, nodeLeg)                   (BaseKnotLegPick — the only rule)
// A node BIGGER than the plan's leg keeps the plan's number exactly (nothing a user sees
// today moves); a node SMALLER than it is sized by its own power. And because
//   off + risk <= HuntSL_node + EngSL_node = (5/8 + 15/64) x H = 55/64 x H < H,
// BOTH legs sit strictly inside the box on EVERY node type — no reserve percentage, no clamp
// constant and no per-type special case.
// THE GATE: the divisor belongs to the plan and the layering law forbids reading
// TradePlanFormulas from this module, so the constants below are kept IN SYNC (and the 55/64
// bound PROVEN from them) by tools/base-count-audit.py [leg-fit], which reads both files —
// drift fails the build, not the chart.
// ONE OWNER: BaseKnotLegPair is the only place the two sizes are decided; the geometry
// (BaseKnotCalcLevels), the R every hover prints (BaseKnotRiskPips), the NAME of that R
// (BaseKnotRiskTag), the stop's sentence (BaseKnotStopWhy) and the entry's
// (BaseKnotEntryWhy / BaseKnotCapClause) all read IT — no line and no number can describe
// two different measurements.
#define BK_NODE_POWER_DIV 4.266666   // == TradePlanFormulas TRADEPLAN_ENG_DIVISOR (gate: leg-fit)
#define BK_NODE_HUNT_NUM  5.0        // 8/3 / 4.266666 == 5/8 exactly — the NODE's own HuntSL
#define BK_NODE_HUNT_DEN  8.0        // ... against the plan's 8/3 (gate: leg-fit keeps one unit)
// The node's own power, in pips — its height over the plan's own Eng divisor. 0 when the box
// has no height yet or the symbol has no pip size: an ABSENCE every caller's fallback names.
double BaseKnotNodeEngPips(const double top, const double bot)
{
   double pip = BaseKnotPipSize();
   if(pip <= 0.0 || BK_NODE_POWER_DIV <= 0.0) return 0.0;
   double h = (top - bot) / pip;
   return (h > 0.0 ? h / BK_NODE_POWER_DIV : 0.0);
}
double BaseKnotNodeHuntPips(const double top, const double bot)
{
   double pip = BaseKnotPipSize();
   if(pip <= 0.0 || BK_NODE_HUNT_DEN <= 0.0) return 0.0;
   double h = (top - bot) / pip;
   return (h > 0.0 ? BK_NODE_HUNT_NUM * h / BK_NODE_HUNT_DEN : 0.0);
}
// THE RULE, in one place — the plan's leg when it is no deeper than the node's own power, the
// node's own power when it is. 0 = BOTH absent (the caller falls back, and NAMES it).
bool BaseKnotLegCapped(const double planPips, const double capPips)
{
   return (capPips > 0.0 && (planPips <= 0.0 || planPips > capPips));
}
double BaseKnotLegPick(const double planPips, const double capPips)
{
   if(BaseKnotLegCapped(planPips, capPips)) return capPips;
   return (planPips > 0.0 ? planPips : 0.0);
}
// THE EFFECTIVE PAIR of one node, in pips — the ONE owner the geometry, the R every text
// prints and both sentences read, so the drawn lines and the printed pips cannot part.
void BaseKnotLegPair(const double top, const double bot, const int kind, const int tfMin,
                     double &offPips, double &riskPips, const datetime anchor = 0)
{
   int    mtf   = BaseKnotMeasureTFMin(kind, tfMin);
   bool   hunt  = BaseKnotOffsetIsHunt(kind, mtf, anchor);
   double capE  = BaseKnotNodeEngPips(top, bot);
   double planO = BaseKnotEntryOffsetPips(kind, mtf, anchor);
   double planR = BaseKnotEngPips(mtf, anchor);
   offPips  = BaseKnotLegPick(planO, hunt ? BaseKnotNodeHuntPips(top, bot) : capE);
   riskPips = BaseKnotLegPick(planR, capE);
   double h = BaseKnotToPips(top - bot);
   if(offPips  <= 0.0) offPips  = (h > 0.0 ? h : 0.0);   // neither source answered — the box'
   if(riskPips <= 0.0) riskPips = (h > 0.0 ? h : 0.0);   //   own height, named by the texts
}
// P-BK-53 (2026-09-16) — ONE SHORT NAME ON THE CHART, THE PROOF IN THE HOVER.
// WHY: P-BK-52 named the ceiling with its formula EVERYWHERE it spoke, so the box' own note
// read «[BUY · the node's own EngSL (its height / 4.2667) 17.9 Pips | …]» — a sentence where
// a NAME belongs (user: «اطلاعات خلاصه و قابل فهمی باشه»). What the user reads a level off is
// the LEG and its SOURCE; the divisor is the PROOF that the number was measured at all, and a
// proof belongs where there is room to read it.
// WHAT: TWO names for ONE fact, both decided by the ONE flag the pick was made with
// (`isHunt` — BaseKnotLegPair's own):
//   * BaseKnotCapTag — the SHORT name ("node EngSL" / "node HuntSL"): what the chart-side
//     note prints and what every `riskTag` inside a hover's parentheses prints;
//   * BaseKnotCapWhy — the SAME source spelled out WITH the arithmetic that sized it
//     ("the node's own EngSL (its height / 4.2667)"): the hovers' own clauses only.
// P-BK-52's rule — a number nobody can check is never printed — still holds: the name rides
// the chart, the proof rides the hover, and neither is a second number.
// THE GATE: tools/base-count-audit.py [leg-fit / the chart's own label] reads BOTH — a formula
// smuggled back into the tag, or a short name leaking into the clause, fails the build.
string BaseKnotCapTag(const bool isHunt)
{
   return (isHunt ? "node HuntSL" : "node EngSL");
}
// ... and the SAME source spelled for the room a HOVER has: the source and the formula that
// sized it, so a number nobody can check never gets printed where it is read out.
string BaseKnotCapWhy(const bool isHunt)
{
   return (isHunt ? "the node's own HuntSL (its height x 5/8)"
                  : "the node's own EngSL (its height / 4.2667)");
}
// ... and the ONE clause every entry sentence appends when the ceiling really spoke (an empty
// string while the plan's leg still fits): the box hover, the note's hover and the entry ray
// share these exact words — the PROOF form (P-BK-53), because a hover has the room for it.
string BaseKnotCapClause(const int measureTF, const bool isHunt, const double top, const double bot,
                         const datetime anchor = 0)
{
   double plan = (isHunt ? BaseKnotHuntPips(measureTF, anchor) : BaseKnotEngPips(measureTF, anchor));
   double cap  = (isHunt ? BaseKnotNodeHuntPips(top, bot) : BaseKnotNodeEngPips(top, bot));
   if(!BaseKnotLegCapped(plan, cap)) return "";
   return " — CAPPED by " + BaseKnotCapWhy(isHunt) + " = " + DoubleToString(cap, 1) + " pips";
}
// ... and the stop's own sentence, shared by the hover and the note, so the two texts can
// never name two different sources for the one R they draw. P-BK-53: it answers WHICH source
// spoke and WHY in plain words (the plan's leg against the node's own), never in code words
// («power stands in» said nothing a user could check).
string BaseKnotStopWhy(const int measureTF, const double top, const double bot, const datetime anchor = 0)
{
   double plan = BaseKnotEngPips(measureTF, anchor);
   double cap  = BaseKnotNodeEngPips(top, bot);
   if(BaseKnotLegCapped(plan, cap))
      return (BaseKnotRiskIsEng(measureTF, anchor)
              ? " — the plan's EngSL of " + BaseKnotTFName(measureTF) + " (" + DoubleToString(plan, 1) +
                " pips) is deeper than the node, so " + BaseKnotCapWhy(false) + " stands in"
              : " — the pump has no EngSL for " + BaseKnotTFName(measureTF) +
                " yet, so " + BaseKnotCapWhy(false) + " stands in");
   if(plan > 0.0) return "";
   return " — neither the plan nor the node could size it, so the box' own height stands in";
}
void BaseKnotCalcLevels(const double top, const double bot, const int dir,
                        const int kind, const int tfMin, double &entry, double &sl,
                        const datetime anchor = 0)
{
   double pip  = BaseKnotPipSize();
   // P-BK-52: the pair comes from ONE owner — the plan's legs, bounded by the node's own
   // power — so the lines drawn here and the R every hover prints cannot part.
   // BKATRLEG-OFF (P-BK-51/52): the retired pair that used the plan's leg UNBOUNDED — a leg
   // deeper than the node put the entry past the box' far edge, and a TF the pump had not
   // pushed put the stop a whole box behind it. Restore by uncommenting the three lines below
   // and dropping the pair above them.
   // BKATRLEG-OFF: int    mtf  = BaseKnotMeasureTFMin(kind, tfMin);
   // BKATRLEG-OFF: double off  = BaseKnotEntryOffsetPips(kind, mtf) * pip;   // P-BK-51: the entry waits this deep
   // BKATRLEG-OFF: double risk = BaseKnotEngPips(mtf) * pip;                 // ... and the stop is ONE EngSL behind it
   double offP = 0.0, riskP = 0.0;
   BaseKnotLegPair(top, bot, kind, tfMin, offP, riskP, anchor);   // P-BK-79: the pair is read at the box' own anchor
   double off  = offP  * pip;   // the entry waits this deep INSIDE the side's own edge
   double risk = riskP * pip;   // ... and the stop is ONE EngSL behind it
   // BKGEOM-OFF (P-BK-50): the retired "ONE R OUTSIDE the edge, stop ON that edge" pair —
   // restore by uncommenting these four lines and DROPPING the two below (the R it reads
   // carries the P-BK-52 ceiling, so restoring it restores that geometry, not the old sizes).
   // BKGEOM-OFF: double r = BaseKnotRiskPips(tfMin, top, bot) * BaseKnotPipSize();
   // BKGEOM-OFF: if(r <= 0.0) r = top - bot;
   // BKGEOM-OFF: if(dir >= 0) { entry = top + r; sl = top; }
   // BKGEOM-OFF: else         { entry = bot - r; sl = bot; }
   if(off  <= 0.0) off  = top - bot;   // no pip size and no pushed value — the box' own height
   if(risk <= 0.0) risk = top - bot;   //   (the same absence rule; every text NAMES the source)
   if(dir >= 0) { entry = top - off; sl = entry - risk; }   // Buy: inside = below the top edge
   else         { entry = bot + off; sl = entry + risk; }   // Sell: inside = above the bottom edge
   // BKTPR-OFF (P-BK-50): the retired R-multiple target. Restore by uncommenting
   // these two lines (and the `TARGET R` sites in BaseKnotSync / BaseKnotSyncLive).
   // BKTPR-OFF: double mult = (g_bkTargetR >= 1 ? (double)g_bkTargetR : BK_TP_R_MULT);
   // BKTPR-OFF: double tp = (dir >= 0 ? entry + r * mult : entry - r * mult);
}

void BaseKnotMakeRay(const string name, const datetime tA, const datetime tB,
                     const double level, const color clr, const int style, const int width,
                     const string tooltip, const long tfMask, const bool rayRight)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, tA, level, tB, level);
   ObjectMove(0, name, 0, tA, level);
   ObjectMove(0, name, 1, tB, level);   // horizontal — Entry/SL project forward (ray-right),
                                          // TP is a short target tick at the right edge (never a ray)
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);   // TF-scoped with the box
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);   // levels read over candles (like TH lines)
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_RAY);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
// TP tick span — the target marker hugs the chart's RIGHT edge, next to the
// price axis (user decision 2026-09-08): a SHORT fixed tick (2 bars) ending
// exactly at the window's right edge time — never a ray, never box-wide.
// Falls back to the current bar (then box-anchored) when the edge/series is
// not convertible.
datetime BaseKnotTPEdgeTime()
{
   long wpx = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(wpx <= 10) return 0;
   int sw = 0; datetime et = 0; double ep = 0;
   if(!ChartXYToTimePrice(0, (int)wpx - 1, 10, sw, et, ep)) return 0;
   if(sw != 0 || et <= 0) return 0;
   return et;
}
void BaseKnotTPTickSpan(const datetime t1, const datetime t2, datetime &ts, datetime &te)
{
   datetime et = BaseKnotTPEdgeTime();
   if(et > 0) { te = et; ts = et - (datetime)(2 * PeriodSeconds()); return; }
   datetime cur0 = iTime(_Symbol, 0, 0);
   ts = (cur0 > 0 ? cur0 : t2);
   te = ts + (datetime)(2 * PeriodSeconds());
}
// Lean edge glue for the 500ms pump: scroll/zoom/new bars only remap TIME, so
// the tick is re-anchored with two ObjectMoves (level untouched) — never a
// full Sync. Missing TPs heal via OBJECT_DELETE, ray-flagged ones via Sync.
// P-BK-50: the box carries up to THREE of these now, and the glue walks exactly
// the set BaseKnotTPCount() draws — the same set the Sync builds and the probe
// below guards, so the three can never drift apart.
void BaseKnotTPGlue(const string pfx, const datetime edgeT)
{
   int n = BaseKnotTPCount();
   for(int k = 1; k <= n; k++)
   {
      string tpNm = BaseKnotTPTickName(pfx, k);
      if(ObjectFind(0, tpNm) < 0) continue;
      if(ObjectGetInteger(0, tpNm, OBJPROP_RAY_RIGHT) != 0) continue;   // structural — the Sync path rebuilds it
      datetime ts = edgeT - (datetime)(2 * PeriodSeconds());
      if((datetime)ObjectGetInteger(0, tpNm, OBJPROP_TIME, 0) != ts ||
         (datetime)ObjectGetInteger(0, tpNm, OBJPROP_TIME, 1) != edgeT)
      {
         ObjectMove(0, tpNm, 0, ts, ObjectGetDouble(0, tpNm, OBJPROP_PRICE, 0));
         ObjectMove(0, tpNm, 1, edgeT, ObjectGetDouble(0, tpNm, OBJPROP_PRICE, 1));
      }
   }
}
// TP tick look — SOLID + THICK: a 2-bar DASHED tick renders as almost nothing,
// so the tiny marker must be solid and thicker to read instantly. P-BK-50 (user:
// «با یک خط کوچک ولی ضخیم که دیده بشه»): 2px was still thin at native res, and the
// box draws up to THREE of these now, so they have to be read apart at a glance.
#define BK_TP_TICK_STYLE STYLE_SOLID
#define BK_TP_TICK_WIDTH 3
// TP staleness for the 500ms pump: only STRUCTURAL drift (a pre-tick ray, an
// older dashed/thin tick, or the retired single tick a pre-P-BK-50 build left
// behind) heals via a full Sync here — edge/scroll/new-bar drift is glued lean by
// BaseKnotTPGlue above. Read-guarded: steady state is compares only, no Sync.
// P-BK-50: the walk is over the DRAWN legs (1..TP COUNT) — a missing tick is the
// OBJECT_DELETE path's business (user-deleted children are not resurrected here),
// and a count the user lowered is healed by the setting's own restyle → Sync.
bool BaseKnotTPStale(const string pfx)
{
   if(ObjectFind(0, BaseKnotTPName(pfx)) >= 0) return true;   // BKTPR-OFF: the pre-P-BK-50 single tick
   int n = BaseKnotTPCount();
   for(int k = 1; k <= n; k++)
   {
      string tpNm = BaseKnotTPTickName(pfx, k);
      if(ObjectFind(0, tpNm) < 0) continue;   // user-deleted children heal via OBJECT_DELETE, not here
      if(ObjectGetInteger(0, tpNm, OBJPROP_RAY_RIGHT) != 0) return true;
      if(ObjectGetInteger(0, tpNm, OBJPROP_STYLE) != BK_TP_TICK_STYLE) return true;
      if(ObjectGetInteger(0, tpNm, OBJPROP_WIDTH) != BK_TP_TICK_WIDTH) return true;
   }
   return false;
}
void BaseKnotMakeBadge(const string name, const string text, const color bg)   // NOBKDEL: retired — no badge is created anymore (kept for one-line restore)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_BADGE_W);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_BADGE_H);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PnlPt(BK_PT_BADGE));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'18,22,33');
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_BADGE);  // P-UI-31: under the settings card
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}
// INFO visibility — Show mode pins the label on; Auto shows it live while
// sizing (LIVE_ tag always writes) and for BK_INFO_GRACE_MS after commit,
// then hides it so the chart stays clean. Full numbers always ride the
// box/edge hover tooltips, so nothing is ever unreachable.
// P-BK-58: and the CORNER rung (2) takes the note off the box altogether — the box-side copy
// is the one that has to be off, because the note then lives in ONE place only (the family's
// row, BaseKnotNoteAtCorner). Both callers of this probe already delete a note they are told
// not to show, so the rung needs no second switch anywhere.
bool BaseKnotInfoVisible(const string id)
{
   if(BaseKnotNoteInCorner()) return false;   // P-BK-58: the note's home is the family's column
   if(g_bkShowInfo == 1) return true;
   int k = BaseKnotFind(id);
   if(k < 0) return true;
   return ((int)(GetTickCount() - g_bkBoxes[k].commitMs) < (int)BK_INFO_GRACE_MS);
}
//+------------------------------------------------------------------+
//| P-BK-58 — THE NOTE HAS TWO HOMES, AND THE USER PICKS ONE.        |
//|                                                                  |
//| «لیبل اطلاعات بیس را کنار همان کارت/ردیف خانوادهٔ لیبلها هم نشان  |
//| بده تا کاربر بتواند بین «چسبیده به باکس» و «گوشهٔ ثابت» یکی را    |
//| انتخاب کند». What each home is FOR: the box-side note tells the  |
//| box' own story where the box is (it moves with the trade, and    |
//| that is what makes it hard to read on a busy chart); the CORNER   |
//| row lines up with the ATR/TH columns and the TRex trade card, so  |
//| the same numbers can be read as a readout.                       |
//| WHAT DOES NOT CHANGE: the TEXT (one writer, BaseKnotWriteInfo),  |
//| its size/font/colour/rung (P-BK-27/56), the box hover tooltips    |
//| and every drawn level. The two homes differ ONLY in the object    |
//| they write to and how it is anchored.                            |
//|                                                                  |
//| WHICH BOX the corner answers (user decision 2026-09-16): THE       |
//| SELECTED one — the user clicked it, so the row answers the        |
//| question he just asked. MT4's own single-select is READ           |
//| (`OBJPROP_SELECTED` on the box' handle, which P-BK-26's           |
//| BKSELECT-KEPT leaves intact), never re-implemented; with nothing  |
//| selected the NEWEST box answers, and the box being SIZED always   |
//| wins (sizing is the one moment the readout is looked at).         |
//|                                                                  |
//| THE SLOT IS PUSHED IN, never read here: the column's margins and  |
//| its row pitch belong to the label module (`inpLabelsMarginLeft`,  |
//| the ATR trade card's own layout), which sits ABOVE this module —  |
//| so it pushes the corner, the x and the y (BaseKnotCornerSlotPush) |
//| and this module only draws there. No margin is ever guessed.      |
//|                                                                  |
//| ONE OBJECT AT A TIME: the writer empties the other home as it     |
//| fills this one, so a mode change can never leave two copies of    |
//| the same number on the chart. Steady state costs NOTHING: the row |
//| is written on a CHANGE (mode, selection, slot, or the box' own    |
//| Sync), never once per pump round.                                 |
//+------------------------------------------------------------------+
bool BaseKnotNoteInCorner() { return (g_bkShowInfo == BK_NOTE_CHART); }
// The row's object name. ONE row for the whole chart (it is the family's column, not a box
// child — see BK_NOTE_CORNER).
string BaseKnotCornerName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + BK_NOTE_CORNER;
}
// The pushed slot (-1 = the family has never pushed one, i.e. there is nowhere to draw).
static int  s_bkCornerSide  = -1;
static int  s_bkCornerX     = 0;
static int  s_bkCornerY     = 0;
static bool s_bkCornerDirty = true;   // a slot write is owed (the row may not exist yet)
static string s_bkCornerId  = "";     // the box the row currently carries ("" = the sizing box)
// The row's own wipe (deinit + a mode change): the object goes AND the books are cleared, so the
// next refresh rebuilds instead of believing the row it just deleted is still there.
void BaseKnotCornerWipe()
{
   string nm = BaseKnotCornerName();
   if(nm != "" && ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   s_bkCornerId    = "";
   s_bkCornerDirty = true;
}
void BaseKnotCornerSlotPush(const int corner, const int xPos, const int yPos)
{
   if(corner == s_bkCornerSide && xPos == s_bkCornerX && yPos == s_bkCornerY) return;
   s_bkCornerSide  = corner;
   s_bkCornerX     = xPos;
   s_bkCornerY     = yPos;
   s_bkCornerDirty = true;   // read by the pump (≤500 ms) — never a chart write per push
}
// THE box the corner answers — see the block above: the SELECTED one, else the NEWEST.
string BaseKnotSelectedId()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   string best = "";
   uint   bestMs = 0;
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string pfx = BaseKnotPrefix(g_bkBoxes[i].id);
      if(pfx == "") continue;
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) continue;
      if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED)) return g_bkBoxes[i].id;   // clicked = the answer
      if(best == "" || g_bkBoxes[i].commitMs >= bestMs)
      {
         best = g_bkBoxes[i].id;
         bestMs = g_bkBoxes[i].commitMs;
      }
   }
   return best;
}
// ONE decision owner for WHERE the note is drawn: the writer (and its callers) ask THIS.
// `id` = "" is the box being SIZED (its own live tag is not in the registry) — it always wins,
// because while the user draws the readout must answer the box under his cursor.
bool BaseKnotNoteAtCorner(const string id)
{
   if(!BaseKnotNoteInCorner()) return false;
   if(id == "") return true;
   return (id == BaseKnotSelectedId());
}
// The row's own keeper — called from the existing 500 ms pump (BaseKnotSyncBadges), so the
// corner follows a selection change, a mode change, a pushed slot or a box that left this TF
// without a new event path of its own. NOTHING IS WRITTEN while nothing changed.
void BaseKnotNoteCornerRefresh()
{
   string nm = BaseKnotCornerName();
   if(nm == "") return;
   if(!BaseKnotNoteInCorner())
   {
      if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);   // the box-side home owns the note now
      s_bkCornerId    = "";
      s_bkCornerDirty = false;   // nothing is owed while the rung is not the corner one
      return;
   }
   if(g_bkState == BK_PREVIEW)
   {
      s_bkCornerDirty = true;   // the live writer owns the row while the user draws — the NEXT round
      return;                    // re-decides, so a cancelled BAND cannot leave its preview text behind
   }
   string id = BaseKnotSelectedId();
   if(id != "" && !BaseKnotVisibleNow(id)) id = "";   // a box hidden on this TF claims no row
   if(id == s_bkCornerId && !s_bkCornerDirty)
   {
      // Steady state: not one chart write. The ONE read left is the heal — something else
      // (a chart-wide cleanup, the user's own delete) may have taken the row away, and a
      // readout that silently disappears is the bug this keeper exists for.
      if(id == "" || ObjectFind(0, nm) >= 0) return;
      s_bkCornerDirty = true;   // rebuild it below
   }
   s_bkCornerId = id;
   s_bkCornerDirty = false;
   if(id == "")
   {
      if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);   // nothing answers: a stale note is worse than none
      return;
   }
   BaseKnotSync(id);   // the ONE writer rebuilds the box AND its note — into the row
   ChartRedraw();
}
// ONE candle's "is it inside the box" read — the BODY is the criterion (both
// open and close inside [bot,top], boundary INCLUSIVE, direction-free): wicks may
// pierce the band, a candle whose BODY is outside is not part of the base.
// Single definition, so every caller counts the same candle the same way.
bool BaseKnotBarBodyInside(const int shift, const double top, const double bot)
{
   double o = iOpen(_Symbol, 0, shift);
   double c = iClose(_Symbol, 0, shift);
   return (o >= bot && o <= top && c >= bot && c <= top);
}
// THE BASE'S OWN LENGTH — the candles that go nowhere, ending where it BREAKS.
//
// P-BK-31 (2026-09-15) — «عدد واقعی ۱۹ باید در هر حالت نشون بده، الان ۲۰ نشون
// میده؛ عقب بکشیم ۴۳ میشه … ۱۹ تا هستش از [شروع] تا اصلاح که کرده و شکسته». Two
// earlier rules measured the WRONG THING:
//   * v1 counted every close inside the band over the box's span (51 bars on a
//     19-candle base — trend candles merely passing through the band counted),
//   * v2 counted every BODY inside the band anywhere in the box (20 on the same
//     base, 43 once the box was widened backwards).
// Both measured the BOX. The base is a property of the PRICE ACTION, so the
// number must not move when the user drags the box: it is the run of candles that
// sit inside the band, ending where price leaves it (the break).
//
// HOW IT IS READ (P-BK-31) + THE TOLERANCE (P-BK-32, 2026-09-15):
//   * the anchor is the box's RIGHT edge — the newer end, which is where the base
//     ends and the break happens (P-BK-29 reads the break to the right of it);
//   * the walk goes OLDER from there, and it ends where price really LEFT the
//     range: ONE isolated out-of-band body is stepped over and NOT counted — the
//     user's «یک کندل منفرد با بدنه بیرونی ران بیس را قطع نکند» — while a CLUSTER of
//     them (BK_BASE_GAP + 1 in a row) is the base's end, because several candles in
//     a row outside the band are a MOVE while a single one is a poke;
//   * THE TOLERANCE IS A COUNT OF CANDLES, NEVER A PRICE MARGIN. Widening the band
//     for the test (x% of it, or k·ATR — the «interaction margin» family of the
//     TradingView range scripts) would put the BAND back inside the number: a box
//     drawn half a pip taller would print another base. The step-over lives on the
//     bar INDEX alone — a morphological CLOSING of the inside/outside series with
//     a one-candle structuring element, i.e. the same debounce every range
//     detector in the wild counts in bars («hold for N consecutive bars», the
//     Darvas-box code's M confirmation candles) — so the number still depends on
//     nothing but the series, the band and the anchor;
//   * A RE-ENTRY IS CONFIRMED BEFORE IT COUNTS (BK_BASE_MIN_BARS): the candles
//     found past a tolerated gap join the base only once BK_BASE_MIN_BARS of them
//     in a row hold the band. Without that confirmation a stray in-band candle on
//     the ENTRY side would re-open the run and inflate the number — exactly the
//     19 -> 20 the user already rejected;
//   * the box may end ON the break — or anywhere INSIDE it, because the user drags
//     the right edge forward over the move (breakout bodies are outside the band) —
//     so the out-of-band candles between the edge and the base are stepped over
//     first, up to BK_BASE_SKIP of them; if the band does not take over within
//     that, there is no base at this anchor and the note omits the number instead
//     of inventing one. P-BK-33 (2026-09-15): that budget was 4, and the user's own
//     box was ONE candle beyond it — right edge 12:49, the base's last in-band body
//     12:44, the break 12:45..12:49 (five BODIES outside the band, band
//     1.15323..1.15346 = the 2.3 pips on his note) — so the number silently vanished
//     from the note «جلو میبریم شمارش کندل ها رو نشون نمیده». P-BK-39: it is the
//     walk's own cap now (300), because a candle count is TF-dependent — the same
//     three-day break is 3 candles on D1 and 49 on H1, and 30 was only enough on the
//     chart it was tuned on;
//   * the box's LEFT edge bounds NOTHING (t1 is only a validity check): dragging
//     the box backwards over older price can no longer inflate the number, which
//     is exactly what the user asked for — the base's length is the same 19 in
//     every state of the box. Verified on the user's own M1 history (EURUSD,
//     15 Sep 2026, band 1.15333..1.15357 = the 2.4 pips on his note): an old build
//     printed 20 with the box on the base and 43 after dragging it back, and this
//     rule prints 19 in both states (the run 11:15..11:33 ending at the box' right
//     edge; 11:14 is the candle that left the band — tolerated once, and only a
//     full base-length stretch older than it could extend the run).
//
// Coherent with the rest of the note: P-BK-28's size class and P-BK-29's node
// type are read from the same base, so count, class and type describe ONE object.
// Cost: one bounded walk — the anchor steps over at most BK_BASE_SKIP bars and the
// run counts at most BK_BASE_MAX (the probe candles are inside that cap), so the
// walk reads at most ~2 · BK_BASE_MAX bars of the current chart, two series reads
// each; it keeps a pathological box (a band wide enough to swallow hours of
// candles) from walking the series.
// 0 = nothing measurable (series not ready, or no base at that anchor) — callers
// then omit the bars part and the size class.
// P-BK-39 (2026-09-15) — «چه از تایم بزرگ به کوچیک و از کوچیک به بزرگ»: the anchor
// budget is THE WALK'S OWN CAP (BK_BASE_MAX), not a third number. P-BK-33 set it to
// 30 chart candles, which is TF-DEPENDENT: 30 M1 candles are half an hour, while the
// user's own D1 box covers THREE D1 candles of break - 49 H1 candles on the H1 chart,
// which blew the budget and made the note read «no base» with its «N bars · D1 base»
// part missing on the very chart the base was measured on (measured on his own
// EURUSD1440/EURUSD60 history). With the budget at the walk's cap the anchor search is
// bounded by exactly what one base may cost the walk, so the SAME box finds the SAME
// base on every chart TF - and a box dragged further than a whole walk from any base
// still honestly reports none instead of latching onto an older range.
#define BK_BASE_SKIP 300      // candles the anchor may step over the break (P-BK-39: the walk's cap)
#define BK_BASE_GAP    1      // isolated out-of-band BODIES the run steps over (a COUNT of candles)
#define BK_BASE_MIN_BARS 3    // «سه کندل درجا زدن» — a re-entry needs a base's own length to count
#define BK_BASE_MAX  300      // hard cap on one walking run (M1: 5 hours — no base is longer)
// P-BK-41 (2026-09-15) — ONE SPAN: THE BASE'S OWN STORY.
// «از جای که وارد بیس شده تا جایی که ازش خارج شده و شکسه و کلوز کرده 9 کندل هستش این
// چرا 38 نوشته … فکر کنم بهتر که از زمانی که وارد بیس شده تا زمانیکه خارج از بیس یا
// گره معاملاتی شده رو تعداد کندل ها شو نشون بده» — the number must be the candles the
// BASE lasted: from the candle that entered the band to the candle that CLOSED OUTSIDE
// it (the break — the knot's own formation), and nothing else.
//
// P-BK-37 had read it as «from the base's start to the BOX' right edge», which made the
// number a property of the BOX instead of the base: with the anchor search budget at
// the walk's cap (P-BK-39: 300 candles — needed so a box drawn over a break still finds
// its base on a higher TF) every candle between the base's exit and the box' right
// edge — a dead zone, or a box simply dragged forward — was counted as if the base had
// lasted it. His own M15 box: a 9-candle base whose box reached ~29 candles past the
// exit printed «38 bars». The END is not the box: the anchor search checked EVERY
// candle from the box' right edge back to the anchor and found them all OUTSIDE the
// band, so the first of them (anchor - 1) IS «the candle that closed outside» — it is
// counted (the knot forms on its close) and the story stops there. Dragging the box
// further right is now FREE — it cannot add a candle the base never lasted — and the
// left edge still bounds nothing at all (P-BK-31).
//
// The CLASS rides the SAME span (one walk, one story — the P-BK-40 law): the rung's
// own candles are read between the base's first candle and its exit, so a box that is
// merely long can no longer let a higher TF be named by candles that are not the base.
// (the span RECORD itself is declared up beside the registry — the tooltip and the
// note read it there, far above this walk.)
// P-BK-40 (2026-09-15) — THE WALK REPORTS BOTH NUMBERS, because they answer two
// different questions and the user needs to see which one he is reading: the return
// is the base's LIFE — its own two ends only, P-BK-41/42 SUPERSEDING the "to the box'
// right edge" reading of P-BK-37 (the note's "N bars": «کندل ورود جز شمارش حساب نکنیم
// ولی کندل خروج جز شمارش حساب بکنیم»), and `sp.still` is how many candles STOOD STILL
// (bodies inside the band — «سه کندل درجا زدن», the base's own length the SIZE CLASS is
// read from, P-BK-28/36). One walk, several answers, never a second count: on the
// user's own D1 box they are 10 and 10 («اینجا چرا ده تا نشون میده در صورتی که 13 تا
// هستش» — the 13 was the box' own reach, which is no longer part of the base), and the
// box hover now spells the band, the entry, the exit and the number out, in that order.
int BaseKnotBarCount(const datetime t1, const datetime t2, const double top, const double bot,
                     BaseKnotSpan &sp)
{
   BaseKnotSpanClear(sp);
   if(t1 <= 0 || t2 <= 0 || top <= bot) return 0;
   int sh1 = iBarShift(_Symbol, 0, t1, false);
   int sh2 = iBarShift(_Symbol, 0, t2, false);
   if(sh1 < 0 || sh2 < 0) return 0;
   // Shift 0 is the LIVE bar, so the box's RIGHT edge (the newer end, where the
   // break is) is the SMALLER shift; walking OLDER increases it.
   int s = (sh1 < sh2 ? sh1 : sh2);
   int total = Bars;
   if(s < 0 || s >= total) return 0;
   // P-BK-34 (2026-09-15) — THE COUNT IS CLOSED-BAR DATA, the same law the node
   // read already obeys (P-BK-29). Shift 0 is the FORMING candle, and iBarShift()
   // answers 0 for ANY time after the last one, so a right edge dragged past the
   // live candle used to anchor the walk — and count — a candle whose body is
   // still moving: on the user's D1 chart that half-formed body was the only one
   // left in the band (the two candles before it ended 0.1..7 points above the
   // box' top), so the note read «1 bars · struct» for a box on a base — «باکس که
   // از کندل لایو جلو میزنه تعداد کندل اشتباه میکنه». A forming candle has not
   // «gone nowhere» yet, and an edge past the live candle must read exactly like
   // an edge ON the newest closed one, so the anchor is at least shift 1.
   if(s == 0) s = 1;
   if(s >= total) return 0;   // the series is a single, still-forming candle
   // P-BK-37 (2026-09-15) — THE NUMBER IS THE BASE'S LIFE. (Its END is no longer the
   // box' right edge — P-BK-41/42 below supersede that half: the number stops at the
   // candle that closed outside the band, and the entry candle is not counted.)
   // The RULE that finds the base is untouched (P-BK-31/32: the anchored
   // run of in-band bodies, one poke stepped over, a re-entry confirmed at a base's
   // own length); what changes is WHICH of its two ends the number reports. It now
   // reports the START (the run's own oldest in-band candle — a property of the
   // price action) instead of the count of in-band bodies, so:
   //   * P-BK-31's promise holds: the box' LEFT edge still bounds nothing (43);
   //   * P-BK-33's promise (a box dragged forward over its own break no longer read
   //     zero) holds through P-BK-41's exit rule instead of by counting the drag;
   //   * the user's own D1 box (13 candles over the base and its break, band
   //     1.1508..1.1579, in-band bodies Aug 5..18 = 10, box reached Aug 21) reads
   //     10 bars · D1 base (P-BK-42: the entry is out, the exit is in);
   //   * a poke INSIDE the base is one of the candles the base lasted, so it is
   //     inside the number (the poke's job is not cutting the RUN — P-BK-32 — not
   //     vanishing from the count).
   // The SIZE CLASS (P-BK-28/36/41) is read on the SAME span — the base's own story —
   // so count and class describe one object, and the rung confirmation is what keeps a
   // box dragged over a long break from inflating the class.
   int edge = s;   // the box' right edge, off the forming candle (P-BK-34)
   // P-BK-43 (2026-09-15) — A STRAY CANDLE IS NOT A BASE, and the anchor search is ONE
   // walk. «الان یک درست برای این بازه باگ داریم … اینجا های که شلوغ میشه همه نباید باگ
   // داشته باشیم»: in a congested zone the candle nearest the box' right edge can be a
   // lone body that happens to hold the band while everything around it pokes out — and
   // that candle used to ANCHOR the whole answer, so the note printed «1 bars · struct»
   // (or a base that is not there) for a box drawn on a real range. The search now asks
   // the SAME question of every candidate it meets: does a base start here? — and only a
   // candle whose run holds a base's own length (BK_BASE_MIN_BARS standing candles, the
   // same three the size class is read from, P-BK-28/36) becomes the anchor. The budget
   // is untouched: every candle examined counts against BK_BASE_SKIP from the box' right
   // edge, so a box dragged further than a whole walk from any base still reads none
   // (P-BK-39) instead of latching onto a range that is not there.
   int anchor = 0;   // the base's NEWEST stand-still candle (P-BK-41)
   int head   = 0;   // ... found on BOTH sides of the box' right edge (P-BK-44)
   int n      = 0;   // base candles counted (drives the cap and the confirmation)
   int gap    = 0;   // consecutive bodies outside the band since the last one inside
   int probe  = 0;   // in-band bodies past a tolerated gap, not yet a base's length
   int oldest = 0;   // shift of the OLDEST candle the base lasted (P-BK-37: the start)
   while(s < total && s - edge < BK_BASE_SKIP)
   {
      if(!BaseKnotBarBodyInside(s, top, bot)) { s++; continue; }   // the break / the dead zone
      // P-BK-44 (2026-09-15) — THE BOX' LINES EXTEND FORWARD TOO. «این چرا عقب میارمش
      // فرق میکنه اعداد … 36 تا درست بودش اون نباید 20 باشه … باید امتداده باکس ها به
      // عقب و جلو خطوط شو در نظر بگیر بای کندل ورود و خروج، ملاک که سقف و کف بیس هستش نه
      // داخل باکس»: when the box' right edge is pulled back INTO the base, the candles
      // that are still holding the band to the RIGHT of that edge are the same base —
      // the drawn rectangle is a pointer, the band is the criterion. So the run is
      // walked NEWER first (the exit side), with the SAME tolerance as the entry side,
      // and only then OLDER (the entry side) from its own newest candle. A box whose
      // edge is inside a base reads the WHOLE base now (his 20 became the 36 his wider
      // box read), and a box dragged past its own break is unchanged: the first candle
      // newer than the run already closed outside, so the run cannot extend at all.
      head = s;
      {
         int fup = s - 1, fgap = 0, fprobe = 0, fn = 0;
         while(fup >= 1 && fn + fprobe < BK_BASE_MAX)
         {
            if(BaseKnotBarBodyInside(fup, top, bot))
            {
               if(fgap == 0) { fn++; head = fup; }
               else
               {
                  fprobe++;
                  if(fprobe >= BK_BASE_MIN_BARS) { fn += fprobe; fprobe = 0; fgap = 0; head = fup; }
               }
            }
            else
            {
               fgap++;
               if(fgap > BK_BASE_GAP) break;
            }
            fup--;
         }
      }
      anchor = head;                   // the run's OWN newest candle: the exit is read off it
      n = 0; gap = 0; probe = 0; oldest = 0;
      // P-BK-32 — THE RUN WITH THE TOLERANCE, walked on its own cursor so a candidate
      // that does not hold a base leaves `s` free to look behind it. `gap` counts the
      // consecutive bodies OUTSIDE the band: one of them (BK_BASE_GAP) is stepped over —
      // a poke does not cut the base — and a CLUSTER ends it. `probe` holds the candles
      // found past a tolerated gap until BK_BASE_MIN_BARS of them in a row hold the band;
      // they join the base only then, which is what stops a stray in-band candle on the
      // ENTRY side from re-opening the run (the 19 -> 20 P-BK-31 rejected). The budget
      // covers the probe as well, so the WALK is capped, not only the count.
      int t = head;   // P-BK-44: the older walk starts at the run's head, so BOTH sides
                      // of the box' right edge are inside the number and the class
      while(t < total && n + probe < BK_BASE_MAX)
      {
         if(BaseKnotBarBodyInside(t, top, bot))
         {
            if(gap == 0)
            {
               n++;                            // the run continues — this candle is base
               oldest = t;                     // ... and it is the new START of the life
            }
            else
            {
               probe++;                        // inside AGAIN, just past the poke
               if(probe >= BK_BASE_MIN_BARS)   // ... and it holds a base's own length
               {
                  n += probe;                  // only then do those candles join the base
                  probe = 0;
                  gap   = 0;
                  oldest = t;                  // the oldest of the confirmed probe candles
               }
            }
         }
         else
         {
            gap++;                             // one body outside — a poke (or the entry)
            if(gap > BK_BASE_GAP) break;       // a CLUSTER of them: this candidate ended here
         }
         t++;
      }
      if(n >= BK_BASE_MIN_BARS && oldest > 0) break;   // THIS candle anchors a base
      s = t;                                           // a stray body: look behind it
      anchor = 0;
   }
   if(anchor <= 0 || oldest <= 0) return 0;   // no base inside the walk's own budget
   // P-BK-44: the EXIT is the first candle NEWER than the run's own newest candle —
   // so it is the real exit candle even when the box' right edge sits inside the base
   // (the run extends past that edge and the exit lies to the RIGHT of the box), and
   // when the newest closed candle is itself still the base there is no exit yet: the
   // number then stops at it instead of reaching into the forming candle (P-BK-34).
   // P-BK-41 — THE STORY ENDS WHERE THE BASE ENDED, and since P-BK-44 that END belongs
   // to the RUN, not to the box: `head` is the run's own newest stand-still candle
   // (found on both sides of the box' right edge), so `head - 1` is the candle that
   // CLOSED OUTSIDE the band — «the candle that closed outside» (the break / the knot's
   // formation). It is INSIDE the story and the story stops there, no matter where the
   // drawn rectangle happens to end: dragged back into the base it still reads the
   // whole base, and dragged forward past the break the run cannot extend at all (the
   // next candle out is already outside), so the number cannot be inflated by the drag.
   int end = (head > 1 ? head - 1 : head);
   // P-BK-42 (2026-09-15) — HOW THE TWO ENDS ARE COUNTED: «اول باید سقف و کف بیس یا
   // گره معاملاتی رو مشخص کنیم که ببینم کدوم کندل وارد شده و کدوم کندل خارج شده — کندل
   // ورود جز شمارش حساب نکنیم ولی کندل خروج جز شمارش حساب بکنیم». The band (top/bot) is
   // what tells the two candles apart: the ENTRY is the base's oldest candle whose body
   // is inside it (`oldest`) and it is NOT counted; the EXIT is the candle that CLOSED
   // OUTSIDE it (`end`) and it IS counted. The note's number is therefore the span
   // between the two, endpoints counted only at the exit end — the candles the base
   // actually held between entering and leaving it. (`still` keeps its own meaning and
   // still counts the entry candle, because it is the base's own LENGTH that the size
   // class is read from — P-BK-28/40 — not the note's span.)
   sp.still  = n;                              // P-BK-40: the class's input (entry included)
   sp.tStart = iTime(_Symbol, 0, oldest);      // the ENTRY candle (not counted)
   sp.tLast  = iTime(_Symbol, 0, head);        // the base's own right side (both sides)
   sp.tExit  = iTime(_Symbol, 0, end);         // the EXIT candle (counted)
   sp.life   = oldest - end;                   // P-BK-42: entry out, exit in
   return sp.life;
}
// P-BK-30: the count is the ONLY part of the SIZING preview that costs a bar walk
// (two series reads per bar over the base run, on a 30 ms cursor path), so
// it gets its own cadence: the box' geometry and the rays stay pixel-live, the
// NUMBER is refreshed at most every BK_LIVE_COUNT_MS. What the user is aiming at
// is the rectangle, not the digits — and the digits are always exact on the frame
// that matters, because the commit runs the authoritative `BaseKnotSync` (plain
// BaseKnotBarCount). Measured effect on the sizing path: ~33 Hz -> ~8 Hz walks,
// with no visible difference in the label.
#define BK_LIVE_COUNT_MS 120
//--- P-BK-45 (2026-09-15) — WHILE THE USER DRAWS: THE BAND IS THE QUESTION, THE EDGES
//--- ARE POINTERS, SO AN EDGE THAT MOVES INSIDE THE RUN THE BAND ALREADY FOUND COSTS
//--- NOTHING. «همون جای که کاربر داره رسم میکنم … بهترن کار چیه که فشار الکی هم نیاد و
//--- اینکه درست هم تشخیص داده بشه».
//---
//--- The walk's own law (P-BK-44) says the answer is a property of the BAND plus the run
//--- that band holds: the box' right edge only says WHERE to start looking, and once the
//--- run is found, sliding the edge over it cannot change the run, its entry, its exit,
//--- its class or its node story. Measured on the user's own EURUSD M15 tape for his
//--- box (band 1.16060..1.16165): sliding the edge from 09-11 00:15 to 05:00 (20
//--- positions, inside the run) and on to 08:00 (12 more, over the dead zone) returned
//--- the IDENTICAL reading — 20 bars · H1 base · CTR — at all 32 positions, and the
//--- first position that changed it was 08:15, where the edge itself lands inside a
//--- LATER base (9 bars · M15). That window is not a tolerance: it is exactly between
//--- the run's own oldest candle and the first in-band candle NEWER than its newest
//--- one, because that candle is what a walk started at the edge would anchor on.
//---
//--- So the cache is keyed on the BAND (top, bot, the newest closed candle, this chart)
//--- and stores that window. A horizontal drag — the common gesture, the one that used
//--- to pay a full walk every BK_LIVE_COUNT_MS — reads the cached span outright; a band
//--- change (a vertical drag) is the only thing that can move the base, and it pays one
//--- walk per cadence exactly as before. The commit still runs the authoritative plain
//--- `BaseKnotBarCount` (P-BK-30), so the preview being cheap never becomes the reading's
//--- source of truth. The class rides the same reuse for free: its memo (P-BK-36) is
//--- keyed on the span's own two ends, which a reused span does not change.
static double   s_bkLiveTop = 0.0;      // the BAND the cached run was found with
static double   s_bkLiveBot = 0.0;
static datetime s_bkLiveBar = 0;        // ... and the newest closed candle it was read on
static int      s_bkLiveLo  = 0;        // the EDGE WINDOW it stays valid for (shifts,
static int      s_bkLiveHi  = -1;       // 0/-1 = no window: nothing to reuse)
int BaseKnotLiveBarCount(const datetime t1, const datetime t2, const double top, const double bot,
                         BaseKnotSpan &sp)
{
   static uint s_ms = 0;
   static int  s_n  = 0;
   static BaseKnotSpan s_sp;   // P-BK-41: the WHOLE span is memoised, not only its count
   uint now = GetTickCount();
   datetime lastClosed = iTime(_Symbol, 0, 1);
   if(s_n > 0 && top == s_bkLiveTop && bot == s_bkLiveBot && lastClosed == s_bkLiveBar &&
      s_bkLiveHi > 0)
   {
      int e = iBarShift(_Symbol, 0, t2, false);
      if(e == 0) e = 1;    // P-BK-34: the edge is read at the newest CLOSED candle
      if(e >= s_bkLiveLo && e <= s_bkLiveHi) { sp = s_sp; return s_n; }   // P-BK-45
   }
   if(now - s_ms < BK_LIVE_COUNT_MS) { sp = s_sp; return s_n; }
   s_ms = now;
   s_n  = BaseKnotBarCount(t1, t2, top, bot, s_sp);
   sp = s_sp;
   if(s_n > 0)
   {
      s_bkLiveTop = top; s_bkLiveBot = bot; s_bkLiveBar = lastClosed;
      int head = iBarShift(_Symbol, 0, s_sp.tLast, false);    // the run's own right side
      int old  = iBarShift(_Symbol, 0, s_sp.tStart, false);   // ... and its oldest candle
      int lo   = 1;
      if(head > BK_BASE_SKIP) lo = head - BK_BASE_SKIP + 1;   // past the budget the walk finds nothing
      for(int e = head - 1; e >= lo; e--)                     // the first in-band candle NEWER
         if(BaseKnotBarBodyInside(e, top, bot)) { lo = e + 1; break; }   // anchors a DIFFERENT run
      s_bkLiveLo = lo;
      s_bkLiveHi = (old > 0 ? old : head);
   }
   else { s_bkLiveLo = 0; s_bkLiveHi = -1; }
   return s_n;
}
//+------------------------------------------------------------------+
//| P-BK-28 — THE BASE'S SIZE CLASS (2026-09-15)                     |
//|                                                                  |
//| The course the user works from defines the base by CANDLE COUNT,  |
//| not by pips: «سه کندل درجا زدن تعریف بیس هستش» — three candles    |
//| going nowhere ARE the base — «و ۹ الی ۱۲ کندل میره برای تایم       |
//| بالاتر») — and the SAME three candles of the time frame above are |
//| 9..12 of ours (3 x M15 = 12 x M5, 3 x H1 = 12 x M15). So the whole|
//| rule is one arithmetic line: the base belongs to the HIGHEST rung |
//| still holding 3 candles inside the box, and the count of OUR bars |
//| that means is 3 * rung / chartTF.                                 |
//|                                                                  |
//|   bars 1..2   -> structure — a knot read as one or two candles    |
//|                  belongs to the STRUCTURE TF, not to a base       |
//|                  («کندل تک یا دو کندل = ساختار»), so it is named  |
//|                  in the note, never silently read as a base;      |
//|   bars 3..8   -> a base of THIS chart's TF (3 candles = a base);  |
//|   bars 9..12  -> the base is one rung up (M5 chart -> M15 base);  |
//|   bars 12+    -> the same rule upward (M15 chart -> H1 base).     |
//|                                                                  |
//| It counts the bars the note ALREADY counts (BaseKnotBarCount —    |
//| P-BK-31/32: the base run — candle BODIES inside the ceiling/floor,|
//| ending at the break, a lone poke stepped over, never the box; and  |
//| P-BK-37: the number is that run's START up to the box' right edge,|
//| so the count and the class describe ONE object), and P-BK-36       |
//| CONFIRMS the rung on the RUNG'S OWN candles: one bounded walk of   |
//| the rung's bars (early exit at 3 confirmations, memoised per Sync),|
//| so the 500 ms pump pays no HTF fetch per box per round.            |
//| ATR is not a class input: it lives ABOVE this layer and only SIZES |
//| the node's numbers (P-BK-35).                                      |
//+------------------------------------------------------------------+
// P-BK-32: BK_BASE_MIN_BARS now sits with the count's own budgets (above
// `BaseKnotBarCount`) because the WALK reads it — candles found past a tolerated
// gap are counted only once a full base's length holds the band. Same value and
// same meaning as here: under 3 candles inside, it is structure, not a base.
// Next rung up MT4's own ladder (0 = already at MN1). Same shape as
// BaseKnotTFName / BaseKnotTFMask above, so an exotic chart TF can never
// name a rung those two do not know.
// P-BK-43 (2026-09-15) — THE BASE'S LADDER IS THE PROJECT'S LADDER: M1 · M5 · M15 · H1 ·
// H4 · D1 · W1 · MN1 — the SAME eight the ATR warm-up queue walks
// (`g_atrWarmupQueue[] = {1, 5, 15, 60, 240, 1440, 10080, 43200}`, ATRCalculations.mqh) and
// the same eight his own label row prints. «هنوز سی دقیقه نشون میده چرا» — M30 is not one
// of our TFs, so «7 bars · M30 base» on an M15 box was a class the ladder had no business
// naming: `3 * 30 / 15 = 6 <= 7` admitted M30 over a base barely three M30 candles long,
// and the rung read then found those three lying inside the band. The ladder steps
// 15 -> 60 now. An M30 CHART still names M30, and it names it as `Period()` — the base's
// own TF — never as a rung.
// P-BK-82 (2026-09-17) — AND M1 IS A RUNG. The user: «چرا تایم گره رو درست و اصولی تشخیص
// نمیده، گره که مال یک دقیقه هستش رو مال پانزده دقیقه نشون میده». The steps above start at
// 5, so a walk that STARTS at 0 — `BaseKnotLadderAll`, i.e. the CLASS read's own ladder —
// could never reach M1: a base whose candles stand still on M1 fell past every rung, and the
// read then named the SPAN's own rung instead (the user's box: 17 minutes wide around a
// 5-bar M1 base — `3 * 15 > 17` refused M15, and the fallback `rungs[i] <= spanMin` named it
// anyway -> «M15 base»). The floor is the ATR queue's own first member (P-BK-43's
// `g_atrWarmupQueue[]` starts at 1) and the eight names above. NOTHING ELSE MOVES: every
// other caller hands a tfMin >= 1, where `tfMin < 5` still answers 5 — the ladder's own walk
// is the only caller that starts from 0, so it is the only one that gains the rung.
int BaseKnotNextTFMin(const int tfMin)
{
   if(tfMin < 1)     return 1;       // P-BK-82: the FLOOR — M1 is a rung of our ladder
   if(tfMin < 5)     return 5;
   if(tfMin < 15)    return 15;
   if(tfMin < 60)    return 60;      // P-BK-43: 30 is NOT in our ladder
   if(tfMin < 240)   return 240;
   if(tfMin < 1440)  return 1440;
   if(tfMin < 10080) return 10080;
   if(tfMin < 43200) return 43200;
   return 0;
}
// P-BK-36 (2026-09-15) — «سه کندل درجا زدن برای مشخص کردن تایم بیس باید مولتی تایم
// باهش تشخیصش … این گره باید برای تایم پایین باهش چون سه کندل درجا زدن نداره»:
// THE RUNG IS CONFIRMED ON THE RUNG'S OWN CANDLES.
//
// P-BK-28's ladder is arithmetic on OUR bars (3 x rung / chartTF <= bars) and that
// is the rung's DISPLACEMENT, nothing more: it says "three candles of that TF fit
// inside this number", never "three candles of that TF stood still here". The two
// part ways whenever the base and the rung are not aligned — 12 M15 candles sitting
// in the upper half of one H1 candle are a base whose H1 candle poked out of the
// band — and the same box then names a different class depending on the chart it is
// read on. So the highest rung the ladder admits is used only when ITS OWN candles
// hold the band: >= BK_BASE_RUNG_MIN of the rung's candles overlapping the box keep
// their BODIES inside [bot,top] — the same criterion the count walks with, spelled
// once, never a margin.
//
// The read is bounded and cheap (the user: «همین که فشار به سیستم نیاد از محاسبات
// الکی»): only the rungs the ladder already admitted are read at all, the scan stops
// on the first BK_BASE_RUNG_MIN confirmations, it examines at most BK_BASE_RUNG_MAX
// rung candles, and the answer is MEMOISED on the exact question (edges, band,
// count, chart TF, newest closed bar) because the note, its hover and the box
// tooltip all ask for the class inside one Sync — one rung read per Sync, not three.
//
// Nothing is ever invented: when the rung's series is not there to be read (offline
// history, a rung the terminal never downloaded) the arithmetic ladder answers,
// exactly as it did before this rule; when a rung's candles do NOT stand still, the
// next rung down is tried; and a base whose rungs never stand still is a base of
// THIS chart's TF.
#define BK_BASE_RUNG_MIN 3     // «سه کندل درجا زدن» — on the RUNG's OWN candles
#define BK_BASE_RUNG_MAX 60    // rung candles examined per rung (a bounded read)
// The rung's series is there to be read at all? (a rung == this chart's TF always is)
bool BaseKnotRungLoaded(const int tfMin)
{
   if(tfMin <= 0) return false;
   if(tfMin == Period()) return true;
   return (iBars(_Symbol, tfMin) > 0);
}
// Does the rung STAND STILL in this band? The number of the rung's candles
// overlapping the box whose BODIES are inside [bot,top]. Bounded: it stops on the
// first BK_BASE_RUNG_MIN confirmations and never reads more than BK_BASE_RUNG_MAX
// rung candles. -1 = the rung's series is not readable (never a 0 dressed up as an
// answer, because 0 and "cannot tell" must not read the same).
// P-BK-41: the span every one of these reads is the BASE'S OWN STORY (its first candle
// to the candle that closed outside the band) — passed in as `s1..s2` so a caller cannot
// quietly hand in the box' own rectangle instead. The note's number and the class are
// read from the SAME span, which is why they can never describe two different objects.
int BaseKnotRungHoldCount(const int tfMin, const datetime s1, const datetime s2,
                          const double top, const double bot)
{
   if(tfMin <= 0 || s2 <= 0 || top <= bot) return -1;
   // P-BK-77 (2026-09-17): THIS CHART'S OWN TF IS READ LIKE ANY OTHER RUNG. It used to
   // answer BK_BASE_RUNG_MIN without reading a single candle ("the walk already did it"),
   // which made the CHART decide the class: on an M15 chart the M15 rung confirmed itself
   // and a box that stood still on M5 was called an «M15 base». The walk is still the
   // chart's, but the RUNG's own candles are the only thing this count may read.
   if(!BaseKnotRungLoaded(tfMin)) return -1;
   int sh1 = iBarShift(_Symbol, CompatTF(tfMin), s1, false);
   int sh2 = iBarShift(_Symbol, CompatTF(tfMin), s2, false);
   if(sh1 < 0 || sh2 < 0) return -1;                // the box is older than this series
   int newer = (sh1 < sh2 ? sh1 : sh2);             // smaller shift = newer candle
   int older = (sh1 < sh2 ? sh2 : sh1);
   if(older - newer + 1 > BK_BASE_RUNG_MAX) older = newer + BK_BASE_RUNG_MAX - 1;
   int held = 0;
   for(int s = newer; s <= older; s++)
   {
      double o = iOpen(_Symbol, tfMin, s);
      double c = iClose(_Symbol, tfMin, s);
      if(o <= 0 || c <= 0) continue;                // series not ready — never invented
      if(o >= bot && o <= top && c >= bot && c <= top)
      {
         held++;
         if(held >= BK_BASE_RUNG_MIN) return held;  // bounded: enough to confirm
      }
   }
   return held;
}
// Minutes of the TF this base belongs to; 0 = unmeasurable (series not
// ready), -1 = structure (1-2 candles — not a base at all).
// P-BK-36: THE LADDER PROPOSES, THE RUNG'S OWN CANDLES DECIDE.
//
// P-BK-77 (2026-09-17, user: «باید تایم گره صد در صد درست تشخیص داده بشه، مهم نیست روی چه
// تایمی هستیم»): THE WHOLE LADDER IS SEARCHED, AND THE SPAN IS COUNTED IN MINUTES. The
// user draws the box with the MEASURING TOOL, so neither the chart's TF nor the box' own
// commit TF is evidence of anything: his node's three candles may belong to a HIGHER time
// than the box was drawn on, or to a LOWER one. The read therefore:
//   * measures the span in MINUTES (`(s2 - s1)/60 + one chart candle`), so no rung is
//     admitted or refused because of which chart happens to be open;
//   * walks the PROJECT'S WHOLE LADDER (M1·M5·M15·H1·H4·D1·W1·MN1), BOTH WAYS — the
//     rungs below the box' TF are candidates exactly like the ones above it;
//   * reads every rung on its OWN candles (P-BK-77's other half lives in
//     BaseKnotRungHoldCount: this chart's TF no longer confirms itself for free);
//   * names the NODE'S TIME as the HIGHEST rung with three of its own candles standing
//     still — the user's own definition of «تایم گره» («سه کندل درجا زدن»): the biggest
//     time in which the three candles are still visible.
// A rung whose series cannot be read is REMEMBERED, not returned on the spot: the walk
// keeps looking for a rung that really stands still and only falls back to it when none
// does (P-BK-36's promise — a class is never dropped because a series is not loaded).
// When NO rung stands still, the answer is the LARGEST rung one candle of which still
// fits the span (a 40-minute band -> M15), never the open chart's TF.
//
// P-BK-80 (2026-09-17) — AND THE CHART CONTRIBUTES NOTHING AT ALL. The user: «تایم گره
// توی یکساعته درست تشخیص داده ... ولی تایم بالا که میریم میزنه ftr، کلا یک گره فقط یک
// تایم میتونه داشته باشه متعلق به یک تایم هستش». The span was still the CHART's: its two
// ends were chart-TF candle times (P-BK-41's walk) and `chartMin` was ADDED to the span
// («the exit candle's own width»), so `3 * rung <= spanMin` admitted a rung on an H4 chart
// that the very same box refused on H1 — 480..660 minutes of base read H1 on H1 and H4 on
// H4, and the taller rung's ATRs then typed a short box FTR. The span is now the BOX' OWN,
// `(t2 - t1) / 60` minutes, and the stand-still walk reads the rung's own candles over that
// same span: the box' two anchors are stored on the OBJECT, so the answer is bit-identical
// on every chart TF — the promise P-BK-77 made and P-BK-41's chart read was still breaking.
// The box' own span is also the honest input: «تایم گره» is a property of what the user
// DREW (the band and the range), never of the chart he happens to look through.
//
// P-BK-82 (2026-09-17) — AND THE LADDER HAS TO REACH M1 (the floor itself lives in
// `BaseKnotNextTFMin`). The walk below starts at the ladder's HIGHEST rung and comes down,
// so a floor at M5 meant a base standing still on M1 could never be NAMED M1: every rung was
// refused and the "nothing stood still" fallback named the span's own rung instead — which
// is exactly how the user's 17-minute box around a 5-bar M1 base came out as «M15 base»
// («گره که مال یک دقیقه هستش رو مال پانزده دقیقه نشون میده»). With M1 in the ladder the
// chart's own TF is always a candidate, so a base of >= 3 stand-still candles confirms a rung
// instead of falling through to the span — and the fallback below is the last resort it was
// always meant to be.
int BaseKnotLadderAll(int &rungs[])
{
   int all[9];
   ArrayInitialize(all, 0);   // explicit: the loop fills it in order, the copy below reads `n` of them
   int n = 0;
   int r = 0;
   for(int i = 0; i < 9; i++)
   {
      r = BaseKnotNextTFMin(r);   // the ONE owner of the ladder's steps
      if(r <= 0) break;
      all[n] = r;
      n++;
   }
   ArrayResize(rungs, n);
   for(int i = 0; i < n; i++) rungs[i] = all[i];
   return n;
}
int BaseKnotBaseTFRead(const int bars, const datetime b1, const datetime b2,
                       const double top, const double bot)
{
   if(bars <= 0) return 0;
   if(bars < BK_BASE_MIN_BARS) return -1;
   // P-BK-80: THE SPAN IS THE BOX' OWN TWO ANCHORS, IN MINUTES, AND NOTHING ELSE. The chart
   // TF used to add its own candle width here (`+ chartMin`) and to supply the span's two
   // ends; both are gone, so `3 * rung <= spanMin` answers the same on M1 and on MN1.
   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0));
   int rungs[9];
   int n = BaseKnotLadderAll(rungs);
   if(n <= 0) return 1;   // no ladder at all — M1 is the only rung left to name
   int unread = 0;   // the HIGHEST rung that fits the span but whose series cannot be read
   for(int i = n - 1; i >= 0; i--)   // the HIGHEST rung first — the first one that stands still IS the answer
   {
      int rung = rungs[i];
      if(3 * rung > spanMin) continue;            // three of its candles cannot fit in the span
      int held = BaseKnotRungHoldCount(rung, b1, b2, top, bot);
      if(held < 0) { if(unread <= 0) unread = rung; continue; }   // cannot tell — keep looking down
      if(held >= BK_BASE_RUNG_MIN) return rung;   // THE NODE'S TIME — «سه کندل درجا زدن»
   }
   if(unread > 0) return unread;   // nothing stood still and a series was unreadable: the ladder stands
   // P-BK-77: nothing stood still at all — the span's OWN rung, the largest one a single
   // candle of which still fits in it. A real TF of THIS span, on every chart.
   // P-BK-80: and a degenerate span (a box narrower than one M1 candle) ends at the
   // ladder's own first rung — never at the open chart's TF, which is what leaked before.
   // P-BK-82: and with M1 IN the ladder this whole branch is a LAST RESORT again — the
   // chart's own TF is a candidate of the walk above, so a base with >= 3 stand-still
   // candles is named by a rung that really holds it, never by the width of the box.
   for(int i = n - 1; i >= 0; i--)
      if(rungs[i] <= spanMin) return rungs[i];
   return rungs[0];
}
// The memo (P-BK-36): the answer is closed-bar data, so it can only change when the
// QUESTION changes — the box' two anchors, its band, the count it was computed from, or a
// new closed bar. P-BK-80: the chart TF is NO LONGER part of the key, because it is no
// longer part of the question — that is the whole promise, and a key that carried it could
// only ever hand the same box two different answers on two charts.
static int      s_bkRungBars   = -1;
static datetime s_bkRungB1     = 0;   // P-BK-80: the BOX' left anchor
static datetime s_bkRungB2     = 0;   // ... and its right anchor (never the story's ends)
static double   s_bkRungTop    = 0.0;
static double   s_bkRungBot    = 0.0;
static datetime s_bkRungBar    = 0;
static int      s_bkRungAnswer = 0;
// P-BK-80: the question is the BOX' OWN geometry alone — its two anchors, its band, and the
// base count it was computed from. No box TF, no chart TF, no chart candle width.
int BaseKnotBaseTFMin(const int bars, const datetime b1, const datetime b2,
                      const double top, const double bot)
{
   datetime lastClosed = iTime(_Symbol, 0, 1);
   if(bars == s_bkRungBars && b1 == s_bkRungB1 && b2 == s_bkRungB2 &&
      top == s_bkRungTop && bot == s_bkRungBot &&
      lastClosed == s_bkRungBar)
      return s_bkRungAnswer;
   int answer = BaseKnotBaseTFRead(bars, b1, b2, top, bot);
   s_bkRungBars = bars; s_bkRungB1 = b1; s_bkRungB2 = b2;
   s_bkRungTop = top; s_bkRungBot = bot;
   s_bkRungBar = lastClosed; s_bkRungAnswer = answer;
   return answer;
}
// Compact note suffix: " · M15 base" / " · H1 base" / " · struct" / "".
// P-BK-80: `b1..b2` = the BOX' OWN two anchors — the only input the class has.
string BaseKnotBaseTag(const int bars, const datetime b1, const datetime b2,
                       const double top, const double bot)
{
   int tf = BaseKnotBaseTFMin(bars, b1, b2, top, bot);
   if(tf == 0) return "";   // unmeasurable — the bars part is omitted too
   if(tf <  0) return " · struct";
   return " · " + BaseKnotTFName(tf) + " base";
}
// The same read spelled out for the hover line (the note's full sentence).
string BaseKnotBaseLine(const int bars, const datetime b1, const datetime b2,
                        const double top, const double bot)
{
   int tf = BaseKnotBaseTFMin(bars, b1, b2, top, bot);
   if(tf == 0) return "\nBase: size not measurable yet";
   if(tf <  0) return "\nBase: " + IntegerToString(bars) +
                      " bars -> structure (a base needs " + IntegerToString(BK_BASE_MIN_BARS) + " candles inside)";
   // P-BK-77: the fallback is the span's OWN rung now (no rung stood still in it), so the
   // sentence may not claim the candles — it is re-read here, on the rung the read named.
   if(BaseKnotRungHoldCount(tf, b1, b2, top, bot) < BK_BASE_RUNG_MIN)
      return "\nBase: " + IntegerToString(bars) + " bars -> " + BaseKnotTFName(tf) +
             " base (no rung of the ladder stood still in it — the span's own rung)";
   // P-BK-36: the claim the class is read from — the rung's OWN candles, spelled out.
   return "\nBase: " + IntegerToString(bars) + " bars -> " + BaseKnotTFName(tf) +
          " base (" + IntegerToString(BK_BASE_RUNG_MIN) + " candles of " + BaseKnotTFName(tf) +
          " stood still in the band)";
}
//+------------------------------------------------------------------+
//| P-BK-47 — THE NOTE'S NODE TYPE IS THE NODE'S LENGTH (the user's own  |
//| rule, 2026-09-15: «دسته بندی گره های معاملاتی براساس طول گره: FTR گرهی |
//| که طولش مساوی تایم تریگر تایمی باشد که گره در آن دیده میشود سه کندل · |
//| ETR گرهی که طولش مساوی تایم پترن باشد · CTR گرهی که طولش مساوی تایم    |
//| ساختار باشد · OTR گرهی که طولش بیشتر از تایم ساختار باشد»).            |
//|                                                                  |
//| The length is read on the PROJECT'S ladder (P-BK-43's own eight),  |
//| and the class P-BK-36 already confirmed IS that length: a node     |
//| reaching the rung one step up holds THREE candles of that rung,    |
//| which IS the pattern time («سه کندل درجا زدن … تایم بالاتر»), two   |
//| steps up is the structure time. So the whole rule is one count of   |
//| RUNGS between the TF the node is SEEN ON (the box' commit TF — a   |
//| property of the BOX) and its class:                                 |
//|                                                                  |
//|   0 rungs  -> FTR — the trigger length: 3 candles of its own TF     |
//|   1 rung   -> ETR — the pattern time (3 candles of the rung above)  |
//|   2 rungs  -> CTR — the structure time (3 candles two rungs above)  |
//|   3+ rungs -> OTR — LONGER than the structure time                  |
//|                                                                  |
//| WHAT PRICE DID NO LONGER NAMES THE TYPE (BKNODEKIND-OFF retires the |
//| P-BK-29/35 read that did: the box' far edge, the second break and   |
//| the "never returned" test). The break's story is still read — on    |
//| the CLASS's own candles, as P-BK-38 read it — but it now names only |
//| the SIDE the trade comes in on (P-BK-46) and the step numbers that  |
//| size it. Two questions, one record, one read: the note, its hover,  |
//| the box tooltip and the pump's shadow can never describe two        |
//| different objects.                                                 |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// P-BK-77: `BaseKnotNodeTFMin` IS GONE (it read the box' own commit TF, its id TF, or this
// chart). It existed so the TYPE could be read on "the TF the node is seen on" — and the
// user draws the box with the MEASURING TOOL, so that TF was never evidence of anything: a
// node seen on M5 whose three candles belong to H1 is an H1 node. The node's TIME is now
// found from the box' own geometry (BaseKnotBaseTFRead, the whole ladder) and is the only
// TF the type is read against. The TF a box LIVES on is still a fact — the TF mask and the
// pump's id read own it — it just no longer names the node's time.
//+------------------------------------------------------------------+
//| P-BK-75 (2026-09-17) — THE TYPE IS THE BOX' HEIGHT AGAINST THE     |
//| MOVEMENT ABILITIES OF THE NODE'S OWN TF.                           |
//|                                                                  |
//| The user restated his own rule («باید اینطوری باشه»):              |
//|   «دسته بندی گره های معاملاتی براساس طول گره … اف تی ار (FTR):      |
//|   گرهی که طولش مساوی توان حرکتی تایمی باشد که گره در آن دیده        |
//|   میشود · ای تی ار(ETR): مساوی توان حرکتی تایم پترن · سی تی ار     |
//|   (CTR): مساوی توان حرکتی تایم ساختار · او تی ار (OTR): بیشتر از    |
//|   توان حرکتی تایم ساختار» + «تایم گره هم که باید سه کندل دیده بشه   |
//|   میشه تایم گره سه کندل درجا زدن» + «طول گره باید با th هر تایم     |
//|   مقایسه بکنی» + «ارتفاع باکس».                                    |
//|                                                                  |
//| «توان حرکتی تایم» IS THAT TIMEFRAME'S ATR (user decision,          |
//| 2026-09-17: «به جای th از atr استفاده بشه» — TH was the first      |
//| answer, ATR replaced it) — the PROJECT'S OWN composite ATR          |
//| (`CalculateWeightedATR`, ATRCalculations.mqh: the weighted SMA      |
//| blend over 5/10/21/66/132/264, the very number the strip and the    |
//| trade plan already read per TF). P-BK-78 (2026-09-17, user:        |
//| «اندازه گره متعلق به تایم بالاتر از تایم گره هستش پس باید ETR        |
//| بشه»): THE THREE ABILITIES ARE THREE TFs' OWN ATR — the node's     |
//| TIME (P-BK-77: the rung whose own three candles stood still), the   |
//| PATTERN time ONE rung above it, and the STRUCTURE time TWO rungs    |
//| above it. So "the size belongs to a higher time than the node's     |
//| time" IS the ETR reading, exactly as the user's own rule spells it  |
//| («مساوی توان حرکتی تایم پترن»), and the 0.25/0.50/1.00 ratios of    |
//| one ATR are gone: they could never say that.                       |
//|                                                                  |
//| THE LENGTH IS THE BOX' HEIGHT (top - bot, the user: «ارتفاع باکس») |
//| and the four names are the four bands that height falls in:        |
//|   h <= trigger   -> FTR — the node's own time's ability            |
//|   h <= pattern   -> ETR — the PATTERN time's (one rung above)      |
//|   h <= structure -> CTR — the STRUCTURE time's (two rungs above)   |
//|   h >  structure -> OTR — LONGER than the structure time's ability |
//| The bands ARE the levels because no name exists BELOW the trigger: |
//| the shortest node there is, IS the trigger length.                 |
//|                                                                  |
//| WHAT THIS REPLACED (BKNODERUNG-OFF, below): the rung count named   |
//| the type by a DURATION — the class the base was GIVEN (P-BK-36:   |
//| three candles of a higher rung standing still inside the band) —   |
//| while the user's rule names it by a PRICE. On one box the two      |
//| could disagree, and the class itself is read against the OPEN      |
//| CHART's TF (BaseKnotBaseTFMin takes no TF), so a TF switch could   |
//| move a type. The height read below takes the NODE's own TF and     |
//| nothing else.                                                      |
//|                                                                  |
//| LAYER LAW: the ATR lives ABOVE this module, so the three numbers   |
//| are PUSHED IN per TF exactly like the EngSL table (P-BK-46/50/51)  |
//| — `BaseKnotEngPump` (EventHandlers) computes one row per TF the    |
//| live boxes ask for and hands it back here. A TF with no row is an  |
//| ABSENCE (0 = "never pushed"), never a guess: the type then stays   |
//| BK_NODE_NONE and every text says so.                               |
//|                                                                  |
//| THE RULE LIVES HERE, NOT AT THE PUSH SITE: the pump hands in ONE   |
//| number per TF — that TF's ATR, nothing else — and this table       |
//| resolves the three abilities from the LADDER. A second place that  |
//| picked a rung or scaled an ATR would be a second owner of the rule.|
//+------------------------------------------------------------------+
#define BK_AB_TF_MAX BK_ENG_ROW_MAX
static int      s_bkAbTF[BK_AB_TF_MAX];
static datetime s_bkAbAnchor[BK_AB_TF_MAX];   // P-BK-79: the bar this ATR was read at
static double   s_bkAbATR[BK_AB_TF_MAX];   // that TF's own composite ATR, price units
static int      s_bkAbN = 0;
// One round of the pump opens with this, so a TF nobody asks for any more cannot
// answer a later question with a stale row.
void BaseKnotAbilityReset() { s_bkAbN = 0; }
// One row per (TF, ANCHOR) — the pump's own ask list (BaseKnotEngNeeds) is the list, so
// the ask and the answer can never disagree about which TFs a box draws with, nor about
// the bar. P-BK-79: the anchor is why this table needed a second key at all — two boxes
// on one TF whose bases ended on two bars must type against two different ATRs, and the
// live row (anchor 0) is the sizing preview's own. A repeated pair overwrites (the newest
// round wins) and a full table refuses quietly: both are bounded refusals, never an
// eviction that would silently drop another box's row.
//
// `atr` is that TF's composite ATR in PRICE units. 0 is the absence ("not warm"), and
// it is stored AS an absence: the row stays 0 and BaseKnotAbilityRow refuses it, so a
// cold ATR can never become a threshold of zero.
void BaseKnotAbilityPush(const int tfMin, const datetime anchor, const double atr)
{
   if(tfMin <= 0) return;
   datetime an = (anchor > 0 ? anchor : 0);   // 0 = the live row (P-BK-79)
   double v = (atr > 0.0) ? atr : 0.0;   // P-BK-78: ONE number per TF — the raw ATR
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      s_bkAbATR[i] = v;
      return;
   }
   if(s_bkAbN >= BK_AB_TF_MAX) return;
   s_bkAbTF[s_bkAbN]     = tfMin;
   s_bkAbAnchor[s_bkAbN] = an;
   s_bkAbATR[s_bkAbN]    = v;
   s_bkAbN++;
}
// ONE (TF, anchor) row's raw ATR. false = never pushed, or pushed while its ATR was not
// warm — an absence the caller reports, never a zero dressed up as a threshold.
bool BaseKnotAbilityRow(const int tfMin, const datetime anchor, double &atr)
{
   atr = 0.0;
   if(tfMin <= 0) return false;
   datetime an = (anchor > 0 ? anchor : 0);
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      atr = s_bkAbATR[i];
      return (atr > 0.0);
   }
   return false;
}
// P-BK-78 — THE THREE ABILITIES, OFF THE LADDER. `tfMin` is the NODE'S TIME (P-BK-77's
// own answer), and the three numbers are the ATR of THAT rung, of the rung ONE step above
// it (the PATTERN time, «تایم پترن») and of the rung TWO steps above it (the STRUCTURE
// time, «تایم ساختار»). P-BK-79: `anchor` is the bar all three are read at — the box' own
// story end — so one box has ONE type for ever once its base is closed. false = the node's
// time is unknown, the ladder has no rung above it (a MN1 node has no pattern time), or one
// of the three TFs was never pushed warm — an absence the caller turns into BK_NODE_NONE,
// never a band out of thin air.
bool BaseKnotAbilityGet(const int tfMin, const datetime anchor,
                        double &trig, double &pat, double &str)
{
   trig = 0.0; pat = 0.0; str = 0.0;
   if(tfMin <= 0) return false;
   int up1 = BaseKnotNextTFMin(tfMin);                          // the pattern time
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);            // the structure time
   if(up1 <= 0 || up2 <= 0) return false;                       // no rung above — nothing to compare against
   if(!BaseKnotAbilityRow(tfMin, anchor, trig)) return false;
   if(!BaseKnotAbilityRow(up1, anchor, pat)) return false;
   if(!BaseKnotAbilityRow(up2, anchor, str)) return false;
   return true;
}
// P-BK-75/76/78 — THE ONLY PLACE THE FOUR NAMES ARE SPELLED. `h` is the box' height (the
// length the user's rule compares); `nodeTFMin` is the NODE'S TIME (P-BK-77: the rung whose
// own three candles stood still), and the three thresholds are the ATRs of that rung and
// the two rungs above it (P-BK-78) — so no chart TF, drag or warm-up can move the type.
// BK_NODE_NONE = nothing to compare against (the node's time is unknown, the ladder has no
// rung above it, or one of the three ATRs is not warm) — an absence, never a band.
//
// P-BK-76 (2026-09-17, user: «هر کدوم از توان حرکتی به اندازه تایم تریگرش محدوده داره
// دیگه … توی مقایسه ها در نظر بگیرش زیاد خشک نباشه در مقایسات»): THE BOUNDARIES ARE THE
// MIDPOINTS, NOT THE LEVELS THEMSELVES. Each ability OWNS A RANGE around itself — half a
// trigger below its own level to half a trigger above — so a box landing a hair either
// side of an ability answers the ability it is NEAREST to instead of flipping on a knife
// edge. The midpoints are computed from the pushed abilities themselves, so nothing is
// hardcoded and a different ATR table moves them with it. OTR keeps the boundary the user
// named for it — «بیشتر از توان حرکتی تایم ساختار» — so the structure ability is CTR's
// ceiling and anything above it is OTR.
// P-BK-79: `anchor` is the bar the three abilities are read at — the box' own story end.
// 0 = the live row, which is what the sizing preview asks for before it has a base.
int BaseKnotNodeKindOfLength(const int nodeTFMin, const double h, const datetime anchor = 0)
{
   double trig = 0.0, pat = 0.0, str = 0.0;
   if(h <= 0.0) return BK_NODE_NONE;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return BK_NODE_NONE;
   if(h <= (trig + pat) * 0.5) return BK_NODE_FTR;   // midpoint of trigger | pattern
   if(h <= (pat + str) * 0.5)  return BK_NODE_ETR;   // midpoint of pattern | structure
   if(h <= str)                return BK_NODE_CTR;   // the structure ability itself
   return BK_NODE_OTR;
}
// P-BK-76: THE TWO BOUNDARIES, for the texts — the same midpoints the read above uses,
// so a tooltip cannot print a band the type was not decided by. P-BK-79: read at the SAME
// anchor the type was, or the printed band would describe another bar's ATR.
double BaseKnotNodeBandFtrEtr(const int nodeTFMin, const datetime anchor = 0)
{
   double trig = 0.0, pat = 0.0, str = 0.0;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return 0.0;
   return (trig + pat) * 0.5;
}
double BaseKnotNodeBandEtrCtr(const int nodeTFMin, const datetime anchor = 0)
{
   double trig = 0.0, pat = 0.0, str = 0.0;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return 0.0;
   return (pat + str) * 0.5;
}
//--- BKNODERUNG-OFF (P-BK-75, 2026-09-17): THE RUNG COUNT THAT NAMED THE TYPE.
//--- It read how many ladder rungs the base's class sat above the TF the node is seen
//--- on (P-BK-47). Retired IN PLACE because the user's rule names the type by the box'
//--- HEIGHT against the ATR abilities, not by a rung distance — restore by uncommenting
//--- the pair below, putting the two calls back into BaseKnotNodeRead and the live read
//--- (the sites BaseKnotNodeKindOfLength now occupies), and re-teaching
//--- base-count-audit's length cases to strip_comments() — never by rewriting the height
//--- read above, which owns the type now. `BK_NODE_RUNG_*` and the `nd.rungs` field stay
//--- as the retired pair's own vocabulary (they are the numbers the pair below compares
//--- against), but NOTHING reads them any more: the field is initialised to -1 and never
//--- set, and the audit's own mirror of the pair is retired the same way.
//
// int BaseKnotNodeRungs(const int nodeTFMin, const int classMin)
// {
//    if(nodeTFMin <= 0 || classMin == 0) return -1;   // no class measured -> no length
//    if(classMin < 0) return -1;                      // structure (1-2 candles): not a base
//    if(classMin == nodeTFMin) return BK_NODE_RUNG_FTR;
//    int rung = nodeTFMin;
//    for(int i = 0; i < 8; i++)                       // the ladder's own eight, bounded
//    {
//       rung = BaseKnotNextTFMin(rung);
//       if(rung <= 0) break;                          // the top of the ladder
//       if(rung == classMin) return i + 1;
//       if(rung > classMin) break;                    // a class the ladder cannot name
//    }
//    return -1;
// }
// int BaseKnotNodeKindOf(const int rungs)
// {
//    if(rungs == BK_NODE_RUNG_FTR) return BK_NODE_FTR;
//    if(rungs == BK_NODE_RUNG_ETR) return BK_NODE_ETR;
//    if(rungs == BK_NODE_RUNG_CTR) return BK_NODE_CTR;
//    if(rungs >  BK_NODE_RUNG_CTR) return BK_NODE_OTR;
//    return BK_NODE_NONE;
// }
// P-BK-48 — L4: the class rung's OWN drift, read closed-bar only and bounded to
// BK_BIAS_CTX_BARS of its bars. +1 = the rung drifts WITH this side, -1 = against it,
// 0 = unknown (no side to compare, series not ready). It is a LABEL, so a chart TF that
// never loads its rung costs one 0 and nothing else — it never decides a side on its own.
int BaseKnotCtxAlign(const int ctxTF, const int side)
{
   if(side == 0) return 0;
   int tf = (ctxTF > 0 && ctxTF != Period() ? ctxTF : 0);
   if(tf > 0 && !BaseKnotRungLoaded(tf)) return 0;
   double now  = iClose(_Symbol, tf, 1);                     // closed bars only
   double then = iClose(_Symbol, tf, BK_BIAS_CTX_BARS);
   if(now <= 0 || then <= 0 || now == then) return 0;         // never invented
   int drift = (now > then ? 1 : -1);
   return (drift == side ? 1 : -1);
}
// ONE read, TWO halves (P-BK-47 + P-BK-29/38 + P-BK-48 + P-BK-81): the LENGTH names the
// type, the base's own EXIT CANDLE names the direction. Fills `nd` — never returns early
// half-filled.
//
// P-BK-38 (2026-09-15) — THE STORY IS TOLD IN THE BASE'S OWN TF's CANDLES, and the
// window is expressed in THAT TF's bars. «از تایم بزرگ به کوچیک و از کوچیک به بزرگ
// باید همون etr نشون بده» is only true if the events are the SAME events: with the
// chart's closes a D1 base was read as "broke, returned, broke again" on H1 (the
// level is crossed all day long) and as "broke, returned, stayed" on D1, and the
// 128-bar window meant five days of story on H1 against six months on D1 — one box,
// two different SIDES, decided by which chart happened to be open. The candidate is
// the class P-BK-36 just confirmed (or this chart's TF when the box has no class
// yet), so the side belongs to the BASE, like its length and its class, and
// switching TFs on one box cannot rewrite it. A rung whose series is not loaded
// falls back to the chart's own closes, exactly as before.
//
// P-BK-81 (2026-09-17) — AND THE WALK NO LONGER STARTS AT THE DRAWN RECTANGLE. It starts
// at the base's OWN EXIT CANDLE (`tExit` — the candle that closed outside the band, the
// very candle the note's number is counted to). That single change is what the user's two
// reports asked for: «کمی که جابجا میکن نوع گره عوض میشه چرا» — the old start was the box'
// right edge, so nudging the box moved the first close the walk examined and the direction
// flipped; and «چرا جهت درست تشخیص نمیده» — on a chart coarser than the node's own time that
// edge sat a whole bar PAST the exit, so the walk's first close was a much later candle
// (often a return) and named the opposite side. One candle, one answer, on every chart.
void BaseKnotNodeRead(const datetime t2, const double top, const double bot,
                      const int nodeTimeMin, const datetime tExit,
                      const datetime anchor,   // P-BK-79: the bar the type's ATRs were pushed at
                      BaseKnotNode &nd)   // P-BK-81: tExit = the base's OWN exit candle
{
   // P-BK-78: ONE TF, TWO JOBS. `nodeTimeMin` is the NODE'S TIME — P-BK-77's answer, the
   // rung whose own three candles stood still — and it is BOTH the TF the type is read
   // against (P-BK-78: its ATR, the rung above's, the rung two above's) and the TF the
   // story is read on (P-BK-38). The box' own commit TF is no longer a separate fact here:
   // the user draws with the measuring tool, so the box' TF never named the node's time.
   // P-BK-79: `anchor` is the BOX' OWN STORY END — the bar the pump read the three ATRs at.
   // It must be handed in, never re-derived here: the pump keyed its rows on exactly this
   // value, and a second derivation (the box' right edge, `Period()`, "now") would ask for
   // a row nobody pushed and type every box BK_NODE_NONE. 0 = no story yet, which IS the
   // live row the sizing preview is answered by.
   nd.anchor = (anchor > 0 ? anchor : 0);
   nd.kind = BK_NODE_NONE; nd.rungs = -1; nd.nodeTF = nodeTimeMin; nd.baseTF = nodeTimeMin;
   nd.side = 0; nd.barsAgo = 0; nd.rebreaks = 0; nd.returned = false; nd.crossed = false;
   nd.baseStep = 0.0; nd.breakStep = 0.0; nd.retStep = 0.0; nd.storyTF = 0;
   nd.height = 0.0; nd.abTrig = 0.0; nd.abPat = 0.0; nd.abStr = 0.0;   // P-BK-75
   //--- (a) THE TYPE — the node's LENGTH against the ATR abilities of the node's own TIME
   //--- (P-BK-75/78). Read FIRST, because it needs nothing this module has to fetch: the TF
   //--- is P-BK-77's answer and the three thresholds were pushed in by the pump.
   //--- The rung count that used to name it is retired (BKNODERUNG-OFF).
   nd.height = top - bot;   // «طول گره» — the box' own height, in price units
   nd.kind = BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor);
   BaseKnotAbilityGet(nodeTimeMin, nd.anchor, nd.abTrig, nd.abPat, nd.abStr);   // published so the tooltip can spell the compare
   //--- (b) THE DIRECTION — P-BK-81: THE BASE'S OWN EXIT CANDLE. A box nobody has left
   //--- still answers 0, and the live price then decides the trade exactly as it did before
   //--- P-BK-46. The story walk below runs FORWARD from this same candle and only measures
   //--- the node's life (return, revisit, second break, far-edge close) — it can never name
   //--- a direction, which is the whole point of the change.
   if(top <= bot || t2 <= 0) return;
   if(s_bkStepATR > 0) nd.baseStep = (top - bot) / s_bkStepATR;
   int tfRead = 0;                        // 0 = this chart (MQL4's own "current" series)
   if(nodeTimeMin > 0 && nodeTimeMin != Period() && BaseKnotRungLoaded(nodeTimeMin))
      tfRead = nodeTimeMin;
   nd.storyTF = (tfRead > 0 ? tfRead : Period());
   int s2 = iBarShift(_Symbol, CompatTF(tfRead), t2, false);
   if(s2 <= 0) return;                    // the edge IS the newest candle — nothing happened after it
   // P-BK-48 — THE WHOLE PAST MARKET OF THIS NODE, from its right side to the newest
   // CLOSED candle, capped by BK_BIAS_MAX bars of the class' TF (the read stays bounded;
   // it is closed-bar data, so a new bar is the only thing that can move it).
   nd.lifeBars = (s2 > 1 ? s2 - 1 : 0);
   int oldest = s2 - BK_BIAS_MAX;
   if(oldest < 1) oldest = 1;             // shift 1 = the newest CLOSED candle (P-BK-34)
   // P-BK-81: WHERE THE WALK STARTS. The base's own exit candle, mapped onto the story TF —
   // `tExit` is the candle that closed outside the band (P-BK-44 reads it off the RUN, so it
   // is the base's own and never the drawn rectangle's). The box' right side is only the
   // FALLBACK: it is used when the base published no exit candle at all (a box whose story
   // has not been read yet) or when that candle is not a CLOSED bar of this TF.
   int start = s2 - 1;
   if(tExit > 0)
   {
      int sX = iBarShift(_Symbol, CompatTF(tfRead), tExit, false);
      if(sX >= 1) start = sX;
   }
   if(start < 1) return;                  // nothing closed to read — never invent a bar
   int    side = 0, brokeAt = 0, rebreaks = 0, revisits = 0, lastSide = 0;
   int    depBars = 0;
   bool   returned = false, insideBefore = true;
   double maxBreak = 0.0, maxRet = 0.0;
   for(int s = start; s >= oldest; s--)   // shifts fall as time grows — this IS chronological
   {
      double c = iClose(_Symbol, tfRead, s);
      if(c <= 0) continue;                // series not ready — skip, never invent a close
      bool inside = (c >= bot && c <= top);
      if(side == 0)
      {
         if(c > top)      { side =  1; maxBreak = c - top; brokeAt = s; depBars = 1; }
         else if(c < bot) { side = -1; maxBreak = bot - c; brokeAt = s; depBars = 1; }
         continue;                        // the break bar is not also a return
      }
      // P-BK-48: the DEPARTURE's own length — the leg that left the base, counted until
      // price first came back inside (it is «طول حرکت» the user reads the node by).
      if(!returned) depBars++;
      if(inside)
      {
         if(!insideBefore) revisits++;    // P-BK-48: a REVISIT — the market came back in
         insideBefore = true;
      }
      else
      {
         lastSide = (c > top ? 1 : -1);   // P-BK-48: the NEWEST close outside the band
         insideBefore = false;
      }
      if(side > 0)
      {
         if(c > top)           { maxBreak = MathMax(maxBreak, c - top); if(returned) rebreaks++; }
         else if(c < top)
         {
            returned = true; maxRet = MathMax(maxRet, top - c);
            // P-BK-35/47: back inside — and if it closed BELOW the box' floor it came
            // out the FAR edge. That is the story's own fact (it sends the trade to the
            // far side, BaseKnotNodeDir); it names no type any more.
            if(c < bot) nd.crossed = true;
         }
      }
      else
      {
         if(c < bot)           { maxBreak = MathMax(maxBreak, bot - c); if(returned) rebreaks++; }
         else if(c > bot)
         {
            returned = true; maxRet = MathMax(maxRet, c - bot);
            if(c > top) nd.crossed = true;   // the mirror image (broke down, ran out the top)
         }
      }
   }
   nd.side = side; nd.barsAgo = brokeAt; nd.rebreaks = rebreaks; nd.returned = returned;
   // BKPAT-OFF (P-BK-81): THE APPROACH LEG AND THE FOUR PATTERN NAMES LIVED HERE. The
   // approach walk read the last close outside the band before the base's own entry
   // (`tFrom`, P-BK-49) and `nd.pattern` was assigned from it and `side` — RBR/RBD/DBR/DBD.
   // Both are gone: RBR and DBR are the SAME direction (Buy) and RBD and DBD are the same
   // (Sell), so the approach could only ever have split continuation from reversal and the
   // four names carried no directional information the exit candle did not already carry.
   // The user's own call: «کلا از شر این rbr , dbd rbd خلاص بشیم و جهت سل و بای به صورت
   // صدردصدی درست تشخیص داده بشه». Restoring them means putting the walk, the two
   // assignments, `BaseKnotPatternName/Tag/Line`, the `BK_PAT_*` defines, the struct's
   // `approach`/`pattern`, the registry's `baseT` and the `tFrom` parameter back, AND
   // re-teaching the audit's gates named "the four names are GONE" — never by rewriting
   // the exit-candle start above, which owns the direction now.
   nd.depBars = depBars; nd.revisits = revisits; nd.lastSide = lastSide;
   if(s_bkStepATR > 0)
   {
      nd.breakStep = maxBreak / s_bkStepATR;
      nd.retStep   = maxRet   / s_bkStepATR;
   }
   // P-BK-48 — THE LIFE STATE (what the market DID with this node since it formed), and
   // the ladder that reads the side off it: CONSUMED first (the interest is spent, and
   // the knot then claims NO trade at all), then the departure, and only when the node's
   // own life says nothing does the LIVE price speak (P-BK-13's rule, sideLevel NONE).
   // P-BK-81: the state is a REPORT about the node's life — it never rewrites the side the
   // exit candle named (BKNODEDIR-OFF already retired the read that let it).
   if(side != 0)
   {
      if(nd.crossed)      nd.state = BK_STATE_CONSUMED;
      else if(returned)   nd.state = BK_STATE_TESTED;
      else                nd.state = BK_STATE_FRESH;
      nd.sideLevel = BK_SIDE_ZONE;
   }
   // P-BK-48 — L4, THE CONTEXT LABEL: whether the class rung the node belongs to is
   // drifting WITH the trade or AGAINST it. It is REPORTED, never a decider on its own.
   nd.ctxAlign = BaseKnotCtxAlign((nodeTimeMin > 0 ? nodeTimeMin : Period()), nd.side);
   // P-BK-48/81: the SIDE half is what makes a node readable on the PAST MARKET («برای
// اینکه سفارش گره بتونم پیدا کنم … شاید در گذشته مارکت هم تست کنمش»): the base's own exit
// candle says which way the orders were left, and the state says whether any of them
// survived.
// P-BK-47 — THE STORY ENDS HERE AND THE TYPE IS NOT ITS TO REWRITE. This is the
   // line the retired P-BK-29/35 rule lived on (BKNODEKIND-OFF): it set `nd.kind`
   // from `!returned` (FTR), `nd.crossed` (OTR), `rebreaks` (CTR) and otherwise ETR.
   // Restoring it means putting `nd.kind = ...` back into the branches below AND
   // re-teaching this audit's length cases — never by rewriting the length read
   // above, which owns the type now. Everything the walk found is still handed out:
   // it is what the life state and the hover's numbers are read from.
}

// BKPAT-OFF (P-BK-81): THE FOUR NAMES' OWN TEXT LIVED HERE — `BaseKnotPatternName`
// ("RBR"/"RBD"/"DBR"/"DBD"), `BaseKnotPatternTag` (the note's " · RBR" suffix) and
// `BaseKnotPatternLine` (the hover's "Pattern: RBR — price rallied into the base …"
// sentence). All three are gone, with the four defines they printed and the approach leg
// that fed them. The direction is now the base's own exit candle's close against the band
// (P-BK-81) and it is spelled by `BaseKnotExitLine` below — one bit, no name to get wrong.
// Restoring the names means restoring the whole BKPAT-OFF block, never re-adding them here
// alone (the audit's "the four names are GONE" gate is the reason).
// P-BK-81: the DIRECTION's own sentence — the ONE candle it was read from, and the promise
// that nothing the node did afterwards can move it. Same text on every chart TF and on the
// past market alike, because the candle is the base's own.
string BaseKnotExitLine(BaseKnotNode &nd)
{
   if(nd.side == 0) return "";
   string legOut = (nd.side > 0 ? "ABOVE the ceiling" : "BELOW the floor");
   return "\nDirection: " + (nd.side > 0 ? "BUY" : "SELL") + " — the base's own EXIT candle closed " +
          legOut +
          "\n      one candle, one answer: a return into the base, a second break of the edge and a" +
          "\n      close through the far edge are the node's LIFE (reported below), never its direction";
}
// The note's short name for a type ("FTR"), or "" for none.
string BaseKnotNodeShort(const int kind)
{
   if(kind == BK_NODE_FTR) return "FTR";
   if(kind == BK_NODE_ETR) return "ETR";
   if(kind == BK_NODE_CTR) return "CTR";
   if(kind == BK_NODE_OTR) return "OTR";
   return "";
}
// P-BK-46/81 — THE BASE'S OWN EXIT CANDLE NAMES THE SIDE, AND THE TRADE RIDES IT (user
// decision 2026-09-15: «براساس نوع گره ورود و تارگت ها مشخص بشه»):
//   * the exit candle CLOSED ABOVE the ceiling — the base was left upward, so the trade
//     comes in on the TOP edge (a buy above a broken ceiling);
//   * it CLOSED BELOW the floor — the base was left downward, so the trade comes in on
//     the BOTTOM edge.
// P-BK-47 moved the TYPE off the story (it is the node's length now) and P-BK-81 moved the
// SIDE onto the ONE candle the base actually left on: the walk's other facts — `returned`,
// `rebreaks`, `crossed` — are the node's LIFE and are REPORTED, never a direction. The
// order the retired read used (the far edge first, then the second break, then the return)
// is what BKNODEDIR-OFF retired: it let price REWRITE the side, which is exactly what the
// user's «کمی که جابجا میکن نوع گره عوض میشه» and «جهت درست تشخیص نمیده» were.
// 0 = the exit candle named nothing (no close outside the band yet, or no exit read): the
// live price decides instead, exactly as it did before P-BK-46. +1 = Buy, -1 = Sell.
int BaseKnotNodeDir(BaseKnotNode &nd)
{
   return nd.side;   // P-BK-81: the base's own EXIT CANDLE's close vs the band (ONE bit, FIXED)
   // BKNODEDIR-OFF (P-BK-49): the P-BK-46/48 read that let price REWRITE the side —
   // restore by uncommenting the four lines below.
   // BKNODEDIR-OFF: if(nd.state == BK_STATE_CONSUMED) return 0;   // P-BK-48: the orders are SPENT
   // BKNODEDIR-OFF: if(nd.rebreaks > 0) return nd.side;          // the same edge broke again
   // BKNODEDIR-OFF: if(nd.returned) return -nd.side;            // a return that stayed inside
   // BKNODEDIR-OFF: return nd.side;                              // never came back (FRESH)
}
// The name the course lists. P-BK-47: the PAIRS beside it (ABO/EBO/CBO/OBO) described
// the break's story — which named the type until the length rule and now names the
// trade's SIDE (BaseKnotNodeDir) — so the type answers the short name alone.
string BaseKnotNodeName(const int kind)
{
   return BaseKnotNodeShort(kind);
}
// Note suffix: " · FTR" / "" (nothing claimed — the note stays short).
string BaseKnotNodeTag(BaseKnotNode &nd)
{
   string s = BaseKnotNodeShort(nd.kind);
   return (s == "" ? "" : " · " + s);
}
// Hover sentence: the claim (the LENGTH), the story that named the side, and the step
// those numbers are in — a type without its numbers is a claim nobody can check.
string BaseKnotNodeLine(BaseKnotNode &nd, const double top, const double bot)
{
   if(nd.kind == BK_NODE_NONE) return "";
   string t = "\nNode: " + BaseKnotNodeShort(nd.kind) + " — ";
   if(nd.kind == BK_NODE_FTR)      t += "the node is as long as its own time's TRIGGER ability";
   else if(nd.kind == BK_NODE_ETR) t += "the node is as long as the PATTERN time's ability";
   else if(nd.kind == BK_NODE_CTR) t += "the node is as long as the STRUCTURE time's ability";
   else                            t += "the node is LONGER than the STRUCTURE time's ability";
   // P-BK-75/78: the length spelled the way it was MEASURED — the box' own HEIGHT against
   // the three ATR abilities of the LADDER: the node's own time (P-BK-77's answer), the
   // PATTERN time one rung above it, and the STRUCTURE time two rungs above it. Each number
   // is named with the TF it was read on, so the compare can be checked against the ladder.
   // The rung count that used to sit here is retired (BKNODERUNG-OFF); the class the base
   // was GIVEN (P-BK-36) still rides `nd.baseTF` and the note's own "… base" suffix.
   t += "\n      length: " + DoubleToString(BaseKnotToPips(nd.height), 1) + " pips (the box' height)";
   if(nd.abStr > 0.0)
   {
      int up1 = BaseKnotNextTFMin(nd.nodeTF);                      // the pattern time
      int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);            // the structure time
      t += " vs " + BaseKnotTFName(nd.nodeTF) + " ATR (trigger " + DoubleToString(BaseKnotToPips(nd.abTrig), 1) + ")" +
           " · " + BaseKnotTFName(up1) + " ATR (pattern " + DoubleToString(BaseKnotToPips(nd.abPat), 1) + ")" +
           " · " + BaseKnotTFName(up2) + " ATR (structure " + DoubleToString(BaseKnotToPips(nd.abStr), 1) + "), in pips";
      // P-BK-76: the bands the height fell in, spelled as the MIDPOINTS they are — so a box
      // a hair either side of an ability can be seen to still answer that ability.
      t += "\n      bands: FTR < " + DoubleToString(BaseKnotToPips(BaseKnotNodeBandFtrEtr(nd.nodeTF, nd.anchor)), 1) +
           " · ETR < " + DoubleToString(BaseKnotToPips(BaseKnotNodeBandEtrCtr(nd.nodeTF, nd.anchor)), 1) +
           " · CTR <= " + DoubleToString(BaseKnotToPips(nd.abStr), 1) + " · OTR above";
   }
   else
      t += " — the ATR of " + BaseKnotTFName(nd.nodeTF) + " (or of the rung above it) is not warm yet, so no type is claimed";
   t += "\n      the type is the HEIGHT against those three — the same on every chart TF";
   // P-BK-46/81: WHAT THE EXIT CANDLE DOES TO THE TRADE — the same rule BaseKnotNodeDir
   // and BaseKnotCalcLevels apply, spelled for the user: which edge the entry sits on
   // (the edge the base was LEFT by) and that the stop is one EngSL behind it.
   // P-BK-51: the placement — the edge is the SIDE's, BOTH legs sit inside it, and the
   // penetration's measure follows the node's TYPE (EngSL for FTR, HuntSL for the longer
   // ones). Built from the SAME two owners the geometry reads, so hover and drawing part not.
   int    wTF  = BaseKnotMeasureTFMin(nd.kind, nd.baseTF);
   bool   wHu  = BaseKnotOffsetIsHunt(nd.kind, wTF, nd.anchor);   // P-BK-79: the box' own anchor
   string wTag = BaseKnotEntryOffsetTag(wHu);
   if(nd.side == 0)
      t += "\n      trade: the live price names the side (the exit candle closed inside the band) — the entry waits ONE " +
           wTag + " INSIDE that edge, the stop ONE EngSL behind it" + BaseKnotCapClause(wTF, wHu, top, bot, nd.anchor);
   // BKNODEDIR-OFF (P-BK-49): else if(nd.crossed || (nd.returned && nd.rebreaks == 0))
   // BKNODEDIR-OFF (P-BK-49):   t += "\n      trade: the return's own side — entry ONE R INSIDE the FAR edge, stop 1 EngSL behind it";
   else
      t += "\n      trade: the side the base was LEFT by — entry ONE " + wTag +
           " INSIDE the edge the exit candle closed past, the stop ONE EngSL behind it" +
           BaseKnotCapClause(wTF, wHu, top, bot, nd.anchor) + BaseKnotExitLine(nd);
   if(nd.side != 0)
   {
      t += "\n      exit candle " + (nd.side > 0 ? "UP " : "DOWN ") + IntegerToString(nd.barsAgo) + " bars ago";
      if(nd.breakStep > 0) t += " · " + DoubleToString(nd.breakStep, 1) + "x step";
      if(nd.retStep > 0)   t += " · returned " + DoubleToString(nd.retStep, 1) + "x step";
      if(nd.crossed)       t += " · ran out the FAR edge";
      if(nd.rebreaks > 0)  t += " · " + IntegerToString(nd.rebreaks) + " re-break(s) of the edge";
   }
   if(nd.baseStep > 0)  t += " · base " + DoubleToString(nd.baseStep, 1) + "x step";
   if(s_bkStepATR > 0)
      t += "\n      step (ATR " + BaseKnotTFName(Period()) + ") = " + DoubleToString(BaseKnotToPips(s_bkStepATR), 1) + " pips";
   else
      t += "\n      step: unknown (ATR not warm yet)";
   // P-BK-38/81: and the EVENTS are the base's own TF's candles, not this chart's.
   if(nd.storyTF > 0)
      t += "\n      story read on " + BaseKnotTFName(nd.storyTF) +
           " candles (the base's own TF) — every chart reads the same side";
   return t;
}
// P-BK-29 — the ONLY way the step gets in (see the statics' note at the top).
// The change guard IS the design: a pump pushing the same ATR every round must
// re-read no note at all, while a value that really moved re-arms the pump's
// gate, so the new numbers land on their own — no flip and no tap needed to see
// them. P-BK-47: the step sizes the BREAK's story (and the R the trade is built
// in, P-BK-46) — it never decides the type, which is the node's LENGTH.
void BaseKnotStepPush(const double atr)
{
   double v = (atr > 0 ? atr : 0.0);
   if(v == s_bkStepATR) return;
   s_bkStepATR = v;
   s_bkNodeBar = 0;   // stale: the next pump re-reads every box' two answers
}
double BaseKnotStepATR() { return s_bkStepATR; }
// P-BK-46 — WHAT THE PUMP LAYERS HAVE TO COMPUTE: the (TF, ANCHOR) PAIRS the live boxes
// call their own. A box whose class is not published yet (and the box being SIZED, which
// has no registry row at all) answers THIS chart's TF at anchor 0, because that is the TF
// and the row the note and the sizing preview would name. Deduped and bounded, so the
// caller computes one EngSL per DISTINCT pair and nothing else: no box, no Eng beyond the
// chart's own.
// P-BK-79 (2026-09-17) — A PAIR, NOT A TF. Two boxes on the SAME TF whose bases ended on
// DIFFERENT bars read DIFFERENT EngSL / HuntSL / TP and are typed against DIFFERENT ladder
// ATRs, so a TF-keyed ask could only ever have one of them answered (the other would fall
// to `0` — the absence — and be sized by its own height). The anchor is the box' own
// `storyT`, the bar its story ended on, and it is the SAME value `BaseKnotNodeRead` is
// handed, so the ask and the read cannot key different rows. `storyT <= 0` (the base has
// not formed yet) asks the LIVE row, which is the row the sizing preview itself reads.
int BaseKnotEngNeeds(int &mins[], datetime &anchors[])
{
   int chartTF = Period();
   if(chartTF <= 0) chartTF = 1;
   int n = 0;
   mins[n] = chartTF; anchors[n] = 0; n++;     // the live sizing preview's own risk (P-BK-79: the LIVE row)
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      int tf = g_bkBoxes[i].baseTFMin;
      if(tf <= 0) tf = chartTF;                // no class published yet — the chart's own
      datetime an = (g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : 0);   // P-BK-79: the bar the story ended on
      // P-BK-78: AND THE TWO RUNGS ABOVE THE CLASS. The type compares the box' height
      // against the ATR of the node's own TIME, of the PATTERN time (one rung above) and of
      // the STRUCTURE time (two rungs above), so a box whose class sits at the ladder's foot
      // would otherwise have no row to be typed against and would answer BK_NODE_NONE for
      // ever. This is the ask side of the SAME rule BaseKnotAbilityGet applies, so the two
      // cannot drift apart. (Before P-BK-78 the slot carried the box' own TF, which stopped
      // naming anything once the type moved onto the class P-BK-77 finds.)
      // P-BK-51: the knot's OWN TF is the class (P-BK-46), and a CTR/OTR knot is measured
      // ONE RUNG ABOVE it («یک تایم بالاتر») — so ONE box can ask for FOUR TFs. They all go
      // through the same dedup, and every one of them is a rung of the same ladder, so the
      // table can never be asked for more than the eight per anchor.
      int asked[4];
      asked[0] = tf;
      asked[1] = BaseKnotNextTFMin(tf);
      asked[2] = (asked[1] > 0 ? BaseKnotNextTFMin(asked[1]) : 0);
      asked[3] = BaseKnotMeasureTFMin(g_bkBoxes[i].nodeKind, tf);
      for(int a = 0; a < 4; a++)
      {
         if(asked[a] <= 0) continue;
         // P-BK-79: the dedup is on the PAIR. The chart's own live row is (chartTF, 0) and
         // the loop below finds it, so the old `asked[a] == chartTF` shortcut is subsumed —
         // and it HAD to go: a box whose story ended on a bar asks (chartTF, storyT), which
         // is a different row and must survive.
         bool dup = false;
         for(int j = 0; j < n; j++) if(mins[j] == asked[a] && anchors[j] == an) { dup = true; break; }
         if(dup) continue;
         if(n >= BK_ENG_ROW_MAX) break;        // bounded: the rest waits for the next round
         mins[n] = asked[a]; anchors[n] = an; n++;
      }
   }
   return n;
}
// THE PUSH. The table is replaced wholesale and the EPOCH moves only when a stored
// row (TF or value) really differs from the last round — so a warm, unchanged chart
// pays a compare per entry and triggers no rebuild at all, while a new bar's EngSL
// (or a box that just published a class) re-arms the pump's gate. P-BK-50: the SAME
// row now carries the plan's three target legs, so ONE round hands over the risk AND
// the targets, and a leg that MOVED re-arms the gate exactly like a moved EngSL.
void BaseKnotEngPush(const int &mins[], const datetime &anchors[], const double &pips[],
                     const double &hunts[], const double &tp1[], const double &tp2[],
                     const double &tp3[], const int n)
{
   int      tfNew[BK_ENG_ROW_MAX];
   datetime anNew[BK_ENG_ROW_MAX];
   double pNew[BK_ENG_ROW_MAX];
   double hNew[BK_ENG_ROW_MAX];
   double t1New[BK_ENG_ROW_MAX];
   double t2New[BK_ENG_ROW_MAX];
   double t3New[BK_ENG_ROW_MAX];
   ArrayInitialize(tfNew, 0);        // explicit: the compare below reads the whole
   ArrayInitialize(anNew, 0);        // table even when this round pushed nothing
   ArrayInitialize(pNew, 0.0);       // P-BK-51: the Hunter leg, same rule
   ArrayInitialize(hNew, 0.0);
   ArrayInitialize(t1New, 0.0);
   ArrayInitialize(t2New, 0.0);
   ArrayInitialize(t3New, 0.0);
   int m = 0;
   for(int i = 0; i < n && m < BK_ENG_ROW_MAX; i++)
   {
      if(mins[i] <= 0) continue;
      tfNew[m] = mins[i];
      anNew[m] = (anchors[i] > 0 ? anchors[i] : 0);   // P-BK-79: 0 = the live row
      pNew[m]  = (pips[i] > 0.0 ? pips[i] : 0.0);   // <= 0 = not pushed, never a size
      hNew[m]  = (hunts[i] > 0.0 ? hunts[i] : 0.0); // P-BK-51: HuntSL, same absence rule
      t1New[m] = (tp1[i] > 0.0 ? tp1[i] : 0.0);     // P-BK-50: the plan's legs — an
      t2New[m] = (tp2[i] > 0.0 ? tp2[i] : 0.0);     // unpushed leg stays ABSENT
      t3New[m] = (tp3[i] > 0.0 ? tp3[i] : 0.0);
      m++;
   }
   bool moved = (m != s_bkEngN);
   for(int i = 0; !moved && i < m; i++)
      if(tfNew[i] != s_bkEngTF[i] || anNew[i] != s_bkEngAnchor[i] ||
         pNew[i] != s_bkEngPips[i] || hNew[i] != s_bkEngHunt[i] ||
         t1New[i] != s_bkEngTP1[i] || t2New[i] != s_bkEngTP2[i] || t3New[i] != s_bkEngTP3[i]) moved = true;
   for(int i = 0; i < m; i++)
   {
      s_bkEngTF[i] = tfNew[i]; s_bkEngAnchor[i] = anNew[i];
      s_bkEngPips[i] = pNew[i]; s_bkEngHunt[i] = hNew[i];
      s_bkEngTP1[i] = t1New[i]; s_bkEngTP2[i] = t2New[i]; s_bkEngTP3[i] = t3New[i];
   }
   s_bkEngN = m;
   if(moved) s_bkEngEpoch++;
}
// The pushed EngSL of one TF AT ONE ANCHOR, in pips. 0 = the pump has no value for that
// (TF, anchor) pair (never invented); tfMin <= 0 means THIS chart's TF (the sizing
// preview's question), and anchor 0 means the LIVE row (P-BK-79: a box with no story yet
// falls back to it rather than inventing a bar).
double BaseKnotEngPips(const int tfMin, const datetime anchor = 0)
{
   int tf = (tfMin > 0 ? tfMin : Period());
   if(tf <= 0) tf = 1;
   for(int i = 0; i < s_bkEngN; i++)
      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor) return s_bkEngPips[i];
   return 0.0;
}
bool BaseKnotRiskIsEng(const int tfMin, const datetime anchor = 0)
{ return (BaseKnotEngPips(tfMin, anchor) > 0.0); }
// P-BK-51 — THE HUNTER LEG, read back the same way: the pushed HuntSL of one TF at one
// anchor in pips, 0 = the pump has no value for it (never invented). It is what an
// ETR/CTR/OTR node's ENTRY waits for («به اندازه huntsl محل ورود»), while every stop stays
// ONE EngSL long.
double BaseKnotHuntPips(const int tfMin, const datetime anchor = 0)
{
   int tf = (tfMin > 0 ? tfMin : Period());
   if(tf <= 0) tf = 1;
   for(int i = 0; i < s_bkEngN; i++)
      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor) return s_bkEngHunt[i];
   return 0.0;
}
// P-BK-50 — THE PLAN'S OWN TARGET LEGS, per TF and anchor, exactly as the pump pushed
// them: TP1..TP3 in pips counted FROM THE ENTRY, which is how the label's `#TPn+` row
// counts them (the plan's legs are entry-relative by construction — the `#` field
// of that row is entry-to-level, and the stop is one of those legs). 0 = the pump
// has no value for that leg: an ABSENCE, never a guess.
double BaseKnotPlanTPPips(const int tfMin, const int k, const datetime anchor = 0)
{
   if(k < 1 || k > BK_TP_PLAN_MAX) return 0.0;
   int tf = (tfMin > 0 ? tfMin : Period());
   if(tf <= 0) tf = 1;
   for(int i = 0; i < s_bkEngN; i++)
      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor)
         return (k == 1 ? s_bkEngTP1[i] : (k == 2 ? s_bkEngTP2[i] : s_bkEngTP3[i]));
   return 0.0;
}
bool BaseKnotPlanWarm(const int tfMin, const datetime anchor = 0)
{ return (BaseKnotPlanTPPips(tfMin, 1, anchor) > 0.0); }
// HOW MANY plan legs a box draws. This IS the old `TARGET R` state (`g_bkTargetR` —
// same chart GV key `BXR`, same FF_ address, so a saved chart keeps its number), and
// P-BK-50 gave the same number a job that is still true: the row reads `TP COUNT`
// (1..3), and the old maximum 4 clamps into it instead of losing the setting.
int BaseKnotTPCount()
{
   int n = g_bkTargetR;
   if(n < 1) n = 1;
   if(n > BK_TP_PLAN_MAX) n = BK_TP_PLAN_MAX;
   return n;
}
// ONE plan target's LEVEL: the plan's pip leg of the knot's TF, measured from the
// ENTRY line — the line the user sees is the entry, so the target is where THAT
// line's own plan puts it. 0 = no level (leg absent, or no entry yet).
double BaseKnotTPLevel(const double entry, const int dir, const int tfMin, const int k,
                       const datetime anchor = 0)
{
   double p = BaseKnotPlanTPPips(tfMin, k, anchor);
   if(p <= 0.0 || entry <= 0.0) return 0.0;
   return (dir >= 0 ? entry + p * BaseKnotPipSize() : entry - p * BaseKnotPipSize());
}
// BKTAGTP-OFF (P-BK-54): THE NOTE'S TARGET FIELD IS RETIRED IN PLACE. The user: «تی پی رو
// … در اطلاعات نشون نده» — the note is read at a glance, the targets are drawn as ticks
// (P-BK-50) and spelled leg by leg in the hover (BaseKnotTPPlanTip, still live), so the
// field was three numbers between the risk and the bar count and nothing else. Restore by
// feeding this tag back into BaseKnotWriteInfo's text (the marked site in the note).
// P-BK-50 — the note's own field: the plan's targets in pips, as drawn. A plan that
// is not warm SAYS SO instead of printing a number nobody can check.
string BaseKnotTPPlanTag(const int tfMin, const datetime anchor = 0)
{
   int n = BaseKnotTPCount();
   string s = "";
   for(int k = 1; k <= n; k++)
   {
      double p = BaseKnotPlanTPPips(tfMin, k, anchor);
      if(p <= 0.0) continue;
      s += (StringLen(s) == 0 ? "" : "/") + DoubleToString(p, 0);
   }
   if(StringLen(s) == 0) return " | TP plan not warm yet";
   return " | TP " + s;
}
// ... and the hover's version: every drawn leg with its LEVEL and its pips from the
// entry, plus what those pips are in R (the box' stop is 1 R), so the tick on the
// chart can be checked against the plan row in the corner.
string BaseKnotTPPlanTip(const int tfMin, const double entry, const int dir, const double rPips,
                         const datetime anchor = 0)
{
   int n = BaseKnotTPCount();
   int dg = GetCachedDigits();
   string t = "";
   for(int k = 1; k <= n; k++)
   {
      double p = BaseKnotPlanTPPips(tfMin, k, anchor);
      double lv = BaseKnotTPLevel(entry, dir, tfMin, k, anchor);
      if(p <= 0.0 || lv <= 0.0) continue;
      // P-BK-50: BOTH readings are spelled out — pips from the ENTRY (how the plan row
      // counts them) and pips from the STOP line plus the R multiple that implies, so a
      // reader can check the tick against whichever of the two he has in mind.
      t += "\n     TP" + IntegerToString(k) + " " + DoubleToString(lv, dg) + " (+" +
           DoubleToString(p, 0) + " pips from the entry" +
           (rPips > 0.0 ? " = " + DoubleToString(p + rPips, 0) + " from the stop, " +
                          DoubleToString(p / rPips, 1) + "R" : "") + ")";
   }
   if(StringLen(t) == 0)
      t = "\n     the plan's targets are not warm yet (nothing pushed for " + BaseKnotTFName(tfMin) + ")";
   return t;
}
// P-BK-46 — R: THE PIPS EVERY LEG OF THE KNOT'S TRADE IS MEASURED IN. THE PLAN's EngSL of
// the knot's measure TF, BOUNDED by the node's own power (P-BK-52 — the plan's leg while it
// is no deeper than the node, the node's own EngSL when it is: the ATR cold case, a rung the
// terminal never loaded, a node smaller than the leg); the box' own height only when NEITHER
// answered. Never <= 0 for a real box, the SAME BaseKnotLegPick rule the geometry is drawn
// with (one owner), and the caller ALWAYS shows which of the three it got
// (BaseKnotRiskTag / BaseKnotStopWhy).
double BaseKnotRiskPips(const int tfMin, const double top, const double bot, const datetime anchor = 0)
{
   double p = BaseKnotLegPick(BaseKnotEngPips(tfMin, anchor), BaseKnotNodeEngPips(top, bot));
   if(p > 0.0) return p;
   return BaseKnotToPips(top - bot);
}
// How the risk is NAMED wherever it is shown — the badge's number and every stop /
// target tooltip: a size without its source is a number nobody can check.
// P-BK-52: the name is decided by the SAME rule the number was picked with, over the SAME
// pair, so a hover can never describe another measurement than the line it sits on.
// P-BK-53: and the name itself is the SHORT one (BaseKnotCapTag) — this is the string that
// reaches the chart-side note, so it says WHICH source spoke and nothing more.
// P-BK-57: the name the LAST rung wears (neither leg answered) has ONE owner here, because
// the note's own height field tests itself against it (see BaseKnotHeightTag): a renamed
// fallback could otherwise print the box' height twice in the same line.
string BaseKnotBoxHeightTag() { return "box height"; }
string BaseKnotRiskTag(const int measureTF, const int baseTF, const double top, const double bot,
                       const datetime anchor = 0)
{
   double plan = BaseKnotEngPips(measureTF, anchor);
   double cap  = BaseKnotNodeEngPips(top, bot);
   if(BaseKnotLegCapped(plan, cap)) return BaseKnotCapTag(false);
   if(plan > 0.0)
   {
      // P-BK-51: a CTR/OTR knot's numbers are read ONE TF HIGHER than its own class, and a
      // size without its source is a number nobody can check — so the reading TF rides
      // beside the name whenever it is not the class the note already prints.
      if(measureTF > 0 && baseTF > 0 && measureTF != baseTF)
         return "EngSL " + BaseKnotTFName(measureTF);
      return "EngSL";
   }
   return BaseKnotBoxHeightTag();
}
// P-BK-57 (2026-09-16, user: «مقدار حرکت رو هم به صورت عدد فقط نمایش بده بفهمیم چقدره»):
// THE NOTE'S SECOND NUMBER IS THE BOX' OWN HEIGHT IN PIPS, AND IT IS BARE. WHY: the risk
// says how big the STOP is, and the note never said how big the BOX is — the one size the
// whole box is read against (the step multiples, the candle count, the class). The user
// asked for the number on its own («به صورت عدد فقط»), so there is no name and no unit
// word on the chart face (P-BK-54's own rule); the HOVER names it, its arithmetic and its
// reading, so P-BK-46's promise (a size without its source is a number nobody can check)
// is kept where there is room for it.
// ONE OWNER: the number is `BaseKnotToPips(top - bot)` — the very expression the risk falls
// back to (BaseKnotRiskPips), so "the box' height" means ONE thing in this module.
// WRITTEN ONCE: when that fallback IS the risk (neither the plan nor the node's own leg
// answered) the first number already carries the height, so this field stays EMPTY and the
// note never prints the same size twice; the test is on the SOURCE (BaseKnotBoxHeightTag),
// never on the two values happening to be equal.
// THE GATE: tools/base-count-audit.py [note height] reads this body AND the note's own text
// expression — a name or unit word in the field, a second copy beside the fallback risk, or
// a box height that stopped coming from BaseKnotToPips fails the build.
string BaseKnotHeightTag(const double top, const double bot, const string riskTag)
{
   if(riskTag == BaseKnotBoxHeightTag()) return "";   // the risk already IS this height
   double p = BaseKnotToPips(top - bot);
   if(p <= 0.0) return "";                            // no box, no number
   return " | " + DoubleToString(p, 1);
}
// ... and the HOVER's own version of the SAME number — the split P-BK-53 made for the risk
// name (the chart face gets the NAME, the hover gets the proof), here for the box' size: one
// line that names it, spells the arithmetic (`top - bottom`) and gives its pips, so P-BK-46's
// promise is kept where there is room for it. The SAME test the field uses (`BaseKnotBoxHeightTag`)
// decides the wording, so a reader is never told to look for a second number the note did not
// print — the number itself and the test both stay owned here, and no caller spells either.
string BaseKnotHeightTip(const double top, const double bot, const string riskTag)
{
   double p = BaseKnotToPips(top - bot);
   if(p <= 0.0) return "";
   return "\n     box height (top - bottom) = " + DoubleToString(p, 1) + " pips - " +
          (riskTag == BaseKnotBoxHeightTag()
           ? "and it IS the risk above: the note prints it once"
           : "the note's own second number, in pips");
}
// P-BK-27 — THE INFO READOUT'S SIZE (user: «اطلاعات بیس نوت خیلی ریزه»).
// It used to be frozen at PnlPt(BK_PT_INFO): a DESIGN nominal, so on a 120-DPI
// terminal the readout drew at 6pt while the box' own text drew at
// `g_bkTextSize` (10 raw pt) — the numbers were the smallest text on the box.
// One owner now, two rungs:
//   * 0 (shipped) = the LABEL FAMILY's own size, `inpFontSize` (P-BK-56 — see below);
//   * 1..24 = the user's OWN raw points, the same unit the neighbouring SIZE /
//     COUNT SIZE / TRADE SIZE rows use. Never PnlPt here: that re-expresses the
//     module's NON-user chrome (P-UI-34), and a panel number that means a
//     different size than the number beside it is the bug, not the feature.
// P-BK-56 (2026-09-16, user: «این لیبل اطلاعات مثل بقیه لیبل اطلاعات باشه»): the shipped
// rung used to be the BOX' text size (`g_bkTextSize`, 10 raw pt), which made the note the
// one readout on the chart sized by a different grid than the label family it sits among
// (``Arial Bold`` 8pt — the ATR/TH columns and the trade card). The note IS that family's
// sibling — a chart-anchored text a human reads (P-UI-85's Z_CHART_LABEL rung) — so it
// follows the SAME grid now: font `inpFontName`, size `inpFontSize`, rung Z_CHART_LABEL.
// The box' own TEXT (the TV-style box label) keeps `g_bkTextSize`: it is box art, not a
// readout. BKINFOSIZE-OFF keeps the retired rung one uncomment away.
int BKInfoFontPt()
{
   int own = ClampSettingInt(g_bkInfoFontSize, 0, 24);
   if(own > 0) return own;                            // the user's own pt — unchanged
   return ClampSettingInt(inpFontSize, 4, 24);         // P-BK-56: the label family's grid
   // BKINFOSIZE-OFF (P-BK-27/56): the retired rung — the box' own text size.
   // BKINFOSIZE-OFF: return ClampSettingInt(g_bkTextSize, 8, 24);
}
// Chart-anchored "[<side> · <riskTag> <risk> | <box height> | N bars · <class> <type>]"
// label at the box' top-right corner (P-BK-57: the second number, bare — BaseKnotHeightTag).
// P-BK-46: the first number is the TRADE'S RISK (R) and `riskTag` NAMES WHERE IT
// CAME FROM — "EngSL" of the knot's own TF (or the node's own when it capped the plan,
// P-BK-52/53), or "box height" while neither answered. A size without its source is a
// number nobody can check.
// P-BK-54 (2026-09-16, user: «تی پی رو … در اطلاعات نشون نده … EngSL 17.9 همین بنویسه
// فقط اینطوری خلاصه‌ه») — THE NOTE CARRIES NO TARGETS AND NO UNIT WORD. WHY: the note is
// read AT A GLANCE on a live chart, and the plan's TP1..TP3 field made it a sentence:
// three numbers the user did not ask for, printed between the risk and the bar count,\r
// while the targets are ALREADY DRAWN (P-BK-50's ticks) and ALREADY SPELLED OUT leg by
// leg in the hover (`tpTip`). So the field is retired IN PLACE (BKTAGTP-OFF —
// `BaseKnotTPPlanTag` is kept, one call away) and the risk reads `EngSL 17.9`, the unit
// implied by the plan's own row (the TRex card prints `Eng.SL: 0.2` the same way).
// WHAT IS NOT AFFECTED: the hover still prints every leg with its level, its pips from
// the entry and its R (BaseKnotTPPlanTip), and the ticks on the chart are unchanged.
// P-BK-57 (2026-09-16, user: «مقدار حرکت رو هم به صورت عدد فقط نمایش بده بفهمیم چقدره»)
// — the SECOND number is the box' OWN HEIGHT, bare (BaseKnotHeightTag): the risk says how
// big the stop is, this says how big the thing the order is read on is. The chart face
// keeps the number alone; the hover right below names it, spells `top - bottom` and gives
// its pips, so the number is checkable where there is room to check it (P-BK-46/53's split).
// THE GATE: tools/base-count-audit.py [note fields]/[note height] reads the note's own TEXT
// expression AND the field's builder — a target field, the word "Pips", or a height field
// that grew a name (or a second copy beside the fallback risk) fails the build.
void BaseKnotWriteInfo(const string in, const datetime t1, const datetime t2,
                       const double top, const double bot,
                       const double hPips, const string tpTip,
                       const string side, BaseKnotSpan &sp,
                       BaseKnotNode &nd, const long tfMask, const string riskTag,
                       const string tradeTip,   // P-BK-51: the stop's sentence + the entry's own
                       const bool atCorner = false)   // P-BK-58: the family's row instead of the box
{
   // P-BK-58: ONE object at a time. The placement is a PARAMETER (decided by
   // BaseKnotNoteAtCorner), and the other home is emptied as this one is written, so a mode
   // change can never leave two copies of the same number on the chart. The box-side note is
   // an OBJ_TEXT pinned to the box' top-right corner (time/price); the corner row is an
   // OBJ_LABEL pinned to the slot the label module pushed in — the same text, the same font,
   // size, colour and rung (P-BK-27/56), only its anchor differs.
   string cn = BaseKnotCornerName();
   if(atCorner)
   {
      if(cn == "" || s_bkCornerSide < 0) return;   // no slot pushed: nothing to draw into
      if(ObjectFind(0, in) >= 0) ObjectDelete(0, in);   // the box-side copy goes with the mode that wanted it
   }
   else if(!BaseKnotNoteInCorner() && cn != "" && ObjectFind(0, cn) >= 0)
      ObjectDelete(0, cn);   // a MODE change took the note back to the box (P-BK-58); while the mode
                             // IS corner the row belongs to BaseKnotNoteCornerRefresh, so a box that
                             // is not the one it answers never wipes it
   // ONE name: everything below is the SAME write in either home — the text, the font, the
   // size, the colour, the rung and the hover are shared, and only the last four lines differ.
   string o = (atCorner ? cn : in);
   if(ObjectFind(0, o) < 0) ObjectCreate(0, o, (atCorner ? OBJ_LABEL : OBJ_TEXT), 0, t2, top);
   int bars = sp.life, still = sp.still;   // P-BK-41: one span, read once
   string barsPart = (bars > 0 ? " | " + IntegerToString(bars) + " bars" : "");
   // P-BK-28: the BASE'S SIZE CLASS rides the note itself — "… | 12 bars · H1 base".
   // P-BK-29: so does the node type — "… · FTR" — when there is one to claim.
   // BKTAGTP-OFF (P-BK-54): the retired plan-target field sat here — restore it by
   // putting `+ tpTag` back after the risk (and taking BaseKnotTPPlanTag from BKTAGTP-OFF
   // in BaseKnotSync / BaseKnotSyncLive, which still build `tpTip` for the hover).
   ObjectSetString(0, o, OBJPROP_TEXT,
                   "[" + side + " · " + riskTag + " " + DoubleToString(hPips, 1) + BaseKnotHeightTag(top, bot, riskTag) + barsPart + BaseKnotBaseTag(still, t1, t2, top, bot) + BaseKnotNodeTag(nd) + "]");   // P-BK-46/40/41: the risk and its source, then the box' own height (P-BK-57), then the class — P-BK-80: off the BOX' own two anchors, so the chart TF cannot move it. P-BK-81: the four pattern names are gone — `side` (BUY/SELL) IS the direction now
   ObjectSetString(0, o, OBJPROP_FONT, inpFontName);   // P-BK-56: the label family's own font
   ObjectSetInteger(0, o, OBJPROP_FONTSIZE, BKInfoFontPt());   // P-BK-27/56
   ObjectSetInteger(0, o, OBJPROP_COLOR, BaseKnotFgForBg());
   ObjectSetInteger(0, o, OBJPROP_ANCHOR, (atCorner ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER));   // P-BK-58: the row is right-aligned in the family's column
   ObjectSetInteger(0, o, OBJPROP_BACK, false);
   ObjectSetInteger(0, o, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, o, OBJPROP_HIDDEN, true);
   // P-BK-56: the note is TEXT A HUMAN READS, so it rides the TEXT layer's rung — the rung
   // the whole label family writes (P-UI-85) and the one that is ABOVE every chart-space art
   // rung, so no box, ray, zone edge or drawn HTF candle can be painted over it. It used to
   // ride Z_BOX_INFO (60): the box family's own rung, i.e. under the box' art and under every
   // label. P-BK-58: the corner row is the same readout, so it rides the same rung.
   ObjectSetInteger(0, o, OBJPROP_ZORDER, Z_CHART_LABEL);
   ObjectSetInteger(0, o, OBJPROP_TIMEFRAMES, tfMask);
   // P-BK-51: the trade's numbers arrive READY-BUILT (`tradeTip` — the stop's size and its
   // placement behind the entry, then how deep the entry waits and what sized it), so this
   // writer never spells a geometry of its own.
   ObjectSetString(0, o, OBJPROP_TOOLTIP, "BK " + side + ": " + tradeTip +
                   (bars > 0 ? ", " + IntegerToString(bars) + " bars" : "") +
                   tpTip +   // P-BK-50: the plan's own targets, leg by leg (level + pips + R) — P-BK-54: the note's ONLY home for them
                   BaseKnotHeightTip(top, bot, riskTag) +   // P-BK-57: the note's bare second number, NAMED here, with its arithmetic
                   BaseKnotBaseLine(still, t1, t2, top, bot) +   // P-BK-80: the class, off the BOX' own two anchors
                   (bars > 0 ? "\n     " + IntegerToString(bars) + " bars: between the ENTRY candle " +
                               "and the EXIT candle (entry not counted, exit counted) · " +
                               IntegerToString(still) + " stood still in the band" : "") +   // P-BK-40/42
                   (bars > 0 ? "\n     band -> entry candle " + TimeToString(sp.tStart, TIME_DATE|TIME_MINUTES) +
                               (sp.tExit > sp.tLast
                                ? " -> exit candle " + TimeToString(sp.tExit, TIME_DATE|TIME_MINUTES)
                                : " -> no exit yet: the base is still holding the band") : "") +
                   BaseKnotNodeLine(nd, top, bot) +   // P-BK-29
                   (atCorner ? "\n     the row above the trade card is this box' note (P-BK-58): " +
                               "the selected box, or the newest while nothing is selected" : ""));
   // P-BK-58: the ONE difference between the two homes — a chart-space text pinned to the box'
   // corner, or a corner-anchored label pinned to the slot the label module pushed in.
   if(atCorner)
   {
      ObjectSetInteger(0, o, OBJPROP_CORNER, s_bkCornerSide);
      ObjectSetInteger(0, o, OBJPROP_XDISTANCE, MathMax(8, s_bkCornerX));
      ObjectSetInteger(0, o, OBJPROP_YDISTANCE, MathMax(8, s_bkCornerY));
   }
   else
   {
      ObjectSetInteger(0, o, OBJPROP_TIME, 0, t2);
      ObjectSetDouble(0, o, OBJPROP_PRICE, 0, top);
   }
}
// Live sizing set — Entry/SL/TP + info shown WHILE drawing (before click 2).
// ONE fixed tag (single sizing at a time); wiped at commit/cancel/deinit.
string BaseKnotLiveTag()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "LIVE_";
}
void BaseKnotWipeLive()
{
   string tag = BaseKnotLiveTag();
   if(tag != "") ObjectsDeleteAll(0, tag);
}
// Live setup preview from corner 1 to the cursor. Direction re-resolves here;
// the commit freezes it. Zero-height cursor = rays hidden, preview rect stays.
void BaseKnotSyncLive(const datetime t2raw, const double p2raw)
{
   string tag = BaseKnotLiveTag();
   if(tag == "") return;
   double top = MathMax(g_bkP1, p2raw), bot = MathMin(g_bkP1, p2raw);
   if(top <= bot) { BaseKnotWipeLive(); return; }
   datetime t1 = g_bkT1, te = t2raw;
   if(te < t1) { datetime tt = t1; t1 = te; te = tt; }
   int dir = BaseKnotResolveDirection(top, bot);
   long tfMask = BaseKnotTFMask(Period());
   // P-BK-46/50: the preview is sized the SAME way the committed box is, with THIS
   // chart's TF as the knot's own — a box being drawn has no class and no type yet
   // (both are readings of the whole story and land at commit), so the side is the
   // live price's, R is EngSL of this chart's TF and the targets are that TF's own
   // plan legs. The commit re-reads all of them.
   // P-BK-51: and with no TYPE there is no HuntSL read either — the preview is the FTR
   // case (ONE EngSL of penetration), and the stop is ONE EngSL behind the entry.
   // P-BK-79: AND WITH NO STORY YET THERE IS NO ANCHOR — every read below asks for the LIVE
   // row (anchor 0), which is exactly the row BaseKnotEngNeeds always pushes first for this
   // chart's TF. The committed Sync re-reads all of them at the box' own `storyT`.
   int    liveTF = Period();
   double entry = 0, sl = 0;
   BaseKnotCalcLevels(top, bot, dir, BK_NODE_NONE, liveTF, entry, sl, 0);
   string riskTag   = BaseKnotRiskTag(liveTF, liveTF, top, bot, 0);   // P-BK-52: named with the number the pick drew
   double hPips  = BaseKnotRiskPips(liveTF, top, bot, 0);
   int dg = GetCachedDigits();
   string side = (dir >= 0 ? "BUY" : "SELL");
   // BKTAGTP-OFF (P-BK-54): string tpTag = BaseKnotTPPlanTag(0);   // the retired note field
   string tpTip = BaseKnotTPPlanTip(0, entry, dir, hPips, 0);   // P-BK-54: the hover keeps every leg
   string edgeLive  = (dir >= 0 ? "top" : "bottom");
   string lvWhy = " (ONE " + BaseKnotEntryOffsetTag(false) + " INSIDE the box' " + edgeLive +
                  " edge — " + BaseKnotEntryWhy(BK_NODE_NONE, liveTF, false, top, bot, 0) + ")";
   string stopWhyLive = " (INSIDE the box' " + edgeLive + " edge, ONE " + riskTag + " behind the entry" +
                        BaseKnotStopWhy(liveTF, top, bot, 0) + ")";
   string tradeTipLive = "risk " + DoubleToString(hPips, 1) + " pips (" + riskTag + ") = the stop" + stopWhyLive +
                         BaseKnotEntryLine(BK_NODE_NONE, liveTF, false, dir, top, bot, 0);
   datetime tLiveFar = te + (te > t1 ? (te - t1) : PeriodSeconds());
   datetime tLiveTps, tLiveTpe;
   BaseKnotTPTickSpan(t1, te, tLiveTps, tLiveTpe);
   BaseKnotMakeRay(tag + "ENTRY", te, tLiveFar, entry, g_bkEntryColor, STYLE_SOLID, BK_LEVEL_WIDTH,
                   "BK " + side + " Entry (sizing): " + DoubleToString(entry, dg) + lvWhy, tfMask, true);
   BaseKnotMakeRay(tag + "SL", te, tLiveFar, sl, g_bkStopColor, STYLE_DASH, BK_LEVEL_WIDTH,
                   "BK " + side + " Stop (sizing): " + DoubleToString(sl, dg) + stopWhyLive, tfMask, true);
   // P-BK-50: the targets are the plan's own legs — one short, THICK tick each at the
   // chart's right edge (never a ray), drawn only for the legs the plan has pushed.
   for(int tk = 1; tk <= BaseKnotTPCount(); tk++)
   {
      double lv = BaseKnotTPLevel(entry, dir, 0, tk, 0);
      if(lv <= 0.0) continue;
      double tpP = BaseKnotPlanTPPips(0, tk, 0);
      BaseKnotMakeRay(tag + "TP" + IntegerToString(tk), tLiveTps, tLiveTpe, lv, g_bkTargetColor,
                      BK_TP_TICK_STYLE, BK_TP_TICK_WIDTH,
                      "BK " + side + " TP" + IntegerToString(tk) + " (sizing): " + DoubleToString(lv, dg) + " (+" +
                      DoubleToString(tpP, 0) + " pips from the entry" +
                      (hPips > 0.0 ? " = " + DoubleToString(tpP + hPips, 0) + " from the stop, " +
                                     DoubleToString(tpP / hPips, 1) + "R" : "") +
                      " — the plan's own TP" + IntegerToString(tk) + ")", tfMask, false);
   }
   BaseKnotSpan spLive;   // P-BK-41: the live label reads the same span record
   BaseKnotLiveBarCount(t1, te, top, bot, spLive);
   // P-BK-29: a box being SIZED pays no STORY read here — the walk of the past market
   // (side, break, second break, state) is what the hot sizing path must not run per mouse
   // move; the committed Sync reads it.
   // P-BK-55 (2026-09-16, user: «توی اطلاعات چرا نوع گره رو نشون نمیده»): THE TYPE IS NOT
   // THAT READ. The type is the node's LENGTH (P-BK-75/78: the box' own HEIGHT against the
   // ATRs of the node's own time and the two rungs above it) — pure arithmetic on numbers
   // the module was PUSHED, no series and no ATR call, so a box being SIZED answers it from
   // the VERY span its class came from. The sizing note used to show a class with no type.
   // ONE RULE, ONE READ: the same two owners the committed read uses
   // (BaseKnotBaseTFMin for the node's time, BaseKnotNodeKindOfLength for the type).
   // The record is zeroed in the SAME shape BaseKnotNodeRead opens with, so an unread half
   // can never be a garbage field the hover prints.
   BaseKnotNode ndLive;
   ndLive.anchor = 0;   // P-BK-79: the preview has no base yet, so it asks for the LIVE row
   ndLive.kind = BK_NODE_NONE; ndLive.rungs = -1; ndLive.nodeTF = 0; ndLive.baseTF = 0;
   ndLive.side = 0; ndLive.barsAgo = 0; ndLive.rebreaks = 0;
   ndLive.returned = false; ndLive.crossed = false;
   ndLive.baseStep = 0.0; ndLive.breakStep = 0.0; ndLive.retStep = 0.0; ndLive.storyTF = 0;
   ndLive.state = 0; ndLive.depBars = 0; ndLive.depStep = 0.0;
   ndLive.revisits = 0; ndLive.lastSide = 0; ndLive.lifeBars = 0;
   ndLive.ctxAlign = 0; ndLive.sideLevel = 0;
   // ... and the TYPE half is read, off the span the note's class came from (P-BK-55).
   int liveClass = BaseKnotBaseTFMin(spLive.still, t1, te, top, bot);   // P-BK-80: the node's time, off the box' own two anchors
   ndLive.height = top - bot;   // P-BK-75: «طول گره» is the box' own height
   ndLive.kind   = BaseKnotNodeKindOfLength(liveClass, ndLive.height, ndLive.anchor);   // P-BK-78/79: the SAME node's time and the SAME anchor the committed read uses
   BaseKnotAbilityGet(liveClass, ndLive.anchor, ndLive.abTrig, ndLive.abPat, ndLive.abStr);
   ndLive.nodeTF = liveClass;   // P-BK-78: the TF the type was read against, published for the hover
   ndLive.baseTF = liveClass;
   bool liveCorner = BaseKnotNoteAtCorner("");   // P-BK-58: while the user SIZES, the row is the answer
   BaseKnotWriteInfo(tag + "INFO", t1, te, top, bot, hPips, tpTip, side,
                     spLive, ndLive, tfMask, riskTag, tradeTipLive, liveCorner);   // P-BK-55: the type rides in `ndLive`
}
// INFO text is chart-anchored and only TF-gated (no pixel button —
// NOBKDEL 2026-09-06: the X delete badge is retired, boxes delete via
// select + Delete key). TF-hidden boxes stay hidden here even when
// their corner is on-screen.
void BaseKnotPlaceBadges(const string pfx, const datetime t1, const datetime t2,
                          const double top, const int tfMin, const long tfMask)
{
   bool tfVis = BaseKnotTFVisible(tfMin);
   string in = BaseKnotInfoName(pfx);
   ObjectSetInteger(0, in, OBJPROP_TIMEFRAMES, (tfVis ? tfMask : OBJ_NO_PERIODS));   // AND the commit mask — never plain ALL
   if(!tfVis) return;
   ObjectSetInteger(0, in, OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, in, OBJPROP_PRICE, 0, top);
}
//+------------------------------------------------------------------+
//| P-BK-59 (2026-09-16) — THE CENTRE GRIP WEARS THE BORDER'S OWN INK.|
//|                                                                  |
//| The dot a user sees in the middle of a SELECTED box is NOT drawn  |
//| by this module: MetaTrader paints its own selection marker there  |
//| (a 2x2 WHITE square, plus one on each control corner — «the       |
//| object can be considered as selected if square markers … appear», |
//| MT4 Help), and it is white on every chart, which is why it        |
//| vanishes on a white background and why no EA call can recolour it.|
//| What CAN be done is cover it: the marker is painted WITH the object|
//| and therefore BELOW every rung above it — the amber edges already  |
//| clip the two corner markers exactly this way (visible in the user's|
//| own screenshot) — so a SCREEN square of our own, wearing the box'  |
//| border ink, hides it whole. A screen object (OBJ_RECTANGLE_LABEL)  |
//| is painted above the whole chart layer (P-UI-31's ladder), so the  |
//| cover cannot be defeated by a re-paint of the chart's own art.    |
//|                                                                  |
//| PLACEMENT IS THE MARKER'S OWN: the box' PIXEL centre, from the two|
//| corners the terminal marks, one read-only ChartTimePriceToXY pair |
//| per pass (never a guess at the chart's zoom, and the same pattern  |
//| BaseKnotGrabRole already uses). A conversion that fails (a box     |
//| scrolled out of the window by TIME) retires the grip: the terminal |
//| draws no marker for an object it cannot place either.              |
//|                                                                  |
//| IT MIRRORS THE TERMINAL, it never invents state: the grip exists   |
//| exactly while MT4 would draw that marker — the box is SELECTABLE   |
//| (unlocked) and SELECTED — so a chart nobody has clicked gains      |
//| nothing. The 500 ms pump is the keeper (selection is an event that |
//| pass already watches, P-BK-58), the drag's own child step carries  |
//| it while the hand moves the box, and the sizing PREVIEW stays out  |
//| of it: the rubber band draws no selectable object, so there is no  |
//| marker to cover until the box is committed.                        |
//+------------------------------------------------------------------+
// P-BK-59 size (2026-09-16, user: «این وسط باکس اون نقطه ضخیم بشه دیده نمیشه
// 5 باشه»): MT4's own marker is a 2x2 at the box' centre, and a 3x3 cover of it
// was still easy to MISS on a busy chart (the user's own screenshot: a navy box
// on a dark chart). 5 px is the user's number — it still reads as a dot on a
// 160x60 px box, and it leaves a clear margin around the marker it covers.
#define BK_DOT_SIZE 5   // px — the user's size (5), always ODD so it centres on one pixel
string BaseKnotDotName(const string pfx)   { return pfx + "DOT"; }
// The box' PIXEL centre — the point the terminal's marker is drawn on.
bool BaseKnotDotPixel(const datetime t1, const datetime t2, const double top, const double bot,
                      int &cx, int &cy)
{
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(!ChartTimePriceToXY(0, 0, t1, top, x1, y1)) return false;
   if(!ChartTimePriceToXY(0, 0, t2, bot, x2, y2)) return false;
   cx = (x1 + x2) / 2;
   cy = (y1 + y2) / 2;
   return true;
}
// Create + style once: the ink is written here and re-compared on later passes.
void BaseKnotDotCreate(const string name, const color clr, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_DOT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_DOT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);     // the frame …
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);   // … and the fill: ONE ink, the border's
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);   // the BOX is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_DOT);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);   // a box hidden on this TF carries no marker
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   "BK box centre grip (P-BK-59): the box' own border ink, drawn over MetaTrader's " +
                   "white selection marker — drag the BOX, never the grip");
}
// Keep or retire the grip of ONE box. Returns true when it wrote anything, so
// the caller can pay ONE repaint (MT4 repaints on every ObjectSet*). Steady state
// is reads only: zero writes while the box, its selection and the ink are still.
bool BaseKnotDotFollow(const string pfx, const datetime t1, const datetime t2,
                       const double top, const double bot, const bool selectable,
                       const bool selected, const color clr, const long tfMask)
{
   if(pfx == "") return false;
   string nm = BaseKnotDotName(pfx);
   if(!selectable || !selected)
   {
      if(ObjectFind(0, nm) >= 0)   // the box is locked, or nothing selected it — the terminal
      {                            // draws no marker here, so the grip goes with it
         ObjectDelete(0, nm);
         return true;
      }
      return false;
   }
   int cx = 0, cy = 0;
   if(!BaseKnotDotPixel(t1, t2, top, bot, cx, cy))   // off the window by TIME: no placeable dot
   {
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); return true; }
      return false;
   }
   if(ObjectFind(0, nm) < 0)
   {
      BaseKnotDotCreate(nm, clr, tfMask);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, cx - BK_DOT_SIZE / 2);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, cy - BK_DOT_SIZE / 2);
      return true;
   }
   bool wrote = false;
   if((color)ObjectGetInteger(0, nm, OBJPROP_BGCOLOR) != clr)   // the card's border colour moved
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, clr);
      wrote = true;
   }
   if((long)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != tfMask)
   {
      ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, tfMask);
      wrote = true;
   }
   int nx = cx - BK_DOT_SIZE / 2, ny = cy - BK_DOT_SIZE / 2;
   if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != nx ||
      (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != ny)
   {
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, nx);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ny);
      wrote = true;
   }
   return wrote;
}
//+------------------------------------------------------------------+
//| P-BK-61 (2026-09-16) — THE GRIP HANDLES.                          |
//|                                                                  |
//| «یک کلیک چپ میکنم راحت هر طرف که بخوام میکشم اینطوری باشه» — the |
//| user's own TradingView screenshot: a selected rectangle wearing    |
//| handles. WHY THEY MUST BE OUR OWN OBJECTS: MetaTrader's own        |
//| rectangle has NO resize points at all (a native drag moves the     |
//| rectangle has NO resize points at all (a native drag moves the     |
//| whole rect), so resize was reachable only through the cursor       |
//| fallback P-BK-18/P-BK-19 retired (BKCURSOR-OFF) — i.e. today it is |
//| simply absent, which is exactly what the user reported.           |
//|                                                                  |
//| MT4 DRAGS OUR CHIP, AND WE WRITE THE BOX. Each handle is a 9x9    |
//| SCREEN square (OBJ_RECTANGLE_LABEL — the family the P-BK-59 grip  |
//| and every card already live in), filled with the box' own border  |
//| ink, sitting exactly ON the point it moves. `SELECTABLE` is the   |
//| whole feature: the terminal hands a press on a selectable screen  |
//| object to its OWN drag — the very thing P-BK-59 had to refuse     |
//| («drag the BOX, never the grip»). So the hand never touches the    |
//| box, the ONE writer of the gesture is this module, and the reading |
//| is the CHIP'S OWN PIXEL (OBJECT_DRAG carries no trusted cursor —   |
//| the box' own follow reads live anchors for the same reason).       |
//|                                                                  |
//| WHEN THEY EXIST: exactly while the box would show MT4's selection |
//| markers — unlocked AND selected (P-BK-59's rule) — PLUS the one    |
//| case that rule cannot see: MT4 single-selects, so grabbing a chip  |
//| takes the selection OFF the box. A chip of this family being        |
//| selected therefore keeps the whole family alive, and the release   |
//| hands the selection BACK to the box, so the next side is one grab  |
//| away — «یک کلیک چپ ... راحت هر طرف که بخوام» with no second click. |
//|                                                                  |
//| BKMIDGRIP-OFF (2026-09-16, user decision — «این وسط‌ها که کار    |
//| نمی‌کنن رو بردار کلا همون چهار گوشه کافیه») : the four MID-EDGE  |
//| chips are RETIRED — four corner handles remain. Restore by adding |
//| the four rows back to `BaseKnotGripSideAt` and raising           |
//| `BK_GRIP_COUNT`; the rest of the family (names, names→side, the   |
//| pixel projection, the keeper's sweep) is deliberately kept TOTAL   |
//| over the side bits, so those rows are the whole restore.           |
//|                                                                  |
//| COST: 4 objects, and steady state is READS ONLY (ink, mask and the|
//| two pixels are compared before every write — the BaseKnotDotFollow|
//| contract). The 500 ms pump is the keeper, the box' own Sync/CLICK  |
//| path is the instant one (a click shows the handles on that frame), |
//| and a box MOVE carries them in its own child step (BK_CH_GRIP).    |
//+------------------------------------------------------------------+
#define BK_GRIP_PX 9      // the chip a hand aims at; odd, so it centres on one pixel
#define BK_GRIP_COUNT 0   // BKGRIP-OFF (P-BK-71): NO live chips — a native MT4 box is moved
                          // by its own body drag, and the user retired every point family. The count
                          // lives HERE so a restore is one number, and every sweep asks it,
                          // never a literal.
// The four sides as BITS (`GS` = grip side) — the node's own bias ladder above
// spells its answers `BK_SIDE_*`, which is a different question entirely. A
// CORNER is two bits (the two sides it moves), so the family below stays total
// over the bit space even though only corners carry chips now.
#define BK_GS_T 1
#define BK_GS_B 2
#define BK_GS_L 4
#define BK_GS_R 8
// A chip's name tail is `G` + a tag (two letters for a corner, one for a retired
// edge chip). NO other child of this family starts with G (BOX, _T/_B/_L/_R,
// ENTRY, SL, TPn, INFO, TEXT, HINT, DOT), so a tag can never be read as another
// child's.
//--- The retired tails' ONE table lives ABOVE, beside BaseKnotRegister (MQL4 needs the
//--- define before its first reader in BaseKnotLazyInit) — see BKDOT-OFF/BKGRIP-OFF/
//--- BKPOINT-OFF (P-BK-71) there.
// BKMIDGRIP-OFF: four corners, `BK_GRIP_COUNT` of them. The single-bit rows are
// the retirement (kept in the comment so the restore is one edit):
//   if(i == 4) return BK_GS_T;   // the top edge's mid chip — retired
//   if(i == 5) return BK_GS_B;   // ...and its three siblings
//   if(i == 6) return BK_GS_L;
//   if(i == 7) return BK_GS_R;
int BaseKnotGripSideAt(const int i)
{
   // BKGRIP-OFF (P-BK-71): the four CORNER rows are retired with the chips — a plain
   // MT4 box has no resize points of its own to cover, and the user asked for no
   // points of ours either («یک باکس خود متاتریدر باشه»). The plan is empty
   // (`BK_GRIP_COUNT` is 0); the rows below ARE the restore path.
   // BKGRIP-OFF: if(i == 0) return (BK_GS_T | BK_GS_L);
   // BKGRIP-OFF: if(i == 1) return (BK_GS_T | BK_GS_R);
   // BKGRIP-OFF: if(i == 2) return (BK_GS_B | BK_GS_L);
   // BKGRIP-OFF: if(i == 3) return (BK_GS_B | BK_GS_R);
   return 0;
}
string BaseKnotGripName(const string pfx, const int side)
{
   if(side == (BK_GS_T | BK_GS_L)) return pfx + "GTL";
   if(side == (BK_GS_T | BK_GS_R)) return pfx + "GTR";
   if(side == (BK_GS_B | BK_GS_L)) return pfx + "GBL";
   if(side == (BK_GS_B | BK_GS_R)) return pfx + "GBR";
   // BKMIDGRIP-OFF: the four mid-edge tails. No live chip carries them, but the
   // function stays TOTAL over the bit space (and the one-time sweep below names
   // them to clean a chart an older build already wrote).
   if(side == BK_GS_T) return pfx + "GT";
   if(side == BK_GS_B) return pfx + "GB";
   if(side == BK_GS_L) return pfx + "GL";
   if(side == BK_GS_R) return pfx + "GR";
   return "";
}
// The name TAIL → side. 0 = not a handle of ours (every other child tail, the BOX
// itself and the four edge tails land here — which is what keeps the router honest).
// BKMIDGRIP-OFF: the single-letter tails stay MAPPED on purpose — a chart that the
// older build already wrote may still carry such a chip until the one-time sweep in
// `BaseKnotLazyInit` deletes it, and a chip the router cannot name would be a
// selectable square that drags nothing.
int BaseKnotGripSide(const string tag)
{
   if(tag == "GTL") return (BK_GS_T | BK_GS_L);
   if(tag == "GTR") return (BK_GS_T | BK_GS_R);
   if(tag == "GBL") return (BK_GS_B | BK_GS_L);
   if(tag == "GBR") return (BK_GS_B | BK_GS_R);
   if(tag == "GT") return BK_GS_T;
   if(tag == "GB") return BK_GS_B;
   if(tag == "GL") return BK_GS_L;
   if(tag == "GR") return BK_GS_R;
   return 0;
}
// The ONE point a chip stands on, in PIXELS: its corner (the mid-edge rows are
// BKMIDGRIP-OFF, kept TOTAL over the bit space for a restore). false = that chip
// has no place on this window (the box is out of it by TIME) and is retired ALONE
// — the terminal places no object it cannot place either (P-BK-59), and the chips
// that still have a place keep theirs.
bool BaseKnotGripPixel(const datetime tL, const double top, const datetime tR, const double bot,
                       const int side, int &cx, int &cy)
{
   long   half = (long)(tR - tL) / 2;
   datetime tMid = (datetime)((long)tL + half);
   double pMid = bot + (top - bot) / 2.0;
   if(side == (BK_GS_T | BK_GS_L)) return ChartTimePriceToXY(0, 0, tL, top, cx, cy);
   if(side == (BK_GS_T | BK_GS_R)) return ChartTimePriceToXY(0, 0, tR, top, cx, cy);
   if(side == (BK_GS_B | BK_GS_L)) return ChartTimePriceToXY(0, 0, tL, bot, cx, cy);
   if(side == (BK_GS_B | BK_GS_R)) return ChartTimePriceToXY(0, 0, tR, bot, cx, cy);
   if(side == BK_GS_T) return ChartTimePriceToXY(0, 0, tMid, top, cx, cy);
   if(side == BK_GS_B) return ChartTimePriceToXY(0, 0, tMid, bot, cx, cy);
   if(side == BK_GS_L) return ChartTimePriceToXY(0, 0, tL, pMid, cx, cy);
   if(side == BK_GS_R) return ChartTimePriceToXY(0, 0, tR, pMid, cx, cy);
   return false;
}
// Create + style once (the ink is written here and RE-COMPARED on every later pass
// — the BaseKnotDotCreate contract). The fill IS the box' border ink, so a handle
// reads as the shape's own mark, the way the user's own screenshot shows it.
void BaseKnotGripCreate(const string name, const color clr, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_GRIP_PX);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_GRIP_PX);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);     // the frame …
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);   // … and the fill: ONE ink
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);   // THIS is the drag (P-BK-61)
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_GRIP);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   "Base box corner — drag it to resize the box (Shift held = magnet: the price " +
                   "snaps to the nearest candle OHLC under it)");
}
// Keep / place / retire the corner chips of ONE box (`BK_GRIP_COUNT` of them).
// true = it wrote something (the caller owes one repaint). `skip` = the side the
// hand is dragging right now (0 = none): THAT chip may never be written mid-gesture
// (P-BK-15 — the terminal cancels a native drag whose object is rewritten), which is
// also the reason the handles are their own objects instead of a resize on the box
// itself.
bool BaseKnotGripsFollow(const string id, const datetime tL, const double top, const datetime tR,
                         const double bot, const bool unlocked, const color clr, const long tfMask,
                         const int skip)
{
   if(BK_GRIP_COUNT <= 0) return false;   // BKGRIP-OFF (P-BK-71): the family is retired —
                                          // the keeper refuses to run, so a partial restore that
                                          // uncomments a call site without a plan still draws nothing
   if(StringLen(inpObjectPrefix) == 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   // SELECTION, MEASURED (never assumed): either the box', or — the case MT4's own
   // single-select creates — one of the chips'. ONE probe decides whether the sweep
   // below is worth its reads at all (the family is created and retired as a set).
   bool sel = (bool)ObjectGetInteger(0, box, OBJPROP_SELECTED);
   if(!sel && ObjectFind(0, BaseKnotGripName(pfx, (BK_GS_T | BK_GS_L))) >= 0)
   {
      for(int i = 0; i < BK_GRIP_COUNT && !sel; i++)
      {
         string cn = BaseKnotGripName(pfx, BaseKnotGripSideAt(i));
         if(cn != "" && ObjectFind(0, cn) >= 0 &&
            (bool)ObjectGetInteger(0, cn, OBJPROP_SELECTED)) sel = true;
      }
   }
   bool want = (unlocked && (sel || skip != 0));
   bool wrote = false;
   for(int i = 0; i < BK_GRIP_COUNT; i++)
   {
      int side = BaseKnotGripSideAt(i);
      if(side == 0 || side == skip) continue;   // the hand's own chip is never touched
      string nm = BaseKnotGripName(pfx, side);
      if(nm == "") continue;
      if(!want)
      {
         if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); wrote = true; }
         continue;
      }
      int cx = 0, cy = 0;
      if(!BaseKnotGripPixel(tL, top, tR, bot, side, cx, cy))
      {
         if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); wrote = true; }
         continue;
      }
      int nx = cx - BK_GRIP_PX / 2, ny = cy - BK_GRIP_PX / 2;
      if(ObjectFind(0, nm) < 0)
      {
         BaseKnotGripCreate(nm, clr, tfMask);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, nx);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ny);
         wrote = true;
         continue;
      }
      if((color)ObjectGetInteger(0, nm, OBJPROP_BGCOLOR) != clr ||
         (color)ObjectGetInteger(0, nm, OBJPROP_COLOR) != clr)
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, clr);
         wrote = true;
      }
      if((long)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != tfMask)
      {
         ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, tfMask);
         wrote = true;
      }
      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTABLE))
      {
         // heal: a chip stored unselectable could never be dragged, i.e. the whole
         // feature would be silently absent (the P-BK-05/06 self-heal pattern).
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, true);
         wrote = true;
      }
      if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != nx ||
         (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != ny)
      {
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, nx);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ny);
         wrote = true;
      }
   }
   return wrote;
}
// The release hands the SELECTION back to the box (the terminal gave it to the chip
// the hand grabbed): the keeper's rule above then keeps the eight handles on screen
// and the NEXT side is one grab away — the user's «یک کلیک چپ ... راحت هر طرف که
// بخوام میکشم» with no second click. Never re-selects a locked box (the keeper
// retires that family anyway) nor one the terminal no longer offers for selection.
void BaseKnotGripReselect(const string id)
{
   if(id == "") return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   if(!(bool)ObjectGetInteger(0, box, OBJPROP_SELECTABLE)) return;
   if(!(bool)ObjectGetInteger(0, box, OBJPROP_SELECTED))
      ObjectSetInteger(0, box, OBJPROP_SELECTED, true);
}
//+------------------------------------------------------------------+
//| P-BK-63 (2026-09-16) — A CLICK OUTSIDE THE BOX LETS IT GO.        |
//|                                                                  |
//| «زمانی که خارج از باکس کلیک شد سلکت بودنش غیرفعال بشه» — the box  |
//| KEEPS its selection where MT4's own rectangle does (BKSELECT-KEPT: |
//| a drag, a resize and a click ON the box never drop it, so the next |
//| gesture needs no re-click), and a click anywhere ELSE on the chart  |
//| lets it go — the same pair MT4's own rectangle answers.            |
//|                                                                  |
//| WHY THIS IS OURS AND NOT THE TERMINAL'S: the box IS selectable, so |
//| an empty-chart click usually deselects it natively. The exception  |
//| is the family we added in P-BK-61: the eight handles are           |
//| SELECTABLE objects too, and MT4 single-selects — so a resize      |
//| hands the selection to the CHIP, and its release hands it BACK to  |
//| the box (`BaseKnotGripReselect`). From the terminal's side the user  |
//| never selected anything but a screen square, so there is no        |
//| terminal-side event that owes the box a deselect; from the user's  |
//| side the box is plainly selected (it wears its handles). One        |
//| explicit owner makes the pair deterministic instead of             |
//| build-dependent — and it is the exact mirror of GripReselect above.|
//|                                                                  |
//| COST — the pass is gated three times BEFORE it reads anything, and |
//| a chart click is user-paced, never a tick:                             |
//|   * the tool must be IDLE (no draw session, no live drag) — a click|
//|     during a gesture is the gesture's own;                       |
//|   * the click must not be the UI's (P-UI-92: a card sits OVER the   |
//|     box, and the Base Box strip EDITS the selected box — dropping  |
//|     that selection on a card click would kill the thing the card is|
//|     editing);                                                      |
//|   * the point must be OUTSIDE every box (a click inside it, or on  |
//|     its drawn border within P-BK-24's own slop, is the box' press).|
//| Only then is the registry walked, and only for a box the terminal   |
//| really reports as SELECTED: no box on the chart, or none selected,  |
//| is one short loop of reads and ZERO writes (steady state).          |
//+------------------------------------------------------------------+
// The box the terminal reports as SELECTED right now — "" when none is.
// Deliberately NOT `BaseKnotSelectedId()`: that answers the NEWEST box when
// nothing is selected (the note's own question, P-BK-58), and a drop must never
// touch a box the user did not select.
string BaseKnotSelectedBoxId()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   BaseKnotLazyInit();
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED)) return g_bkBoxes[i].id;
   }
   return "";
}
// P-BK-71: THE SELECTION WEARS NO MARK OF OURS. P-BK-59's centre grip and P-BK-61's
// handles USED to exist exactly while the box was selected, and their keepers
// re-measured that on the 500 ms pump — that is why a drop used to wipe them on the
// click's own frame. Both families are retired now (BKDOT-OFF/BKGRIP-OFF), so the wipe
// below answers the same call with the retired tails' table and nothing else.
// A locked box answers nothing here (the keeper retired its family already), and
// a name that was never created is one `ObjectFind` and no delete.
// P-BK-71: NO live point family is left to wipe on a deselect — the box wears the
// terminal's own markers and nothing of ours. What stays is the FAST cleanup of a chart
// an older build already drew: the retired tails' ONE table (BaseKnotRetiredPointName),
// walked here on the click's own frame so no ghost square waits for the next re-attach.
// A name that was never created is one `ObjectFind` and no delete.
bool BaseKnotSelectionMarkersWipe(const string id)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   bool wrote = false;
   // BKDOT-OFF (P-BK-71): the centre cover is one of the thirteen tails the table
   // names ("DOT"), so it is swept by the same walk — BaseKnotDotName stays the name's
   // ONE owner for the restore.
   // BKGRIP-OFF (P-BK-71): the family plans no live chip (`BK_GRIP_COUNT` is 0), so this
   // walks the RETIRED tails from their ONE table instead — every square that could still
   // sit on a chart an older build wrote and drag nothing.
   for(int i = 0; i < BK_RETIRED_POINTS; i++)
   {
      string tail = BaseKnotRetiredPointName(i);
      if(tail == "") continue;
      string nm = pfx + tail;
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); wrote = true; }
   }
   return wrote;
}
// THE entry, called from `BaseKnotOnChartEvent`'s CLICK branch (id 4 — the event
// MT4 sends for a click on the CHART; a click on a SELECTABLE object is
// CHARTEVENT_OBJECT_CLICK, id 1, and the branches above own it). true = it
// dropped a selection, so the caller owes one repaint.
bool BaseKnotDeselectOnChartClick(const int mx, const int my)
{
   if(g_bkState != BK_IDLE || s_bkDragId != "") return false;   // a gesture owns the mouse
   if(!UILeftButtonUp()) return false;   // the ONE button owner (P-UI-73): a press echo is
                                         // not a click, and the "outside" test below is
                                         // measured against a live native drag otherwise
   if(UIPointerOverSurface(mx, my)) return false;               // P-UI-92: the UI is over the box
   int sw = 0; datetime ct = 0; double cp = 0;
   if(ChartXYToTimePrice(0, mx, my, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
   {
      if(BaseKnotBoxAt(ct, cp) != "") return false;     // inside a box: its own press
      if(BaseKnotBoxAtPx(mx, my) != "") return false;   // ...or on its drawn border (P-BK-24)
   }
   string sel = BaseKnotSelectedBoxId();
   if(sel == "") return false;   // nothing of ours is selected — the common case
   BaseKnotDropSelection(sel);   // P-BK-26's ONE owner: read-guarded, one write
   BaseKnotSelectionMarkersWipe(sel);
   return true;
}
// (Re)build every child of one box from its live anchors. Direction is read
// from the registry — NEVER recomputed here (P-BK-13: the pump /
// drag-release refresh it via BaseKnotRefreshDirection BEFORE calling Sync,
// so Sync itself stays flicker-free).
void BaseKnotSync(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   int dir = g_bkBoxes[k].dir;
   int tfMin = g_bkBoxes[k].tfMin;
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);   // legacy registry rows
   long tfMask = BaseKnotTFMask(tfMin);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, tfMask);
   BaseKnotStyleBox(box);   // fill layer + drag handle — the VISIBLE border is the 4 edges below
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, !g_bkBoxes[k].locked);   // lock heal: handle follows the registry
   // P-BK-46/50: the trade's own numbers are computed BELOW, right after the node read
   // — the knot's TYPE decides which edge the entry sits on and its CLASS (its own
   // TF) decides what R is measured in (and which TF's plan the targets come from),
   // and both arrive from the walk and the read.
   double entry = 0, sl = 0;
   int dg = GetCachedDigits();
   // P-BK-30: ONE walk per Sync, shared by the box tooltip, the four edges and
   // the note — the count used to be computed twice per Sync (the tooltip and the
   // INFO label), so a box that is repainted (drag release, 500 ms pump, TF
   // switch) paid the bar walk twice over. With the body rule the walk is also
   // the same number everywhere on the box, so the note and the hover can never
   // disagree about how many candles the base holds.
   // P-BK-41: ONE SPAN for everything — the base's own story (its first candle to the
   // candle that closed outside the band). The number, the class, the node's story and
   // the note's own badge all read THIS record, so no two of them can disagree about
   // where the base started, where it ended, or which TF it belongs to.
   BaseKnotSpan sp;
   int bars = BaseKnotBarCount(t1, t2, top, bot, sp);
   int still = sp.still;
   // P-BK-36/38: the CLASS comes first now, because it is also what the node's
   // story is read on — one box, one TF, one story, whichever chart opens it. Both
   // numbers are published on the registry, so the pump's change check reads the
   // SAME story instead of a second one of its own. P-BK-40: the class is read from
   // the candles that STOOD STILL (a base's own length), while the note's number
   // stays the base's LIFE.
   // P-BK-75: anchored on the TF the BOX is seen on, so a TF switch cannot move the
   // class (and with it the story, the entry and the plan legs that ride it).
   // P-BK-80: and the class' SPAN IS THE BOX' OWN TWO ANCHORS (`t1..t2`), never the story
   // span `sp.tStart..sp.tExit` — that span is read off the CHART's candles (P-BK-41), so
   // feeding it here is exactly what let one box answer H1 on an H1 chart and H4 on an H4
   // chart. The box' anchors are stored on the OBJECT: the same on every chart, always.
   int baseTF = BaseKnotBaseTFMin(still, t1, t2, top, bot);   // P-BK-80: the node's time, from the box' own geometry
   g_bkBoxes[k].baseTFMin = baseTF;
   g_bkBoxes[k].storyT = sp.tLast;   // P-BK-41: the same story the pump re-reads
   g_bkBoxes[k].exitT  = sp.tExit;   // P-BK-81: the base's OWN exit candle — the ONE candle the
                                     //          direction is read from, published so the pump's
                                     //          own read cannot land on a different one
   // P-BK-29/47: ONE node read per Sync — the note's suffix, its hover sentence, the
   // box/edge tooltip and the pump's shadow all read the SAME record, so the type (the
   // LENGTH) and the side (the break's story) can never disagree with themselves between
   // two objects on one box.
   BaseKnotNode nd;
   // P-BK-41: the story starts where the BASE stopped moving (its last stand-still
   // candle), not at the box' right edge — a box dragged past its own break no longer
   // pushes the read forward and hides the break that made the knot.
   // P-BK-47/78: and the LENGTH is read on the NODE'S OWN TIME (P-BK-77's answer — the rung
   // whose own three candles stood still), while `baseTF` IS that answer: those two were
   // the whole input of the type, so no ATR, no chart TF and no drag can move it. The box'
   // commit TF no longer enters here at all: the user draws with the measuring tool.
   // P-BK-81: and the DIRECTION is read at the base's OWN EXIT CANDLE (`sp.tExit`) — the same
   // candle the note's number is counted to, so the two can never describe different bars.
   BaseKnotNodeRead((sp.tLast > 0 ? sp.tLast : t2), top, bot, baseTF,
                    sp.tExit, g_bkBoxes[k].storyT, nd);   // P-BK-79: the SAME anchor the pump keyed its rows on
   g_bkBoxes[k].nodeKind = nd.kind;   // published → the pump's gate compares against this
   // P-BK-46 — THE BREAK'S STORY NAMES THE SIDE (BaseKnotNodeDir), and the answer
   // is PUBLISHED (registry + chart GV) because the pump's price-follow must not
   // flip a knot whose trade is already named by what price DID.
   int ndDir = BaseKnotNodeDir(nd);
   g_bkBoxes[k].nodeSide = ndDir;     // P-BK-47: published for the same reason (the follow reads it)
   if(ndDir != 0 && ndDir != dir)
   {
      dir = ndDir;
      g_bkBoxes[k].dir = dir;
      GlobalVariableSet(BaseKnotGV(id), (double)dir);
   }
   // P-BK-46/50/51 — R IS EngSL OF THE KNOT'S OWN TF (the class just published), and
   // the box' own height only while the pump has no EngSL for that TF. P-BK-51's
   // geometry: the ENTRY waits ONE EngSL (FTR) or ONE HuntSL (ETR/CTR/OTR) INSIDE the
   // edge the side comes in on, the STOP is ONE EngSL behind the entry, and the TARGETS
   // are the plan's own TP1..TP3 of the same TF — every one of them SAYS which measure /
   // which TF / which plan it rode.
   // P-BK-51: which TF's numbers the knot is measured in — its own class for FTR/ETR, ONE
   // RUNG ABOVE it for CTR/OTR (BaseKnotMeasureTFMin is the ONE owner of that hop; the
   // geometry below asks the same function, so the drawn legs and the texts cannot part).
   // P-BK-79: AND EVERY ONE OF THEM IS READ AT THE BOX' OWN ANCHOR (`nd.anchor` — the bar its
   // story ended on), the very key the pump pushed its rows with, so the drawn legs and the
   // printed pips come off ONE row and a box whose base ended on an older bar keeps the numbers
   // that bar's market gave it instead of today's drifted ATR.
   int    mTF       = BaseKnotMeasureTFMin(nd.kind, baseTF);
   if(mTF <= 0) mTF = (baseTF > 0 ? baseTF : Period());
   string riskTag   = BaseKnotRiskTag(mTF, baseTF, top, bot, nd.anchor);   // P-BK-52: named with the number the pick drew
   double hPips  = BaseKnotRiskPips(mTF, top, bot, nd.anchor);
   bool   offIsHunt = BaseKnotOffsetIsHunt(nd.kind, mTF, nd.anchor);   // P-BK-51: which measure the TYPE asks for
   BaseKnotCalcLevels(top, bot, dir, nd.kind, baseTF, entry, sl, nd.anchor);
   // BKTAGTP-OFF (P-BK-54): string tpTag = BaseKnotTPPlanTag(baseTF);   // the retired note field
   string tpTip = BaseKnotTPPlanTip(baseTF, entry, dir, hPips, nd.anchor);   // P-BK-54: the hover keeps every leg
   string side = (dir >= 0 ? "BUY" : "SELL");
   // P-BK-51: the trade's own two sentences, ready-built — how deep the entry waits and
   // what sized the stop. The box hover, the note's hover and the two rays read THESE.
   string edgeName  = (dir >= 0 ? "top" : "bottom");
   string entryLine = BaseKnotEntryLine(nd.kind, mTF, offIsHunt, dir, top, bot, nd.anchor);
   string stopWhy   = " (ONE " + riskTag + " behind the entry, INSIDE the box' " + edgeName + " edge" +
                      BaseKnotStopWhy(mTF, top, bot, nd.anchor) + ")";
   string tradeTip  = "risk " + DoubleToString(hPips, 1) + " pips (" + riskTag + ") = the stop" + stopWhy + entryLine;
   string tip = BaseKnotBoxTooltip(id, t1, t2, top, bot, side, hPips, tpTip, sp,
                                   riskTag, BaseKnotNodeLine(nd, top, bot), entryLine);
   ObjectSetString(0, box, OBJPROP_TOOLTIP, tip);
   // BKEDGE-OFF (P-BK-74): the visible border is the BOX' OWN outline now — the
   // rectangle wears the border ink in BaseKnotStyleBox, so there is nothing to
   // draw beside it. The four trend-line children are retired in place: the
   // function below stays compiled and this one call is the whole restore.
   // BaseKnotDrawEdges(pfx, t1, p1, t2, p2,
   //                   GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth, tip, tfMask);
   BaseKnotPlaceText(pfx, t1, t2, top, bot, tfMask, tip);   // existing user text follows the box (never resurrected)
   datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   datetime tps, tpe;
   BaseKnotTPTickSpan(t1, t2, tps, tpe);   // TP tick rides the right edge, not the box
   // P-BK-46/50: the entry line names the edge the side came in on AND the one-R
   // offset (the user's own call), the stop names the edge it IS — the knot's own
   // trade, spelled out.
   // P-BK-47: this edge is the SIDE's call (the break's story, or the live price when the
   // story names none) — the TYPE is a length and never claimed an edge. The tooltip says
   // which of the two spoke, the same way the entry's measure names where its depth came from.
   // P-BK-51: and HOW DEEP the entry waits INSIDE that edge (EngSL for FTR, HuntSL for the
   // longer nodes) — the box hover's own sentence, spelled once by BaseKnotEntryLine.
   string entryWhy = " (ONE " + BaseKnotEntryOffsetTag(offIsHunt) + " INSIDE the box' " + edgeName + " edge — " +
                     BaseKnotEntryWhy(nd.kind, mTF, offIsHunt, top, bot, nd.anchor) + "; the side is " +
                     (nd.side != 0 ? "the base's own exit candle" : "the live price") + ")";
   BaseKnotMakeRay(BaseKnotEntryName(pfx), t2, tFar, entry, g_bkEntryColor, STYLE_SOLID, BK_LEVEL_WIDTH,
                   "BK " + side + " Entry: " + DoubleToString(entry, dg) + entryWhy, tfMask, true);
   BaseKnotMakeRay(BaseKnotSLName(pfx), t2, tFar, sl, g_bkStopColor, STYLE_DASH, BK_LEVEL_WIDTH,
                   "BK " + side + " Stop: " + DoubleToString(sl, dg) + ", INSIDE the box' " + edgeName +
                   " edge, ONE " + riskTag + " behind the entry" + BaseKnotStopWhy(mTF, top, bot, nd.anchor) + ")", tfMask, true);
   // P-BK-50: the TARGETS are the plan's own legs (TP1..TP3) — one SHORT, THICK tick
   // each at the chart's right edge, never a ray and never box-wide (the user's own
   // 2026-09-08 decision, now for three of them). A leg the plan has not pushed is
   // NOT drawn: absence is never turned into a level.
   for(int tk = 1; tk <= BaseKnotTPCount(); tk++)
   {
      double lv = BaseKnotTPLevel(entry, dir, baseTF, tk, nd.anchor);
      if(lv <= 0.0) continue;
      double tpP = BaseKnotPlanTPPips(baseTF, tk, nd.anchor);
      BaseKnotMakeRay(BaseKnotTPTickName(pfx, tk), tps, tpe, lv, g_bkTargetColor,
                      BK_TP_TICK_STYLE, BK_TP_TICK_WIDTH,
                      "BK " + side + " TP" + IntegerToString(tk) + ": " + DoubleToString(lv, dg) + " (+" +
                      DoubleToString(tpP, 0) + " pips from the entry" +
                      (hPips > 0.0 ? " = " + DoubleToString(tpP + hPips, 0) + " from the stop, " +
                                     DoubleToString(tpP / hPips, 1) + "R" : "") +
                      " — the plan's own TP" + IntegerToString(tk) + " of " + BaseKnotTFName(baseTF) + ")", tfMask, false);
   }
   ObjectDelete(0, BaseKnotTPName(pfx));   // BKTPR-OFF: purge a pre-P-BK-50 build's single tick
   ObjectDelete(0, BaseKnotDelName(pfx));   // NOBKDEL 2026-09-06: X badge retired — purge pre-retire badges
   ObjectDelete(0, BaseKnotBuyName(pfx));   // NOBUYSELL: purge pre-2026-09-06 direction badges
   // P-BK-58: WHERE this box' note is drawn is ONE question, asked once (BaseKnotNoteAtCorner):
   // the family's row for the selected/newest box in the corner mode, the box' own corner
   // otherwise. A box the row does not answer keeps NO box-side note in that mode — the note
   // exists in exactly one place at a time.
   bool atCorner = BaseKnotNoteAtCorner(id);
   if(atCorner || BaseKnotInfoVisible(id))
   {
      BaseKnotWriteInfo(BaseKnotInfoName(pfx), t1, t2, top, bot, hPips, tpTip, side,
                        sp, nd, tfMask, riskTag, tradeTip, atCorner);
      if(!atCorner) BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin, tfMask);
   }
   else
      ObjectDelete(0, BaseKnotInfoName(pfx));   // the other home owns it (P-BK-58), or the grace is over
   // BKDOT-OFF (P-BK-71): the centre cover is retired — a native box wears the
   // terminal's own markers and no cover of ours.
   // BKDOT-OFF: BaseKnotDotFollow(pfx, t1, t2, top, bot, !g_bkBoxes[k].locked,
   // BKDOT-OFF:                      (bool)ObjectGetInteger(0, box, OBJPROP_SELECTED),
   // BKDOT-OFF:                      GetBoxBorderRenderColor(), tfMask);
   // BKGRIP-OFF (P-BK-71): and the corner chips are retired — the INSTANT half of
   // their keeper goes with them.
   // BKGRIP-OFF: if(BaseKnotGripsFollow(id, t1, top, t2, bot, !g_bkBoxes[k].locked,
   // BKGRIP-OFF:                           GetBoxBorderRenderColor(), tfMask, s_bkGripLive))
   // BKGRIP-OFF:    ChartRedraw();
}
// Shared drag-paint budget: position writes are cheap, FULL repaints are not
// (a heavy chart costs 100ms+ per repaint — an unthrottled ChartRedraw per
// drag event turns dragging into a slideshow that only settles on release).
// Every drag painter (event sync, cursor follow, strip follow) draws through
// here (30ms); the release path repaints unconditionally (final frame).
void BaseKnotDragPaint()
{
   uint now = GetTickCount();
   if(now - s_bkDragPaintMs < 30) return;
   s_bkDragPaintMs = now;
   ChartRedraw();
}
// Lean child mover — ObjectMove ONLY (no style/color/create/delete syscalls)
// for per-step drag following. Same geometry as Sync (levels via
// BaseKnotCalcLevels, text via BaseKnotTextPlace), so the authoritative
// release Sync lands on identical pixels. Missing children are skipped (the
// release Sync rebuilds them) — never resurrect mid-drag.
// P-PERF-42: the ONE existence probe — reads only, 10 names (P-BK-61 added the handle
// set, which is one name: the eight chips live and die together), once per gesture.
int BaseKnotChildMaskBuild(const string pfx)
{
   int m = 0;
   // BKEDGE-OFF (P-BK-74): the border is the box' own outline, so the four edge
   // names are gone and their four probes could only ever answer "no" — the
   // gesture's ONE existence sweep is that much cheaper.
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_T) >= 0)            m |= BK_CH_EDGE_T;
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_B) >= 0)            m |= BK_CH_EDGE_B;
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_L) >= 0)            m |= BK_CH_EDGE_L;
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_R) >= 0)            m |= BK_CH_EDGE_R;
   if(ObjectFind(0, BaseKnotEntryName(pfx)) >= 0)     m |= BK_CH_ENTRY;
   if(ObjectFind(0, BaseKnotSLName(pfx)) >= 0)        m |= BK_CH_SL;
   if(ObjectFind(0, BaseKnotTPTickName(pfx, 1)) >= 0) m |= BK_CH_TP;    // P-BK-50: bit 6 = TP1
   if(ObjectFind(0, BaseKnotTPTickName(pfx, 2)) >= 0) m |= BK_CH_TP2;   //           TP2/TP3 take the
   if(ObjectFind(0, BaseKnotTPTickName(pfx, 3)) >= 0) m |= BK_CH_TP3;   //           next free bits
   if(ObjectFind(0, BaseKnotInfoName(pfx)) >= 0)      m |= BK_CH_INFO;
   if(ObjectFind(0, BaseKnotTextName(pfx)) >= 0)      m |= BK_CH_TEXT;
   // BKDOT-OFF (P-BK-71): the centre cover is retired — nothing probes it any more.
   // BKDOT-OFF: if(ObjectFind(0, BaseKnotDotName(pfx)) >= 0)       m |= BK_CH_DOT;   // P-BK-59: the centre grip
   // BKGRIP-OFF (P-BK-71): same for the corner chips (the plan is empty, so a probe
   // could only ever answer "no").
   // BKGRIP-OFF: if(ObjectFind(0, BaseKnotGripName(pfx, (BK_GS_T | BK_GS_L))) >= 0) m |= BK_CH_GRIP;   // P-BK-61: the handle set (one probe)
   return m;
}
// ObjectMove ONLY (no style/color/create/delete syscalls) for per-step drag
// following. P-PERF-42: no `ObjectFind` here any more — the caller only passes
// names its gesture mask proved exist (a missing object would have made
// ObjectMove a silent no-op, i.e. the probe only paid terminal calls).
void BaseKnotMoveOne(const string nm, const datetime tA, const double pA,
                     const datetime tB, const double pB)
{
   ObjectMove(0, nm, 0, tA, pA);
   ObjectMove(0, nm, 1, tB, pB);
}
void BaseKnotMoveChildren(const string id, datetime t1, const double p1,
                          datetime t2, const double p2)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   if(ObjectFind(0, BaseKnotBoxName(pfx)) < 0) return;
   // P-PERF-42: built on the gesture's FIRST move (a tap never builds it), and
   // rebuilt whenever the id it was built for is not the box being moved.
   if(s_bkChildMaskId != id)
   {
      s_bkChildMaskId = id;
      s_bkChildMask = BaseKnotChildMaskBuild(pfx);
   }
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   double entry = 0, sl = 0;
   // P-BK-46/50/51: the SAME geometry the release Sync lands on — the node's TYPE (published
   // on the registry, so a drag never moves the levels to another measure mid-gesture) and
   // the TF its class was read on, so the entry / stop / targets never jump during a drag.
   // P-BK-79: and the SAME ANCHOR — the box' own `storyT`, the key the pump pushed its rows
   // with, so a drag follows the levels the release Sync will land on and never a live row
   // the box does not draw with.
   datetime an = g_bkBoxes[k].storyT;
   BaseKnotCalcLevels(top, bot, g_bkBoxes[k].dir, g_bkBoxes[k].nodeKind, g_bkBoxes[k].baseTFMin, entry, sl, an);
   datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   datetime tps, tpe;
   BaseKnotTPTickSpan(t1, t2, tps, tpe);   // TP tick rides the right edge, not the box
   // BKEDGE-OFF (P-BK-74): the border IS the box, so a body drag carries no edge
   // — the terminal moves the rectangle and its outline with it, natively and for
   // free. The four lines below are the whole restore (with the four probes above
   // and the Sync call site).
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_T) != 0) BaseKnotMoveOne(pfx + BK_EDGE_T, t1, top, t2, top);
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_B) != 0) BaseKnotMoveOne(pfx + BK_EDGE_B, t1, bot, t2, bot);
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_L) != 0) BaseKnotMoveOne(pfx + BK_EDGE_L, t1, bot, t1, top);
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_R) != 0) BaseKnotMoveOne(pfx + BK_EDGE_R, t2, bot, t2, top);
   if((s_bkChildMask & BK_CH_ENTRY) != 0)  BaseKnotMoveOne(BaseKnotEntryName(pfx), t2, entry, tFar, entry);
   if((s_bkChildMask & BK_CH_SL) != 0)     BaseKnotMoveOne(BaseKnotSLName(pfx), t2, sl, tFar, sl);
   // P-BK-50: one tick per DRAWN plan leg — the mask bit the gesture's probe found
   // decides, so a leg that was not there at the press is never created mid-drag.
   for(int tk = 1; tk <= BK_TP_PLAN_MAX; tk++)
   {
      int bit = (tk == 1 ? BK_CH_TP : (tk == 2 ? BK_CH_TP2 : BK_CH_TP3));
      if((s_bkChildMask & bit) == 0) continue;
      double lv = BaseKnotTPLevel(entry, g_bkBoxes[k].dir, g_bkBoxes[k].baseTFMin, tk, an);
      if(lv <= 0.0) continue;
      BaseKnotMoveOne(BaseKnotTPTickName(pfx, tk), tps, lv, tpe, lv);
   }
   // BKDOT-OFF (P-BK-71): the centre cover is retired, so the drag carries nothing here.
   // BKDOT-OFF: if((s_bkChildMask & BK_CH_DOT) != 0)
   // BKDOT-OFF: {
   // BKDOT-OFF:    int dcx = 0, dcy = 0;
   // BKDOT-OFF:    if(BaseKnotDotPixel(t1, t2, top, bot, dcx, dcy))
   // BKDOT-OFF:    {
   // BKDOT-OFF:       string dn = BaseKnotDotName(pfx);
   // BKDOT-OFF:       ObjectSetInteger(0, dn, OBJPROP_XDISTANCE, dcx - BK_DOT_SIZE / 2);
   // BKDOT-OFF:       ObjectSetInteger(0, dn, OBJPROP_YDISTANCE, dcy - BK_DOT_SIZE / 2);
   // BKDOT-OFF:    }
   // BKDOT-OFF: }
   if((s_bkChildMask & BK_CH_INFO) != 0)   ObjectMove(0, BaseKnotInfoName(pfx), 0, t2, top);
   if((s_bkChildMask & BK_CH_TEXT) != 0)
   {
      string tn = BaseKnotTextName(pfx);
      datetime tx; double px; int anchor;
      BaseKnotTextPlace(t1, t2, top, bot, tx, px, anchor);
      ObjectMove(0, tn, 0, tx, px);
   }
   // BKGRIP-OFF (P-BK-71): the corner chips are retired, so the move step carries none —
   // a native box drag moves the whole box and every live child above follows it.
   // BKGRIP-OFF: if((s_bkChildMask & BK_CH_GRIP) != 0)
   // BKGRIP-OFF: {
   // BKGRIP-OFF:    int gTf = g_bkBoxes[k].tfMin;
   // BKGRIP-OFF:    if(gTf <= 0) gTf = BaseKnotIdTF(id);
   // BKGRIP-OFF:    BaseKnotGripsFollow(id, t1, top, t2, bot, !g_bkBoxes[k].locked,
   // BKGRIP-OFF:                        GetBoxBorderRenderColor(), BaseKnotTFMask(gTf), s_bkGripLive);
   // BKGRIP-OFF: }
}
// Unified per-step drag follow — the ONLY mid-drag children writer (P-BK-07).
// Both event channels call it with what they carry: OBJECT_DRAG brings live
// anchors only (its cursor coords are untrusted — in-repo pattern, TH3Tool
// reads anchors there too), MOUSE_MOVE brings the trusted cursor. Source
// priority is single: BOX live anchors while the terminal moves them (exact —
// MT4 magnet/snap included, ~14 cheap syscalls, never a full Sync),
// [BKCURSOR-OFF: the cursor-delta path that used to run "only while anchors sit
// frozen mid-drag" is retired dead-by-construction below — the terminal's own
// native drag is the ONE writer of a box, and it is the LIVE one.] Release still does the
// authoritative BaseKnotSync; the 500 ms pump heals anything that loses it
// (P-BK-18).
//
// P-BK-18 (2026-09-14, user report «یکیش لایو درگ میشه یکیش نمیشه»): the
// CHILD MOVE STEP IS NOT BUDGETED ANY MORE. It used to share one 30 ms gate
// with the cursor fallback and the paint, so the border (4 OBJ_TREND edges) was
// up to 30 ms of cursor travel BEHIND the native BOX rectangle — the fill
// tracked the hand at event rate while the border stepped at 33 fps, which is
// exactly what "one drags live, the other does not" looks like on a fast drag.
// The move step is CHANGE-DRIVEN (4 property reads, then writes only when the
// box really moved), so an unbudgeted call is free while nothing moves, and it
// never adds a REPAINT: MT4 already repaints the dragged box on this very
// frame, and BaseKnotDragPaint() keeps its own 30 ms gate. The runs are
// therefore pixel-locked with the fill and no heavier than before.
void BaseKnotFollowDrag(const string id, const datetime curT, const double curP)
{
   s_bkDragActMs = GetTickCount();   // activity even when the cursor budget below absorbs this call
   BaseKnotReassertLock(false);   // P-BK-14: the drag owns the view until release (drag took ctxToo=false)
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(t1 != s_bkFolT1 || t2 != s_bkFolT2 || p1 != s_bkFolP1 || p2 != s_bkFolP2)
   {
      // P-BK-19a: the anchors moved WITHOUT us — a fallback write folds itself
      // into s_bkFol* the moment it lands, so a difference here IS somebody else
      // moving the box, i.e. the TERMINAL's own native drag. The gesture is
      // claimed for the rest of it: a second writer is the P-BK-07 fight, and
      // P-BK-15 says MT4 cancels the drag the second writer would be fighting.
      s_bkNativeClaim = true;
      s_bkFolT1 = t1; s_bkFolT2 = t2; s_bkFolP1 = p1; s_bkFolP2 = p2;
      uint mkT = GetTickCount();   // P-PERF-43: this gesture measures itself (see the release line)
      BaseKnotMoveChildren(id, t1, p1, t2, p2);
      uint mkD = GetTickCount() - mkT;
      if(mkD > s_bkPerfMoveWorst) s_bkPerfMoveWorst = mkD;
      s_bkPerfPasses++;
   }
   // BKCURSOR-OFF (2026-09-14, user decision — «داخل باکس دوتا درگ فعال داریم،
   // یکیش رو حذف کن، اونی که لایو نیست»). TWO drags wrote the box: the
   // TERMINAL's own native drag (the LIVE one — it moves the anchors at event
   // rate and MT4 repaints the fill on that same frame) and this CURSOR-DELTA
   // fallback, which was rate-limited by design (BK_DRAG_CURSOR_MS 30) because
   // every write it makes is a full repaint the terminal did not ask for — i.e.
   // the one the user feels as stepped, not live. The live path is enough on any
   // build that drags the box at all (that is what the gesture ledger shows:
   // `native=1` on every real drag), so the second writer is retired DEAD BY
   // CONSTRUCTION, exactly like the panel drag (PANELDRAG-OFF). Its whole body
   // stays in place and compiles, so a restore is one word. TO RESTORE: drop the
   // `false &&`, and keep the P-BK-19a claim + the P-BK-19b role measurement
   // (BaseKnotGrabRole) that made it a second writer of ONE owner instead of a
   // fight — the gate group `[bkcursor-off]` asserts the retirement in both
   // directions, so a half-restore FAILS.
   else if(false && !s_bkNativeClaim &&
           curT > 0 && curP > 0 && id == s_bkDragId && s_bkDragT0 > 0 &&
           GetTickCount() - s_bkOwnerMs >= BK_DRAG_OWNER_MS)
   {
      // P-BK-18: THIS path moves the BOX itself (below), so it keeps the budget
      // — an unbudgeted box-write storm would drive a repaint per mouse move
      // where the terminal is not repainting anything of its own.
      uint cms = GetTickCount();
      if(cms - s_bkDragMs < BK_DRAG_CURSOR_MS) return;
      s_bkDragMs = cms;
      // Anchors frozen and NOBODY else claimed the box: the terminal is NOT
      // moving it natively on this gesture (frozen build, or the grab never
      // engaged), so the cursor owns it (the press latch belongs to s_bkDragId,
      // so only that box may use it). Absolute from the press base (never
      // incremental), so rounds converge exactly and can never drift or
      // double-count; the moment the terminal moves the anchors itself, the
      // exact branch above wins again.
      //
      // P-BK-19b: write ONLY what the press grabbed (s_bkGrabSel, measured on the
      // press pixels). A body grab translates both corners with their offset kept
      // — byte-identical to P-BK-16 — while an edge/corner grab is a RESIZE: that
      // side's value follows the cursor and the OPPOSITE side is never written.
      int dt = (int)(curT - s_bkDragT0);
      double dp = curP - s_bkDragP0;
      datetime ft1 = s_bkDragBT1, ft2 = s_bkDragBT2;
      double fp1 = s_bkDragBP1, fp2 = s_bkDragBP2;
      if(s_bkGrabSel == BK_GRAB_ALL)   // body grab = MOVE (the press offset is preserved)
      {
         ft1 += dt; ft2 += dt; fp1 += dp; fp2 += dp;
      }
      else                             // edge/corner grab = RESIZE (only the grabbed side travels)
      {
         if((s_bkGrabSel & BK_GRAB_T1) != 0) ft1 = curT;
         if((s_bkGrabSel & BK_GRAB_P1) != 0) fp1 = curP;
         if((s_bkGrabSel & BK_GRAB_T2) != 0) ft2 = curT;
         if((s_bkGrabSel & BK_GRAB_P2) != 0) fp2 = curP;
      }
      if(!s_bkFallLogged)   // ONE line per gesture: who owned it is the answer the next report needs
      {
         s_bkFallLogged = true;
         Print("[BK] drag cursor-owned box=", id, " role=", s_bkGrabSel,
               (s_bkGrabSel == BK_GRAB_ALL ? " (move)" : " (resize)"));
      }
      ObjectMove(0, box, 0, ft1, fp1);
      ObjectMove(0, box, 1, ft2, fp2);
      s_bkFolT1 = ft1; s_bkFolT2 = ft2; s_bkFolP1 = fp1; s_bkFolP2 = fp2;
      uint fkT = GetTickCount();   // P-PERF-43
      BaseKnotMoveChildren(id, ft1, fp1, ft2, fp2);
      uint fkD = GetTickCount() - fkT;
      if(fkD > s_bkPerfMoveWorst) s_bkPerfMoveWorst = fkD;
      s_bkPerfPasses++;
   }
   // BKCURSOR-OFF: the live path is the ONLY path — no anchor move and no
   // terminal drag means there is nothing to follow and nothing to paint.
   else return;   // nothing moved — skip the repaint too
   uint pkT = GetTickCount();   // P-PERF-43: the repaint is the other half of the lag
   BaseKnotDragPaint();
   uint pkD = GetTickCount() - pkT;
   if(pkD > s_bkPerfPaintWorst) s_bkPerfPaintWorst = pkD;
}
//+------------------------------------------------------------------+
//| P-BK-61 — THE HANDLE GESTURE: the terminal drags the CHIP, we    |
//| write the grabbed side of the box.                               |
//|                                                                  |
//| ONE WRITER, AND IT IS NOT THE DRAGGED OBJECT. A native drag is   |
//| cancelled by rewriting the object the terminal drags (P-BK-15) — |
//| here that object is the CHIP, so the box, its four edges,         |
//| Entry/SL/TP, the note and every OTHER chip are free to follow     |
//| live, while the chip under the hand is left exactly where the     |
//| terminal put it (the keeper's `skip`). The P-BK-59 grip already   |
//| proved the other half of the same rule: a screen object written   |
//| during a BOX drag does not cancel that drag.                     |
//|                                                                  |
//| ROLES BY VALUE, NEVER BY INDEX: the box' two anchors arrive in    |
//| either order (every other reader here normalises with min/max),   |
//| so "the top edge" IS whichever anchor holds the top price. A side |
//| dragged past the far one MIRRORS the rectangle instead of          |
//| inverting it — what the terminal's own rectangle does — and since |
// the roles are min/max the box can never collapse to zero height.  |
//|                                                                  |
//| THE TIME LANDS ON A BAR OPEN when one is that close (`the terminal|
// snaps corner times to bar opens` — BaseKnotCommit's own rule), so  |
// a resized box keeps the base walk counting WHOLE candles. A time  |
// PAST the last bar (the very common "pull the right edge into the  |
// future") has no such bar and is kept exactly as the hand left it. |
//+------------------------------------------------------------------+
datetime BaseKnotGripSnapTime(const datetime t)
{
   if(t <= 0) return t;
   int shift = iBarShift(_Symbol, 0, t, false);
   if(shift < 0) return t;
   datetime bo = iTime(_Symbol, 0, shift);
   if(bo <= 0) return t;
   double half = (double)PeriodSeconds() / 2.0;
   if(MathAbs((double)(t - bo)) > half) return t;   // not "that close" to a bar open
   return bo;
}
//+------------------------------------------------------------------+
//| P-BK-61 — AND THE CONTROL MAGNET.                                |
//|                                                                  |
//| «با کنترل هم مگنت فعال میشه ... حرکت رو چسبوند به کندل های و لو  |
//| که دقیق باشه» — while the hand drags a handle AND Shift is held, |
//| the price it writes snaps to the candle HIGH/LOW of the bar under|
//| the cursor, inside `inpMagnetSensitivityPips` (MAGNET SENS — the |
//| user's own input, still editable on the indicator's Inputs tab;   |
//| its card row stays retired). A plain (Shift-free) handle drag is  |
//| still hand-exact, which is the whole point of the modifier.       |
//|                                                                  |
//| WHY THIS IS NOT BKMAGNET2-OFF REVIVED: that decision («مگنت نمیخواد|
// باشه حذفش کن») retired the magnet on the BOX' OWN drag, and the box |
// still stays exactly where the hand let it go. This is a different  |
// gesture, asked for later, gated by a modifier the user holds on     |
// purpose, and it never runs inside BaseKnotFollowDrag (the box' live |
// follow) nor in BaseKnotSnapPrice (the draw-time owner, which stays  |
// the identity). `check_bkmagnet` now asserts all four of those —    |
// see tools/panel-wiring-audit.py, and never relax that group without|
// reading it first.
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-BK-66 — THE MAGNET'S MODIFIER IS SHIFT, NOT CONTROL.           |
//|                                                                  |
//| Reported: «من ctrl که میگیرم برای مگنت این باکس رو کپی میکنه» —  |
//| MetaTrader's own Ctrl+drag DUPLICATES a draggable object, and    |
//| the box' handles ARE draggable objects (their OBJPROP_SELECTABLE |
//| is what makes them handles at all, P-BK-61), so the terminal     |
//| cloned the chip instead of letting the magnet snap it. Ctrl is   |
//| the terminal's copy gesture, so the magnet needed another key.   |
//|                                                                  |
//| THE FOUR POLLABLE MODIFIERS, and why only one works:             |
//|   * SHIFT   — pollable as TERMINAL_KEYSTATE_SHIFT, and MT4 binds |
//|               no object-drag behaviour to it. THIS IS THE CHOICE.|
//|   * CONTROL — the terminal's duplicate gesture. Never again.     |
//|   * ALT     — pollable as TERMINAL_KEYSTATE_MENU, but Windows    |
//|               and the terminal both eat it (menus, Alt+Tab):     |
//|               a magnet that dies on a window switch is worse     |
//|               than no magnet.                                    |
//|   * MIDDLE  — pollable (TERMINAL_KEYSTATE_MIDDLE), but no hand   |
//|              holds the middle button while dragging the left one.|
//|                                                                  |
//| The probe is ONE function by ROLE (UIMagnetModifierDown(), see   |
//| UtilityFunctions.mqh), so the next report is a key name, not a   |
//| refactor — and `check_bkmagnet` asserts BOTH halves: the probe   |
//| reads SHIFT, and nothing in the magnet's path spells CONTROL.    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-BK-64 (2026-09-16) — THE MAGNET MEASURES IN PIXELS.            |
//|                                                                  |
//| Reported: «مگنت درست کار نمی‌کنه». The gate was the UNIT, not the |
//| idea: `inpMagnetSensitivityPips` × the symbol's pip. 10 pips on a |
//| D1 GBP/USD chart is under ONE pixel of a 1000-pip candle — the    |
//| hand aims at a wick it can SEE, and at that zoom ±5 px IS ±50     |
//| pips, so the gate was narrower than the eye and the magnet never  |
//| fired. A magnet that only works when you are already exact reads  |
//| as dead.                                                          |
//|                                                                  |
//| HOW THE SHIPPED MAGNETS DO IT (the reference this follows, from   |
//| the published MetaTrader magnet utilities — MT5's own chart       |
//| magnet and the MQL5 market tools «OHLC Magnet» 38178, «KT Drawing |
//| Tool» 161169, «Easy Toolbar»'s magnet mode — all of them the SAME |
//| rule): the reach is a PIXEL PROXIMITY, and the target is the      |
//| NEAREST of a bar's FOUR prices — «drag ... within the Pixel        |
//| Proximity ... snaps to Open/High/Low/Close», «stick to nearest     |
//| Open/High/Low/Close values of bars». Pixels are what the hand     |
//| actually controls, and the conversion is the chart's own price→Y   |
//| projection, so nothing here assumes a zoom, a timeframe or an      |
//| instrument.                                                       |
//|                                                                  |
//| SO: the candidates are O/H/L/C of the bar under the cursor (the    |
//| time was already snapped to a bar OPEN by BaseKnotGripSnapTime, so |
//| it is the bar the user points at); the winner is the smallest PIXEL|
//| distance to the dragged point; the reach is the user's own        |
//| `inpMagnetSensitivityPips` converted through the LIVE pip→pixel    |
//| scale and then clamped to [BK_MAGNET_MIN_PX, BK_MAGNET_MAX_PX] —   |
//| so a snap is never unreachable (a wide zoom cannot shrink the      |
//| reach to nothing) and never wild (a tight zoom cannot fling the    |
//| edge across the candle). Sensitivity 0 keeps its old meaning as    |
//| the tightest reach the hand can still use.                        |
//|                                                                  |
//| COST: reads only, on the gesture's own OBJECT_DRAG steps (nothing  |
//| per tick): 4 bar reads + up to 6 projections per step, and ZERO    |
//| when the magnet is off or Shift is not held — `BaseKnotGripDrag`   |
//| gates the call, and the two early returns here are the other half. |
//+------------------------------------------------------------------+
#define BK_MAGNET_MIN_PX 8    // a hand cannot aim finer than this at any zoom
#define BK_MAGNET_MAX_PX 26   // ...and a snap must stay local (never across the candle)
static double s_bkMagnetPx = -1.0;   // px distance of the last snap (-1 = it did not fire)
double BaseKnotGripSnapPrice(const datetime t, const double price)
{
   s_bkMagnetPx = -1.0;
   if(t <= 0 || price <= 0) return price;
   if(!inpEnableMagnet) return price;
   int shift = iBarShift(_Symbol, 0, t, false);
   if(shift < 0) return price;
   double cand[4];
   cand[0] = iOpen(_Symbol, 0, shift);
   cand[1] = iHigh(_Symbol, 0, shift);
   cand[2] = iLow(_Symbol, 0, shift);
   cand[3] = iClose(_Symbol, 0, shift);
   int dx = 0, dy = 0;
   if(!ChartTimePriceToXY(0, 0, t, price, dx, dy)) return price;
   double pipPx = 0.0;   // the user's own sensitivity, in the unit the hand uses
   int sx = 0, sy = 0;
   if(ChartTimePriceToXY(0, 0, t, price + BaseKnotPipSize(), sx, sy))
      pipPx = MathAbs((double)(sy - dy));
   double gatePx = pipPx * (double)inpMagnetSensitivityPips;
   if(gatePx < BK_MAGNET_MIN_PX) gatePx = BK_MAGNET_MIN_PX;
   if(gatePx > BK_MAGNET_MAX_PX) gatePx = BK_MAGNET_MAX_PX;
   double best = price, bestPx = -1.0;
   for(int i = 0; i < 4; i++)
   {
      if(cand[i] <= 0) continue;   // an absence (no data for that bar) — never invented
      int cx = 0, cy = 0;
      if(!ChartTimePriceToXY(0, 0, t, cand[i], cx, cy)) continue;
      double d = MathAbs((double)(cy - dy));
      if(bestPx < 0.0 || d < bestPx) { bestPx = d; best = cand[i]; }
   }
   if(bestPx < 0.0 || bestPx > gatePx) return price;   // nothing inside the proximity
   s_bkMagnetPx = bestPx;   // the gesture ledger reads this (one line per snap)
   return best;
}
// A handle drag → the grabbed side of the box, live (one OBJECT_DRAG per step: the
// channel the box' own follow already runs on). `name` is the chip the terminal moved;
// its CENTRE pixel is the reading (see the block above). Locked boxes answer nothing:
// the keeper has already retired their family.
void BaseKnotGripDrag(const string id, const int side, const string name)
{
   if(id == "" || name == "" || side == 0) return;
   if(BaseKnotFind(id) < 0) return;
   if(BaseKnotLocked(id)) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   int gx = (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) + BK_GRIP_PX / 2;
   int gy = (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) + BK_GRIP_PX / 2;
   int w = 0; datetime gt = 0; double gp = 0;
   if(!ChartXYToTimePrice(0, gx, gy, w, gt, gp)) return;
   if(w != 0 || gt <= 0 || gp <= 0) return;
   bool modifier = UIMagnetModifierDown();   // P-BK-66: SHIFT — MT4's Ctrl+drag copies the chip
   gt = BaseKnotGripSnapTime(gt);
   if(modifier && (side & (BK_GS_T | BK_GS_B)) != 0) gp = BaseKnotGripSnapPrice(gt, gp);
   // P-BK-64: the magnet answers with a NUMBER — once per gesture, on the step that
   // snapped, carrying the pixel distance it accepted and the value it took. A
   // snapping gesture is rare (modifier held + inside the proximity), so the line costs
   // nothing in steady state and turns the next report into a reading.
   if(s_bkMagnetPx >= 0.0 && !s_bkMagnetLogged)
   {
      s_bkMagnetLogged = true;
      Print("[BK] magnet box=", id, " side=", side, " px=", (int)s_bkMagnetPx,
            " -> ", DoubleToString(gp, GetCachedDigits()));
   }
   datetime bt1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime bt2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double bp1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double bp2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   datetime tL = bt1, tR = bt2;
   if(tR < tL) { datetime tt = tL; tL = tR; tR = tt; }
   double top = MathMax(bp1, bp2), bot = MathMin(bp1, bp2);
   if((side & BK_GS_T) != 0) top = gp;
   if((side & BK_GS_B) != 0) bot = gp;
   if((side & BK_GS_L) != 0) tL = gt;
   if((side & BK_GS_R) != 0) tR = gt;
   // THE GESTURE IS THE TERMINAL'S (it drags the chip): claim it, so the release path
   // Syncs exactly this box, the pump leaves it alone for the rest of the gesture
   // (P-BK-15), and the retired cursor fallback could never touch it either.
   s_bkNativeClaim = true;
   // P-BK-65: the terminal NAMED this chip, so THIS PRESS IS A RESIZE — the answer
   // the release needs, latched here and cleared only by a witness that cannot lie
   // (the release, the pump's silence watchdog, an OBJECT_DRAG that names the BOX
   // instead, or teardown). `s_bkGripLive` below stays what it always was: which
   // chip the hand holds RIGHT NOW, i.e. the keeper's skip.
   s_bkGripGesture = side;
   s_bkBoxNamed    = false;   // it is dragging a CHIP, so by definition not the box
   s_bkGripLive = side;
   s_bkDragId = id;
   s_bkDragActMs = GetTickCount();
   ObjectMove(0, box, 0, tL, top);
   ObjectMove(0, box, 1, tR, bot);
   BaseKnotMoveChildren(id, tL, top, tR, bot);   // the SAME mover every other live step uses
   BaseKnotDragLockOn();                         // a resize owns the view, like a move
   if(!s_bkGripLogged)
   {
      s_bkGripLogged = true;
      Print("[BK] grip resize box=", id, " side=", side,
            " tag=", StringSubstr(name, StringLen(pfx)), " magnet=", (modifier ? 1 : 0));
   }
   BaseKnotDragPaint();
}
//+------------------------------------------------------------------+
//| P-BK-61b (2026-09-16) — THE BODY DRAG IS A MOVE, AND ONLY A MOVE.|
//|                                                                  |
//| User: «این باکس الآن از دو روش میشه بزرگ و کوچیکش کرد ... از رنگ  |
//| ریسایز نشه فقط درگ بشه» — resize must have ONE home (the eight   |
//| handles on the border), and grabbing the FILL must only carry the|
//| box. WHY IT COULD GROW BEFORE: MetaTrader's own magnet snaps EACH |
//| of a dragged rectangle's two anchors to a wick INDEPENDENTLY (the |
//| fact behind P-BK-25's "a whole-box MOVE can read as a one-side     |
//| resize"), so a body drag on a magnet-enabled terminal could leave |
//| the box a different SIZE than the hand took it with.             |
//|                                                                  |
//| WHAT IS RESTORED, AND WHAT IS NOT: only the SIZE — from the      |
//| press-time snapshot, which P-BK-25's `s_bkSnapTrusted` proves was |
//| taken BEFORE the terminal moved anything (a snapshot taken mid-   |
//| drag could read a translation as a resize, and a role that cannot |
//| be measured must not invent one). The POSITION stays exactly where|
//| the hand let it go, magnet included (BKMAGNET2-OFF's own rule).   |
//|                                                                  |
//| COST: one call at the RELEASE only, steady state an anchor read   |
//| plus a compare; and it runs after the button is up, never into a  |
//| live native drag (P-BK-15). The alternative — translating the box |
//| by the hand's own cursor delta — was rejected because it would    |
//| throw the terminal's own position snapping away with it.          |
//+------------------------------------------------------------------+
bool BaseKnotBodySizeHeal(const string id)
{
   if(id == "" || !s_bkSnapTrusted) return false;   // unmeasured baseline — never invent
   // P-BK-65: AND THE HEAL'S OWN PRECONDITION IS THE GESTURE, NOT THE BASELINE. This
   // function exists for ONE fault shape — MetaTrader's magnet enlarging the FILL of a
   // rectangle the TERMINAL is moving. A press that dragged a CHIP is a resize the user
   // asked for, and restoring a press-time size there is exactly the «برمی‌گرده سر جای
   // خودش» report (the far edge jumped to `tL + wT`). `s_bkBoxNamed` is that answer from
   // the terminal's own mouth (its OBJECT_DRAG named the BOX), so the heal now needs the
   // trusted baseline AND a terminal-named box drag: even if the release's own gate were
   // ever lost to a future edit, a chip gesture still cannot spring the box back.
   if(!s_bkBoxNamed) return false;
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   datetime pT1 = s_bkDragBT1, pT2 = s_bkDragBT2;
   if(pT2 < pT1) { datetime pt = pT1; pT1 = pT2; pT2 = pt; }
   double pTop = MathMax(s_bkDragBP1, s_bkDragBP2), pBot = MathMin(s_bkDragBP1, s_bkDragBP2);
   long   wT = (long)(pT2 - pT1);
   double hP = pTop - pBot;
   if(wT <= 0 || hP <= 0) return false;   // the snapshot cannot describe a box
   datetime lt1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime lt2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double lp1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double lp2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   datetime tL = lt1, tR = lt2;
   if(tR < tL) { datetime tt = tL; tL = tR; tR = tt; }
   double top = MathMax(lp1, lp2), bot = MathMin(lp1, lp2);
   if((long)(tR - tL) == wT && MathAbs((top - bot) - hP) < GetCachedPoint())
      return false;   // the size IS the press-time size — a pure move, nothing to write
   // The size comes back around the corner the drop left in place (the box' left /
   // top edge IS the hand's own answer for where the box went): one write pair, and
   // never a touch on the position.
   ObjectMove(0, box, 0, tL, top);
   ObjectMove(0, box, 1, (datetime)((long)tL + wT), top - hP);
   return true;
}
void BaseKnotDelete(const string id)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx != "") ObjectsDeleteAll(0, pfx);   // one call wipes box + all children
   BaseKnotUnregister(id);
   ChartRedraw();
}
// Re-assert the border look on every committed box (Base Box card edits
// apply live; Lite-safe: mirrors + Object* calls only). Delegates to
// BaseKnotSync so the 4 edge segments (the visible border) follow too.
void BaseKnotRestyleAll()
{
   if(StringLen(inpObjectPrefix) == 0) return;
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      BaseKnotSync(g_bkBoxes[i].id);
   }
   ChartRedraw();
}
// Visible right now? Box exists AND its commit-TF mask covers the current
// chart TF (hidden-above boxes report false — UI side closes their strip).
bool BaseKnotVisibleNow(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   if(ObjectFind(0, BaseKnotBoxName(pfx)) < 0) return false;
   int tfMin = g_bkBoxes[k].tfMin;
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);
   return BaseKnotTFVisible(tfMin);
}
// Hit-test: id of the committed box containing (t,price), or "".
// UI side uses it for hold-on-box → settings (no UI deps here).
string BaseKnotBoxAt(const datetime t, const double price)
{
   if(t <= 0 || price <= 0 || StringLen(inpObjectPrefix) == 0) return "";
   BaseKnotLazyInit();
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
      double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
      if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
      double top = MathMax(p1, p2), bot = MathMin(p1, p2);
      if(t >= t1 && t <= t2 && price >= bot && price <= top) return g_bkBoxes[i].id;
   }
   return "";
}
// P-BK-24 — THE SAME QUESTION, ASKED IN PIXELS. `BaseKnotBoxAt` is an exact
// INSIDE test in price/time terms, which is the right answer when the cursor is
// genuinely inside the box — and the wrong one when the user presses the drawn
// border: the visible line is `inpBoxBorderWidth` px wide and sits ON the
// boundary, so its outer half is already outside the rectangle, and the terminal
// accepts that press (its own hit test has a few px of tolerance) while our
// latch did not. The press point is therefore measured against the box's two
// corners through `ChartTimePriceToXY` (the same projection `BaseKnotGrabRole`
// already uses), inflated by `BK_PRESS_SLOP_PX` — never a price estimate.
string BaseKnotBoxAtPx(const int mx, const int my)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   BaseKnotLazyInit();
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
      if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0),
                             ObjectGetDouble(0, box, OBJPROP_PRICE, 0), x1, y1)) continue;
      if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1),
                             ObjectGetDouble(0, box, OBJPROP_PRICE, 1), x2, y2)) continue;
      if(mx >= MathMin(x1, x2) - BK_PRESS_SLOP_PX && mx <= MathMax(x1, x2) + BK_PRESS_SLOP_PX &&
         my >= MathMin(y1, y2) - BK_PRESS_SLOP_PX && my <= MathMax(y1, y2) + BK_PRESS_SLOP_PX)
         return g_bkBoxes[i].id;
   }
   return "";
}
// P-BK-19b — WHAT did this press grab? MEASURED in pixels against the box's own
// two corners (ChartTimePriceToXY — the same call the placement rule and the
// box's own preview place objects with), never assumed: inside
// BK_GRAB_CORNER_PX of a corner ⇒ that corner's two values; inside
// BK_GRAB_EDGE_PX of one edge ⇒ that edge's single value; anywhere else ⇒ the
// body (all four = the P-BK-16 MOVE). Neither axis counts as an edge if the box
// is too small to aim inside it (every press would land in the band), and a box
// whose corners cannot be projected (off-window, zero-size) answers BK_GRAB_ALL —
// a role that cannot be measured must not invent, it falls back to the move it
// always did. Reads only; called once per gesture, at the press.
int BaseKnotGrabRole(const string box, const int mx, const int my)
{
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   datetime bt1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime bt2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   if(!ChartTimePriceToXY(0, 0, bt1, ObjectGetDouble(0, box, OBJPROP_PRICE, 0), x1, y1)) return BK_GRAB_ALL;
   if(!ChartTimePriceToXY(0, 0, bt2, ObjectGetDouble(0, box, OBJPROP_PRICE, 1), x2, y2)) return BK_GRAB_ALL;
   int dCorner = BK_GRAB_CORNER_PX, dEdge = BK_GRAB_EDGE_PX;
   if(MathAbs(mx - x1) <= dCorner && MathAbs(my - y1) <= dCorner)   // corner at anchor 1
      return BK_GRAB_T1 | BK_GRAB_P1;
   if(MathAbs(mx - x2) <= dCorner && MathAbs(my - y2) <= dCorner)   // corner at anchor 2
      return BK_GRAB_T2 | BK_GRAB_P2;
   int wSpan = MathAbs(x2 - x1), hSpan = MathAbs(y2 - y1);
   if(wSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(mx - x1) <= dEdge) return BK_GRAB_T1;   // vertical edge, anchor 1
   if(wSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(mx - x2) <= dEdge) return BK_GRAB_T2;   // vertical edge, anchor 2
   if(hSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(my - y1) <= dEdge) return BK_GRAB_P1;   // horizontal edge, anchor 1
   if(hSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(my - y2) <= dEdge) return BK_GRAB_P2;   // horizontal edge, anchor 2
   return BK_GRAB_ALL;   // body press = MOVE
}
// P-BK-18 — does the box's own VISIBLE top edge still describe the box?
// The top edge is the child that carries both the box's time span and its top
// price, so it is the cheapest honest witness that the border is where the box
// is; false = the border is behind and needs the authoritative Sync (the pump's
// settle heal). Reads only: three property reads in steady state, no writes.
bool BaseKnotBorderSettled(const string pfx, const datetime t1, const datetime t2, const double top)
{
   string edgeT = pfx + BK_EDGE_T;
   if(ObjectFind(0, edgeT) < 0) return false;   // missing edge = not settled (Sync rebuilds it)
   if((datetime)ObjectGetInteger(0, edgeT, OBJPROP_TIME, 0) != t1) return false;
   if((datetime)ObjectGetInteger(0, edgeT, OBJPROP_TIME, 1) != t2) return false;
   return (ObjectGetDouble(0, edgeT, OBJPROP_PRICE, 0) == top);
}
// Per-tick (500 ms) re-glue: scroll/zoom moves pixel badges, box anchors don't.
void BaseKnotSyncBadges()
{
   BaseKnotLazyInit();   // the registry IS the box list — rebuild once (guarded, O(1) after)
   // P-BK-58: the corner row's own keeper rides this pump (≤500 ms in Lite, and on every chart
   // change): a selection, a mode change, a pushed slot or a box that left this TF are all
   // noticed here, without a second event path of its own. NOTHING is written while nothing
   // changed — steady state is a compare (see BaseKnotNoteCornerRefresh).
   BaseKnotNoteCornerRefresh();
   if(BaseKnotSessionActive()) BaseKnotReassertLock(true);   // P-BK-14: pump drift-heal (timer path, tick-less charts)
   if(s_bkDragLock && g_bkState == BK_IDLE &&
      UILeftButtonUp() &&          // the ONE button owner (P-UI-73): both MQL4
                                   // conventions must agree, or a live drag
                                   // would be torn down by the watchdog
      GetTickCount() - s_bkDragActMs > 1500)
   {
      // Missed release (button up off-window, event stream silent): never
      // leave the view locked. The 1.5 s silence requirement keeps KEYSTATE
      // flicker mid-hold (P-BK-05) from false-triggering — a real drag keeps
      // producing events. KEYSTATE poll in the timer path is P-BK-03 pattern.
      s_bkDragId = "";
      BaseKnotGestureClear();   // P-BK-65/P-BK-61: no release, no live side — and the
                                // gesture's KIND goes with it, so the next press starts
                                // fresh. The settle heal below then Syncs the box from the
                                // anchors the resize already wrote.
      s_bkGripLogged = false; s_bkMagnetLogged = false;
      BaseKnotDragLockOff();
   }
   if(ArraySize(g_bkBoxes) == 0) return;
    datetime tpEdge = BaseKnotTPEdgeTime();   // chart-global: one conversion for the whole pump
    double bkRef = BaseKnotLiveRef();         // P-BK-13: one live price for every follow check below
    // BKEDGE-OFF (P-BK-74): this probe fed the P-BK-18 settle heal only, so it is
    // dormant with it — the restore re-adds this line and the heal together.
    // BKEDGE-OFF: bool bkHandOff = UILeftButtonUp();   // P-BK-18: ONE button probe for the settle heal below
    // P-BK-29/47 — the NOTE'S TWO ANSWERS are derived closed-bar data, so the pump is
    // what has to notice they moved: the LENGTH moves with the class (a new closed bar
    // the rung's own candles are re-read on, or a drag) and the SIDE with the break's
    // story (a break, a return or a second break). The step arrives from the UI layer
    // asynchronously (which zeroes s_bkNodeBar). One chart read for the WHOLE pump,
    // never per box; steady state costs nothing and a moved answer costs one Sync.
    datetime bkNodeBarNow = iTime(_Symbol, 0, 0);
    bool bkNodeDue = (bkNodeBarNow != s_bkNodeBar);
    if(bkNodeDue) s_bkNodeBar = bkNodeBarNow;
    // P-BK-46 — a pushed EngSL that MOVED rewrites every knot's stop and target (the
    // entry and the side stay), so the whole pump rebuilds them once. The ask / push
    // pair runs BEFORE this function (see BaseKnotEngPump), so the epoch read here is
    // this round's own answer; steady state is one compare.
    bool bkEngDue = (s_bkEngEpoch != s_bkEngSeen);
    if(bkEngDue) s_bkEngSeen = s_bkEngEpoch;
    // PERF: coalesce repaints — N boxes healing in one pump used to issue N
    // full ChartRedraws; final pixels are identical with one after the loop.
    bool bkNeedPaint = false;
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      // P-BK-15: hands off the actively-dragged box — MT4 cancels an
      // in-progress native drag when the object is rewritten mid-gesture, so
      // any pump Sync/heal/glue here snaps the box back to the drag start.
      // The release path Syncs authoritatively (dir flip included), so
      // nothing is lost by skipping these 500 ms rounds.
      if(s_bkDragId != "" && g_bkBoxes[i].id == s_bkDragId) continue;
      string pfx = BaseKnotPrefix(g_bkBoxes[i].id);
      if(pfx == "") continue;
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) continue;
      // P-BK-13 auto-follow: a stale side (committed long ago and crossed
      // since, or dragged across the price) flips here — one Sync rebuilds
      // Entry/SL/TP + tooltips. Inside keeps, so vibration never flickers.
      if(BaseKnotRefreshDirection(g_bkBoxes[i].id, bkRef))
      {
         BaseKnotSync(g_bkBoxes[i].id);
         // No bottom hint on flip either: the rebuilt badge + tooltips already
         // show the new side where the box is.
         bkNeedPaint = true;
      }
      // P-BK-05/06 self-heal + TV-fill 2026-09-07: the BOX rect is the fill
      // layer. Re-assert it within 500 ms when it drifts from the live fill
      // look (bg + FILL false when fill invisible) — read-guarded, so steady
      // state costs syscalls only. Missing edge segments (the visible
      // border) are rebuilt via a full Sync.
      if(!BaseKnotFillHealed(box))
      {
         BaseKnotStyleBox(box);
         bkNeedPaint = true;
      }
      // BKEDGE-OFF (P-BK-74): the four "is an edge segment missing" probes are
      // retired with the family — there is nothing beside the box to lose.
      if(BaseKnotTPStale(pfx))   // pre-tick ray → rebuild
       {
         BaseKnotSync(g_bkBoxes[i].id);
         bkNeedPaint = true;
      }
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
      double top = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      double bot = MathMin(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      // BKEDGE-OFF (P-BK-74) — RETIRED HERE: the P-BK-18 SETTLE HEAL. It compared
      // the top edge against the box on this 500 ms pump because the visible border
      // was a COPY of the box (four trend lines our own follow had to keep in step),
      // so a lost gesture end — a motionless release emits NO mouse-move at all
      // (P-BK-03), a registry gap skips the follow, MT4's own snap at the drop can
      // land a pixel the last follow never saw — left the copy behind until a TF
      // switch. The border IS the box now: the terminal moves it with the rectangle,
      // natively, so there is no second copy to fall behind and nothing to compare.
      // The full story, the dormant `BaseKnotBorderSettled` and the one-line restore
      // are at the retired block below.
      // P-BK-29: the type moved (new bar / warm step) → publish it through the
      // same authoritative Sync the flip and settle heals use. The dragged box
      // never reaches here (it is skipped at the top of the loop — P-BK-15:
      // writing into a live native drag cancels it), and the shadow compare is
      // two ints, so a box whose story is unchanged is never touched.
      if(bkNodeDue)
      {
         BaseKnotNode ndNow;
         BaseKnotNodeRead((g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : t2), top, bot,
                          g_bkBoxes[i].baseTFMin,
                          g_bkBoxes[i].exitT, g_bkBoxes[i].storyT, ndNow);   // P-BK-38/41/47/78/79/81: the SAME story, from the SAME exit candle, on the SAME node's time, at the SAME anchor
         // P-BK-47: BOTH answers are compared — the type (the LENGTH: the class or the box'
         // TF moved) and the side (the break's story: a break, a return, a second break).
         if(ndNow.kind != g_bkBoxes[i].nodeKind || BaseKnotNodeDir(ndNow) != g_bkBoxes[i].nodeSide)
         {
            BaseKnotSync(g_bkBoxes[i].id);
            bkNeedPaint = true;
         }
      }
      // P-BK-46: the knot's risk moved (a new bar's EngSL, or the class it is read
      // on) — one authoritative Sync re-measures the stop, the target and the texts.
      if(bkEngDue)
      {
         BaseKnotSync(g_bkBoxes[i].id);
         bkNeedPaint = true;
      }
      // BKEDGE-OFF (P-BK-74): THE SETTLE HEAL IS RETIRED WITH THE THING IT HEALED.
      // P-BK-18 existed because the visible border was a COPY of the box (four
      // trend lines that our own follow had to keep in step), so a lost gesture
      // end left the copy behind. The border IS the box now — the terminal moves
      // it with the rectangle, natively, and there is no second copy to fall
      // behind. `BaseKnotBorderSettled` stays compiled (dead by construction) and
      // this one line is the restore.
      // BKEDGE-OFF: if(bkHandOff && !BaseKnotBorderSettled(pfx, t1, t2, top))
      // BKEDGE-OFF: {
      // BKEDGE-OFF:    BaseKnotSync(g_bkBoxes[i].id);
      // BKEDGE-OFF:    bkNeedPaint = true;
      // BKEDGE-OFF: }
      int tfMin = g_bkBoxes[i].tfMin;
      if(tfMin <= 0) tfMin = BaseKnotIdTF(g_bkBoxes[i].id);
      if(tpEdge > 0 && BaseKnotTFVisible(tfMin)) BaseKnotTPGlue(pfx, tpEdge);   // right-edge hug, hidden-TF boxes skipped
      if(ObjectFind(0, BaseKnotTextName(pfx)) >= 0)   // user text re-glues with the box
         BaseKnotPlaceText(pfx, t1, t2, top, bot, BaseKnotTFMask(tfMin), "");
      if(BaseKnotInfoVisible(g_bkBoxes[i].id))
         BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin, BaseKnotTFMask(tfMin));
      else if(ObjectFind(0, BaseKnotInfoName(pfx)) >= 0)
      {
         ObjectDelete(0, BaseKnotInfoName(pfx));   // Auto grace over — hide within 500 ms
         bkNeedPaint = true;
      }
      // BKDOT-OFF (P-BK-71): the centre cover is retired — the keeper has no call site.
      // BKDOT-OFF: if(BaseKnotDotFollow(pfx, t1, t2, top, bot, !g_bkBoxes[i].locked,
      // BKDOT-OFF:                            (bool)ObjectGetInteger(0, box, OBJPROP_SELECTED),
      // BKDOT-OFF:                            GetBoxBorderRenderColor(), BaseKnotTFMask(tfMin)))
      // BKDOT-OFF:          bkNeedPaint = true;
      // BKGRIP-OFF (P-BK-71): and the corner chips ride no pass any more (`skip` was 0
      // here on purpose; the retired keeper refuses to run anyway).
      // BKGRIP-OFF: if(BaseKnotGripsFollow(g_bkBoxes[i].id, t1, top, t2, bot, !g_bkBoxes[i].locked,
      // BKGRIP-OFF:                              GetBoxBorderRenderColor(), BaseKnotTFMask(tfMin), 0))
      // BKGRIP-OFF:          bkNeedPaint = true;
   }
   if(bkNeedPaint) ChartRedraw();
}

//+------------------------------------------------------------------+
//| Commit click 2 → freeze the box, spawn Entry/SL/TP + badges.      |
//+------------------------------------------------------------------+
void BaseKnotCommit(const datetime t2, const double p2raw)
{
   double pt = GetCachedPoint();
   if(pt <= 0) pt = _Point;
   double p2 = BaseKnotSnapPrice(t2, p2raw);
   if(t2 <= 0) return;
   datetime tc = t2;
   if(tc == g_bkT1) tc = g_bkT1 + PeriodSeconds();   // same-bar drag: corner times snap to bar opens,
                                                     // so the honest box is one bar wide — never reject it
   if(tc < g_bkT1) { datetime tt = g_bkT1; g_bkT1 = tc; tc = tt; double pp = g_bkP1; g_bkP1 = p2; p2 = pp; }   // dragged right-to-left: store canonical corner order
   if(MathAbs(p2 - g_bkP1) < pt)   // a true point-click, not a box — ignore it silently (no bottom text)
   {
      return;
   }
   int tfMin = Period();
   string id = IntegerToString((long)tfMin) + "_" + IntegerToString((long)GetTickCount());
   while(BaseKnotFind(id) >= 0) id += "r" + IntegerToString(MathRand() % 1000);
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, g_bkT1, g_bkP1, tc, p2)) return;
   BaseKnotStyleBox(box);   // fill layer + drag handle (ZORDER included) — the VISIBLE border is 4 edges drawn in Sync below
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, true);   // THE handle: drag moves children
   ObjectSetInteger(0, box, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, BaseKnotTFMask(tfMin));
   ObjectSetString(0, box, OBJPROP_TOOLTIP, "Base box — drag to move (lines follow) · select + Delete key removes all");
   // Direction is AUTOMATIC at commit (no Buy/Sell badge): box below
   // the live price = demand = Buy; box above it = supply = Sell; a commit
   // landing with the price inside resolves by entry side (see resolver).
   // Afterwards it keeps following via BaseKnotRefreshDirection (P-BK-13).
   double bkTop = MathMax(g_bkP1, p2), bkBot = MathMin(g_bkP1, p2);
   int dir = BaseKnotResolveDirection(bkTop, bkBot);
   BaseKnotRegister(id, dir, tfMin);
   BaseKnotSync(id);
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   g_bkState = BK_IDLE;   // single-shot: tool OFF after one box — stray clicks draw nothing
   g_bkHeld = false;
   BaseKnotUnlockChart();
   g_bkRestoreReq = true;   // UI side re-shows the hidden ring menu
   // No bottom hint: the info lives ON the box (INFO badge + hover tooltips).
   // To look again: tap the box (re-opens the badge grace) or hover it.
   // P-BK-73: and the box is handed ITS OWN selection, exactly as MT4's own
   // rectangle is still in edit mode when the draw is let go — that is what
   // makes the terminal paint the five markers, i.e. the corner handles the
   // native resize (P-BK-72) is measured against. Last write of the commit,
   // after every property this function owns, so nothing here can undo it.
   BaseKnotSelectBox(id);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| P-BK-21 — THE ADJUST MAGNET: the magnet lives on the RELEASE.     |
//|
//| «می‌خوام روی یک شدو بزارم، بارها باید انجام بدم که روی همون چیز |
//| بزارم» — placing an EDGE of a committed box on a wick was          |
//| pixel work: the terminal's native drag lands the anchor where the  |
//| cursor is, and one chart pixel is many pips once the chart is      |
//| zoomed out, so the target is reachable only by repeating the drag. |
//|
//| BKMAGNET-OFF (2026-09-06) retired the DRAW-time magnet for a real    |
//| reason — corners jumped onto candle shadows and the box never        |
//| landed where the user clicked — and that decision stands:            |
//| `BaseKnotSnapPrice` is still the identity for corner 1 / corner 2.   |
//| The two gestures are NOT the same question, though. While DRAWING    |
//| the user is sketching a range and any pull is noise; while ADJUSTING |
//| he has already chosen the edge and is asking for EXACTLY that wick.  |
//| So the magnet is now a property of the ADJUST gesture only:          |
//|  · it runs ONCE, on the release (the terminal's drag is over —       |
//|    writing into a live native drag would cancel it, P-BK-15);        |
//|  · it may move ONE price anchor — the side the gesture moved and     |
//|    only when it is the ONLY side that moved, so a whole-box move     |
//|    keeps its exact geometry;                                         |
//|  · it is side-aware (the top side may only take a High, the bottom   |
//|    side only a Low), so a snap can never cross the opposite edge;    |
//|  · candidate wicks are the moved anchor's own bar ±BK_MAGNET_BARS,   |
//|    inside `g_magnetSensitivityPips` × the SYMBOL's pip (gold, JPY,   |
//|    indices and crypto included — never a hard-coded point).          |
//| These are the retirement's own knobs, so the two settings that the   |
//| card had left inert (MAGNET / MAGNET SENS) are live again.           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| BKMAGNET2-OFF (2026-09-15, user decision — «مگنت نمیخواد باشه حذفش |
//| کن»): the ADJUST magnet is RETIRED — both functions below are        |
//| commented in place (the BKMAGNET-OFF pattern), so the release does   |
//| not snap and the box stays where the hand let it go, exactly like    |
//| MT4's own rectangle. `g_enableMagnet` / `g_magnetSensitivityPips`     |
//| have no reader again, so the card hides their rows (P-UI-47's shape).|
//| To restore: uncomment the two functions + the release call and       |
//| re-add the two card rows, then re-teach `[bkmagnet]`.                |
//+------------------------------------------------------------------+
// #define BK_MAGNET_BARS 1   // candidate window around the anchor's bar (taste)

// Nearest candle extreme to `price`, restricted to the side being moved.
// `topSide` = the anchor is the box's upper corner, so only Highs qualify.
// double BaseKnotMagnetPrice(const datetime t, const double price, const bool topSide)
// {
//    if(!g_enableMagnet) return price;
//    if(t <= 0 || price <= 0) return price;
//    double pip = BaseKnotPipSize();
//    double gate = (double)g_magnetSensitivityPips * pip;
//    if(gate <= 0) gate = pip;   // sensitivity 0 = exact touch only (retired rule)
//    int sh = iBarShift(_Symbol, 0, t, false);
//    if(sh < 0) return price;
//    double best = price, bestD = gate;
//    for(int k = -BK_MAGNET_BARS; k <= BK_MAGNET_BARS; k++)
//    {
//       int s = sh + k;
//       if(s < 0) continue;
//       double cand = 0.0;
//       if(topSide) cand = iHigh(_Symbol, 0, s);
//       else        cand = iLow(_Symbol, 0, s);
//       if(cand <= 0) continue;
//       double d = MathAbs(price - cand);
//       if(d <= bestD) { bestD = d; best = cand; }   // <= : a tie takes the LATER bar
//    }
//    return best;
// }

// ONE write per adjusted gesture, issued on the release, before the Sync that
// repaints the children. Compares the box's live anchors against the press-time
// snapshot the native-drag latch already took (s_bkDragBP1/BP2).
// void BaseKnotMagnetSettle(const string bid)
// {
//    if(!g_enableMagnet || bid == "") return;
//    // P-BK-25: the magnet's whole decision is "did ONE side move?" — a comparison
//    // against a snapshot of the press. A gesture we ADOPTED mid-drag has no such
//    // snapshot (its baseline was taken after the terminal had already moved the
//    // box), so the honest answer is to snap NOTHING: leave the box exactly where
//    // the hand let it go. A role that cannot be measured must not invent.
//    if(!s_bkSnapTrusted) return;
//    if(BaseKnotFind(bid) < 0) return;
//    string box = BaseKnotBoxName(BaseKnotPrefix(bid));
//    if(ObjectFind(0, box) < 0) return;
//    double pt = GetCachedPoint();
//    if(pt <= 0) pt = _Point;
//    double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
//    double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
//    bool moved1 = (MathAbs(p1 - s_bkDragBP1) > pt * 0.5);
//    bool moved2 = (MathAbs(p2 - s_bkDragBP2) > pt * 0.5);
//    if(moved1 == moved2) return;   // a whole-box move (or a tap) — never re-shape it
//    int idx = (moved1 ? 0 : 1);
//    datetime ta = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, idx);
//    double pa = (idx == 0 ? p1 : p2);
//    double other = (idx == 0 ? p2 : p1);
//    double snap = BaseKnotMagnetPrice(ta, pa, (pa > other));
//    if(MathAbs(snap - pa) <= pt * 0.5) return;   // already on the wick — zero writes
//    if(!ObjectMove(0, box, idx, ta, snap)) return;
//    Print("[BK] magnet box=", bid, " side=", (idx == 0 ? 1 : 2), " ",
//          DoubleToString(pa, _Digits), " -> ", DoubleToString(snap, _Digits),
//          " (", DoubleToString(BaseKnotToPips(MathAbs(snap - pa)), 1), " pips)");
// }

// Press (MOUSE_MOVE rising edge, or a CLICK when no press edge was seen —
// some builds/mice emit no clean rising edge): ARMED → corner 1. Never
// commits — the release (or the next click) is corner 2.
void BaseKnotPress(const datetime t, const double praw)
{
   if(g_bkState != BK_ARMED) return;
   uint now = GetTickCount();
   if(now - g_bkArmedMs < BK_ARM_GUARD) return;      // the arming click's own echo (CLICK path only)
   double p = BaseKnotSnapPrice(t, praw);
   g_bkT1 = t; g_bkP1 = p;
   g_bkLiveT = t; g_bkLiveP = p;
   g_bkHeld = true;
   g_bkState = BK_PREVIEW;
   string pv = BaseKnotPrevTag();
   if(pv == "") return;
   // P-BK-74: the rubber band is ONE rectangle again (the family the commit
   // hands over), hollow and foreground, wearing the final look — what the user
   // sizes is literally what he gets.
   BaseKnotDrawPreviewRect(pv, t, p, t, p,
                           GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth,
                           "Base box sizing — release / second click to commit", BaseKnotTFMask(Period()));
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Master event entry — call FIRST in OnChartEventHandler; true =    |
//| consumed (caller must return immediately, no chart-click leak).   |
//+------------------------------------------------------------------+
bool BaseKnotOnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   BaseKnotLazyInit();
   string tag = (StringLen(inpObjectPrefix) > 0 ? inpObjectPrefix + BK_TAG : "");

   //--- BK clicks die here (any state, incl. IDLE) so they never reach menus.
   //--- Direction is automatic (box below live price = Buy, above = Sell).
   //--- NOBKDEL: no X badge is created anymore; a DEL click below only fires
   //--- for pre-retire badges and still deletes the box (then purges).
   if(id == CHARTEVENT_OBJECT_CLICK && tag != "")
   {
      if(StringFind(sparam, tag) == 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = "", kind = "";
         BaseKnotSplitTail(tail, bid, kind);   // LAST underscore: ids hold one too
         if(kind == "DEL")
         {
            int k = BaseKnotFind(bid);
            BaseKnotDelete(bid);   // unknown id → still wipe by prefix
            if(k < 0 && tag != "")
            {
               ObjectsDeleteAll(0, tag + bid + "_");
               ChartRedraw();
            }
            return true;
         }
         if(kind == "BUY") { ObjectDelete(0, sparam); return true; }   // NOBUYSELL leftover
         if(kind == "") return true;   // PREVIEW/HINT tails — swallow, no action
         // Click-to-recall: a tap on a committed box re-opens its INFO grace,
         // so the badge comes back for BK_INFO_GRACE_MS — the "look again"
         // path, with the info exactly ON the box (never at the bottom).
         // One Sync per click (clicks are rare; drags already Sync on release).
         int kr = BaseKnotFind(bid);
         if(kr >= 0)
         {
            g_bkBoxes[kr].commitMs = GetTickCount();
            BaseKnotSync(bid);
            ChartRedraw();
         }
         return true;   // clicks on box/lines/info text die here — never reach menus
      }
   }

   //--- BKGRIP-OFF (P-BK-71): the HANDLE drag is retired with the chips — the box'
   //--- own body drag is the only native gesture now, and it arrives on the BOX branch
   //--- below. The tail mapping stays (that is how a ghost chip from an older build is
   //--- still NAMED), but nothing routes into the resize writer any more.
   if(id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0)
   {
      string gtail = StringSubstr(sparam, StringLen(tag));
      string gid = "", gkind = "";
      BaseKnotSplitTail(gtail, gid, gkind);
      int gside = BaseKnotGripSide(gkind);
      if(gside != 0)
      {
         // BKGRIP-OFF: BaseKnotGripDrag(gid, gside, sparam);
         // BKGRIP-OFF: return true;
      }
   }

   //--- box drag → children follow; box delete → cascade; child delete → heal
   if(id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0 &&
      StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
   {
       string tail = StringSubstr(sparam, StringLen(tag));
       string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
       if(bid == "PREVIEW") return true;
        if(BaseKnotFind(bid) >= 0)
        {
           if(BaseKnotLocked(bid)) return true;   // locked — swallow, children stay put
           // P-BK-19a: the terminal just NAMED the object it is dragging, so the
           // gesture is ITS — the cursor fallback stays off for the rest of it.
           s_bkNativeClaim = true;
           // P-BK-65: AND IT JUST SAID WHICH OBJECT: the BOX, not a chip. That is the
           // ground truth behind two answers this press needs — "the body-size heal may
           // run" (`s_bkBoxNamed`) and "this press is NOT a resize" (a chip gesture
           // latched earlier belongs to a gesture that is already over: the terminal
           // cannot drag a chip and the box at once). Two stores on the gesture's own
           // events; nothing here runs per tick.
           s_bkBoxNamed    = true;
           s_bkGripGesture = 0;
           // Unified lean follow (P-BK-07): anchor-exact moves only — never a
           // full Sync per step (its style/tooltip rewrites lagged children
           // behind the native BOX on heavy charts). This event carries no
           // trusted cursor (in-repo pattern: TH3Tool reads live anchors here
           // too), so it is anchor-exact only — the cursor fallback that used to
           // ride the MOUSE_MOVE channel is RETIRED (BKCURSOR-OFF). Release still
           // does the authoritative Sync.
           if(bid != s_bkDragId)
           {
              // Overlap hole: the press latched another box — adopt the
              // actually-dragged one (cursor base stays: same press point).
              string abox = BaseKnotBoxName(BaseKnotPrefix(bid));
              if(ObjectFind(0, abox) >= 0)
              {
                 s_bkDragId = bid; s_bkDragMoved = true;
                 Print("[BK] drag adopt box=", bid, " (the press missed it)");   // diag: terminal drags a box the press missed
                 s_bkSnapTrusted = false;   // P-BK-25: this baseline is taken MID-DRAG
                 BaseKnotDragLockOn();   // definitively dragging — freeze the view
                 s_bkDragBT1 = (datetime)ObjectGetInteger(0, abox, OBJPROP_TIME, 0);
                 s_bkDragBT2 = (datetime)ObjectGetInteger(0, abox, OBJPROP_TIME, 1);
                 s_bkDragBP1 = ObjectGetDouble(0, abox, OBJPROP_PRICE, 0);
                 s_bkDragBP2 = ObjectGetDouble(0, abox, OBJPROP_PRICE, 1);
                    s_bkFolT1 = s_bkDragBT1; s_bkFolT2 = s_bkDragBT2;
                    s_bkFolP1 = s_bkDragBP1; s_bkFolP2 = s_bkDragBP2;
                }
             }
            BaseKnotFollowDrag(bid, 0, 0);
         }
         else
         {
            // Diag: a BK BOX is being dragged but the registry doesn't know
            // it — children can't follow. Throttled: DRAG fires per step.
            static string s_bkDiagUnk = "";
            static uint s_bkDiagUnkMs = 0;
            uint unow = GetTickCount();
            if(bid != s_bkDiagUnk || unow - s_bkDiagUnkMs > 5000)
            { s_bkDiagUnk = bid; s_bkDiagUnkMs = unow; Print("[BK] drag: box not in registry ", bid); }
         }
         return true;
    }
   if(id == CHARTEVENT_OBJECT_DELETE && tag != "" && StringFind(sparam, tag) == 0)
   {
      string ltag = BaseKnotLiveTag();
      if(ltag != "" && StringFind(sparam, ltag) == 0) return true;   // live sizing set — owned by the draw flow
      // Only the BOX triggers the cascade (children deletes re-enter as no-ops).
      if(StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
         if(bid == "PREVIEW" || bid == "HINT") return true;
         BaseKnotDelete(StringSubstr(tail, 0, StringLen(tail) - 4));
      }
       else
       {
          // A manually deleted child (ENTRY/SL/TP/INFO/edge, or a pre-retire
          // DEL) self-heals via re-sync; trailing deletes of an already-gone box just mop up.
          // Edge segments (P-BK-06 visible border) end with _T/_B/_L/_R — strip
          // to the parent id first (SplitTail would cut at the wrong underscore).
          int slen = StringLen(sparam);
          if(slen >= 2 &&
             (StringSubstr(sparam, slen - 2) == BK_EDGE_T || StringSubstr(sparam, slen - 2) == BK_EDGE_B ||
              StringSubstr(sparam, slen - 2) == BK_EDGE_L || StringSubstr(sparam, slen - 2) == BK_EDGE_R))
          {
             string tailE = StringSubstr(sparam, StringLen(tag));
             string bidE = StringSubstr(tailE, 0, StringLen(tailE) - 2);   // drop "_X"
             if(StringLen(bidE) > 0 && StringSubstr(bidE, StringLen(bidE) - 1) == "_")
                bidE = StringSubstr(bidE, 0, StringLen(bidE) - 1);          // drop pfx trailing "_"
             if(BaseKnotFind(bidE) >= 0)
             {
                string pfxE = BaseKnotPrefix(bidE);
                if(ObjectFind(0, BaseKnotBoxName(pfxE)) >= 0) BaseKnotSync(bidE);
                else BaseKnotDelete(bidE);
                ChartRedraw();
             }
             return true;
          }
          string tail = StringSubstr(sparam, StringLen(tag));
         string bid = "", kind = "";
         BaseKnotSplitTail(tail, bid, kind);
         if(kind == "") return true;   // PREVIEW/HINT transient — swallow
         if(BaseKnotFind(bid) >= 0)
         {
            string pfx = BaseKnotPrefix(bid);
            if(ObjectFind(0, BaseKnotBoxName(pfx)) >= 0) BaseKnotSync(bid);
            else BaseKnotDelete(bid);
            ChartRedraw();
         }
         else if(bid != "")
         {
            // Trailing delete of an already-removed box (or a half-built
            // orphan): mop up by prefix, no redraw — the BOX branch redraws.
            ObjectsDeleteAll(0, BaseKnotPrefix(bid));
         }
      }
      return true;
   }

   //--- view moved under pixel badges → re-glue (never consumed)
   if(id == CHARTEVENT_CHART_CHANGE) { BaseKnotSyncBadges(); return false; }

   //--- ESC leaves the session from anywhere
   if(id == CHARTEVENT_KEYDOWN && lparam == 27 && BaseKnotSessionActive())
   {
      BaseKnotCancel();
      return true;
   }

    //--- IDLE box-drag follow (unified lean follow, P-BK-07): the terminal
    //--- moves the BOX natively and children follow through BaseKnotFollowDrag —
    //--- anchor-exact and unbudgeted (the ONE, LIVE writer; the cursor-delta
    //--- fallback is retired, BKCURSOR-OFF). One paint budget, then one
    //--- authoritative BaseKnotSync from the committed anchors on release.
    //--- Never consumes — menus/panels/hold still see every move (Lite-safe:
    //--- Object* only).
   if(id == CHARTEVENT_MOUSE_MOVE && g_bkState == BK_IDLE)
   {
      int sst = (int)StringToInteger(sparam);
      bool sleft = ((sst & 1) != 0);
      bool srising = (sleft && !g_bkLeftPrev);
      bool sfalling = (!sleft && g_bkLeftPrev);
      g_bkLeftPrev = sleft;
       if(srising)
       {
          s_bkDragActMs = GetTickCount();
          // P-BK-65: A RISING EDGE WHILE A CHIP IS HELD IS A FLICKER, NOT A PRESS.
          // The terminal's own OBJECT_DRAG of a chip is the ground truth that this
          // press is a RESIZE, and re-labelling it here is what made a resize snap
          // back (see the P-BK-65 block above the statics): the release then read it
          // as a body drag and the size heal put the old size back, and the keeper
          // rewrote the chip under the hand. While that latch is live the press edge
          // leaves the GESTURE's identity alone — it may only touch the fields a new
          // gesture needs. A REAL press always finds the latch at 0 (the release or
          // the silence watchdog cleared it), so a fresh gesture still starts fresh.
          const bool bkGripHeld = (s_bkGripGesture != 0);
          if(!bkGripHeld)
          {
             s_bkDragId = ""; s_bkDragMoved = false;
             s_bkSnapTrusted = false;   // P-BK-25: a fresh press has no trusted baseline yet
             // P-BK-19: a fresh press is a fresh gesture — nobody owns it yet, and
             // the window in which the terminal is asked first starts NOW.
             s_bkNativeClaim = false; s_bkOwnerMs = GetTickCount(); s_bkFallLogged = false;
             s_bkBoxNamed = false;   // P-BK-65: no terminal-named box drag in this press yet
             // P-PERF-42/41: the child mask is re-probed for THIS gesture (the same
             // box dragged twice probes twice) and the timing counters restart.
             s_bkChildMaskId = ""; s_bkPerfMoveWorst = 0; s_bkPerfPaintWorst = 0; s_bkPerfPasses = 0;
             s_bkGripLive = 0; s_bkGripLogged = false; s_bkMagnetLogged = false;   // P-BK-61: a fresh press is a fresh gesture
          }
          int ssw = 0; datetime sct = 0; double scp = 0;
         // P-UI-92: a press that lands ON a visible UI surface is the UI's pixel — the
         // card/strip/menu sits OVER the box, so the user is reading or setting a
         // control, not grabbing what is behind it. Without this test the latch armed
         // on the hidden box and the next move dragged it (click bleed-through: the
         // panel's own press is classified in the UI half of the same event, which
         // runs AFTER this one). The press is never consumed by the box tool — the
         // rejection is deliberately NOT a claim on the gesture.
         // P-BK-65: while a chip is held this press edge owns NOTHING — the live
         // resize already latched its box and took its baseline before the terminal
         // moved anything, and a mid-drag snapshot here would be the P-BK-25 trap.
         if(!bkGripHeld &&
            !UIPointerOverSurface((int)lparam, (int)dparam) &&
            ChartXYToTimePrice(0, (int)lparam, (int)dparam, ssw, sct, scp) && ssw == 0 && sct > 0 && scp > 0)
         {
            string shit = BaseKnotBoxAt(sct, scp);   // exact INSIDE test first — it never lies
            if(shit == "") shit = BaseKnotBoxAtPx((int)lparam, (int)dparam);   // P-BK-24: the drawn BORDER is a target too
            if(shit != "" && BaseKnotFind(shit) >= 0 && !BaseKnotLocked(shit))
            {
               string shbox = BaseKnotBoxName(BaseKnotPrefix(shit));
               if(ObjectFind(0, shbox) >= 0)
               {
                  s_bkDragId = shit;
                  s_bkDragT0 = sct; s_bkDragP0 = scp;
                  s_bkDragX0 = (int)lparam; s_bkDragY0 = (int)dparam;
                   s_bkDragBT1 = (datetime)ObjectGetInteger(0, shbox, OBJPROP_TIME, 0);
                   s_bkDragBT2 = (datetime)ObjectGetInteger(0, shbox, OBJPROP_TIME, 1);
                    s_bkDragBP1 = ObjectGetDouble(0, shbox, OBJPROP_PRICE, 0);
                    s_bkDragBP2 = ObjectGetDouble(0, shbox, OBJPROP_PRICE, 1);
                    s_bkFolT1 = s_bkDragBT1; s_bkFolT2 = s_bkDragBT2;
                    s_bkFolP1 = s_bkDragBP1; s_bkFolP2 = s_bkDragBP2;
                     // P-BK-72: the press-time grab role is LIVE — its consumer is NOT the
                     // retired cursor fallback (BKCURSOR-OFF stays dead) but the release's
                     // size heal below: a press on a corner/edge marker is a native RESIZE
                     // (the docs' own rule — anchors change the size), and the heal must
                     // only ever fire for a BODY move. BaseKnotGrabRole stays the measurer.
                     s_bkGrabSel = BaseKnotGrabRole(shbox, s_bkDragX0, s_bkDragY0);
                    s_bkSnapTrusted = true;   // P-BK-25: OUR press latched it — the baseline predates any terminal move
                    Print("[BK] drag latch box=", shit);   // diag: press found a box — follow armed
                }
            }
         }
      }
      else if(sfalling)
      {
         // Release after a REAL drag: authoritative final from committed anchors
         // (guarantees "correct on release" even where no mid-drag event fired).
         // A tap (no move) syncs nothing — tap-select stays untouched.
         // Overlap hole: the press candidate may differ from the truly dragged
         // box — the drop point is under the cursor, so sync that box too.
          // P-BK-61: a HANDLE resize ends here too, and it owes the same authoritative
          // Sync even when the hand barely moved (a 3px correction is a resize, not a
          // tap) — so the gesture's own flag joins the condition. P-BK-65: that flag
          // is the KIND (`s_bkGripGesture`, latched from the terminal's own
          // OBJECT_DRAG of a chip), never the keeper's `s_bkGripLive` — a mouse-channel
          // flicker cleared the skip and the release then re-sized the box back. The
          // flag is READ and CLEARED first, so the Sync below may glue every chip, the
          // one the hand just let go of included (never written while the terminal
          // still held it).
          // P-BK-65: THE KIND OF GESTURE DECIDES THIS PATH, NEVER THE SKIP FIELD.
          // `s_bkGripLive` says which chip the hand holds (the keeper's skip, cleared
          // by a press edge); `s_bkGripGesture` says this press WAS a resize, and only
          // a real end can clear it. Reading the skip here is the bug the user
          // reported: one flicker made the release call a resize a body drag.
          int bkGripWas = s_bkGripGesture;
          s_bkGripLive = 0; s_bkGripLogged = false; s_bkMagnetLogged = false;
          s_bkGripGesture = 0; s_bkBoxNamed = false;   // this gesture is over
          if(s_bkDragId != "" && (s_bkDragMoved || bkGripWas != 0))
          {
              // P-PERF-43: the same line carries WHAT the gesture cost, split by
              // phase — the ledger that answers the next "the drag lags" with a
              // number (children/box writes vs the throttled repaint) instead of a
              // guess. One line per gesture, never per step.
              Print("[BK] drag release sync box=", s_bkDragId, " native=", (s_bkNativeClaim ? 1 : 0),
                    " follow=", s_bkPerfPasses, " move=", (int)s_bkPerfMoveWorst, "ms paint=",
                    (int)s_bkPerfPaintWorst, "ms resize=", bkGripWas);   // diag: authoritative final
              bool painted = false;
             double relRef = BaseKnotLiveRef();   // P-BK-13: a drag across the price flips NOW, not 500 ms later
             int ssw3 = 0; datetime sct3 = 0; double scp3 = 0;
             if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, ssw3, sct3, scp3) && ssw3 == 0 && sct3 > 0 && scp3 > 0)
             {
                string sdrop = BaseKnotBoxAt(sct3, scp3);
                if(sdrop != "" && sdrop != s_bkDragId && BaseKnotFind(sdrop) >= 0 && !BaseKnotLocked(sdrop))
                {
                   BaseKnotRefreshDirection(sdrop, relRef);
                   BaseKnotSync(sdrop);
                   painted = true;
                }
             }
             if(BaseKnotFind(s_bkDragId) >= 0)
             {
                 // BKMAGNET2-OFF (2026-09-15, user decision): the ADJUST magnet
                 // is retired — the release does not snap (the engine above is
                 // commented). The box stays where the hand let it go.
                 // BaseKnotMagnetSettle(s_bkDragId);
                  // P-BK-61b/P-BK-72: a BODY drag carries the box and nothing else — the size
                  // the hand took it with comes back before the authoritative Sync (a
                  // HANDLE drag, bkGripWas, IS the size gesture and is left alone — and so
                  // is a NATIVE corner/edge resize: the press-time role says it was never
                  // a body move, so the heal would spring the user's own resize back).
                  if(bkGripWas == 0 && s_bkGrabSel == BK_GRAB_ALL) BaseKnotBodySizeHeal(s_bkDragId);
                 BaseKnotRefreshDirection(s_bkDragId, relRef);
                BaseKnotSync(s_bkDragId);
                painted = true;
             }
            if(painted) ChartRedraw();
            // P-BK-61: a RESIZE hands the selection back to the box (the terminal gave
            // it to the chip), so the corner handles stay on screen and the next side is
            // one grab away — no second click.
            if(bkGripWas != 0) BaseKnotGripReselect(s_bkDragId);
          }
           // BKSELECT-KEPT (2026-09-15, user decision — «مثل خود متاتریدر»):
           // the box STAYS selected after a drag, like MT4's own rectangle, so
           // a second resize needs no re-click (P-BK-26's drop forced a
           // select-then-drag double step for every edge). The hijack P-BK-26
           // feared is gone with the retired cursor fallback (BKCURSOR-OFF):
           // nothing of ours writes the box except this gesture's own follow,
           // and the terminal single-selects on press like for its own objects.
           // Deselect as always via empty-chart click / Esc / another object.
          s_bkDragId = ""; s_bkDragMoved = false;
          BaseKnotDragLockOff();   // gesture over — hand the view back (self-guarded)
       }
      else if(sleft && s_bkDragId != "")
      {
         if(BaseKnotFind(s_bkDragId) < 0) { s_bkDragId = ""; s_bkDragMoved = false; }
         else
         {
            int smx = (int)lparam, smy = (int)dparam;
            if(!s_bkDragMoved &&
               MathAbs(smx - s_bkDragX0) <= BK_DRAG_SLOP && MathAbs(smy - s_bkDragY0) <= BK_DRAG_SLOP)
            {
               // still inside press slop — a hold, not a drag (strip may open)
            }
             else
             {
                s_bkDragMoved = true;
                BaseKnotDragLockOn();   // past slop = real drag: freeze the view like MT4's own tools
                // Cursor-carrying channel (MOUSE_MOVE coords are trusted —
                // OBJECT_DRAG's are not, so that branch is anchor-exact only).
                // Same unified follow; the shared 30ms gate inside absorbs
                // duplicates, so the channels never fight and neither starves.
                int ssw2 = 0; datetime sct2 = 0; double scp2 = 0;
                if(ChartXYToTimePrice(0, smx, smy, ssw2, sct2, scp2) && ssw2 == 0 && sct2 > 0 && scp2 > 0)
                   BaseKnotFollowDrag(s_bkDragId, sct2, scp2);
             }
         }
      }
   }

   //--- P-BK-63: a CLICK (id 4 = a click on the CHART; a click on a SELECTABLE
   //--- object arrives as OBJECT_CLICK, id 1, and the branches above own it)
   //--- that lands OUTSIDE every box lets the box' selection go — the mirror of
   //--- `BaseKnotGripReselect`, so the handles that a click shows disappear on
   //--- the click that dismisses them. Right-clicks are left alone (the context
   //--- menu is a different gesture), and the event is NOT consumed: the menu
   //--- and panel halves read it exactly as they did before.
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") < 0 &&
      BaseKnotDeselectOnChartClick((int)lparam, (int)dparam))
   {
      ChartRedraw();
      return false;
   }

   if(!BaseKnotSessionActive()) return false;

   //--- right-click cancels (both encodings MT4 uses)
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      if((st & 2) != 0) { BaseKnotCancel(); return true; }
   }
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") >= 0) { BaseKnotCancel(); return true; }

   //--- press / drag / release (native-like). Rising = corner 1 on PRESS;
   //--- held moves = live preview; falling (release) = commit at release.
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      bool left = ((st & 1) != 0);
      bool rising  = (left && !g_bkLeftPrev);
      bool falling = (!left && g_bkLeftPrev);
      g_bkLeftPrev = left;
      if(rising)
      {
         // P-UI-92: a press on a UI surface belongs to the UI, not to the draw session.
         // Corner 1 must not be placed at the chart price hidden under the card (a
         // press/release pair on the panel used to place BOTH corners of a box the
         // user never saw). The event is still swallowed so the session keeps owning
         // the mouse; the UI half of this same event runs right after the domain half.
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
         if(g_bkState == BK_ARMED)
         {
            int sw = 0; datetime ct = 0; double cp = 0;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
               BaseKnotPress(ct, cp);
         }
         else if(g_bkState == BK_PREVIEW)
            g_bkHeld = true;   // corner-2 drag begins (corner 1 stays)
         return true;
      }
      if(falling)
      {
         // P-UI-92: the release that lands on a UI surface is not a chart release —
         // committing here would put corner 2 under the panel from a press the panel
         // already consumed. The session stays alive so sizing continues from the last
         // chart point the cursor actually visited.
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
         if(g_bkState == BK_PREVIEW)
         {
            g_bkHeld = false;
            int sw = 0; datetime ft = 0; double fp = 0;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ft, fp) && sw == 0 && ft > 0 && fp > 0)
               BaseKnotCommit(ft, fp);
            else if(g_bkLiveT > 0)
               BaseKnotCommit(g_bkLiveT, g_bkLiveP);   // released off-chart → last seen point
         }
         return true;
      }
      //--- rubber-band: live preview follows the cursor while HELD (drag)
      //--- and while hovering (tap-tap sizing) — zero indicator work.
      //--- throttled: a mouse-move storm must never pin the CPU (30 ms ≈ 33 fps).
      if(g_bkState == BK_PREVIEW)
      {
         static uint s_bkRubberMs = 0;
         uint nowR = GetTickCount();
         if(nowR - s_bkRubberMs < 30) return true;   // swallow, skip the redraw
         s_bkRubberMs = nowR;
         BaseKnotReassertLock(true);   // P-BK-14: the session owns the view until commit/cancel
         int sw = 0; datetime ht = 0; double hp = 0;
         string pv = BaseKnotPrevTag();
         if(pv != "" && ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ht, hp) && sw == 0 && ht > 0 && hp > 0)
         {
            hp = BaseKnotSnapPrice(ht, hp);   // click = corner (magnet off — identity)
            // P-BK-74: ONE rectangle, moved — no delete/recreate per frame, so a
            // hover costs two ObjectMove calls and one paint, not a create storm.
            BaseKnotDrawPreviewRect(pv, g_bkT1, g_bkP1, ht, hp,
                                    GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth,
                                    "Base box sizing — release / second click to commit", BaseKnotTFMask(Period()));
             g_bkLiveT = ht; g_bkLiveP = hp;
             BaseKnotSyncLive(ht, hp);   // Entry/SL/TP + info follow while sizing
            ChartRedraw();
         }
         return true;
      }
      return (g_bkState == BK_PREVIEW);   // swallow moves mid-gesture, ignore idle hovers
   }

   //--- CLICK fallback (tap path + builds with no clean press/release edge:
   //--- ARMED+CLICK = corner 1, PREVIEW+CLICK = corner 2 commit; after a
   //--- drag-release commit the state is IDLE so the trailing CLICK dies).
   if(id == CHARTEVENT_CLICK)
   {
      // P-UI-92: the tap/commit path is the one that actually leaked — CLICK carries
      // the price under the cursor (`dparam`), so a click on a panel committed a box
      // corner AT THE PRICE HIDDEN BEHIND IT. A click on a UI surface is the UI's:
      // swallowed here, acted on by the UI half of the same event.
      if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
      int sw = 0; datetime ct = 0; double cp = 0;
      if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
      {
         if(g_bkState == BK_ARMED)
            BaseKnotPress(ct, cp);
         else if(g_bkState == BK_PREVIEW)
         {
            g_bkHeld = false;
            BaseKnotCommit(ct, cp);
         }
      }
      return true;
   }

   return false;
}

#endif // BASE_KNOT_TOOL_MQH
