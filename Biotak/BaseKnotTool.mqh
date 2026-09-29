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
//|    for an FTR node and ONE HuntSL for ETR/CTR/OTR, read on the NODE'S|
//|    OWN time, while the SL is ALWAYS one EngSL behind the entry read  |
//|    on the NODE TYPE'S OWN time (P-BK-83: ETR one rung above the      |
//|    node's time, CTR two, OTR three). The TARGETS are the plan's OWN  |
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
//|  * P-BK-83 (2026-09-17) — THE STOP IS READ ON THE NODE TYPE'S OWN    |
//|    TIME (the ENTRY stays on the node's own). The stop used the node's|
//|    own class for FTR **and ETR**, so an ETR node standing on an M1   |
//|    base wore EngSL(M1): the user's box read                        |
//|    `[BUY · EngSL 0.3 | 2.9 | 5 bars · M1 base · ETR]` — a 0.3-pip   |
//|    stop on a 2.9-pip node whose LENGTH belongs to M5. The type IS the|
//|    rung whose ability the length matched (P-BK-75/78), so the time   |
//|    that OWNS the node is its own time stepped up by the type's own   |
//|    count: FTR 0 · ETR 1 · CTR 2 · OTR 3 (BaseKnotMeasureHops is the  |
//|    ONE owner). The ENTRY does not hop — the user confirmed that read |
//|    («ورودش که درسته»): BaseKnotEntryTFMin is the node's own time.    |
//|    The label prints the stop's TF beside the name (`EngSL M5`)       |
//|    whenever it differs from the class, and nothing moves outside the |
//|    box: P-BK-52's 55/64 bound caps each leg by the node's own power. |
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
//|    (= TH points, pushed in by the pump layers — TH lives in THCalculations,|
//|    below this module, so it is never read here) only size the break story's    |
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

#include "BaseKnot_Base.mqh"
#include "BaseKnot_Measure.mqh"
#include "BaseKnot_Nodes.mqh"
#include "BaseKnot_Plan.mqh"
#include "BaseKnot_Drag.mqh"

#endif // BASE_KNOT_TOOL_MQH
