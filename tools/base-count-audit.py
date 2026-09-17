#!/usr/bin/env python3
"""base-count-audit — the gate behind P-BK-31/32/33/34 (the note's "N bars · M15 base").

WHY THIS EXISTS
Every base knot carries one number the user reads to size a trade: `N bars` in
`[BUY · EngSL 2.4 | 26.4 | N bars · M15 base · OTR]` (P-BK-54 gave the note this
glance shape - risk + source, then the base's own story; P-BK-57 put the box'
own height, bare, between them), and the SAME number picks
the size class (`3 x rung / chartTF`, P-BK-28). It is the only part of the note
that is a BAR WALK instead of arithmetic on the box, so it is the only part that
can disagree with what the user sees on the chart - and it did, twice:

  * v1 counted every CLOSE inside the ceiling/floor over the box's span, so
    trend candles merely passing through the band counted (a 19-candle base read
    51);
  * v2 counted every BODY inside the band ANYWHERE in the box, so the number
    measured the BOX, not the base: 20 with the box on the base («الان حالت
    واقعی ۲۰ نشون میده»), and 43 once the same box was widened backwards over
    an older ranging stretch. The base itself never changed - only how far the
    user had dragged.

The rule the user asked for is the base's own length: «۱۹ تا هستش از [شروع] تا
اصلاح که کرده و شکسته» and «در هر حالت باید ۱۹ نشون بده». So the walk is anchored
on the box' RIGHT edge (the newer end, where the break is - P-BK-29 reads the
break to the right of it), steps over at most BK_BASE_SKIP breakout candles, and
then counts the run of in-band bodies going older. The box' LEFT edge bounds
NOTHING.

P-BK-32 (2026-09-15) is the TOLERANCE the user asked for next: «معیار داخل بودن
کندل در باند بیس را طوری تنظیم کن که یک کندلِ منفرد با بدنه بیرونی ران بیس را قطع
نکند، بدون اینکه عدد دوباره به پهنای باکس وابسته شود». Its ARCHITECTURE is the
point: a tolerance is a COUNT OF CANDLES, never a price margin. A margin (x% of
the band, or k*ATR - the "interaction margin" family of the TradingView range
scripts) would put the BAND back inside the number, and a box drawn half a pip
taller would print another base; a count lives on the bar index alone - a
morphological CLOSING of the inside/outside series with a 1-candle structuring
element, which is the debounce every range detector in the wild counts in bars
(TradingView's "hold for N consecutive bars", the Darvas-box code's M
confirmation candles). Concretely: ONE isolated out-of-band BODY is stepped over
and NOT counted, a CLUSTER (BK_BASE_GAP + 1 in a row) ends the base, and the
candles found past a tolerated gap join the base only once BK_BASE_MIN_BARS of
them in a row hold the band - the confirmation that keeps a stray in-band candle
on the ENTRY side from re-opening the run (the 19 -> 20 this gate exists for).

P-BK-33 (2026-09-15) is the budget the walk steps over the break WITH: «اینکه جلو
میبریم شمارش کندل ها رو نشون نمیده». The anchor is the box' right edge and the user
drags that edge FORWARD over the break, so the candles between the edge and the base
have to be stepped over. At 4 they were one candle short of his own box - edge at
12:49, the base's last in-band body at 12:44, the break 12:45..12:49, band
1.15323..1.15346 = the 2.3 pips of his note, all read off his own M1 history
(EURUSD, 15 Sep 2026) - so the walk answered "no base" and the note silently
dropped its "N bars · M15 base" part. The budget is BK_BASE_SKIP = 30 candles now
(half an hour of break on M1), and the MODEL reads that number FROM THE SOURCE
(`budgets()`), so lowering it backunder a covered break fails the model here and the gate cannot go stale.

P-BK-39 (2026-09-15) — the anchor budget is no longer a third number of its own but
the walk's own cap (BK_BASE_SKIP == BK_BASE_MAX == 300 bars). A count of candles is
TF-DEPENDENT: the same three-day break the user's D1 box covers is 3 candles on D1
and 49 on H1, so the 30 that was enough on M1 measured the number away on the H1
chart of the very same box (measured on his own EURUSD1440/EURUSD60 history: D1 13
bars, H1 none). A box dragged further than one whole walk from any base still
reports none, which is what the budget is for.

P-BK-34 (2026-09-15) is the SAME anchor seen from the other side: «باکس که از کندل
لایو جلو میزنه تعداد کندل اشتباه میکنه». iBarShift() answers 0 for ANY time after
the last one, so a right edge dragged past the live candle anchored the walk - and
the count - ON the forming candle: on the user's D1 chart that half-formed body was
the only one left in the band (the two candles before it ended 0.1..7 points above
the box' top) and the note read "1 bars · struct" for a box on a base. The count is
CLOSED-BAR data, the law the node read has always obeyed (P-BK-29): the anchor is at
least shift 1, so an edge past the live candle reads exactly like an edge ON the
newest closed one.

P-BK-37 (2026-09-15) — «الان از لو باکس تا زمانی که باکس شکسته شده رو تعداد کندل رو
میخوام»: the number the note prints became the base's LIFE instead of the count of
in-band bodies, and it STARTS at the run's own oldest in-band candle — a property of
the PRICE ACTION, never the box' left edge («اینجا چرا ده تا نشون میده در صورتی که
13 تا هستش»). Its END, read as «the box' right edge», is superseded below.

P-BK-41/42 (2026-09-15) — «از جای که وارد بیس شده تا جایی که ازش خارج شده و شکسه و
کلوز کرده 9 کندل هستش این چرا 38 نوشته … فکر کنم بهتر که از زمانی که وارد بیس شده تا
زمانیکه خارج از بیس یا گره معاملاتی شده رو تعداد کندل ها شو نشون بده» + «اول باید
سقف و کف بیس یا گره معاملاتی رو مشخص کنیم … کندل ورود جز شمارش حساب نکنیم ولی کندل
خروج جز شمارش حساب بکنیم»: the number's two ends belong to the BASE, not to the box.
With the anchor budget at the walk's cap (P-BK-39) every candle between the base and
the box' right edge was counted as if the base had lasted it — a nine-candle base
whose box reached ~29 candles past its exit printed «38 bars». Now the anchor search
finds the base nearest the box' right edge, the first candle it examined just past it
(`anchor - 1`) is «the candle that closed outside the band» — the EXIT, and it IS
counted — and the base's oldest in-band candle is the ENTRY, which is NOT. So the
number is `oldest - end`: dragging the box further right is free, and the same box on
any chart TF reads the same base. The CLASS (P-BK-36) and the node's story (P-BK-38)
read that SAME span, so a box that is merely long can no longer let a higher TF be
named by candles that are not the base. Every earlier promise survives: the LEFT edge
still bounds nothing (the 43), an edge past the live candle still reads like an edge ON
it (P-BK-34), and the walk stays capped (P-BK-39).

P-BK-35 (2026-09-15) — «توی تایم بالا سه کندل درجا زدن هستش گره etr هستش، توی تایم
پایین میایم گره میشه otr … چه از تایم بزرگ به کوچیک و از کوچیک به بزرگ باید همون
etr نشون بده»: the three return types (OTR/CTR/ETR) are read from the BOX' OWN
LEVELS — out-to-return is the return's closes running past the FAR edge — and never
from `retStep > 1.0`. The step split made ONE base read ETR on the TF it was
measured on and OTR one rung down, where the same step is ~24x smaller and the very
same return is "more than one step tall". A type that changes with the window it is
looked through is a reading of the window, not of the base. FTR is unchanged (no
size is claimed), the second-break test (CTR) was always a level test, and the step
is still pushed in and printed — it SIZES the numbers now, it decides nothing.

P-BK-36 (2026-09-15) — «سه کندل درجا زدن برای مشخص کردن تایم بیس باید مولتی تایم
باشه تشخیصش … این گره باید برای تایم پایین باشه چون سه کندل درجا زدن نداره»: the
size class is CONFIRMED ON THE RUNG'S OWN CANDLES. P-BK-28's ladder (3 x rung /
chartTF <= bars) is the rung's DISPLACEMENT, not the rung standing still; so the
highest rung the ladder admits is used only when >= BK_BASE_RUNG_MIN of ITS OWN
candles overlapping the box keep their bodies inside the band, and the next rung
down is tried otherwise. Bounded by design («همین که فشار به سیستم نیاد از محاسبات
الکی»): only the admitted rungs are read, the scan exits on the first confirmations,
it examines at most BK_BASE_RUNG_MAX rung candles, and the answer is memoised on the
exact question so one Sync's note, hover and tooltip share ONE read. An unreadable
rung series (offline history) keeps the ladder's answer; a base whose rungs never
stand still is a base of THIS chart's TF.

P-BK-43 (2026-09-15) — two bugs the user caught on one M15 chart, in the CHOPPY places
(«اینجا های که شلوغ میشه همه نباید باگ داشته باشیم»):

  * «هنوز سی دقیقه نشون میده چرا» — a 7-candle M15 box printed «7 bars · M30 base».
    M30 is not one of OUR timeframes: the project's own ladder (the ATR warm-up queue,
    `{1, 5, 15, 60, 240, 1440, 10080, 43200}`, the same eight his label row prints) has
    no 30, but `BaseKnotNextTFMin` stepped 15 -> 30 like the terminal's TF list, and
    `3 * 30 / 15 = 6 <= 7` admitted M30 over a base barely three M30 candles long. The
    LADDER IS THE PROJECT'S LADDER now; an M30 CHART still names M30 as `Period()`.
  * «1 bars · struct» for a box drawn on a real range — in a congested zone the candle
    nearest the box' right edge can be a lone body that holds the band while everything
    around it pokes out, and it used to ANCHOR the whole answer: one stray candle, one
    bar, and the base three candles behind it was never looked at. The anchor search now
    asks the SAME question of every candidate it meets — "does a base start here?" — and
    only a candle whose run holds BK_BASE_MIN_BARS standing candles becomes the anchor; a
    stray body is stepped over and the search looks behind it, all inside the SAME budget
    (BK_BASE_SKIP candles from the box' right edge), so a box whose whole walk holds no
    base reads none instead of a made-up bar count.

P-BK-44 (2026-09-15) — the END of the story belongs to the RUN, not to the drawn box:
«این چرا عقب میارمش فرق میکنه اعداد … همون 36 تا درست بودش اون نباید 20 باشه … باید
امتداده باکس ها به عقب و جلو خطوط شو در نظر بگیر بای کندل ورود و خروج، ملاک که سقف و
کف بیس هستش نه داخل باکس». Pulling the right edge back INTO the base used to lose every
candle that was still holding the band to the right of that edge (36 became 20) — the
band is the criterion, the rectangle is a pointer. So the run is now walked on BOTH
sides of the box' right edge: NEWER first (the exit side, with the same tolerance and
the same cap), then OLDER from its own newest candle (the entry side), and the exit is
the first candle newer than the RUN's head — so it is the real exit candle even when it
lies to the right of the rectangle, while a box dragged past its own break is untouched
(the run cannot extend at all: the next candle already closed outside). The class's
span and the node's story start ride the same head (P-BK-41).

P-BK-81 (2026-09-17) — and the SIDE is the BASE'S OWN EXIT CANDLE, and it is FIXED. The
user: «چرا جهت درست تشخیص نمیده rbr , dbd rbd … کلا از شر این rbr , dbd rbd خلاص بشیم و
جهت سل و بای به صورت صدردصدی درست تشخیص داده بشه». P-BK-49's four names are GONE: the
standard definitions make RBR and DBR BOTH Buy and RBD and DBD BOTH Sell («the move OUT of
the base decides the direction … the exit shows current intent»), so the approach leg could
only split continuation from reversal and the four names carried no directional information
the exit leg did not already carry. The story walk now STARTS at the base's own exit candle
— the candle that CLOSED OUTSIDE the band, the very one the note's number is counted to —
instead of one bar after the box' right edge: the old start moved with the drawn rectangle
(«کمی که جابجا میکن نوع گره عوض میشه چرا») and, on a chart coarser than the node's own
time, sat a whole bar PAST the exit, so the first close it examined was a later candle —
often a return — and named the opposite side. What the P-BK-46 read did instead was let
price REWRITE the side later (the return's own edge, the second break, and P-BK-48's zeroing
of a CONSUMED node) — which on history answers whatever price did LAST: the LIVE price's
business, not the base's. Retired in place (BKNODEDIR-OFF), replaced by ONE return off
`nd.side`, so the same box reads the same direction on every chart and in the past
market alike.

P-BK-82 (2026-09-17) — and M1 IS A RUNG OF THE LADDER THE CLASS IS FOUND ON. The user:
«چرا تایم گره رو درست و اصولی تشخیص نمیده، گره که مال یک دقیقه هستش رو مال پانزده دقیقه
نشون میده». The read walks the ladder from its HIGHEST rung DOWN and returns the first rung
whose OWN three candles stood still; `BaseKnotNextTFMin` answered 5 for a walk that starts at
0, so that ladder began at M5 and a base standing still on M1 could never be NAMED M1 — every
rung was refused and the "nothing stood still" fallback named the SPAN's own rung instead
(his box: 17 minutes wide around a 5-bar M1 base, so `3 * 15 > 17` refused M15 and
`rungs[i] <= spanMin` named it anyway → «M15 base»). The floor is M1 now — the ATR warm-up
queue's own first member and the eight P-BK-43 names — so the chart's own TF is always a
candidate and the fallback is the last resort it was always meant to be. Nothing else moves:
every other caller hands a tfMin >= 1, where `tfMin < 5` still answers 5. `ladder()` derives
its floor from the code's own first branch, so a model that walks a ladder the code does not
have cannot happen again.

P-BK-47 (2026-09-15) — THE TYPE IS THE NODE'S LENGTH, and the break's story keeps only
its SIDE (see check 7). The user's rule, word for word: «دسته بندی گره های معاملاتی
براساس طول گره: FTR گرهی که طولش مساوی تایم تریگر تایمی باشد که گره در آن دیده میشود
سه کندل · ETR گرهی که طولش مساوی تایم پترن باشد · CTR گرهی که طولش مساوی تایم ساختار
باشد · OTR گرهی که طولش بیشتر از تایم ساختار باشد». It lands on machinery this repo
already had: P-BK-36's class IS the node's length in whole rungs (three candles of the
rung it reaches — the pattern time one step up, the structure time two steps up), so
the type became a COUNT OF RUNGS between the TF the node is SEEN ON (the box' commit
TF, a property of the box) and the class, and every closes-based branch of the retired
read was RETIRED IN PLACE (BKNODEKIND-OFF). The retired read's OWN facts survive where
they were always about something else — the break's story still names the trade's SIDE
(P-BK-46) — which is why this gate keeps the story model, the far-edge read and the
`BaseKnotNodeDir` order, and only the TYPE moved.

P-BK-38 (2026-09-15) — and the EVENTS of that story are the base's own TF's
candles. Fixing the level test (P-BK-35) still left the type able to move with the
chart: with THIS chart's closes the user's D1 box was "broke, returned, broke
again" on H1 - the level is crossed all day long - and "broke, returned, stayed"
on D1, and the 128-bar window was five days of story on H1 against six months on
D1 (measured on his own EURUSD60/EURUSD1440 history: ETR on D1, CTR on H1 for the
same box). So the read runs on the class's TF (published on the registry, so the
pump compares against the SAME story), the window is a count of THAT TF's bars,
and a rung whose series is not loaded falls back to the chart's own closes.

Checks, all on the source (+ one model), no terminal:

  1 OWNER    one definition of the count and one definition of the body
             criterion: no other module may walk the series for this number,
             and `BaseKnotBarCount` may not re-spell "inside the band" itself.
  2 ANCHOR   the walk starts at the SMALLER of the two edge shifts (the right
             edge; shift 0 is the live bar), the LEFT edge is never a bound - no
             `hi = (sh1 > sh2 ? ...)`, no `s <= hi`, that line is what came back
             as 43 - and the anchor is lifted off the FORMING candle (shift 0 ->
             1), so the count is closed-bar data (P-BK-34). The answer itself is
             the story's own span (P-BK-42: `sp.life = oldest - end`, the entry
             candle out and the exit candle in), and that END belongs to the RUN
             (P-BK-44: the first candle newer than the run's own head) - never to
             the box' rectangle, whichever side of it the edge falls on.
  3 BREAK/GAP the step over the break is bounded by BK_BASE_SKIP (P-BK-39: the
             walk's own cap, TF-fair - a box dragged over its own break still
             reads that base on ANY chart TF, a box ending further than a whole
             walk from any base reports "no base", 0, instead of latching onto a
             later return run) and every candle the anchor search EXAMINES counts
             against it (P-BK-43); a candidate anchors the walk only when its own
             run holds BK_BASE_MIN_BARS standing candles, so a stray body in a
             congested zone is stepped over and the base behind it is found
             instead of an invented «1 bars»; the run is walked on BOTH sides of
             the box' right edge - NEWER first (P-BK-44: the box' lines extend
             forward, so a box pulled back into the base still reads it whole)
             and then OLDER from its own head, with the same tolerance, the same
             confirmation and the same cap on each side; a lone out-of-band body
             is tolerated (the gap is counted) and the poke is inside the story, a cluster
             ends the run and a re-entry past a gap counts only at
             BK_BASE_MIN_BARS; and the walk carries NO band term of its own (no
             top/bot outside the shared criterion), so the tolerance can never
             become a function of the box - that is the line that came back as 43
             and then as 20.
  4 BUDGET   BK_BASE_MAX caps one walking run (the probe candles included) and
             BK_LIVE_COUNT_MS caps the live (mouse path) cadence, so a wide box
             cannot walk the series on every cursor frame.
  5 ONE SPAN  `BaseKnotSync` runs ONE walk into a `BaseKnotSpan` and hands that
             record to the box tooltip, the four edges, the note and the size class;
             the number, the class and the node's story all read ITS two ends
             (P-BK-41/42), the story's right side is published for the pump, and
             neither the tooltip builder nor the note writer counts for itself.
  6 MODEL    the walk modelled as a run of in/out flags reproduces the MQL4 loop
             and proves the promises the user made us write down: dragging the
             LEFT edge never moves the number, a box that ends inside the base
             is truncated at its own right edge, a break of <= SKIP candles is
             stepped over (P-BK-33's five included), a longer break has no base
             at that anchor, ONE poked-out body does not cut the base (and is not
             counted), two in a row do end it, and a stray in-band candle on the
             entry side cannot inflate the count, and P-BK-41/42's own cases:
             the box' edge ON the base (the entry still out), the box' edge ON the
             exit (counted), five / thirty / thirty-one break candles past the base
             (the SAME number every time),             the USER'S OWN M15 BOX (nine candles
             whose box reached ~29 past the exit: 38 under the retired P-BK-37
             reading, 9 now), the USER'S OWN D1 BOX (10, entry out / exit in), a box
             PULLED BACK into the base (P-BK-44: 8 under the retired edge-bound end,
             the whole 19 now), a CONGESTED box whose nearest body is a stray candle
             (P-BK-43: «1 bars» then, the base behind it now), a box whose walk holds
             no base at all (0), the cap, and - P-BK-40 - the same walk's OTHER
             answer, the stand-still count the class is read from.
  7 NODE     the four types ARE THE NODE'S LENGTH (P-BK-75) — the box' own HEIGHT
             (`top - bot`, in price units) against the MOVEMENT ABILITY of the TF
             the node is SEEN ON, and NOTHING else: the kind is ONE assignment off
             `BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor)` (so no branch
             and no restored read can rewrite it), that read touches four numbers and no
             series at all (no closes, no ATR call, no `Period()`), and every unknown
             (a zero/negative height, a TF whose ATR was never pushed) answers an
             ABSENCE instead of a band. «توان حرکتی» IS THAT TIMEFRAME'S ATR
             (2026-09-17: «به جای th از atr استفاده بشه») — the project's own
             composite ATR (`CalculateWeightedATR`) — and P-BK-78 makes the THREE
             abilities THREE TIMEFRAMES' ATRs: the NODE'S OWN TIME's (`trigger`), the
             PATTERN time's — ONE RUNG ABOVE it on the project's ladder (`pattern`) —
             and the STRUCTURE time's, TWO rungs above (`structure`). The old
             0.25/0.50/1.00 ratios are GONE: they could only ever express «a fraction
             of this TF's own ATR», never «belongs to a HIGHER time» — the user's own
             report («اندازه گره مال یک تایم بالاتر از تایم گره هستش پس etr باید
             باشه»). They are PUSHED IN per TF (the layer law: `THCalculations.mqh`
             sits ABOVE `BaseKnotTool.mqh`), the push stores ONE RAW ATR per TF and
             scales nothing (a ratio at the push site would be a second owner of the
             rule), and the Get resolves the LADDER itself, reusing the pump's own ask
             list so the ask and the answer cannot disagree about which TFs a box
             draws with.
             The four bands are the user's rule, made tolerant (P-BK-76): FTR up to
             the MIDPOINT of trigger|pattern, ETR up to the midpoint of
             pattern|structure, CTR up to the structure ability itself, OTR above
             it — so no box lands on a knife edge. The thresholds come from the
             NODE'S OWN TIME (`nodeTimeMin` — P-BK-77's answer), never from the open
             chart, so one box has ONE type on every chart TF. Sync classes the base
             BEFORE the length is measured, and the class IS the TF the length is
             measured on (P-BK-77): the box' OWN commit TF (`BaseKnotNodeTFMin`) no
             longer enters the read at all, because the user draws with the measuring
             tool and the box' TF never named the node's time. The pump asks the SAME
             question of the SAME story candle and the SAME TF, and BOTH answers are
             published and compared (the type, and the side the break's story names).
             The RETIRED reading (P-BK-47: the rung count above the node's TF) is
             kept in place behind `BKNODERUNG-OFF` and is asserted DEAD on
             `strip_comments()` text — a name test on raw source would pass on the
             retirement comment alone (P-BK-74).
             P-BK-38/81 ride here, as the SIDE: the story still runs on the
             CLASS' own candles (so one box has one side on every chart), the far
             edge is still read off top/bot (the node's LIFE STATE, P-BK-48), and
             `BaseKnotNodeDir` is ONE return off `nd.side` — with the P-BK-46
             branches retired in place, so no return, second break or far-edge close
             can rewrite which side the base left on.
             P-BK-81 (2026-09-17) — THE FOUR PATTERN NAMES ARE GONE AND THE
             DIRECTION IS ONE BIT. The user: «چرا جهت درست تشخیص نمیده rbr , dbd
             rbd … کلا از شر این rbr , dbd rbd خلاص بشیم و جهت سل و بای به صورت
             صدردصدی درست تشخیص داده بشه». The standard definitions make RBR and DBR
             BOTH Buy and RBD and DBD BOTH Sell — «the move OUT of the base decides
             the direction, because the move into it only shows past direction while
             the exit shows current intent» (alphaexcapital.com) — so the approach
             leg could only split continuation from reversal and the four names
             carried no directional information the exit leg did not already carry.
             `BK_PAT_*`, `BK_APPROACH_MAX`, the struct's `approach`/`pattern`, the
             approach walk, the two assignments, `BaseKnotPatternName/Tag/Line` and
             the registry's `baseT` are DELETED (the `BKPAT-OFF` markers are prose,
             like BKNODEKIND-OFF: there is no corpse to test on). The DIRECTION is
             `nd.side`, read off the base's OWN EXIT CANDLE: the story walk now
             STARTS at that candle — the one that CLOSED OUTSIDE the band, the very
             candle the note's number is counted to (`sp.tExit`, published as the
             registry's `exitT` so the pump reads the same candle) — instead of one
             bar after the box' right edge. That start is the whole fix for the
             user's two reports: the old start moved with the drawn rectangle (a nudge
             flipped the side), and on a chart coarser than the node's own time it sat
             a whole bar PAST the exit, so the first close it examined was a later
             candle — often a return — and named the opposite side. Above the ceiling
             -> +1 Buy, below the floor -> -1 Sell, inside -> 0 (the live price's
             turn). A later return, a revisit, a second break and a far-edge close are
             the node's LIFE and are REPORTED; none of them is a direction.
             The model then proves the promises on scenes: the six band answers,
             the four HEIGHT bands on a real ladder (a height on each side of each
             midpoint, a height equal to the structure ability, one above it, and
             the absence when that TF's ATR was never pushed), the story scenes'
             sides (the exit candle's, in BOTH directions, return or not), the step
             moving the numbers but never the side, the closes moving the side but
             never the type, and — the point of the length change — the RETIRED
             reading's own answer for the user's D1 box (ETR) against the length's
             (FTR: it is its own trigger).
  8 RUNG     THE NODE'S TIME IS CHART-INDEPENDENT (P-BK-77, 2026-09-17 — the user:
             «اولین چیزی که خیلی مهم تایم گره باید پیدا بکنیم ... صدردصد تایم گره درست
             تشخیص داده بشه که فرقی نکنه در چه تایم فریمی هستیم»). The class is
             CONFIRMED on the rung's OWN candles (P-BK-36), on the PROJECT'S WHOLE
             LADDER (P-BK-43: M1·M5·M15·H1·H4·D1·W1·MN1, no M30 — enumerated by
             `BaseKnotLadderAll`, the ONE owner, off `BaseKnotNextTFMin`), and the walk
             goes TOP-DOWN: the FIRST rung whose own candles stand still
             (`BaseKnotRungHoldCount >= BK_BASE_RUNG_MIN`) IS the node's time — the
             user's own definition of «تایم گره» («سه کندل درجا زدن»), and their own
             choice of the HIGHEST rung when several stand still. A rung whose series
             cannot be read is REMEMBERED (`unread`) and answers only when nothing
             stood still at all; and a band where nothing stood still falls back to the
             SPAN'S OWN RUNG (the largest rung a single candle of which still fits),
             never to the open chart's TF. The retired free confirmation —
             `if(tfMin == Period()) return BK_BASE_RUNG_MIN;`, which let THIS chart's
             own TF confirm itself without reading a single candle and so made the
             CHART decide the class — is GONE. The class' own texts
             (`BaseKnotBaseTag` / `BaseKnotBaseLine`) take NO TF at all, and the hover
             RE-READS the rung it named before it claims its candles.
             P-BK-80 (2026-09-17) — AND THE SPAN IS THE BOX' OWN. The user:
             «تایم گره توی یکساعته درست تشخیص داده ... ولی تایم بالا که میریم میزنه ftr
             کلا یک گره فقط یک تایم میتونه داشته باشه متعلق به یک تایم هستش». The span
             used to be `(s2 - s1)/60 + the chart's own candle width`, over the STORY
             span `sp.tStart..sp.tExit` — and that span is read off the CHART's candles
             (P-BK-41), so the SAME box measured 480..660 minutes on H1 and 480+240 ..
             660+240 on H4: the `+ chartMin` admitted a TALLER rung on the higher chart,
             and the taller rung's ATRs then typed a short box FTR. Now the span is
             `(b2 - b1)/60` over the BOX' OWN two anchors (`t1..t2`, the values stored
             on the chart OBJECT) with NO chart term and NO `chartMin` anywhere in the
             read, so the answer is bit-identical on every chart TF. The memo keys on
             `bars`, `b1`, `b2`, the band and a new closed bar — the chart's candle
             width is gone from the key too, because it is no longer an input. Every
             call site hands the box' own two anchors (`t1, t2`; the live preview its
             own `t1, te`).
  9 AS-OF    EVERY NUMBER THE KNOT DRAWS IS READ AT THE BOX' OWN BAR (P-BK-79,
             2026-09-17 — the user: «مثلا atr یک دقیقه زمان گره بوده مثلا 20 ... با
             گذشت زمان ممکن 40 بشه یا 10 بشه که اینطوری نمیشه نوع گره دقیق مشخص
             کرد»). Every number the knot drew was a LIVE read: the strip ATR took no
             shift, the plan's EngSL / HuntSL / TP1..3 were pushed PER TF and cached
             per TF, and the type compared the box' height against TODAY's ATR — so one
             box changed its type and its levels as the market's volatility moved, and
             TWO boxes on the same TF could never be told apart: the table had one row
             for the both of them. A ROW IS NOW `(TF, ANCHOR)`, where the anchor is the
             box' own `storyT` — the bar its story ended on, which is the same bar the
             type and the story are read from — and 0 means «no anchor»: the LIVE row,
             which is what the sizing preview asks for before it has a base. One table,
             one key, one owner per side (`BaseKnotEngNeeds` asks, `BaseKnotEngPush`
             answers, and a moved ANCHOR re-arms the pump's gate exactly like a moved
             EngSL). Every reader takes the anchor as a DEFAULTED LAST parameter, so a
             caller that never learned the word — the plan card, the live preview —
             stays byte-identical; the committed box reads `nd.anchor`, the preview
             reads 0, and a drag follows the SAME anchor the release Sync will land on.
             The ATR side is a SIBLING read (`CalculateWeightedATRAt`), never a shift on
             the live one: the live cache's ten rows must not be evicted by boxes, and
             the anchored read is keyed on the BAR'S OWN TIME (a shift-keyed cache
             would serve a stale answer). The model proves the ask list on the pair:
             two boxes on one TF with two story ends get TWO rows, two boxes that ended
             on the same bar SHARE one, a CTR/OTR box asks its measure rung at its own
             anchor, a box with neither class nor story stays on the live row, and the
             list is bounded like the table.

Run:  python tools/base-count-audit.py [--selftest]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KNOT = "Biotak/BaseKnotTool.mqh"

_PATCHED = {}
_CACHE = {}


# --- source access (patchable, so --selftest can doctor a file) --------------
def read(path):
    if path in _PATCHED:
        return _PATCHED[path]
    if path not in _CACHE:
        with open(ROOT / path, "r", encoding="utf-8", errors="replace") as fh:
            _CACHE[path] = fh.read()
    return _CACHE[path]


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def body(text, signature):
    """the `{ ... }` block of the function declared at `signature` (comment-free)."""
    src = strip_comments(text)
    i = src.find(signature)
    if i < 0:
        return None
    j = src.find("{", i)
    if j < 0:
        return None
    depth = 0
    for k in range(j, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[j:k + 1]
    return None


# --- 1..5: the source checks -------------------------------------------------
def check_owner():
    """one count owner, one body-criterion owner, no module-counting elsewhere."""
    knot = strip_comments(read(KNOT))
    out = []
    for name in ("BaseKnotBarCount", "BaseKnotBarBodyInside"):
        got = len(re.findall(r"^\s*(?:bool|int)\s+" + name + r"\s*\(", knot, flags=re.M))
        out.append(("one definition of %s (found %d)" % (name, got), got == 1))
    walk = body(read(KNOT), "int BaseKnotBarCount(")
    if walk is None:
        return out + [("BaseKnotBarCount is present", False)]
    out.append(("the walk reads no series itself (no iOpen/iClose re-spelling)",
                re.search(r"i(?:Open|Close)\s*\(", walk) is None))
    out.append(("the walk uses the shared body criterion",
                walk.count("BaseKnotBarBodyInside(") >= 2))
    others = []
    for path in sorted(ROOT.glob("Biotak/*.mqh")):
        rel = path.relative_to(ROOT).as_posix()
        if rel != KNOT and "BaseKnotBarCount" in strip_comments(read(rel)):
            others.append(Path(rel).name)
    out.append(("no other module counts the base (%s)" % (", ".join(others) or "none"),
                not others))
    return out


def check_anchor():
    """the walk is anchored on the RIGHT edge and the LEFT edge bounds nothing."""
    walk = body(read(KNOT), "int BaseKnotBarCount(")
    if walk is None:
        return [("BaseKnotBarCount is present", False)]
    out = []
    out.append(("the anchor is the smaller shift (the box' right edge)",
                re.search(r"int\s+\w+\s*=\s*\(\s*(\w+)\s*<\s*(\w+)\s*\?\s*\1\s*:\s*\2\s*\)",
                          walk) is not None))
    out.append(("the LEFT edge is not used as a bound (no max-shift)",
                re.search(r"\(\s*(\w+)\s*>\s*(\w+)\s*\?\s*\1\s*:\s*\2\s*\)", walk) is None))
    allowed = re.sub(r"[^\n]*iBarShift\([^;]*;", "", walk)                       # edge -> shift
    allowed = re.sub(r"[^\n]*sh1\s*<\s*0[^;]*;", "", allowed)                     # the shift guard
    allowed = re.sub(r"[^\n]*\bt1\s*<=\s*0[^;]*;", "", allowed)                   # the validity guard
    allowed = re.sub(r"[^\n]*int\s+\w+\s*=\s*\([^;]*\)\s*;", "", allowed)      # the anchor line
    left = re.findall(r"\b(?:t1|t2|sh1|sh2)\b", allowed)
    out.append(("the edges enter only through the validity guard and the anchor (%d left)"
                % len(left), not left))
    out.append(("no walking bound on the older shift", re.search(r"<=\s*hi\b|\bhi\s*=", walk) is None))
    # P-BK-34: a forming candle is not base data - the anchor is at least shift 1
    out.append(("the anchor is never the FORMING candle (shift 0 -> shift 1)",
                re.search(r"if\s*\(\s*s\s*==\s*0\s*\)\s*s\s*=\s*1\s*;", walk) is not None))
    # P-BK-41/42: the NUMBER is the base's own story — its oldest stand-still candle
    # (the ENTRY, not counted) to the candle that CLOSED OUTSIDE the band (the EXIT,
    # counted, «کندل خروج») — never the box' own reach.
    out.append(("the exit is the candle just past the RUN's own newest candle (P-BK-44)",
                re.search(r"int\s+end\s*=\s*\(\s*head\s*>\s*1\s*\?\s*head\s*-\s*1\s*:\s*head\s*\)",
                          walk) is not None))
    out.append(("the answer is the span between the entry and that exit (entry out, exit in)",
                re.search(r"sp\.life\s*=\s*oldest\s*-\s*end;", walk) is not None
                and re.search(r"return\s+sp\.life;", walk) is not None))
    out.append(("... and it is NEVER the box' own reach (P-BK-37's reading is gone)",
                re.search(r"return\s+oldest\s*-\s*edge\s*\+\s*1;", walk) is None
                and re.search(r"int\s+edge\s*=\s*s;", walk) is not None))
    out.append(("the base's own right side is the anchor (the exit is read off it)",
                re.search(r"anchor\s*=\s*head;", walk) is not None
                and walk.find("int anchor = 0;") > walk.find("if(s == 0) s = 1;")   # P-BK-43
                and walk.find("anchor = head;") > walk.find("int anchor = 0;")))
    out.append(("the in-band body count is not reported as the answer",
                re.search(r"return\s+n;", walk) is None))
    lifted = walk.find("if(s == 0) s = 1;")
    latched = walk.find("int edge = s;")
    out.append(("the edge is latched AFTER the forming candle is lifted off",
                lifted >= 0 and latched >= 0 and lifted < latched))
    return out


def check_break_and_budget():
    """the break is stepped over (bounded), a lone poke is tolerated, a cluster ends."""
    walk = body(read(KNOT), "int BaseKnotBarCount(")
    if walk is None:
        return [("BaseKnotBarCount is present", False)]
    src = strip_comments(read(KNOT))
    live = body(read(KNOT), "int BaseKnotLiveBarCount(") or ""
    out = []
    for macro in ("BK_BASE_SKIP", "BK_BASE_GAP", "BK_BASE_MIN_BARS",
                  "BK_BASE_MAX", "BK_LIVE_COUNT_MS"):
        out.append(("%s is a numeric budget" % macro,
                    re.search(r"#define\s+" + macro + r"\s+\d+", src) is not None))
    # P-BK-43: ONE budget for the whole anchor search (every candle examined counts),
    # and a candidate only becomes the anchor when it HOLDS A BASE.
    out.append(("the step over the break is bounded in the walk",
                re.search(r"s\s*-\s*edge\s*<\s*BK_BASE_SKIP", walk) is not None))
    out.append(("a candidate anchors the walk only when its run holds a base",
                re.search(r"if\(n\s*>=\s*BK_BASE_MIN_BARS\s*&&\s*oldest\s*>\s*0\)\s*break;",
                          walk) is not None))
    out.append(("a stray body is stepped over and the search looks behind it",
                re.search(r"\bs\s*=\s*t;", walk) is not None
                and re.search(r"!BaseKnotBarBodyInside\(s,\s*top,\s*bot\)\)\s*\{\s*s\+\+;\s*continue;\s*\}",
                              walk) is not None))
    out.append(("... on a cursor of its own, so the anchor search is never consumed",
                re.search(r"int\s+t\s*=\s*head;", walk) is not None
                and re.search(r"while\(t\s*<\s*total", walk) is not None))
    # P-BK-44: the box' lines extend FORWARD — the run is walked NEWER first, with the
    # SAME tolerance and the same cap, so a box pulled back into the base reads it whole
    # while a box dragged past its break is untouched (the next candle out already blocks
    # the extension).
    out.append(("the run is walked NEWER first too (the box' lines extend forward)",
                re.search(r"int\s+fup\s*=\s*s\s*-\s*1", walk) is not None
                and re.search(r"if\(fgap\s*>\s*BK_BASE_GAP\)\s*break;", walk) is not None
                and re.search(r"fn\s*\+\s*fprobe\s*<\s*BK_BASE_MAX", walk) is not None))
    out.append(("... with the SAME confirmation (a re-entry holds a base's own length)",
                re.search(r"if\(fprobe\s*>=\s*BK_BASE_MIN_BARS\)", walk) is not None))
    out.append(("the base's own right side is the RUN's head, not the box' edge",
                re.search(r"sp\.tLast\s*=\s*iTime\(_Symbol,\s*0,\s*head\)", walk) is not None))
    out.append(("the walking run is capped in the walk (probe included)",
                re.search(r"n\s*\+\s*probe\s*<\s*BK_BASE_MAX", walk) is not None))
    out.append(("the live count is rate-limited",
                "BK_LIVE_COUNT_MS" in live and "GetTickCount" in live))
    out.append(("a walk that holds no base at all returns 0 (never «1 bars»)",
                re.search(r"if\(anchor\s*<=\s*0\s*\|\|\s*oldest\s*<=\s*0\)\s*return\s+0;",
                          walk) is not None))
    # P-BK-32: the tolerance itself - a lone poke is stepped over, a cluster ends.
    out.append(("a lone out-of-band body is tolerated (gap counted, not a stop)",
                re.search(r"(?<![A-Za-z_])gap\s*\+\+", walk) is not None
                and re.search(r"(?<![A-Za-z_])gap\s*>\s*BK_BASE_GAP", walk) is not None))
    guarded = re.search(r"if\(gap\s*==\s*0\)[\s\S]{0,60}?n\+\+;", walk)
    out.append(("the tolerated body is NOT counted (n grows only when gap == 0)",
                guarded is not None
                and len(re.findall(r"(?<![A-Za-z_])n\+\+;", walk)) == 1))
    out.append(("a re-entry past the gap counts only at a base's own length",
                re.search(r"(?<![A-Za-z_])probe\s*>=\s*BK_BASE_MIN_BARS", walk) is not None
                and re.search(r"n\s*\+=\s*probe", walk) is not None))
    # THE ARCHITECTURE LAW of the tolerance: bar index, never price. Only way a
    # margin could be measured against the band is through top/bot, so the walk
    # may use them in the shared criterion and nowhere else.
    bare = re.sub(r"BaseKnotBarBodyInside\([^)]*\)", "", walk)   # the shared criterion
    bare = re.sub(r"[^\n]*top\s*<=\s*bot[^;]*;", "", bare)         # the validity guard
    out.append(("the tolerance is a count, not a margin (no band term in the walk)",
                re.search(r"\btop\b|\bbot\b", bare) is None))
    return out


def check_one_value():
    """one walk per Sync, the same number to the tooltip, the note and the class."""
    out = []
    sync = body(read(KNOT), "void BaseKnotSync(")
    live = body(read(KNOT), "void BaseKnotSyncLive(")
    if sync is None or live is None:
        return [("BaseKnotSync/BaseKnotSyncLive are present", False)]
    out.append(("Sync walks the base once (%d)" % sync.count("BaseKnotBarCount("),
                sync.count("BaseKnotBarCount(") == 1))
    out.append(("Sync hands that span to the box tooltip",
                re.search(r"BaseKnotBoxTooltip\([^;]*\bsp\b", sync) is not None))
    out.append(("Sync hands the same span to the note",
                re.search(r"BaseKnotWriteInfo\([^;]*\bsp\b", sync) is not None))
    out.append(("the live preview reads the shared live counter",
                live.count("BaseKnotLiveBarCount(") == 1 and "BaseKnotBarCount(" not in live))
    # P-BK-40: ONE walk, TWO answers — the life for the note, the stand-still count
    # for the class. They are different numbers and must never be swapped, and the
    # stand-still answer is an OUT-PARAMETER of the SAME walk (never a second count
    # grown by a caller).
    plain_all = strip_comments(read(KNOT))
    walkfn = body(read(KNOT), "int BaseKnotBarCount(") or ""
    walksig = ""
    if "int BaseKnotBarCount(" in plain_all:
        walksig = plain_all[plain_all.index("int BaseKnotBarCount("):]
        walksig = walksig[:walksig.index("{")] if "{" in walksig else walksig
    out.append(("the walk reports the candles that STOOD STILL as well (same walk, one span record)",
                re.search(r"BaseKnotSpan\s*&\s*sp", walksig) is not None
                and "sp.still  = n;" in walkfn))
    out.append(("the walk hands out its own two ends (entry + exit), not only a count",
                "sp.tStart = iTime" in walkfn and "sp.tExit  = iTime" in walkfn
                and "sp.tLast  = iTime" in walkfn))
    out.append(("the note's number is that span's own count",
                re.search(r"BaseKnotSpan sp;\s*\n\s*int bars = BaseKnotBarCount\(t1, t2, top, bot, sp\)", sync) is not None))
    out.append(("the CLASS is read from the candles that stood still",
                re.search(r"BaseKnotBaseTFMin\(still,", sync) is not None))
    # P-BK-41/42/80: ONE span — the number, the class, the node's read and the note's own
    # badge all read the SAME record, so no two of them can describe different objects.
    # P-BK-80: the CLASS is the one exception, and on purpose: its span is the BOX' own two
    # anchors, not the chart-read story span — feeding it `sp.tStart..sp.tExit` is exactly
    # what let one box answer H1 on an H1 chart and H4 on an H4 chart.
    out.append(("the class is read on the BOX' own two anchors, never the chart-read span",
                re.search(r"BaseKnotBaseTFMin\(still,\s*t1,\s*t2,\s*top,\s*bot\)",
                          sync) is not None
                # P-BK-77: and it is asked the box' OWN geometry ONLY — no TF argument,
                # because the box' commit TF no longer names the node's time.
                and "BaseKnotNodeTFMin" not in sync))
    out.append(("the node's story is read from the base's own right side",
                re.search(r"BaseKnotNodeRead\(\(sp\.tLast\s*>\s*0\s*\?\s*sp\.tLast\s*:\s*t2\),", sync) is not None))
    out.append(("the story's right side is published for the pump (one story, one candle)",
                "g_bkBoxes[k].storyT = sp.tLast;" in sync))
    for name, sig in (("the box tooltip", "string BaseKnotBoxTooltip("),
                      ("the note", "void BaseKnotWriteInfo(")):
        blk = body(read(KNOT), sig) or ""
        out.append(("%s spells the entry/exit rule out" % name,
                    "entry candle" in blk and "exit candle" in blk))
    for name, sig in (("BaseKnotBoxTooltip", "string BaseKnotBoxTooltip("),
                      ("BaseKnotWriteInfo", "void BaseKnotWriteInfo(")):
        blk = body(read(KNOT), sig) or ""
        out.append(("%s does not count for itself" % name,
                    "BaseKnotBarCount" not in blk and "iBarShift" not in blk))
    for name, sig in (("BaseKnotBaseTag", "string BaseKnotBaseTag("),
                      ("BaseKnotBaseLine", "string BaseKnotBaseLine(")):
        blk = body(read(KNOT), sig) or ""
        out.append(("%s is arithmetic on the same number" % name,
                    "bars" in blk and "iBarShift" not in blk and "BaseKnotBarCount" not in blk))
    return out


# --- 6: the walk as a model (mirrors the MQL4 loop line for line) ------------
# P-BK-33: the model takes the walk's BUDGETS FROM THE SOURCE (never its own
# copy), so it cannot drift from the code - lowering `#define BK_BASE_SKIP` below
# the break a box covers fails the model cases below instead of passing silently.
_BUDGETS = {}


def budgets():
    src = read(KNOT)
    if _BUDGETS.get("src") is src:          # same source object -> same numbers
        return _BUDGETS["v"]
    plain = strip_comments(src)

    def num(name, default):
        m = re.search(r"#define\s+" + name + r"\s+(\d+)", plain)
        return int(m.group(1)) if m else default

    _BUDGETS["src"] = src
    _BUDGETS["v"] = {"skip": num("BK_BASE_SKIP", 30), "gap": num("BK_BASE_GAP", 1),
                     "min_bars": num("BK_BASE_MIN_BARS", 3), "cap": num("BK_BASE_MAX", 300)}
    return _BUDGETS["v"]


def walk_span(flags, right):
    """`flags[i]` = the i-th bar's body is inside the band; OLDER bars = larger i.

    Mirrors BaseKnotBarCount (P-BK-31's anchored run + P-BK-32's tolerance + P-BK-37's
    start + P-BK-41/42's two ends): anchor on `right` (the box' right edge), step over
    <= skip out-of-band bars (the box may be dragged forward over its own break), then
    walk OLDER to find where the base STARTED - a lone out-of-band body (<= gap in a
    row) is stepped over, a cluster ends the run, and the candles found past a
    tolerated gap join the base only once min_bars of them in a row hold the band. The
    walk (the probe included) is capped at cap. All the numbers come from the SOURCE.

    Returns `(life, still, oldest, head)`: the last two are the run's OWN two ends, and
    P-BK-45's edge window is built from them — so the live preview proves a repeat read is
    the SAME read instead of trusting a tolerance:

    * `life` is the note's number (P-BK-42): the candles between the ENTRY (the base's
      oldest in-band candle - NOT counted) and the EXIT (the candle that closed outside
      the band - counted, it is «کندل خروج»), where the exit is the first candle the
      anchor search examined just past the anchor. A box whose right edge sits ON the
      base has no exit inside it, so the edge itself ends the span. P-BK-37's «to the
      box' right edge» counted the dead zone a dragged box covers - the 38 for a
      9-candle base - and is gone.
    * `still` is how many candles STOOD STILL (P-BK-40), the base's own length the size
      class is read from - the entry candle included, because it is the base's length,
      not the note's span.
    """
    b = budgets()
    total = len(flags)
    if right < 0 or right >= total:
        return 0, 0
    # P-BK-43: the anchor search asks the SAME question of every candidate it meets -
    # "does a base start here?" - and only a candle whose run holds a base's own length
    # becomes the anchor; a stray body is stepped over and the search looks behind it,
    # all inside the SAME budget (BK_BASE_SKIP candles from the box' right edge).
    edge = right
    s = right
    anchor, head, n, gap, probe, oldest = 0, 0, 0, 0, 0, -1
    while s < total and s - edge < b["skip"]:
        if not flags[s]:
            s += 1
            continue
        # P-BK-44: the run is walked NEWER first (the exit side), with the same
        # tolerance, so a box whose right edge sits inside the base still finds the
        # base's own newest candle - and its exit - past that edge.
        head = s
        fup, fgap, fprobe, fn = s - 1, 0, 0, 0
        while fup >= 1 and fn + fprobe < b["cap"]:
            if flags[fup]:
                if fgap == 0:
                    fn += 1
                    head = fup
                else:
                    fprobe += 1
                    if fprobe >= b["min_bars"]:
                        fn += fprobe
                        fprobe, fgap = 0, 0
                        head = fup
            else:
                fgap += 1
                if fgap > b["gap"]:
                    break
            fup -= 1
        anchor = head
        n = gap = probe = 0
        oldest = -1
        t = head
        while t < total and n + probe < b["cap"]:
            if flags[t]:
                if gap == 0:
                    n += 1
                    oldest = t
                else:
                    probe += 1
                    if probe >= b["min_bars"]:
                        n += probe
                        oldest = t
                        probe, gap = 0, 0
            else:
                gap += 1
                if gap > b["gap"]:
                    break
            t += 1
        if n >= b["min_bars"] and oldest >= 0:
            break
        s = t
        anchor = 0
    if anchor <= 0 or oldest < 0:
        return 0, 0, -1, -1
    end = head - 1 if head > 1 else head
    return oldest - end, n, oldest, head


def walk_parts(flags, right):
    """The same walk, the two numbers its callers already asked for (P-BK-40/42)."""
    life, still, _oldest, _head = walk_span(flags, right)
    return life, still


def live_window(flags, right):
    """P-BK-45: the EDGE window a found run keeps its answer over, `(lo, oldest)` in shifts.

    Mirrors `BaseKnotLiveBarCount`. The walk's own law says the answer belongs to the BAND
    and the run that band holds — the box' right edge only says where to start looking —
    so while the edge slides over the run the reading cannot change. The window is not a
    tolerance, it is exactly:

    * the run's own OLDEST candle (`oldest`) as the far end — an edge farther back than
      the run's first candle anchors something else;
    * the first in-band candle NEWER than the run's own right side, plus one, as the near
      end — a walk started THERE anchors that candle and finds ITS run instead;
    * and never farther from the run's right side than the anchor budget (`skip`), because
      past it a walk started at the edge finds no base at all.

    `None` when the walk found no base: nothing is reusable.
    """
    b = budgets()
    life, still, oldest, head = walk_span(flags, right)
    if life <= 0 or oldest < 0 or head < 0:
        return None
    lo = max(0, head - b["skip"] + 1)
    e = head - 1
    while e >= lo:
        if flags[e]:
            lo = e + 1
            break
        e -= 1
    return (lo, oldest)


def walk_v43(flags, right):
    """The RETIRED P-BK-41/42 reading: the story's END was read off the BOX, so a box
    pulled back into the base lost the candles that were still holding the band to the
    right of its edge («این چرا عقب میارمش فرق میکنه اعداد … اون نباید 20 باشه»)."""
    b = budgets()
    total = len(flags)
    if right < 0 or right >= total:
        return 0
    s, skip = right, 0
    while s < total and skip < b["skip"] and not flags[s]:
        s += 1
        skip += 1
    if s >= total or not flags[s]:
        return 0
    anchor = s
    n, gap, probe, oldest = 0, 0, 0, -1
    while s < total and n + probe < b["cap"]:
        if flags[s]:
            if gap == 0:
                n += 1
                oldest = s
            else:
                probe += 1
                if probe >= b["min_bars"]:
                    n += probe
                    oldest = s
                    probe, gap = 0, 0
        else:
            gap += 1
            if gap > b["gap"]:
                break
        s += 1
    if oldest < 0:
        return 0
    end = anchor - 1 if anchor > right else right
    return oldest - end


def walk_v41(flags, right):
    """The RETIRED P-BK-41 anchor rule: the FIRST in-band body the search met anchored
    the answer, base or not - so one stray candle in a congested box printed «1 bars".
    Kept as the model's teeth for «اینجا های که شلوغ میشه»."""
    b = budgets()
    total = len(flags)
    if right < 0 or right >= total:
        return 0
    s, skip = right, 0
    while s < total and skip < b["skip"] and not flags[s]:
        s += 1
        skip += 1
    if s >= total or not flags[s]:
        return 0
    anchor = s
    n, gap, probe, oldest = 0, 0, 0, -1
    while s < total and n + probe < b["cap"]:
        if flags[s]:
            if gap == 0:
                n += 1
                oldest = s
            else:
                probe += 1
                if probe >= b["min_bars"]:
                    n += probe
                    oldest = s
                    probe, gap = 0, 0
        else:
            gap += 1
            if gap > b["gap"]:
                break
        s += 1
    if oldest < 0:
        return 0
    end = anchor - 1 if anchor > right else right
    return oldest - end


def walk(flags, right):
    """The note's number: the base's own story (P-BK-42)."""
    return walk_parts(flags, right)[0]


def walk_still(flags, right):
    """The SAME walk reporting the candles that STOOD STILL (P-BK-40): the class's
    input, the base's own length - a poke inside the story is not one of them."""
    return walk_parts(flags, right)[1]


def walk_v37(flags, right):
    """The RETIRED P-BK-37 reading: the span ran to the BOX' right edge, so a box
    dragged past its own break counted every candle it covered. Kept as the model's
    teeth for the user's «38 bars for a 9-candle base»."""
    b = budgets()
    total = len(flags)
    if right < 0 or right >= total:
        return 0
    s, skip = right, 0
    while s < total and skip < b["skip"] and not flags[s]:
        s += 1
        skip += 1
    if s >= total or not flags[s]:
        return 0
    n, gap, probe, oldest = 0, 0, 0, -1
    while s < total and n + probe < b["cap"]:
        if flags[s]:
            if gap == 0:
                n += 1
                oldest = s
            else:
                probe += 1
                if probe >= b["min_bars"]:
                    n += probe
                    oldest = s
                    probe, gap = 0, 0
        else:
            gap += 1
            if gap > b["gap"]:
                break
        s += 1
    return 0 if oldest < 0 else oldest - right + 1


def walk_v31(flags, right):
    """The RETIRED P-BK-31 rule: the run stops at the FIRST body outside the band.

    Kept as the model's own teeth - cutting the base on one poke is exactly what
    the user complained about.
    """
    b = budgets()
    total = len(flags)
    if right < 0 or right >= total:
        return 0
    s, skip = right, 0
    while s < total and skip < b["skip"] and not flags[s]:
        s += 1
        skip += 1
    if s >= total or not flags[s]:
        return 0
    n = 0
    while s < total and n < b["cap"] and flags[s]:
        n += 1
        s += 1
    return n


def walk_gap_only(flags, right):
    """The tolerance WITHOUT the re-entry confirmation (the cheaper variant of
    option A): here to prove the confirmation earns its keep on the entry side."""
    b = budgets()
    total = len(flags)
    if right < 0 or right >= total:
        return 0
    s, skip = right, 0
    while s < total and skip < b["skip"] and not flags[s]:
        s += 1
        skip += 1
    if s >= total or not flags[s]:
        return 0
    n, gap = 0, 0
    while s < total and n < b["cap"]:
        if flags[s]:
            n += 1
            gap = 0
        else:
            gap += 1
            if gap > b["gap"]:
                break
        s += 1
    return n


def model_scenes():
    """The synthesized series the promises are checked on (shared with the selftest)."""
    base = [False] * 70
    for i in range(40, 59):          # bars 40..58 = a 19-candle base; 40 is its newest bar
        base[i] = True
    scattered = base[:]
    scattered[36] = True             # a lone in-band candle NEWER than the box' right edge
    scattered[62] = True             # a lone in-band candle OLDER than the base
    poked = base[:]
    poked[50] = False                # ONE body poked out INSIDE the base
    clustered = base[:]
    clustered[50] = False            # TWO in a row outside: a move, not a poke
    clustered[51] = False
    # 59 is the ENTRY candle (the first out-of-band body the walk meets going
    # older); 60+ is what lies beyond it - the side the confirmation protects.
    entry = base[:]
    entry[60] = True                 # ONE stray in-band candle beyond the entry candle
    two = base[:]
    two[60] = True                   # TWO in a row: still under a base's length
    two[61] = True
    older = base[:]                  # THREE in a row (a base of its own) beyond them
    older[60] = True
    older[61] = True
    older[62] = True
    # P-BK-39: a base 330 candles past the anchor - farther than one whole walk
    deep = [False] * 400
    for i in range(340, 359):
        deep[i] = True
    # P-BK-40: THE USER'S OWN D1 BOX, bar for bar: the anchor is Aug 21, the three
    # breakout bodies (Aug 21/20/19) sit between it and the base, the base is the ten
    # stand-still bodies Aug 18..5, and Aug 4/3 pierce the floor and end the run.
    # P-BK-42: the ENTRY (Aug 5) is not counted and the EXIT (Aug 19) is, so the note
    # now reads 10 - the same number as the base's own length on this box.
    d1 = [False, False, False] + [True] * 10 + [False, False]
    # P-BK-41/42: THE USER'S OWN M15 BOX - a nine-candle base whose box was dragged
    # over its own break AND ~29 candles of dead zone. Shifts: 30..38 are the base's
    # nine candles (38 = the ENTRY), 29 is the candle that closed outside (the EXIT,
    # counted) and 0..28 are the dead zone the box still covers. P-BK-37 answered 38
    # (the box' whole reach); the base's own story is 9.
    zone = [False] * 60
    for i in range(30, 39):
        zone[i] = True
    # P-BK-43: A CONGESTED BOX - the user's «1 bars · struct». Shifts: 0..9 = the dead
    # zone the box covers, 10 = a STRAY body that happens to hold the band, 11..14 = the
    # cluster that cuts it, and 15..23 = the real nine-candle base behind it.
    crowd = [False] * 60
    crowd[10] = True
    for i in range(15, 24):
        crowd[i] = True
    # ... and a box whose whole walk holds no base at all: one stray candle, nothing else.
    nobase = [False] * 60
    nobase[10] = True
    # P-BK-45: TWO BASES IN ONE WALK — the newer one (4..8) lies behind an out-of-band
    # stretch, so an edge that slides onto it anchors ITS run (5 bars, its own exit), not
    # the older base's (9). This is the geometry the live preview's edge window has to
    # stop at: reusing across it would hand the note a base from a different place.
    nested = [False] * 60
    for i in range(4, 9):
        nested[i] = True
    for i in range(15, 24):
        nested[i] = True
    return {"base": base, "scattered": scattered, "poked": poked,
            "clustered": clustered, "entry": entry, "two": two, "older": older,
            "deep": deep, "d1": d1, "zone": zone, "crowd": crowd, "nobase": nobase,
            "nested": nested}


def model_cases():
    """(name, expected, flags, right) — the promises the rule has to keep.

    P-BK-42: the number is the base's OWN STORY — the candles between the entry (not
    counted) and the exit (counted). Dragging the box further past the exit is free, so
    every drag case below reads the SAME number.
    """
    s = model_scenes()
    cap = budgets()["cap"]
    return [
        ("the box ends ON the base's last candle: the exit next door is counted (19)",
         19, s["base"], 40),
        ("the box' edge IS the exit candle: it is counted (19)", 19, s["base"], 39),
        ("3 break candles past the base read 19 - the drag adds nothing",
         19, s["base"], 37),
        ("4 break candles past the base read 19", 19, s["base"], 36),
        ("5 break candles past the base read 19 (the user's own box)", 19, s["base"], 35),
        ("30 candles past the base read 19 (P-BK-41: the dead zone is not the base)",
         19, s["base"], 10),
        ("31 candles past the base read 19 (the anchor budget is the walk's cap)",
         19, s["base"], 9),
        ("the user's own M15 box: nine candles read 9, not the 38 of its reach",
         9, s["zone"], 1),
        ("... and the same box dragged further still reads 9", 9, s["zone"], 0),
        ("a STRAY body in a congested box does not anchor it: the base behind reads 9",
         9, s["crowd"], 0),
        ("a box whose walk holds no base at all reads none (never «1 bars»)",
         0, s["nobase"], 0),
        ("a base farther than one whole walk is not this anchor's base", 0, s["deep"], 10),
        ("the user's own D1 box reads 10 bars (entry out, exit in)", 10, s["d1"], 0),
        ("a box PULLED BACK into the base reads the WHOLE base (the user's 20 vs 36)",
         19, s["base"], 45),
        ("... and pulled back further still reads the whole base (19)",
         19, s["base"], 56),
        ("a scattered candle NEWER than the box' edge changes nothing",
         19, s["scattered"], 39),
        ("a scattered candle older than the base changes nothing", 19, s["scattered"], 40),
        ("ONE poked-out body does not cut the base - and it is inside the story",
         19, s["poked"], 40),
        ("TWO out-of-band bodies in a row end the base", 10, s["clustered"], 40),
        ("a stray in-band candle beyond the base's oldest candle changes nothing",
         19, s["entry"], 40),
        ("two in-band candles past the gap are still not a base", 19, s["two"], 40),
        ("three in a row past the gap are the same band (the gap candle is inside too)",
         23, s["older"], 40),
        ("the cap holds on a runaway band", cap - 1, [True] * (cap + 50), 1),
    ]


def check_model():
    out = []
    for name, want, flags, right in model_cases():
        got = walk(flags, right)
        out.append(("%s (%d)" % (name, got), got == want))
    # P-BK-40: the SAME walk answers the other question too, and the two must not be
    # each other: life vs stand-still.
    s = model_scenes()
    for name, want, flags, right in (
            ("the base's own length is its stand-still run", 19, s["base"], 40),
            ("the user's D1 box: its ten candles all stood still", 10, s["d1"], 0),
            ("a poke is inside the story but not a stand-still candle (18 of 19)",
             18, s["poked"], 40),
            ("a cluster ends the stand-still run too", 10, s["clustered"], 40),
            ("a confirmed re-entry joins the stand-still run (22 of 23)", 22, s["older"], 40),
            ("the user's M15 box stands still for its whole nine (9 of 9)", 9, s["zone"], 1),
            ("a STRAY body is not a base candle - the nine behind it are (9)", 9, s["crowd"], 0)):
        got = walk_still(flags, right)
        out.append(("%s (%d)" % (name, got), got == want))
    return out


# --- invariance: the promise the user asked for, swept over every drag -------
def check_invariance():
    """no LEFT edge exists at all — prove it on every anchor of the walk's own shape."""
    base = [False] * 400
    for i in range(40, 59):
        base[i] = True
    wrong = []
    for right in range(0, 380):
        # dragging the LEFT edge = adding older in-band candles to the picture; the
        # walk cannot see them unless they are CONTIGUOUS with the run at `right`.
        a = walk(base, right)
        extended = base[:]
        for i in range(300, 400):
            extended[i] = True
        b = walk(extended, right)
        if b != a:
            wrong.append((right, a, b))
    # The anchors that legitimately change are (a) those whose own run reaches the cap,
    # and (b) P-BK-43's own rule: an anchor whose walk holds NO base at all (answer 0)
    # may find one further back once an older range exists — that is the search looking
    # BEHIND a stray body, which is exactly what it is for. An anchor that already
    # reads a base may never be renumbered by older candles: the left edge still
    # bounds nothing.
    cap = budgets()["cap"]
    reach = [r for r in wrong
             if r[1] != 0 and any(base[i] for i in range(r[0], min(len(base), r[0] + cap)))]
    return [("an older range inside the band never renumbers an anchor that reads a base "
             "(%d anchor(s) moved, %d with a base of their own)" % (len(wrong), len(reach)),
             not reach)]


# --- 7: the node type (P-BK-75/76) — the box' HEIGHT against its TF's ATR ---------
NODE_NONE, NODE_FTR, NODE_ETR, NODE_CTR, NODE_OTR = 0, 1, 2, 3, 4
NODE_NAME = {NODE_NONE: "none", NODE_FTR: "FTR", NODE_ETR: "ETR",
             NODE_CTR: "CTR", NODE_OTR: "OTR"}
# BKPAT-OFF (P-BK-81): the four pattern names' own constants lived here —
# `PAT_NONE, PAT_RBR, PAT_RBD, PAT_DBR, PAT_DBD` and `PAT_NAME`. They are gone with
# `BK_PAT_*`, the approach walk and `BaseKnotPatternName`; the direction is one bit now
# (`node_side_model`), and restoring the names means restoring that whole block AND the
# `check_node` gates named "the four names are GONE".


def ladder():
    """The PROJECT'S ladder, READ FROM THE SOURCE (`BaseKnotNextTFMin`, P-BK-43):
    M1 · M5 · M15 · H1 · H4 · D1 · W1 · MN1. A model carrying its own copy of the
    ladder could name a rung the code cannot (the M30 that came back once as
    «M30 base»), so it is derived here like every other budget.

    P-BK-82 (2026-09-17): AND THE FLOOR IS DERIVED TOO. This used to seed itself with a
    hard-coded `[1]` — the ladder the DOCS name — while `BaseKnotNextTFMin` answered 5 for
    a walk that starts at 0, so the model walked a ladder the code did not have and the
    missing M1 rung could not fail anything. The first branch's own answer IS the floor now,
    so a ladder that stops reaching M1 fails the floor gate in `check_rung` instead of
    quietly changing the answer."""
    blk = body(read(KNOT), "int BaseKnotNextTFMin(") or ""
    steps = [(int(m.group(1)), int(m.group(2)))
             for m in re.finditer(r"if\(tfMin\s*<\s*(\d+)\)\s*return\s+(\d+);", blk)]
    if not steps:
        return []
    out, cur = [steps[0][1]], steps[0][1]   # the FLOOR is the first branch's own answer
    for bound, nxt in steps:
        if cur < bound:
            out.append(nxt)
            cur = nxt
    return out


def ladder_next(tf, lad):
    """Mirrors BaseKnotNextTFMin's own shape: the first rung ABOVE this TF (0 = the top),
    so an exotic chart TF is stepped ONTO the ladder, never between two of its rungs."""
    for r in lad:
        if r > tf:
            return r
    return 0


# BKNODERUNG-OFF (P-BK-75, 2026-09-17): the TYPE no longer rides the ladder.
# The two mirrors below modelled the RETIRED read (the rung count above the node's TF
# and the four band defines it fell in). They are kept in place, not deleted, so the
# restore path is the module's own: uncomment, put the two calls back into
# BaseKnotNodeRead / the live read, and re-teach the gates in `check_node` that are
# named "RETIRED" — nothing else in this file reads them.
#
# def rung_band(name):
#     """One of P-BK-47's band defines, read FROM THE SOURCE (0/1/2 = the trigger, the
#     pattern and the structure time — the numbers the code actually compares against)."""
#     m = re.search(r"#define\s+" + name + r"\s+(\d+)", strip_comments(read(KNOT)))
#     return int(m.group(1)) if m else None
#
# def node_kind_model(rungs):
#     """Mirrors BaseKnotNodeKindOf: the bands the rung count falls in."""
#     f, p, c = (rung_band("BK_NODE_RUNG_FTR"), rung_band("BK_NODE_RUNG_ETR"),
#                rung_band("BK_NODE_RUNG_CTR"))
#     if rungs == f:
#         return NODE_FTR
#     if rungs == p:
#         return NODE_ETR
#     if rungs == c:
#         return NODE_CTR
#     if rungs > c:
#         return NODE_OTR
#     return NODE_NONE
#
# def node_rungs_model(node_tf, class_tf, lad=None):
#     """Mirrors BaseKnotNodeRungs: how many LADDER RUNGS the class sits ABOVE the TF the
#     node is seen on. -1 = nothing to class (no class, a structure of 1-2 candles, or a
#     class the ladder cannot name above that TF)."""
#     if lad is None:
#         lad = ladder()
#     if node_tf <= 0 or class_tf <= 0:
#         return -1
#     if class_tf == node_tf:
#         return 0
#     rung = node_tf
#     for i in range(8):                       # the ladder's own eight, bounded
#         rung = ladder_next(rung, lad)
#         if rung == 0:
#             return -1                        # the top of the ladder
#         if rung == class_tf:
#             return i + 1
#         if rung > class_tf:
#             return -1                        # a class the ladder cannot name
#     return -1


def node_kind_model(h, trig, pat, str_):
    """Mirrors BaseKnotNodeKindOfLength (P-BK-75/76): the bands the box' HEIGHT falls
    in, against the three MOVEMENT ABILITIES of the TF the node is SEEN ON. NO closes,
    NO step, NO chart TF and NO ATR enter this function — `h` against those three is
    the whole input, which is why nothing price did can move a type any more.

    The boundaries are the MIDPOINTS of adjacent abilities (P-BK-76: «زیاد خشک نباشه
    در مقایسات»), and OTR keeps the user's own ceiling — «بیشتر از توان حرکتی تایم
    ساختار». A missing ability (str_ <= 0, i.e. that TF's ATR was never pushed) is an
    ABSENCE, never a zero dressed as a threshold."""
    if h <= 0.0 or str_ <= 0.0:
        return NODE_NONE
    if h <= (trig + pat) * 0.5:
        return NODE_FTR
    if h <= (pat + str_) * 0.5:
        return NODE_ETR
    if h <= str_:
        return NODE_CTR
    return NODE_OTR


def node_story_model(closes, top, bot, step=0.0):
    """Mirrors the story walk in BaseKnotNodeRead (P-BK-29/35/81): the exit, the return,
    the far edge and the second break on the class's own candles. Its FIRST close IS the
    base's own exit candle (P-BK-81: the walk starts there, not at the drawn rectangle),
    so the side it names is that candle's answer and nothing else — never the type
    (P-BK-47).

    `step` is accepted and IGNORED on purpose: the story's SIDE is a fact about levels,
    and the step only SIZES the numbers beside it.
    """
    side, returned, rebreaks, crossed = 0, False, 0, False
    for c in closes:
        if side == 0:
            if c > top:
                side = 1
            elif c < bot:
                side = -1
            continue
        if side > 0:
            if c > top:
                if returned:
                    rebreaks += 1
            elif c < top:
                returned = True
                if c < bot:                      # out the FAR edge
                    crossed = True
        else:
            if c < bot:
                if returned:
                    rebreaks += 1
            elif c > bot:
                returned = True
                if c > top:
                    crossed = True
    return {"side": side, "returned": returned, "rebreaks": rebreaks, "crossed": crossed}


def node_side_model(story):
    """Mirrors BaseKnotNodeDir (P-BK-81): the base's OWN EXIT CANDLE decides the side and
    it is FIXED — a return into the base, a second break of the same edge and a close
    through the far edge all leave it alone (that is what makes a box on the PAST market
    read its own direction). +1 / -1 / 0, where 0 = the exit candle closed inside the
    band (nothing claimed): the live price's turn.

    `story["side"]` IS that candle's answer: P-BK-81 starts the walk AT the exit candle,
    so its first close is the one that names the side. The walk's other facts
    (`returned`, `rebreaks`, `crossed`) are the node's LIFE — reported, never a direction.
    """
    return story["side"]


# BKPAT-OFF (P-BK-81): `node_pattern_model(approach, side)` and `node_pattern_scenes()`
# lived here — the [APPROACH]-base-[DEPARTURE] model and the four scenes that pinned
# RBR/RBD/DBR/DBD. Restoring the names means restoring both, the `PAT_*` constants above
# and the `check_node_model` loop that walked the scenes.


def node_exit_start_model(s2, s_x):
    """Mirrors the START of the story walk in BaseKnotNodeRead (P-BK-81): the base's OWN
    exit candle whenever it is a CLOSED bar of the story TF, and the box' own right side
    (`s2 - 1`) ONLY as the fallback — a base that published no exit candle at all, or one
    whose exit candle is the forming bar.

    `s2` = the shift of the base's right side (`sp.tLast`), `s_x` = the shift the base's own
    exit candle (`sp.tExit`) maps to on the story TF (`-1` = none published).

    The three answers that matter: an exit on the SAME bar as the base's right side starts
    one bar EARLIER than the old read did (that bar's close IS the exit's close, and the
    old read stepped straight past it — which is how a coarse chart named a later candle,
    often a return, as the direction); an exit one bar past the base reproduces the old
    start exactly (so a fine chart's answer is unchanged); and no exit at all falls back to
    the box' own right side instead of inventing a candle.
    """
    start = s2 - 1
    if s_x >= 1:
        start = s_x
    return start


def node_exit_start_scenes():
    """(name, s2, s_x, expected start) — the start rule's three cases and its two
    fallbacks."""
    return [
        ("the exit candle IS a closed bar of the story TF -> the walk starts THERE", 6, 5, 5),
        ("... and an exit on the SAME bar as the base's right side starts one bar earlier "
         "(its close IS the exit's close — the coarse-chart case)", 6, 6, 6),
        ("... nor does an exit two bars earlier skip the story it must measure", 9, 7, 7),
        ("no exit candle published (a box whose story was never read) -> the box' own right side",
         6, -1, 5),
        ("an exit candle that is the FORMING bar is not a closed fact -> the box' own right side",
         6, 0, 5),
    ]


# The user's own D1 box (AMarkets-Demo EURUSD D1, 15 Sep 2026): band
# 1.1508..1.15791, and the closes AFTER the box' right edge, 20 Aug -> 15 Sep.
# The base (bodies inside the band, 5..18 Aug) is 10 candles and the box spans 13
# - P-BK-37's number - while the break story is ETR on the D1 chart and was OTR on
# an H1 chart, where the very same return is 3.8 H1 steps deep.
D1_TOP, D1_BOT = 1.15791, 1.15080
D1_CLOSES = [1.16771, 1.16757, 1.16629, 1.16732, 1.16494, 1.16511, 1.15812,
             1.16164, 1.15924, 1.15877, 1.16251, 1.16122, 1.16213, 1.16230,
             1.16324, 1.16111, 1.15966, 1.15476, 1.15336]
D1_STEP, H1_STEP = 0.0090, 0.0012   # ~90 and ~12 pips: the step each chart TF pushes in


def node_story_scenes():
    """(name, expected side, closes, top, bot) — what the DEPARTURE names. It is the
    first close outside the band, in BOTH directions, and NOTHING after it may move the
    side: return, second break and far-edge close are all answered the same (P-BK-49).
    This is the half of the pattern the past market reads, so the scenes are its proof."""
    top, bot = 1.1600, 1.1500
    return [
        ("a box nobody has left names no side (the live price's turn)",
         0, [1.1550, 1.1570], top, bot),
        ("an UP departure rides UP (+1)",
         1, [1.1650, 1.1700], top, bot),
        ("... and a return into the base does NOT flip it (+1, not the return's side)",
         1, [1.1650, 1.1550], top, bot),
        ("... nor does a second break of the same edge (+1)",
         1, [1.1650, 1.1550, 1.1620], top, bot),
        ("... nor a close clean through the FAR edge (+1)",
         1, [1.1650, 1.1490], top, bot),
        ("... nor a deep return in steps (the step never decides a side)",
         1, [1.1650, 1.1510], top, bot),
        ("a DOWN departure rides DOWN (-1)",
         -1, [1.1450, 1.1400], top, bot),
        ("... and a return into the base does NOT flip it (-1)",
         -1, [1.1450, 1.1550], top, bot),
        ("... nor a close clean through the far (top) edge (-1)",
         -1, [1.1450, 1.1620], top, bot),
        ("the user's own D1 box DEPARTED UP: the past market reads +1 (was -1)",
         1, D1_CLOSES, D1_TOP, D1_BOT),
        ("a swing that returns and re-breaks still rides the FIRST departure's side (+1)",
         1, [1.1650, 1.1550, 1.1620, 1.1555, 1.1630], top, bot),
    ]


def node_length_scenes():
    """(name, expected type, height, trigger, pattern, structure) — the TYPE, whose ONLY
    inputs are the height and the three abilities of the LADDER around the node's own
    time: the same list would answer the same types on any closes, any step and any
    chart TF.

    P-BK-78: the three abilities are THREE TIMEFRAMES' ATRs — the node's own time's
    (`trigger`), the PATTERN time's (one rung above it, `pattern`) and the STRUCTURE
    time's (two rungs above, `structure`). A natural ladder has a bigger ATR the higher
    you climb, so the scene's three are 25 / 50 / 100 pips (say the node's time, the
    rung above and the rung above that), and the two midpoints P-BK-76 moved the
    boundaries onto are 37.5 and 75. The ratios the OLD reading used (0.25 / 0.50 /
    1.00 of ONE TF's ATR) are gone: they could never express «the size belongs to a
    time ABOVE the node's time» — the user's own ETR report."""
    return [
        ("a box with no height claims nothing", NODE_NONE, 0.0, 25.0, 50.0, 100.0),
        ("a box as tall as the NODE'S OWN TIME's ATR -> FTR", NODE_FTR, 25.0, 25.0, 50.0, 100.0),
        ("... and one up to the trigger|pattern MIDPOINT is still FTR",
         NODE_FTR, 37.5, 25.0, 50.0, 100.0),
        ("a box past that midpoint -> ETR (its size belongs to a time ABOVE the node's)",
         NODE_ETR, 37.6, 25.0, 50.0, 100.0),
        ("a box as tall as the PATTERN time's ATR -> ETR", NODE_ETR, 50.0, 25.0, 50.0, 100.0),
        ("... and one up to the pattern|structure MIDPOINT is still ETR",
         NODE_ETR, 75.0, 25.0, 50.0, 100.0),
        ("a box past that midpoint -> CTR", NODE_CTR, 75.1, 25.0, 50.0, 100.0),
        ("a box as tall as the STRUCTURE time's ATR -> CTR", NODE_CTR, 100.0, 25.0, 50.0, 100.0),
        ("a box LONGER than the structure time's ATR -> OTR", NODE_OTR, 100.1, 25.0, 50.0, 100.0),
        ("... and stays OTR however much longer it is (4x)", NODE_OTR, 400.0, 25.0, 50.0, 100.0),
        ("a TF whose ATR was never pushed claims nothing (an absence, not a band)",
         NODE_NONE, 50.0, 0.0, 0.0, 0.0),
    ]


def node_kind_v29_retired(closes, top, bot):
    """The RETIRED P-BK-29/35 reading: these very closes NAMED the type
    (`!returned` -> FTR, the far edge -> OTR, a second break -> CTR, else ETR). Kept so the
    audit can prove the length rule answers DIFFERENTLY on the user's own box instead of
    saying so in prose — that box changed from ETR to FTR the day the length owned the type.
    """
    s = node_story_model(closes, top, bot)
    if s["side"] == 0:
        return NODE_NONE
    if not s["returned"]:
        return NODE_FTR
    if s["crossed"]:
        return NODE_OTR
    if s["rebreaks"] > 0:
        return NODE_CTR
    return NODE_ETR


def check_node():
    """P-BK-47/81 — the type is the node's LENGTH (the box' height against the ladder's
    ATRs); the base's OWN EXIT CANDLE names the trade's SIDE and nothing else, and the two
    can never change places."""
    src = read(KNOT)
    blk = body(src, "void BaseKnotNodeRead(")
    if blk is None:
        return [("BaseKnotNodeRead is present", False)]
    plain = strip_comments(src)
    out = []
    # --- the LENGTH half: the type comes from the rung count and from nothing else
    # P-BK-77/78: ONE TF, and it is the NODE'S OWN TIME the ladder search found — the box'
    # own commit TF (`baseTFMin`) no longer has a parameter here at all.
    # P-BK-81: and the datetime BEFORE the anchor is the base's OWN EXIT CANDLE (`tExit`),
    # never the base's entry (`tFrom`): the approach leg it anchored is gone.
    out.append(("the read takes the NODE'S OWN TIME as its only TF (P-BK-77/78)",
                re.search(r"void\s+BaseKnotNodeRead\s*\(\s*const\s+datetime\s+t2,\s*const\s+double\s+top,\s*"
                          r"const\s+double\s+bot,\s*const\s+int\s+nodeTimeMin,\s*const\s+datetime\s+tExit,",
                          plain) is not None
                and re.search(r"const\s+int\s+nodeTimeMin,\s*const\s+datetime\s+tFrom,", plain) is None
                and "nd.nodeTF = nodeTimeMin; nd.baseTF = nodeTimeMin;" in blk))
    kinds = [k.strip() for k in re.findall(r"nd\.kind\s*=\s*([^;]+);", blk)]
    out.append(("the type is ONE read off the box' HEIGHT (its reset, then the height - no branch)",
                kinds == ["BK_NODE_NONE",
                          "BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor)"]))
    out.append(("the retired level read cannot set the type again (BKNODEKIND-OFF)",
                re.search(r"nd\.kind\s*=\s*BK_NODE_(FTR|ETR|CTR|OTR);", blk) is None
                # ... and no branch of the retired read hangs a `nd.kind = ` off price action
                and re.search(r"if\([^\n]*nd\.(crossed|returned|rebreaks)[^\n]*\)[^\n]*nd\.kind\s*=", blk) is None
                and re.search(r"retStep\s*[<>]=?\s*[0-9]", blk) is None))
    out.append(("... and no ATR gate withholds it (the length needs no size at all)",
                re.search(r"s_bkStepATR\s*<=\s*0\s*\)\s*return", blk) is None))
    out.append(("the LENGTH is read BEFORE the story walk (it needs no series)",
                blk.find("nd.kind = BaseKnotNodeKindOfLength(") > 0
                and blk.find("nd.kind = BaseKnotNodeKindOfLength(") < blk.find("iClose(")))
    # P-BK-75/76: the rung count is RETIRED IN PLACE — tested on strip_comments(), because
    # the retirement comments spell the old definitions verbatim and a NAME test against
    # raw source would pass on the corpse (the "gate satisfied by code that no longer runs"
    # trap P-BK-74 paid for).
    out.append(("the rung count that used to name the type is RETIRED, not merely unused",
                "int BaseKnotNodeRungs(" not in plain and "int BaseKnotNodeKindOf(" not in plain
                and "BKNODERUNG-OFF" in src))
    hb = body(src, "int BaseKnotNodeKindOfLength(") or ""
    out.append(("the four names' sizes are spelled in ONE place — the HEIGHT against the abilities",
                hb != ""
                and all(("BK_NODE_" + x) in hb for x in ("FTR", "ETR", "CTR", "OTR"))
                and re.search(r"if\(h\s*<=\s*str\)\s*return\s+BK_NODE_CTR;", hb) is not None
                and re.search(r"return\s+BK_NODE_OTR;", hb) is not None))
    out.append(("... and the bands are the MIDPOINTS of the abilities, never hardcoded (P-BK-76)",
                re.search(r"if\(h\s*<=\s*\(trig\s*\+\s*pat\)\s*\*\s*0\.5\)\s*return\s+BK_NODE_FTR;",
                          hb) is not None
                and re.search(r"if\(h\s*<=\s*\(pat\s*\+\s*str\)\s*\*\s*0\.5\)\s*return\s+BK_NODE_ETR;",
                              hb) is not None
                and re.search(r"0\.375|0\.75", hb) is None))
    out.append(("... and the thresholds come from the NODE'S OWN TF, pushed in (never the chart's)",
                re.search(r"BaseKnotAbilityGet\(\s*nodeTFMin\s*,", hb) is not None
                and "Period()" not in hb))
    out.append(("... and a TF whose ATR was never pushed answers an ABSENCE, never a band",
                re.search(r"if\(h\s*<=\s*0\.0\)\s*return\s+BK_NODE_NONE;", hb) is not None))
    # P-BK-75/78 (2026-09-17, user: «به جای th از atr استفاده بشه» + «اندازه گره متعلق به
    # تایم بالاتر از تایم گره هستش پس باید ETR بشه»): THE ABILITY IS THAT TF'S OWN ATR, AND
    # THE THREE ABILITIES ARE THREE TFs' ATRs. The push stores ONE raw number per TF and
    # scales nothing (a ratio at the push site would be a second owner of the rule); the Get
    # resolves the LADDER — the node's own time, the pattern time one rung above, the
    # structure time two rungs above — and a cold ATR stays an ABSENCE, never a zero dressed
    # up as a threshold.
    ab = body(src, "void BaseKnotAbilityPush(") or ""
    abg = body(src, "bool BaseKnotAbilityGet(") or ""
    abr = body(src, "bool BaseKnotAbilityRow(") or ""
    out.append(("the push stores that TF's RAW ATR and scales NOTHING (one number, one owner)",
                re.search(r"double\s+v\s*=\s*\(atr\s*>\s*0\.0\)\s*\?\s*atr\s*:\s*0\.0;", ab) is not None
                and re.search(r"\*\s*0\.\d", ab) is None
                and re.search(r"BK_AB_(TRIG|PAT)_RATIO", plain) is None))
    out.append(("... and the three abilities are the LADDER's three ATRs (P-BK-78)",
                re.search(r"BaseKnotNextTFMin\(\s*tfMin\s*\)", abg) is not None
                and re.search(r"BaseKnotNextTFMin\(\s*up1\s*\)", abg) is not None
                and re.search(r"if\(up1\s*<=\s*0\s*\|\|\s*up2\s*<=\s*0\)\s*return\s+false;", abg) is not None
                and abg.count("BaseKnotAbilityRow(") == 3))
    out.append(("... and a cold ATR is stored AS an absence, never as a threshold of zero",
                re.search(r"return\s+\(atr\s*>\s*0\.0\);", abr) is not None
                and re.search(r"double\s+v\s*=\s*\(atr\s*>\s*0\.0\)\s*\?\s*atr\s*:\s*0\.0;", ab) is not None))
    # ... and the ASK side must carry the CLASS and the two rungs above it, or the ladder the
    # Get reads would have no rows and every box would answer BK_NODE_NONE for ever.
    needs = body(src, "int BaseKnotEngNeeds(") or ""
    out.append(("the ask list carries the class AND the two rungs above it (P-BK-78)",
                re.search(r"asked\[0\]\s*=\s*tf;", needs) is not None
                and re.search(r"asked\[1\]\s*=\s*BaseKnotNextTFMin\(\s*tf\s*\);", needs) is not None
                and re.search(r"asked\[2\]\s*=\s*\(asked\[1\]\s*>\s*0\s*\?\s*BaseKnotNextTFMin\(asked\[1\]\)\s*:\s*0\);",
                              needs) is not None
                and re.search(r"int\s+asked\[4\];", needs) is not None
                and "BaseKnotNodeTFMin(i)" not in needs))
    sync = body(src, "void BaseKnotSync(") or ""
    pump = body(src, "void BaseKnotSyncBadges(") or ""
    out.append(("Sync classes the base BEFORE the length is counted (one class, one type)",
                "BaseKnotBaseTFMin(" in sync and "BaseKnotNodeRead(" in sync
                and sync.find("BaseKnotBaseTFMin(") < sync.find("BaseKnotNodeRead(")
                and "baseTFMin = baseTF" in sync))
    # P-BK-77/78: THE NODE'S TIME IS THE CLASS, AND THE BOX' OWN COMMIT TF NO LONGER NAMES
    # IT. `BaseKnotNodeRead` takes ONE TF (P-BK-78), and the Sync hands it the class the
    # ladder search just found — a `Period()` or a box-TF read here would put the type back
    # on the chart the user happens to be looking at, which is the whole bug.
    out.append(("Sync counts the length on the CLASS the ladder search just found",
                re.search(r"BaseKnotNodeRead\([^;]*,\s*baseTF,\s*", sync) is not None
                and "BaseKnotNodeTFMin" not in plain))
    # P-BK-67: the class and the foot are asked INSIDE THE SAME CALL - the pump's own
    # settle heal (BaseKnotMarkSettled) legitimately reads the published class too, so a
    # bare "the pump mentions g_bkBoxes[i].baseTFMin somewhere" would pass for the wrong
    # reason (the mutant that zeroes the NODE READ's class went unseen exactly that way).
    out.append(("... and the pump asks the SAME question of the SAME story and the SAME TF",
                re.search(r"BaseKnotNodeRead\([^;]*g_bkBoxes\[i\]\.baseTFMin,\s*"
                          r"g_bkBoxes\[i\]\.exitT", pump) is not None
                and re.search(r"storyT\s*>\s*0\s*\?\s*g_bkBoxes\[i\]\.storyT\s*:\s*t2", pump) is not None))
    out.append(("Sync publishes BOTH answers and the pump compares both",
                "g_bkBoxes[k].nodeKind = nd.kind;" in sync
                and "g_bkBoxes[k].nodeSide = ndDir;" in sync
                and re.search(r"ndNow\.kind\s*!=\s*g_bkBoxes\[i\]\.nodeKind", pump) is not None
                and "BaseKnotNodeDir(ndNow) != g_bkBoxes[i].nodeSide" in pump))
    # --- the SIDE half: P-BK-81's rule — the base's OWN EXIT CANDLE, and it is FIXED
    dblk = body(src, "int BaseKnotNodeDir(") or ""
    out.append(("the SIDE is ONE return off the exit candle's own read (one bit, no branch)",
                re.search(r"return\s+nd\.side;", dblk) is not None
                and re.search(r"\bif\s*\(", dblk) is None
                and re.search(r"nd\.(crossed|returned|rebreaks|state)\b", dblk) is None))
    out.append(("... so nothing price did LATER can rewrite it (retired in place)",
                re.search(r"BKNODEDIR-OFF[^\n]*if\(nd\.(state|returned|rebreaks|crossed)", src)
                is not None))
    out.append(("the TYPE no longer answers the side (a length is not an edge)",
                "nd.kind" not in dblk))
    out.append(("the live-price follow leaves a NAMED SIDE alone (not a named type)",
                "if(g_bkBoxes[k].nodeSide != 0) return false;" in plain))
    # The enum crossing in front of `tfRead` is OPTIONAL, and three forms are
    # accepted because the tree has legitimately used all three:
    #     tfRead                    - MQL4, where the enum IS the minute count
    #     (ENUM_TIMEFRAMES)tfRead   - MQL5 before R-TF-UNIT
    #     CompatTF(tfRead)          - MQL5 after R-TF-UNIT, the sanctioned crossing
    # The history: MQL5 converts a CONSTANT int to an enum implicitly but NOT a
    # variable, so `iBarShift(_Symbol, 0, t, false)` compiles bare (20 sites pass
    # the literal 0) while a variable needs help. MQL5Compat.mqh covers
    # iClose/iOpen/iHigh/iLow/iTime with a casting macro but has none for
    # iBarShift, so the crossing belongs at the call site.
    #
    # What this check is really about is that the lookup uses `tfRead` - the
    # CLASS's own timeframe - and never the chart's, so the crossing is tolerated
    # rather than treated as a lost invariant.
    _TFREAD = r"(?:\(ENUM_TIMEFRAMES\)\s*tfRead|CompatTF\(\s*tfRead\s*\)|tfRead)"
    out.append(("the story still runs on the CLASS' own candles (one side, one box)",
                re.search(r"BaseKnotRungLoaded\(nodeTimeMin\)", blk) is not None
                and re.search(r"iBarShift\(_Symbol,\s*" + _TFREAD + r",\s*t2", blk) is not None
                and re.search(r"iClose\(_Symbol,\s*tfRead,\s*s\)", blk) is not None))
    out.append(("... and the far edge is still read off the box (the node's own life)",
                re.search(r"if\(c\s*<\s*bot\)\s*nd\.crossed\s*=\s*true;", blk) is not None
                and re.search(r"if\(c\s*>\s*top\)\s*nd\.crossed\s*=\s*true;", blk) is not None))
    # --- P-BK-81: THE WALK STARTS AT THE BASE'S OWN EXIT CANDLE, NEVER AT THE DRAWN BOX.
    # The user's two reports — «کمی که جابجا میکن نوع گره عوض میشه چرا» and «چرا جهت درست
    # تشخیص نمیده» — are both this start: it moved with the box, and on a chart coarser than
    # the node's own time it stepped PAST the exit candle.
    out.append(("the walk STARTS at the base's own exit candle, mapped onto the story TF",
                re.search(r"int\s+sX\s*=\s*iBarShift\(_Symbol,\s*" + _TFREAD + r",\s*tExit,\s*false\);",
                          blk) is not None
                and re.search(r"if\(sX\s*>=\s*1\)\s*start\s*=\s*sX;", blk) is not None))
    out.append(("... and the box' own right side is ONLY the fallback (no exit candle, or one "
                "that is the forming bar)",
                re.search(r"int\s+start\s*=\s*s2\s*-\s*1;", blk) is not None
                and re.search(r"if\(tExit\s*>\s*0\)", blk) is not None
                and re.search(r"for\(int\s+s\s*=\s*start;\s*s\s*>=\s*oldest;\s*s--\)", blk) is not None
                # ... and the loop no longer starts at the box: that IS the old read.
                and re.search(r"for\(int\s+s\s*=\s*s2\s*-\s*1;", blk) is None))
    out.append(("... and the walk refuses to read a bar that is not closed",
                re.search(r"if\(start\s*<\s*1\)\s*return;", blk) is not None))
    out.append(("the read takes the base's OWN EXIT CANDLE, and no base ENTRY at all",
                re.search(r"const\s+int\s+nodeTimeMin,\s*const\s+datetime\s+tExit,", plain) is not None
                and re.search(r"\btFrom\b", plain) is None))
    # --- the texts: the claim AND the numbers it was read from
    line = body(src, "string BaseKnotNodeLine(") or ""
    out.append(("the hover says the type IS the length", "the type is the HEIGHT" in line))
    out.append(("... and names the box' height beside the three abilities it was compared to",
                "pips (the box' height)" in line and "nd.height" in line
                and "trigger " in line and "pattern " in line and "structure " in line))
    out.append(("... and the bands it fell in, off the SAME midpoints the read uses (P-BK-76)",
                "bands:" in line and "BaseKnotNodeBandFtrEtr(nd.nodeTF, nd.anchor)" in line
                and "BaseKnotNodeBandEtrCtr(nd.nodeTF, nd.anchor)" in line))
    out.append(("... keeping the TF-invariance promise for the type",
                "the same on every chart TF" in line))
    out.append(("... while the story, its direction and its step ride their own lines",
                "story read on" in line and "trade:" in line))
    namefn = body(src, "string BaseKnotNodeName(") or ""
    out.append(("the classic pairs (the story's names) are no longer printed as the type",
                "ABO" not in namefn and "ABO" not in line))
    # --- P-BK-81: THE FOUR NAMES ARE GONE — the defines, the fields, the read, the texts.
    out.append(("the four names are GONE: no define, no struct field, no assignment",
                re.search(r"#define\s+BK_PAT_\w+", plain) is None
                and re.search(r"#define\s+BK_APPROACH_MAX\b", plain) is None
                and re.search(r"\bnd\.pattern\b", plain) is None
                and re.search(r"\bnd\.approach\b", plain) is None
                and re.search(r"\bBK_PAT_\w+", plain) is None
                and re.search(r"\bBK_APPROACH_MAX\b", plain) is None))
    out.append(("... their three functions are gone with them",
                re.search(r"string\s+BaseKnotPattern(Name|Tag|Line)\s*\(", plain) is None))
    out.append(("... and no text prints them any more (the names are on no object)",
                not re.search(r'"(RBR|RBD|DBR|DBD)"', plain)))
    out.append(("... the retirement is marked in place, not silently deleted",
                "BKPAT-OFF" in src))
    # ... and what replaced them: the direction's own sentence, off the ONE candle.
    out.append(("the direction gets its own sentence, off the exit candle",
                re.search(r"string\s+BaseKnotExitLine\s*\(\s*BaseKnotNode\s*&nd\s*\)", plain) is not None
                and "the base's own EXIT candle closed" in plain))
    wib = body(src, "void BaseKnotWriteInfo(") or ""
    out.append(("the hover spells the direction and the note carries it as BUY/SELL",
                "BaseKnotExitLine(nd)" in line
                and "BaseKnotPatternTag(nd)" not in wib
                and "the side the base was LEFT by" in line
                and "exit candle " in line))
    out.append(("Sync publishes the base's EXIT candle and reads the direction at it",
                "g_bkBoxes[k].exitT  = sp.tExit;" in sync
                and re.search(r"\bsp\.tExit,\s*g_bkBoxes\[k\]\.storyT,\s*nd\);", sync) is not None
                # ... and the base's ENTRY is gone with the approach leg it anchored. The
                # `\b` matters: `g_bkBoxes[k].baseTFMin` (the CLASS) is a different field and
                # a bare substring test would call it the retired one.
                and re.search(r"g_bkBoxes\[k\]\.baseT\b", sync) is None))
    out.append(("... and the pump re-reads the SAME direction, off the SAME exit candle",
                re.search(r"g_bkBoxes\[i\]\.exitT,\s*g_bkBoxes\[i\]\.storyT,\s*ndNow\)", pump)
                is not None
                # P-BK-79: and BOTH hand the read the box' own `storyT` as the anchor — the
                # very key the pump pushed its rows with, so the type the pump compares is
                # the type the Sync published and not a live row nobody draws with.
                and re.search(r"g_bkBoxes\[i\]\.baseT\b", pump) is None))
    out.append(("... and the registry carries the exit candle (published, not re-derived)",
                re.search(r"datetime\s+exitT;", plain) is not None
                and re.search(r"g_bkBoxes\[n\]\.exitT\s*=\s*0;", plain) is not None
                and re.search(r"datetime\s+baseT;", plain) is None))
    return out


def check_node_model():
    out = []
    for name, want, h, trig, pat, str_ in node_length_scenes():
        got = node_kind_model(h, trig, pat, str_)
        out.append(("%s (%s)" % (name, NODE_NAME[got]), got == want))
    lad = ladder()
    out.append(("the model still reads the PROJECT's ladder (M1·M5·M15·H1·H4·D1·W1·MN1, no M30)",
                lad == [1, 5, 15, 60, 240, 1440, 10080, 43200]))
    # P-BK-78: the three abilities are THREE RUNGS' OWN ATRs, so the SAME box height can
    # be two types on two ladders — the whole point of «توان حرکتی تایمی که گره در آن دیده
    # میشود» read one rung up: a 50-pip box is OTR on a foot-of-the-ladder node (the three
    # ATRs 6.25 / 12.5 / 25), ETR when the node's time, its rung above and the rung above
    # that are 25 / 50 / 100, and FTR two rungs higher (100 / 200 / 400). The retired
    # 0.25 / 0.50 / 1.00 ratios could not answer this at all.
    out.append(("the abilities are the THREE rungs' own ATRs (P-BK-78) — a 50-pip box is "
                "OTR where they are 6.25/12.5/25, ETR where they are 25/50/100, "
                "FTR where they are 100/200/400",
                node_kind_model(50.0, 6.25, 12.5, 25.0) == NODE_OTR
                and node_kind_model(50.0, 25.0, 50.0, 100.0) == NODE_ETR
                and node_kind_model(50.0, 100.0, 200.0, 400.0) == NODE_FTR))
    triples = [(25.0, 50.0, 100.0), (1.0, 2.0, 4.0), (100.0, 200.0, 400.0)]
    steps = [(0.0, 1.0), (1.0, 50.0), (50.0, 99.0), (99.0, 100.0), (100.0, 101.0), (101.0, 1e6)]
    monotone = all(node_kind_model(h2, t, p, s) >= node_kind_model(h1, t, p, s)
                   for (t, p, s) in triples for (h1, h2) in steps)
    out.append(("and the answer is MONOTONE in the height — a taller box never comes back a "
                "shorter type, on any ability triple", monotone))
    for name, want, closes, top, bot in node_story_scenes():
        got = node_side_model(node_story_model(closes, top, bot))
        out.append(("%s (%+d)" % (name, got), got == want))
    sides = {node_side_model(node_story_model(D1_CLOSES, D1_TOP, D1_BOT, s))
             for s in (0.00005, 0.0005, H1_STEP, D1_STEP, 1.0)}
    out.append(("the step never moves the SIDE (it only sizes its numbers) (%d answer(s))"
                % len(sides), len(sides) == 1))
    out.append(("and the closes never move the TYPE — one box answers ONE type across every "
                "story scene (%d answer(s))"
                % len({node_kind_model(top - bot, 25.0, 50.0, 100.0)
                       for _, _, _, top, bot in node_story_scenes()}),
                len({node_kind_model(top - bot, 25.0, 50.0, 100.0)
                     for _, _, _, top, bot in node_story_scenes()}) == 1))
    out.append(("the retired STORY reading named the user's own D1 box ETR — and the height rule "
                "reads NO story at all (its whole input is the height + the three abilities)",
                node_kind_v29_retired(D1_CLOSES, D1_TOP, D1_BOT) == NODE_ETR
                and node_kind_model.__code__.co_argcount == 4))
    out.append(("... while its SIDE is the exit candle's: the box' first close outside was ABOVE "
                "the band, so +1",
                node_side_model(node_story_model(D1_CLOSES, D1_TOP, D1_BOT)) == 1))
    # P-BK-81: THE WALK'S START IS THE BASE'S OWN EXIT CANDLE. These are the cases the user's
    # two reports were about — the old start moved with the drawn rectangle, and on a chart
    # coarser than the node's own time it stepped PAST the exit candle.
    for name, s2, s_x, want in node_exit_start_scenes():
        got = node_exit_start_model(s2, s_x)
        out.append(("%s (start %d)" % (name, got), got == want))
    starts = {node_exit_start_model(6, s_x) for s_x in (4, 5, 6)}
    out.append(("and the start is never LATER than the base's own right side — the walk can "
                "only move EARLIER, never past the exit (%d answer(s))" % len(starts),
                all(s <= 6 for s in starts)))
    return out


# --- 8: the size class (P-BK-36) — the rung's OWN candles decide ----------------
def rung_min():
    m = re.search(r"#define\s+BK_BASE_RUNG_MIN\s+(\d+)", strip_comments(read(KNOT)))
    return int(m.group(1)) if m else 3


def rung_model(ladder, holds, span_min, chart=None):
    """Mirrors BaseKnotBaseTFRead (P-BK-77). `ladder` is the PROJECT'S WHOLE ladder and
    `span_min` is the span in MINUTES; the walk goes TOP-DOWN, and the first rung whose own
    candles stand still (holds[i] >= rung_min()) IS the node's time — the user's own
    definition («تایم گره سه کندل درجا زدن»): the biggest time in which three candles are
    still visible. A rung whose three candles cannot fit the span (3 * rung > span_min) is
    not a candidate at all; a rung whose series cannot be read (holds[i] < 0) is REMEMBERED
    and only answers when no rung stood still; and the miss fallback is the LARGEST rung one
    candle of which fits the span — never the open chart's TF, which `chart` is here ONLY to
    disprove."""
    _ = chart   # never the answer — see the docstring
    unread = 0
    for i in range(len(ladder) - 1, -1, -1):
        if 3 * ladder[i] > span_min:
            continue
        if holds[i] < 0:
            if unread == 0:
                unread = ladder[i]
            continue
        if holds[i] >= rung_min():
            return ladder[i]
    if unread:
        return unread
    for i in range(len(ladder) - 1, -1, -1):
        if ladder[i] <= span_min:
            return ladder[i]
    return 0


def check_rung_model():
    # the THREE is hard-coded here on purpose: «سه کندل درجا زدن» is the promise, so
    # shrinking BK_BASE_RUNG_MIN has to fail these cases, not move them.
    # The ladder is the project's own eight (P-BK-43); `holds` is what each rung's OWN
    # candles answered: 3 = stood still (the read stops counting there), 0-2 = not enough,
    # -1 = the series cannot be read.
    ladder = [1, 5, 15, 60, 240, 1440, 10080, 43200]
    return [
        ("the HIGHEST rung whose own three candles stood still IS the node's time",
         rung_model(ladder, [3, 3, 3, 3, 0, 0, 0, 0], 200) == 60),
        ("a rung that does NOT stand still drops the answer to the rung below",
         rung_model(ladder, [3, 3, 3, 0, 0, 0, 0, 0], 200) == 15),
        ("only TWO of a rung's candles standing still is not a base (the user's own case)",
         rung_model(ladder, [3, 3, 2, 0, 0, 0, 0, 0], 200) == 5),
        ("the answer does NOT follow the open chart's TF (M15 on an H4 chart)",
         rung_model(ladder, [3, 3, 3, 0, 0, 0, 0, 0], 200, chart=240) == 15),
        ("... nor the box' TF: a node drawn on M1 whose three candles are H1 reads H1",
         rung_model(ladder, [3, 3, 3, 3, 0, 0, 0, 0], 200, chart=1) == 60),
        ("a rung whose three candles cannot fit the span is not a candidate at all",
         rung_model(ladder, [3, 3, 3, 3, 0, 0, 0, 0], 10) == 1),
        ("an unreadable rung series is remembered, NOT returned on the spot",
         rung_model(ladder, [0, 0, 3, -1, 0, 0, 0, 0], 200) == 15),
        ("... and it answers only when no rung stood still at all",
         rung_model(ladder, [0, 0, 0, -1, 0, 0, 0, 0], 200) == 60),
        ("nothing standing still at all: the span's own rung (a 40-minute band -> M15)",
         rung_model(ladder, [0, 0, 0, 0, 0, 0, 0, 0], 40) == 15),
        ("... and the same span answers the same rung on any chart",
         rung_model(ladder, [0, 0, 0, 0, 0, 0, 0, 0], 40, chart=1440) == 15),
    ]


def check_rung():
    """P-BK-36 — the class is confirmed on the rung's own candles, cheaply."""
    src = read(KNOT)
    plain = strip_comments(src)
    out = []
    out.append(("the class takes the BOX' OWN two anchors (P-BK-80: never a chart term)",
                re.search(r"int\s+BaseKnotBaseTFMin\s*\(\s*const\s+int\s+bars,\s*const\s+datetime\s+b1,\s*"
                          r"const\s+datetime\s+b2,\s*const\s+double\s+top,\s*const\s+double\s+bot\s*\)",
                          plain) is not None
                and re.search(r"BaseKnotBaseTFMin\s*\([^)]*baseMin", plain) is None))
    out.append(("... and EVERY call hands it the box' own two anchors, never the story span",
                re.search(r"BaseKnotBaseTFMin\([^)]*\bt1\b", plain) is not None
                and re.search(r"BaseKnotBaseTFMin\([^)]*sp\.t(Start|Exit)\b", plain) is None))
    out.append(("... and the read itself walks b1..b2",
                re.search(r"BaseKnotBaseTFRead\(bars,\s*b1,\s*b2,\s*top,\s*bot\)", plain) is not None
                and re.search(r"BaseKnotRungHoldCount\(rung,\s*b1,\s*b2,", plain) is not None))
    read_block = body(src, "int BaseKnotBaseTFRead(")
    hold = body(src, "int BaseKnotRungHoldCount(")
    if read_block is None or hold is None:
        return out + [("the rung confirmation is present", False)]
    # P-BK-43: the ladder is the PROJECT'S ladder, not the terminal's TF list: the same
    # eight the ATR warm-up queue walks and his own label row prints — no M30.
    atr = read("Biotak/ATRCalculations.mqh")
    q = re.search(r"g_atrWarmupQueue\[\]\s*=\s*\{([^}]*)\}", atr)
    queue = [int(x) for x in q.group(1).split(",")] if q else []
    nextblk = body(src, "int BaseKnotNextTFMin(") or ""
    rungs = [int(m.group(1)) for m in
             re.finditer(r"if\(tfMin\s*<\s*\d+\)\s*return\s+(\d+);", nextblk)]
    out.append(("the base's ladder IS the project's ladder (M1·M5·M15·H1·H4·D1·W1·MN1)",
                bool(queue) and rungs == queue))
    out.append(("... and M30 is not a rung of it (a 7-candle M15 box is not «M30 base»)",
                30 not in rungs))
    # P-BK-82 (2026-09-17, user: «چرا تایم گره رو درست و اصولی تشخیص نمیده، گره که مال یک
    # دقیقه هستش رو مال پانزده دقیقه نشون میده»): M1 IS THE LADDER'S FLOOR. The walk that
    # names the class starts at the HIGHEST rung and comes down, so a floor at M5 left a base
    # standing still on M1 with no rung able to name it: every rung was refused and the
    # "nothing stood still" fallback named the SPAN's own rung instead — the user's 17-minute
    # box around a 5-bar M1 base came out «M15 base». The gate is the code's own first branch,
    # and `ladder()` takes its floor from that same branch, so the model can never walk a
    # ladder the code does not have again.
    out.append(("M1 IS A RUNG — the class ladder's floor reaches the terminal's smallest TF",
                re.search(r"if\(tfMin\s*<\s*1\)\s*return\s+1;", nextblk) is not None
                and bool(rungs) and rungs[0] == 1
                and ladder()[:1] == [1]))
    # P-BK-77 (2026-09-17, user: «باید تایم گره صد در صد درست تشخیص داده بشه، مهم نیست روی چه
    # تایمی هستیم»): THE SEARCH IS THE WHOLE LADDER AND THE SPAN IS MINUTES. Everything below
    # is what makes the answer the SAME on every chart TF.
    ladder_fn = body(src, "int BaseKnotLadderAll(") or ""
    out.append(("the WHOLE ladder has ONE enumerator, off the ONE step owner",
                ladder_fn != "" and "BaseKnotNextTFMin(r)" in ladder_fn
                and re.search(r"for\(int\s+i\s*=\s*0;\s*i\s*<\s*9;\s*i\+\+\)", ladder_fn) is not None))
    out.append(("... and the search admits on MINUTES, not on chart candles (P-BK-77)",
                re.search(r"spanMin\s*=\s*\(int\)\(\(b2\s*>\s*b1\s*\?\s*\(b2\s*-\s*b1\)\s*/\s*60\s*:\s*0\)\);",
                          read_block) is not None
                and re.search(r"3\s*\*\s*rung\s*>\s*spanMin", read_block) is not None
                and re.search(r"3\s*\*\s*rung\s*/\s*chartMin", read_block) is None))
    # P-BK-80 (2026-09-17, user: «تایم بالا که میریم میزنه ftr ... کلا یک گره فقط یک تایم
    # میتونه داشته باشه متعلق به یک تایم هستش»): THE CHART CONTRIBUTES NOTHING TO THE SPAN.
    # The old span was `(s2 - s1)/60 + the chart's own candle width` over the CHART-read story
    # span, so one box measured 480..660 minutes on H1 and 720..900 on H4 — the `+ chartMin`
    # admitted a TALLER rung on the higher chart, and that rung's ATRs typed a short box FTR.
    out.append(("... with NO chart term in the span at all (P-BK-80: the `+ unit` is gone)",
                re.search(r"\+\s*unit", read_block) is None
                and re.search(r"\bchartMin\b", read_block) is None
                and re.search(r"int\s+spanMin\s*=\s*\(int\)\(\(b2\s*>\s*b1\s*\?\s*\(b2\s*-\s*b1\)\s*/\s*60\s*:\s*0\)\);",
                              read_block) is not None))
    out.append(("... and the read takes no chart TF and no chart candle width at all",
                re.search(r"int\s+BaseKnotBaseTFRead\s*\(\s*const\s+int\s+bars,\s*const\s+datetime\s+b1,\s*"
                          r"const\s+datetime\s+b2,\s*const\s+double\s+top,\s*const\s+double\s+bot\s*\)",
                          plain) is not None
                and re.search(r"\bchartMin\b", plain) is None))
    out.append(("... and a band nothing stood still in still falls back to the SPAN's own rung",
                re.search(r"return\s+rungs\[0\];", read_block) is not None))
    out.append(("... and it walks the ladder TOP-DOWN, so the FIRST rung that stands still wins",
                re.search(r"for\(int\s+i\s*=\s*n\s*-\s*1;\s*i\s*>=\s*0;\s*i--\)", read_block) is not None
                # ... and NEVER bottom-up: a walk that starts at the ladder's foot would let
                # the SMALLEST time win, which is the opposite of the user's own rule.
                and re.search(r"for\(int\s+i\s*=\s*0;\s*i\s*<\s*n;", read_block) is None))
    out.append(("a rung is named ONLY through the rung's own candles",
                re.search(r"held\s*>=\s*BK_BASE_RUNG_MIN\)\s*return\s+rung;", read_block) is not None))
    out.append(("an unreadable rung series is REMEMBERED, not returned on the spot",
                re.search(r"if\(held\s*<\s*0\)\s*\{\s*if\(unread\s*<=\s*0\)\s*unread\s*=\s*rung;\s*continue;\s*\}",
                          read_block) is not None
                and re.search(r"if\(unread\s*>\s*0\)\s*return\s+unread;", read_block) is not None))
    out.append(("... and the miss fallback is the SPAN's own rung, never the open chart's",
                re.search(r"if\(rungs\[i\]\s*<=\s*spanMin\)\s*return\s+rungs\[i\];", read_block) is not None
                and re.search(r"return\s+chartMin;", read_block) is None
                and re.search(r"return\s+from;", read_block) is None))
    # P-BK-77: THIS CHART'S OWN TF IS READ LIKE ANY OTHER RUNG. The shortcut that answered
    # BK_BASE_RUNG_MIN for `tfMin == Period()` without reading a candle made the CHART decide
    # the class — the exact bug the user reported.
    out.append(("this chart's own TF is read like any other rung (no free confirmation)",
                re.search(r"if\(tfMin\s*==\s*Period\(\)\)\s*return\s+BK_BASE_RUNG_MIN;", plain) is None
                and re.search(r"if\(!BaseKnotRungLoaded\(tfMin\)\)\s*return\s+-1;", hold) is not None))
    # P-BK-77: the box' own commit TF is NOT the node's time any more — the reader is gone.
    out.append(("the box' commit TF no longer names the node's time (the reader is gone)",
                "int BaseKnotNodeTFMin(" not in plain))
    out.append(("the class' texts take NO TF at all (the read owns the question)",
                re.search(r"string\s+BaseKnotBaseTag\([^)]*const\s+double\s+bot\s*\)", plain) is not None
                and re.search(r"string\s+BaseKnotBaseLine\([^)]*const\s+double\s+bot\s*\)", plain) is not None
                and re.search(r"baseMin", plain) is None))
    out.append(("the hover claims the rung's candles only after RE-READING that rung",
                re.search(r"if\(BaseKnotRungHoldCount\(tf,\s*b1,\s*b2,\s*top,\s*bot\)\s*<\s*BK_BASE_RUNG_MIN\)",
                          plain) is not None
                and "no rung of the ladder stood still" in plain))
    out.append(("the rung read uses the RUNG's own series",
                re.search(r"iOpen\(_Symbol,\s*tfMin,", hold) is not None
                and re.search(r"iClose\(_Symbol,\s*tfMin,", hold) is not None))
    out.append(("the rung read uses the SHARED body shape (no margin, no ATR)",
                re.search(r"o\s*>=\s*bot\s*&&\s*o\s*<=\s*top\s*&&\s*c\s*>=\s*bot\s*&&\s*c\s*<=\s*top",
                          hold) is not None
                and re.search(r"top\s*-\s*bot|\*\s*0\.", hold) is None))
    out.append(("the rung read is bounded (max rung candles per rung)",
                "BK_BASE_RUNG_MAX" in hold
                and re.search(r"older\s*-\s*newer\s*\+\s*1\s*>\s*BK_BASE_RUNG_MAX", hold) is not None))
    out.append(("... and stops on the first confirmations",
                re.search(r"if\(held\s*>=\s*BK_BASE_RUNG_MIN\)\s*return\s+held;", hold) is not None))
    out.append(("the rung budgets are numbers",
                re.search(r"#define\s+BK_BASE_RUNG_MIN\s+\d+", plain) is not None
                and re.search(r"#define\s+BK_BASE_RUNG_MAX\s+\d+", plain) is not None))
    out.append(("a rung stands still by a BASE'S OWN LENGTH (the same 3, one meaning)",
                rung_min() == budgets()["min_bars"]))
    memo = body(src, "int BaseKnotBaseTFMin(")
    out.append(("the class is memoised on the exact question (one read per Sync)",
                memo is not None and "s_bkRungAnswer" in memo and "s_bkRungBar" in memo
                and "s_bkRungBase" not in memo))
    # P-BK-80: the memo keys on the BOX' OWN two anchors, and the chart's candle width is
    # gone from the key — it is no longer an input, so it cannot be a key.
    out.append(("... and the key is the box' own two anchors, with NO chart term (P-BK-80)",
                memo is not None and "s_bkRungB1" in memo and "s_bkRungB2" in memo
                and "s_bkRungChart" not in memo and "Period()" not in memo))
    note = body(src, "void BaseKnotWriteInfo(") or ""
    out.append(("the note's class rides the BOX' own two anchors (P-BK-80)",
                re.search(r"BaseKnotBaseTag\(still,\s*t1,\s*t2,\s*top,\s*bot\)", note) is not None
                and re.search(r"BaseKnotBaseTag\(bars,", note) is None
                and re.search(r"BaseKnotBaseTag\(still,\s*sp\.", note) is None))
    hover = body(src, "string BaseKnotBaseLine(") or ""
    out.append(("the hover line claims the rung's own candles",
                "stood still in the band" in hover))
    return out


# --- report ------------------------------------------------------------------
def run_checks():
    rows = []
    for fn in (check_owner, check_anchor, check_break_and_budget, check_one_value,
               check_model, check_invariance, check_node, check_node_model,
               check_rung, check_rung_model, check_live_reuse, check_leg_fit,
               check_asof, check_label_short, check_note_fields, check_note_height,
               check_note_life, check_note_home):
        rows.extend(fn())
    return rows


# --- 9: P-BK-45 — the live preview, and the edges that cannot change it ----
def check_live_reuse():
    """while the user draws: the BAND decides the base, the edges are only pointers.

    Source rows: the reuse is keyed on the band (never on an edge), its window is built
    from the run's OWN two ends plus the first in-band candle newer than that run, it
    never reaches farther than the anchor budget, and a walk that found nothing leaves
    nothing to reuse. Model rows: the window is SOUND (every edge inside it reads the
    same base, the same stand-still count and the same two ends) and USEFUL (it covers
    the run's own span), and it stops where a newer base begins.
    """
    out = []
    live = body(read(KNOT), "int BaseKnotLiveBarCount(")
    if live is None:
        return [("the live counter is present", False)]
    out.append(("the reuse is keyed on the BAND and the newest closed candle, never on an edge",
                re.search(r"top == s_bkLiveTop && bot == s_bkLiveBot && lastClosed == s_bkLiveBar", live) is not None))
    out.append(("only an edge INSIDE the window may reuse",
                re.search(r"e >= s_bkLiveLo && e <= s_bkLiveHi", live) is not None))
    out.append(("a reuse returns the cached span - no second walk, one object",
                live.count("BaseKnotBarCount(") == 1 and "{ sp = s_sp; return s_n; }" in live))
    out.append(("the window's far end is the run's OWN oldest candle",
                "s_bkLiveHi = (old > 0 ? old : head);" in live))
    out.append(("its near end is the first in-band candle NEWER than the run's right side",
                "if(BaseKnotBarBodyInside(e, top, bot)) { lo = e + 1; break; }" in live))
    out.append(("... and never farther from that run than the anchor budget",
                "if(head > BK_BASE_SKIP) lo = head - BK_BASE_SKIP + 1;" in live))
    out.append(("the window rides the span the walk published, not the box' rectangle",
                "s_sp.tLast" in live and "s_sp.tStart" in live))
    out.append(("a walk that finds no base leaves nothing to reuse",
                "else { s_bkLiveLo = 0; s_bkLiveHi = -1; }" in live))
    #--- the model: soundness over every scene, and the boundary itself ----------
    sc = model_scenes()
    disagreed = 0
    windows = 0
    for name in ("base", "zone", "crowd", "nested", "poked", "older", "d1"):
        flags = sc[name]
        for ref in range(len(flags)):
            win = live_window(flags, ref)
            if win is None:
                continue
            windows += 1
            same = walk_span(flags, ref)
            for e in range(win[0], win[1] + 1):
                if walk_span(flags, e) != same:
                    disagreed += 1
    out.append(("every edge inside a window reads the SAME base (%d windows, %d disagreed)"
                % (windows, disagreed), windows > 0 and disagreed == 0))
    # the boundary: the newer base is where the window must stop, and one candle past it
    # really is a DIFFERENT reading (the fault a too-wide window would ship).
    nested = sc["nested"]
    win = live_window(nested, 15)
    inside = walk_span(nested, win[0])[0]
    outside = walk_span(nested, win[0] - 1)[0]
    out.append(("the window stops at the newer base and one candle past it reads another base (%d vs %d)"
                % (inside, outside), inside == 9 and outside == 5))
    out.append(("... so the window never covers the newer base's own candles (%d > %d)"
                % (win[0], walk_span(nested, 0)[3]), win[0] == 9))
    return out


# --- 10: P-BK-52 — the node's own power is the CEILING of both legs ----------
# The knot's two legs are the PLAN's (EngSL / HuntSL of the measure TF, P-BK-46/51) and the
# plan may publish a leg DEEPER than the node it is drawn in — the entry then landed past the
# box' opposite edge while the hover said «INSIDE the box' top edge», and a TF the pump had
# never pushed fell back to the box' WHOLE height (the stop a whole box behind the entry).
# The fix is a CEILING: the node's own power (its height over the plan's OWN divisor) bounds
# both legs, so `off + risk <= 5/8 H + 15/64 H = 55/64 H` and BOTH sit inside on every type.
# The divisor cannot be imported (layering law: the plan sits ABOVE this module), so this
# gate is what keeps the two IN SYNC — and it PROVES the bound from the source constants
# instead of trusting the comment.
PLAN = "Biotak/TradePlanFormulas.mqh"


def _defines(src):
    """`#define NAME value` as floats, for the constants the two files must agree on."""
    out = {}
    for m in re.finditer(r"^#define\s+([A-Za-z_]\w*)\s+([^\s/]+)", src, flags=re.M):
        try:
            out[m.group(1)] = float(m.group(2))
        except ValueError:
            pass
    return out


def check_leg_fit():
    """P-BK-52: one owner for the pair, one rule, one unit — and the box is never left."""
    src = strip_comments(read(KNOT))
    plan = strip_comments(read(PLAN))
    out = []
    for name in ("BaseKnotNodeEngPips", "BaseKnotNodeHuntPips", "BaseKnotLegPick",
                 "BaseKnotLegCapped", "BaseKnotLegPair", "BaseKnotCapTag", "BaseKnotCapWhy"):
        got = len(re.findall(r"^\s*(?:double|bool|void|string)\s+" + name + r"\s*\(", src, flags=re.M))
        out.append(("one definition of %s (found %d)" % (name, got), got == 1))

    b, p = _defines(src), _defines(plan)
    div = b.get("BK_NODE_POWER_DIV", 0.0)
    plan_div = p.get("TRADEPLAN_ENG_DIVISOR", 0.0)
    out.append(("the node's divisor IS the plan's own (%.6f vs %.6f)" % (div, plan_div),
                div > 0.0 and abs(div - plan_div) < 1e-9))
    hunt = (b.get("BK_NODE_HUNT_NUM", 0.0) / b["BK_NODE_HUNT_DEN"]
            if b.get("BK_NODE_HUNT_DEN") else 0.0)
    want = (p.get("TRADEPLAN_HUNTER_NUM", 0.0) / p["TRADEPLAN_HUNTER_DEN"] / plan_div
            if p.get("TRADEPLAN_HUNTER_DEN") and plan_div else 0.0)
    # 1e-6, not 1e-9: the plan spells 64/15 as the literal 4.266666, so 8/3 ÷ 4.266666 holds only
    # to that many digits — the tolerance IS that spelling, and a real drift is a whole pip.
    out.append(("the node's Hunt leg is that same unit (%.7f vs %.7f)" % (hunt, want),
                hunt > 0.0 and abs(hunt - want) < 1e-6))
    fit = hunt + 1.0 / div if div else 9.9
    out.append(("both legs fit INSIDE the box by construction (%.6f + %.6f = %.6f <= 1)"
                % (hunt, 1.0 / div if div else 0.0, fit), fit <= 1.0))

    calc = body(read(KNOT), "void BaseKnotCalcLevels(") or ""
    pair = body(read(KNOT), "void BaseKnotLegPair(") or ""
    out.append(("the geometry takes its pair from the ONE owner",
                "BaseKnotLegPair(top, bot, kind, tfMin, offP, riskP, anchor);" in calc))
    out.append(("the pair's ENTRY leg is picked against the node's power",
                re.search(r"offPips\s*=\s*BaseKnotLegPick\(", pair) is not None))
    out.append(("... and so is the leg the stop is drawn with",
                re.search(r"riskPips\s*=\s*BaseKnotLegPick\(", pair) is not None))
    out.append(("... and never sizes a leg off the plan unbounded (no raw Eng/Hunt size)",
                re.search(r"=\s*BaseKnot(?:Eng|Hunt)Pips\s*\(", calc) is None))
    risk = body(read(KNOT), "double BaseKnotRiskPips(") or ""
    out.append(("the R every text prints is picked by the same rule",
                "BaseKnotLegPick(" in risk))
    tag = body(read(KNOT), "string BaseKnotRiskTag(") or ""
    out.append(("... and the NAME of that R by the same rule too",
                "BaseKnotLegCapped(" in tag and "BaseKnotCapTag(" in tag))
    why = body(read(KNOT), "string BaseKnotEntryWhy(") or ""
    out.append(("the entry's sentence names the ceiling when it spoke",
                "BaseKnotCapClause(" in why))
    stopwhy = body(read(KNOT), "string BaseKnotStopWhy(") or ""
    out.append(("the stop's sentence names its source (plan / node / box)",
                "BaseKnotRiskIsEng(" in stopwhy and stopwhy.count("stands in") == 3))
    for name, guard in (("BaseKnotNodeEngPips", "BK_NODE_POWER_DIV <= 0.0"),
                        ("BaseKnotNodeHuntPips", "BK_NODE_HUNT_DEN <= 0.0")):
        fn = body(read(KNOT), "double %s(" % name) or ""
        out.append(("%s guards its own divisor (never a Zero Divide)" % name,
                    guard in fn and "pip <= 0.0" in fn))
    out.append(("the retired unbounded pair is kept in place, restorable (`-OFF`, never rewritten)",
                read(KNOT).count("BKATRLEG-OFF:") >= 3))
    others = []
    for path in sorted(ROOT.glob("Biotak/*.mqh")):
        rel = path.relative_to(ROOT).as_posix()
        if rel != KNOT and "BaseKnotNodeEngPips" in strip_comments(read(rel)):
            others.append(Path(rel).name)
    out.append(("no other module sizes a knot's legs (%s)" % (", ".join(others) or "none"),
                not others))
    return out


# --- 10b: P-BK-79 — every number the knot draws is read AS OF the box' own bar ----------
# The user's report: «مثلا atr یک دقیقه زمان گره بوده مثلا 20 … با گذشت زمان ممکن 40 بشه یا 10
# بشه که اینطوری نمیشه نوع گره دقیق مشخص کرد». Every number the knot drew was a LIVE read:
# the strip ATR took no shift at all, the plan's EngSL / HuntSL / TP1..3 were pushed per TF
# and cached per TF, and the type compared the box' height against TODAY's ATR. So ONE box
# changed its type and its levels as the market's volatility moved, and TWO boxes on the SAME
# TF could never be told apart — the table had one row for the both of them.
# THE RULE: a row is (TF, ANCHOR), where the anchor is the box' own `storyT` — the bar its
# story ended on, which is the same bar the type and the story are read from. 0 means "no
# anchor": the LIVE row, which is what the sizing preview asks for before it has a base.
# ONE TABLE, ONE KEY, ONE OWNER PER SIDE: BaseKnotEngNeeds asks, BaseKnotEngPush answers,
# and every reader takes the anchor as a DEFAULTED last parameter — so a caller that never
# learned the word (the live preview, the plan card) is byte-identical to what it was.
ASOF_ROW_MAX = 48
EVENT = "Biotak/EventHandlers.mqh"
ATR = "Biotak/ATRCalculations.mqh"


def asof_ask(boxes, chart_tf, lad):
    """Mirrors BaseKnotEngNeeds: the (TF, anchor) pairs one pump round asks for.

    `boxes` is a list of (tf, storyT, kind). The live row comes first, then each box asks
    its own TF, the two rungs above it and its measure TF — ALL AT ITS OWN ANCHOR — and the
    list is deduped on the PAIR and bounded exactly like the table.
    """
    out = [(chart_tf, 0)]
    for tf, story, kind in boxes:
        tf = tf or chart_tf
        an = story or 0
        up1 = ladder_next(tf, lad)
        up2 = ladder_next(up1, lad) if up1 else 0
        measure = up1 if kind in (NODE_CTR, NODE_OTR) else tf
        for a in (tf, up1, up2, measure):
            if a <= 0 or (a, an) in out:
                continue
            if len(out) >= ASOF_ROW_MAX:
                break
            out.append((a, an))
    return out


def check_asof():
    """P-BK-79: one row per (TF, anchor), and the anchor is the box' own story end."""
    out = []
    src = read(KNOT)
    plain = strip_comments(src)
    lad = ladder()
    #--- the model: the ask list is keyed on the PAIR, not on the TF -----------------
    two = asof_ask([(60, 1000, NODE_ETR), (60, 2000, NODE_ETR)], 60, lad)
    out.append(("two boxes on the SAME TF, different story ends -> TWO rows for that TF (%s)"
                % (two,),
                (60, 1000) in two and (60, 2000) in two
                and sum(1 for tf, _ in two if tf == 60) == 3))
    same = asof_ask([(60, 1000, NODE_ETR), (60, 1000, NODE_ETR)], 60, lad)
    out.append(("... and two boxes that ended on the SAME bar share ONE row each (%s)" % (same,),
                same == [(60, 0), (60, 1000), (240, 1000), (1440, 1000)]))
    hop = asof_ask([(60, 1000, NODE_CTR)], 60, lad)
    out.append(("... and a CTR/OTR box asks its measure rung too, at its own anchor (%s)" % (hop,),
                (60, 1000) in hop and (240, 1000) in hop and (1440, 1000) in hop))
    bare = asof_ask([(0, 0, NODE_NONE)], 15, lad)
    out.append(("... while a box with no class and no story stays on the LIVE row (%s)" % (bare,),
                bare[0] == (15, 0) and all(an == 0 for _, an in bare)))
    many = asof_ask([(60, 1000 + i, NODE_ETR) for i in range(40)], 60, lad)
    out.append(("... and the list is BOUNDED like the table (%d rows)" % len(many),
                len(many) <= ASOF_ROW_MAX))
    #--- the table: the anchor rides beside the TF -----------------------------------
    out.append(("the table carries the ANCHOR beside the TF (P-BK-79)",
                "#define BK_ENG_ROW_MAX %d" % ASOF_ROW_MAX in src
                and "static datetime s_bkEngAnchor[BK_ENG_ROW_MAX];" in src))
    for col in ("s_bkEngTF", "s_bkEngAnchor", "s_bkEngPips", "s_bkEngHunt",
                "s_bkEngTP1", "s_bkEngTP2", "s_bkEngTP3"):
        got = len(re.findall(r"static\s+\w+\s+%s\[BK_ENG_ROW_MAX\];" % col, src))
        out.append(("the row's %s is sized by the ROW bound (found %d)" % (col, got), got == 1))
    out.append(("... and no TF-only bound is left behind (the half-renamed define that shipped)",
                "BK_ENG_TF_MAX" not in plain))
    out.append(("the ability table is keyed on the pair too (one ladder, two tables)",
                "#define BK_AB_TF_MAX BK_ENG_ROW_MAX" in src
                and "static datetime s_bkAbAnchor[BK_AB_TF_MAX];" in src
                and "s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an" in src))
    #--- the push: the anchors arrive and the anchor re-arms the gate -----------------
    push = body(src, "void BaseKnotEngPush(") or ""
    out.append(("the push takes the anchors beside the TFs and stores the pair",
                re.search(r"void\s+BaseKnotEngPush\s*\(\s*const\s+int\s+&mins\[\],\s*"
                          r"const\s+datetime\s+&anchors\[\]", plain) is not None
                and "anNew[m] = (anchors[i] > 0 ? anchors[i] : 0);" in push
                and "s_bkEngAnchor[i] = anNew[i];" in push))
    out.append(("... and a MOVED anchor re-arms the gate exactly like a moved EngSL",
                re.search(r"tfNew\[i\]\s*!=\s*s_bkEngTF\[i\]\s*\|\|\s*"
                          r"anNew\[i\]\s*!=\s*s_bkEngAnchor\[i\]", push) is not None))
    #--- the readers: the pair, never the TF ------------------------------------------
    for sig, who in (("double BaseKnotEngPips(", "the risk"),
                     ("double BaseKnotHuntPips(", "the Hunter leg"),
                     ("double BaseKnotPlanTPPips(", "the plan's target legs")):
        fn = body(src, sig) or ""
        out.append(("%s is read at ONE (TF, anchor) pair, never a TF alone" % who,
                    re.search(r"s_bkEngTF\[i\]\s*==\s*tf\s*&&\s*s_bkEngAnchor\[i\]\s*==\s*anchor",
                              fn) is not None))
    #--- the ask: the pair, and the dedup on the pair ---------------------------------
    needs = body(src, "int BaseKnotEngNeeds(") or ""
    out.append(("the ask list carries the ANCHOR beside every TF (P-BK-79)",
                re.search(r"int\s+BaseKnotEngNeeds\s*\(\s*int\s+&mins\[\],\s*"
                          r"datetime\s+&anchors\[\]\s*\)", plain) is not None
                and "mins[n] = chartTF; anchors[n] = 0; n++;" in needs
                and "datetime an = (g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : 0);" in needs
                and "mins[n] = asked[a]; anchors[n] = an; n++;" in needs))
    out.append(("... and the dedup is on the PAIR — the chart-TF shortcut had to go",
                re.search(r"mins\[j\]\s*==\s*asked\[a\]\s*&&\s*anchors\[j\]\s*==\s*an", needs)
                is not None
                and "asked[a] == chartTF" not in needs))
    #--- the read: the anchor is HANDED IN, never re-derived ---------------------------
    nread = body(src, "void BaseKnotNodeRead(") or ""
    out.append(("the read TAKES the anchor as its own argument",
                re.search(r"const\s+datetime\s+anchor,\s*BaseKnotNode\s+&nd\)", plain) is not None))
    out.append(("... and never re-derives it from the box' edge or the clock",
                "nd.anchor = (anchor > 0 ? anchor : 0);" in nread
                and re.search(r"nd\.anchor\s*=\s*(?:t2|tExit|Period\(\)|TimeCurrent\(\))", nread)
                is None))
    out.append(("... and the box' record PUBLISHES the bar it was read at",
                "datetime anchor;" in (body(src, "struct BaseKnotNode") or "")))
    #--- every reader threads it, as a DEFAULTED last parameter ------------------------
    unthreaded = []
    for name in ("BaseKnotOffsetIsHunt", "BaseKnotEntryOffsetPips", "BaseKnotEntryWhy",
                 "BaseKnotEntryLine", "BaseKnotCapClause", "BaseKnotStopWhy",
                 "BaseKnotLegPair", "BaseKnotCalcLevels", "BaseKnotRiskPips",
                 "BaseKnotRiskTag", "BaseKnotTPLevel", "BaseKnotTPPlanTag",
                 "BaseKnotTPPlanTip", "BaseKnotNodeKindOfLength", "BaseKnotNodeBandFtrEtr",
                 "BaseKnotNodeBandEtrCtr"):
        m = re.search(r"^\s*(?:bool|int|double|string|void)\s+%s\s*\(([^)]*)\)" % name, plain,
                      re.M)
        if not re.search(r"const\s+datetime\s+anchor\s*=\s*0", m.group(1) if m else ""):
            unthreaded.append(name)
    out.append(("every reader takes the anchor as a DEFAULTED last parameter (%s)"
                % (", ".join(unthreaded) or "all %d" % 16), not unthreaded))
    #--- the call sites: the committed box, the preview and the drag -------------------
    sync = body(src, "void BaseKnotSync(") or ""
    liveb = body(src, "void BaseKnotSyncLive(") or ""
    drag = body(src, "void BaseKnotMoveChildren(") or ""
    line = body(src, "string BaseKnotNodeLine(") or ""
    out.append(("the committed box reads EVERY number at `nd.anchor`",
                "BaseKnotCalcLevels(top, bot, dir, nd.kind, baseTF, entry, sl, nd.anchor);" in sync
                and "BaseKnotRiskTag(mTF, baseTF, top, bot, nd.anchor)" in sync
                and "BaseKnotRiskPips(mTF, top, bot, nd.anchor)" in sync
                and "BaseKnotStopWhy(mTF, top, bot, nd.anchor)" in sync
                and "BaseKnotEntryLine(nd.kind, mTF, offIsHunt, dir, top, bot, nd.anchor)" in sync
                and "BaseKnotTPPlanTip(baseTF, entry, dir, hPips, nd.anchor)" in sync
                and "BaseKnotTPLevel(entry, dir, baseTF, tk, nd.anchor)" in sync
                and "BaseKnotPlanTPPips(baseTF, tk, nd.anchor)" in sync))
    out.append(("... and the sizing preview reads the LIVE row (anchor 0) and says so",
                "ndLive.anchor = 0;" in liveb
                and "BaseKnotCalcLevels(top, bot, dir, BK_NODE_NONE, liveTF, entry, sl, 0);" in liveb
                and "BaseKnotRiskPips(liveTF, top, bot, 0)" in liveb
                and "BaseKnotTPLevel(entry, dir, 0, tk, 0)" in liveb))
    out.append(("... and a drag follows the SAME anchor the release Sync will land on",
                re.search(r"datetime\s+an\s*=\s*g_bkBoxes\[k\]\.storyT;", drag) is not None
                and "g_bkBoxes[k].baseTFMin, entry, sl, an);" in drag
                and "g_bkBoxes[k].baseTFMin, tk, an);" in drag))
    out.append(("... and the box hover's own sentences ride the SAME anchor",
                "BaseKnotOffsetIsHunt(nd.kind, wTF, nd.anchor)" in line
                and "BaseKnotCapClause(wTF, wHu, top, bot, nd.anchor)" in line))
    #--- the pump: the plan is computed AT the row's anchor ---------------------------
    ev = strip_comments(read(EVENT))
    out.append(("the pump asks for the pairs and computes each row at ITS anchor",
                "datetime anchors[BK_ENG_ROW_MAX];" in ev
                and "int n = BaseKnotEngNeeds(mins, anchors);" in ev
                and "TradePlanCompute(mins[i], plan, anchors[i])" in ev
                and "BaseKnotEngPush(mins, anchors, pips, hunts, tp1, tp2, tp3, n);" in ev
                and "BaseKnotAbilityPush(mins[i], anchors[i], ab[i]);" in ev))
    #--- the ATR side: a SIBLING read, keyed by the bar's own TIME --------------------
    atr = read(ATR)
    out.append(("the anchored ATR is a SIBLING of the live read, never a shift on it",
                "ATRWeightedComposite(tf, 1)" in (body(atr, "double CalculateWeightedATR(") or "")
                and "return CalculateWeightedATR(t);" in (body(atr, "double CalculateWeightedATRAt(") or "")))
    out.append(("... keyed by the BAR'S OWN TIME (a shift-keyed cache would serve a stale answer)",
                "barTime = iTime(Symbol(), t, shift);" in (body(atr, "double CalculateWeightedATRAt(") or "")))
    out.append(("... and its cache is big enough for the pump's own ask list (%d rows)"
                % ASOF_ROW_MAX,
                "#define ATR_ANCHOR_CACHE_SIZE %d" % ASOF_ROW_MAX in atr))
    return out


# --- 11: P-BK-53 — the chart's OWN label is a NAME, the proof rides the hover --------
# The user's ask («اطلاعات خلاصه و قابل فهمی باشه») came from a note that read
# «[BUY · the node's own EngSL (its height / 4.2667) 17.9 Pips | …]»: P-BK-52 had named
# the ceiling with its FORMULA everywhere it spoke. The chart-side note has room for a NAME
# and nothing else; the hover has room for the proof — and P-BK-52's own rule (a number
# nobody can check is never printed) survives by putting the proof where it is READ OUT.
# ONE flag (`isHunt`, the one the pick was made with) decides both names, so the short one
# and the long one can never describe different legs.
def check_label_short():
    """P-BK-53: the chart's label is a NAME; the formula lives in the hover's clause."""
    src = read(KNOT)
    out = []
    tag = body(src, "string BaseKnotCapTag(")
    why = body(src, "string BaseKnotCapWhy(")
    if tag is None or why is None:
        return [("the short name and the proof form both exist", False)]
    names = re.findall(r'"([^"]*)"', tag)   # the literals the name is built from
    out.append(("the chart's own name is a NAME — no formula, no bracket, no divisor (%s)"
                % (" | ".join(names) or "nothing"),
                names == ["node HuntSL", "node EngSL"]
                and all("height" not in n and "/" not in n and "(" not in n for n in names)))
    out.append(("... and it still says WHICH leg the node sized (both names spelled)",
                len(names) == 2 and "HuntSL" in names[0] and "EngSL" in names[1]))
    out.append(("... and ONE flag decides both names (the pick's own `isHunt`)",
                tag.count("isHunt") == 1 and why.count("isHunt") == 1))
    out.append(("the hover keeps the arithmetic that sized the number",
                "its height / 4.2667" in why and "its height x 5/8" in why))
    clause = body(src, "string BaseKnotCapClause(") or ""
    out.append(("the ceiling's clause prints the PROOF, never the short name again",
                "BaseKnotCapWhy(isHunt)" in clause and "BaseKnotCapTag(" not in clause))
    stopwhy = body(src, "string BaseKnotStopWhy(") or ""
    out.append(("the stop's sentence says the node's own leg in words a user can check",
                stopwhy.count("BaseKnotCapWhy(false)") == 2
                and "stands in" in stopwhy and "power" not in stopwhy))
    rt = body(src, "string BaseKnotRiskTag(") or ""
    out.append(("the name the chart-side note prints is the SHORT one",
                "return BaseKnotCapTag(false);" in rt and "BaseKnotCapWhy" not in rt))
    wib = body(src, "void BaseKnotWriteInfo(") or ""
    out.append(("the note hands the name through — it spells no formula of its own",
                "riskTag" in wib and "4.2667" not in wib and "5/8" not in wib))
    return out


# --- 12: P-BK-54 — the note is a GLANCE: no targets, no unit word ----------------
# The user: «تی پی رو … در اطلاعات نشون نده … EngSL 17.9 همین بنویسه فقط اینطوری خلاصهه».
# The note is read AT A GLANCE on a live chart, so it prints the risk and its SOURCE
# (P-BK-46/53) and nothing the chart already draws: the plan's legs are TICKS on the chart
# (P-BK-50) and every leg with its level, its pips and its R in the HOVER
# (BaseKnotTPPlanTip). The retired field stays ONE uncomment away (BKTAGTP-OFF).
def check_note_fields():
    """P-BK-54: the chart's note is risk + source + the base's story, and nothing else."""
    src = read(KNOT)
    wib = body(src, "void BaseKnotWriteInfo(")
    if wib is None:
        return [("the note's writer is present", False)]
    out = []
    plain = strip_comments(wib)
    at = plain.find("OBJPROP_TEXT,")
    expr = plain[at:plain.find(");", at)] if at >= 0 else ""
    out.append(("the note's own text still carries the risk and the NAME of its source",
                "riskTag" in expr and "DoubleToString(hPips, 1)" in expr and "side" in expr))
    out.append(("... and NO target field in it (the plan's legs live in the hover now)",
                "tpTag" not in expr and "BaseKnotTPPlanTag(" not in expr))
    # ... read on the LITERALS: the field name `hPips` carries the word, so a raw
    # `"Pips" in expr` would pass for the wrong reason (and fail on the right one).
    lits = re.findall(r'"([^"]*)"', expr)
    out.append(("... and no unit word — the plan's own row names the unit (`Eng.SL: 0.2`)",
                not any("Pips" in s for s in lits)))
    out.append(("the class and the type still ride the note, and NO pattern name does "
                "(P-BK-28/29, P-BK-81: the four names are gone)",
                all(x in expr for x in ("BaseKnotBaseTag(", "BaseKnotNodeTag("))
                and "BaseKnotPatternTag(" not in expr))
    # P-BK-57: the note's SECOND number is the box' own height, and it rides the ONE owner
    # that builds it — read on the expression, so a hand-spelt copy in the text fails.
    out.append(("the box' own height rides the note, from its one owner (P-BK-57)",
                "BaseKnotHeightTag(top, bot, riskTag)" in expr))
    sig = src[src.find("void BaseKnotWriteInfo("):src.find("{", src.find("void BaseKnotWriteInfo("))]
    out.append(("the writer no longer even takes a target field", "tpTag" not in sig))
    out.append(("the hover KEEPS the plan's own legs, leg by leg",
                "tpTip" in plain and "BaseKnotTPPlanTip(" in strip_comments(src)))
    for fn, who in (("void BaseKnotSync(", "the committed box"),
                    ("void BaseKnotSyncLive(", "the live preview")):
        blk = body(src, fn) or ""
        out.append(("%s still builds that leg list and hands it to the writer" % who,
                    "BaseKnotTPPlanTip(" in blk and "tpTip," in blk))
    out.append(("the retired target field is kept in place, restorable (BKTAGTP-OFF)",
                src.count("BKTAGTP-OFF") >= 3))
    return out


# --- 12b: P-BK-57 — the note's second number: the BOX' own height, BARE ----------------
# The user: «مقدار حرکت رو هم به صورت عدد فقط نمایش بده بفهمیم چقدره». The risk says how big
# the STOP is; the note never said how big the BOX is — the size everything else is read
# against (the step multiples, the candle count, the class). The chart face gets the NUMBER
# ALONE (no name, no unit word — P-BK-54's own rule), the hover gets the name and the
# arithmetic, and the field is WRITTEN ONCE: when the risk' own source IS the box' height
# (BaseKnotBoxHeightTag), the first number already carries it and this one stays empty.
# One owner: `BaseKnotToPips(top - bot)` — the very expression BaseKnotRiskPips falls back
# to, so "the box' height" cannot mean two things in this module.
def check_note_height():
    """P-BK-57: the box' own height, in pips, bare beside the risk — never twice."""
    src = read(KNOT)
    fn = body(src, "string BaseKnotHeightTag(")
    if fn is None:
        return [("the note's height field has one owner", False)]
    out = []
    plain = strip_comments(fn)
    # only what the field actually WRITES: `return "";` contributes no literal at all, so
    # an empty string is dropped and what is left must be the separator alone.
    written = [s for s in re.findall(r'"([^"]*)"', plain) if s]
    out.append(("the field writes a bare number — a separator and nothing else (%s)"
                % (" | ".join(written) or "nothing"),
                written == [" | "]
                and not any(ch.isalpha() or ch.isdigit() for s in written for ch in s)))
    out.append(("... and no unit word, the plan's own row names the unit (P-BK-54)",
                not any("Pips" in s or "pip" in s for s in written)))
    out.append(("... and its number is the module's ONE box height (`BaseKnotToPips`)",
                "BaseKnotToPips(top - bot)" in plain))
    out.append(("... and it is written ONCE — silent while the risk IS that height (P-BK-46)",
                re.search(r'if\s*\(\s*riskTag\s*==\s*BaseKnotBoxHeightTag\(\)\s*\)\s*return\s*"";',
                          plain) is not None))
    out.append(("... and an empty box claims no height (no zero, no negative)",
                "p <= 0.0" in plain))
    # the fallback NAME has one owner too — the tag the note prints and the tag this field
    # tests itself against must be the same string, or the note prints the size twice.
    rt = strip_comments(body(src, "string BaseKnotRiskTag(") or "")
    out.append(("the risk' fallback name and the height's own test are ONE string",
                "return BaseKnotBoxHeightTag();" in rt
                and 'return "box height";' not in rt))
    # ... and the hover names what the chart face only numbers (P-BK-46's promise keeps):
    # a SIBLING owner, so the writer hands the fact through and spells nothing itself.
    tip = body(src, "string BaseKnotHeightTip(")
    if tip is None:
        out.append(("the hover's own version of the number exists", False))
    else:
        tplain = strip_comments(tip)
        out.append(("the hover NAMES it, with `top - bottom` and its pips (ONE spelling)",
                    tplain.count("box height (top - bottom) = ") == 1
                    and "BaseKnotToPips(top - bot)" in tplain))
        out.append(("... on the SAME number and the SAME test the field uses (one owner)",
                    tplain.count("BaseKnotToPips(top - bot)") == 1
                    and "riskTag == BaseKnotBoxHeightTag()" in tplain))
    wib = strip_comments(body(src, "void BaseKnotWriteInfo(") or "")
    out.append(("... and the note writer hands it through, spelling no arithmetic of its own",
                "BaseKnotHeightTip(top, bot, riskTag)" in wib
                and "box height (top - bottom)" not in wib))
    return out


# --- 13: P-BK-55/56 — the note's TYPE and the note's LOOK ---------------------------
# P-BK-55 (2026-09-16, user: «توی اطلاعات چرا نوع گره رو نشون نمیده»): the type is the node's
# LENGTH — a count of rungs between the class the note already prints and the TF the node is
# seen on — so a box being SIZED can answer it from the very span its class came from. It used
# to claim BK_NODE_NONE while sizing, i.e. the note showed a class with no type beside it.
# P-BK-56 (user: «این لیبل اطلاعات مثل بقیه لیبل اطلاعات باشه»): the note is a chart-anchored
# text a human reads, so it follows the LABEL FAMILY's own grid — font `inpFontName`, size
# `inpFontSize`, rung Z_CHART_LABEL — instead of the box' own text size and the box' art rung.
def check_note_life():
    """P-BK-55/56: the sizing note reads the TYPE; the note looks like the label family."""
    src = read(KNOT)
    live = body(src, "void BaseKnotSyncLive(")
    if live is None:
        return [("the live preview is present", False)]
    out = []
    out.append(("the sizing note reads the TYPE from the very span its class comes from",
                "BaseKnotNodeKindOfLength(liveClass," in live
                and "BaseKnotBaseTFMin(spLive." in live))
    out.append(("... on the SAME rule the committed read uses (one length, two callers)",
                "BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor)"
                in (body(src, "void BaseKnotNodeRead(") or "")
                # P-BK-77/78/80: and BOTH callers read the type against the LADDER's own
                # answer — the live preview's class comes off the same whole-ladder search,
                # with NO extra TF argument, and its span is the BOX' own two anchors
                # (`t1..te`, the rubber band), never the chart-read story span.
                and re.search(r"BaseKnotBaseTFMin\(spLive\.still,\s*t1,\s*te,"
                              r"\s*top,\s*bot\)", live) is not None
                and "spLive.tStart" not in live and "spLive.tExit" not in live
                # P-BK-79: and at the SAME KIND OF KEY — the live preview's anchor is 0 (the
                # LIVE row, the only one it can have before a base exists), while the committed
                # read carries the box' own `storyT`. A preview that copied `nd.anchor` or a
                # committed read that fell back to 0 would draw the other one's numbers.
                and "BaseKnotNodeKindOfLength(liveClass, ndLive.height, ndLive.anchor)" in live
                and "ndLive.anchor = 0;" in live
                and "BaseKnotAbilityGet(liveClass, ndLive.anchor," in live))
    out.append(("... while the STORY stays a committed-only read (no side, no story TF live)",
                "ndLive.side = 0;" in live and "ndLive.storyTF = 0;" in live))
    wib = strip_comments(body(src, "void BaseKnotWriteInfo(") or "")
    out.append(("the note's FONT is the label family's own (`inpFontName`, never a literal)",
                "OBJPROP_FONT, inpFontName" in wib
                and not re.search(r'OBJPROP_FONT,\s*"', wib)))
    fn = body(src, "int BKInfoFontPt(")
    if fn is None:
        out.append(("the note's size owner exists", False))
    else:
        out.append(("the note's shipped size is the LABEL grid (`inpFontSize`)",
                    "ClampSettingInt(inpFontSize, 4, 24)" in fn))
        # the marker lives in a COMMENT, and body() strips those — so the retired rung
        # is read on the RAW source (a marker the gate cannot see is a marker nobody keeps).
        out.append(("... and the retired rung (the box' own text size) is kept, restorable",
                    src.count("BKINFOSIZE-OFF") >= 2
                    and "BKINFOSIZE-OFF: return ClampSettingInt(g_bkTextSize, 8, 24);" in src))
    out.append(("the note rides the TEXT layer's rung (Z_CHART_LABEL), not the box' art one",
                "OBJPROP_ZORDER, Z_CHART_LABEL" in wib and "Z_BOX_INFO" not in wib))
    return out


# --- 14: P-BK-58 — the note's SECOND HOME (the family's corner) ---------------------
# The user: «لیبل اطلاعات بیس را کنار همان کارت/ردیف خانوادهٔ لیبلها هم نشان بده تا کاربر
# بتواند بین «چسبیده به باکس» و «گوشهٔ ثابت» یکی را انتخاب کند». The note's TEXT and its one
# writer do not change; its HOME becomes a user setting (`g_bkShowInfo`'s third rung). What can
# silently break, and what this section reads the source for:
#
#   * the note drawn TWICE (a mode change that leaves the box-side copy behind, or a box that
#     is not the one the row answers wiping the row);
#   * the row drawn NOWHERE (the decision owner not consulted, the box-side probe not refusing
#     in corner mode, or the row's keeper never called);
#   * a margin GUESSED by this module (the slot must be pushed in by the label module, which
#     owns the column: `inpLabelsMargin*` may not appear in this file);
#   * a row that answers a box the user did not choose (the SELECTED box, MT4's own single
#     select — the newest only while nothing is selected);
#   * a stale row after a cancel (the keeper must stand down while the box is being SIZED, and
#     re-decide the round after);
#   * a per-round cost (the keeper writes on a CHANGE only).
def check_note_home():
    """P-BK-58: one note, two homes, one decision owner — and no margin guessed."""
    src = read(KNOT)
    out = []
    plain = strip_comments(src)
    place = body(src, "bool BaseKnotNoteInCorner(")
    ask = body(src, "bool BaseKnotNoteAtCorner(")
    sel = body(src, "string BaseKnotSelectedId(")
    ref = body(src, "void BaseKnotNoteCornerRefresh(")
    wib = body(src, "void BaseKnotWriteInfo(")
    for name, fn in (("the rung reader", place), ("the placement owner", ask),
                     ("the selected-box read", sel), ("the row's keeper", ref),
                     ("the note writer", wib)):
        if fn is None:
            return [("the note's home has ONE owner per question (%s)" % name, False)]
    vis = body(src, "bool BaseKnotInfoVisible(")
    out.append(("the box-side probe refuses in the corner rung (one place at a time)",
                vis is not None and re.search(r"if\s*\(\s*BaseKnotNoteInCorner\(\)\s*\)\s*return\s*false;",
                                              strip_comments(vis)) is not None))
    out.append(("the rung is the setting's own, never a literal (the user picks it)",
                "g_bkShowInfo == BK_NOTE_CHART" in strip_comments(place)))
    out.append(("... and it is ONE question — the writer's callers ask the owner",
                plain.count("BaseKnotNoteAtCorner(") == 3   # the owner + the two Sync sites
                and "BaseKnotNoteAtCorner(\"\")" in plain))   # the box being SIZED always wins
    # the keeper: called by the pump, stands down while sizing, writes only on a change
    pump = body(src, "void BaseKnotSyncBadges(")
    out.append(("the row's keeper rides the existing pump (no second event path)",
                pump is not None and "BaseKnotNoteCornerRefresh();" in strip_comments(pump)))
    rp = strip_comments(ref)
    out.append(("... it stands down while the box is being SIZED (the live writer owns it)",
                "g_bkState == BK_PREVIEW" in rp))
    out.append(("... and it re-decides the round AFTER (a cancelled band leaves no preview)",
                re.search(r"if\s*\(\s*g_bkState\s*==\s*BK_PREVIEW\s*\)\s*\{[^}]*"
                          r"s_bkCornerDirty\s*=\s*true;", rp, flags=re.S) is not None))
    out.append(("... it deletes a row nothing answers (a stale note is worse than none)",
                "if(id == \"\")" in rp and "ObjectDelete(0, nm)" in rp))
    out.append(("... a box hidden on this TF claims no row",
                "BaseKnotVisibleNow(id)" in rp))
    out.append(("... steady state is ONE compare — no write per pump round",
                re.search(r"if\(id == s_bkCornerId && !s_bkCornerDirty\)\s*\{", rp) is not None))
    out.append(("... and the row SELF-HEALS if something else deleted it",
                re.search(r"if\(id == s_bkCornerId && !s_bkCornerDirty\)\s*\{[^}]*"
                          r"ObjectFind\(0, nm\)", rp, flags=re.S) is not None))
    # the selected box: MT4's own single select first, the newest commit otherwise
    sp = strip_comments(sel)
    out.append(("the row answers the SELECTED box (the terminal's own select, read not rebuilt)",
                "OBJPROP_SELECTED" in sp and "BaseKnotBoxName(pfx)" in sp))
    out.append(("... and the NEWEST box while nothing is selected",
                "commitMs" in sp))
    # the slot: pushed in, never guessed here
    out.append(("this module reads NO column margin — the slot is pushed in from above",
                not re.search(r"inpLabelsMargin", plain)))
    out.append(("... and the pushed slot is the row's only source of corner/x/y",
                "s_bkCornerSide" in strip_comments(wib) and "s_bkCornerX" in strip_comments(wib)
                and "s_bkCornerY" in strip_comments(wib)
                and plain.count("s_bkCornerSide  = corner;") == 1))   # ONE writer of the slot
    # ONE object at a time, both directions of a mode change
    wp = strip_comments(wib)
    out.append(("the two homes never both hold the note (the writer empties the other one)",
                re.search(r"if\(atCorner\)\s*\{[^}]*ObjectDelete\(0, in\);", wp, flags=re.S) is not None
                and re.search(r"else if\(!BaseKnotNoteInCorner\(\)", wp) is not None))
    out.append(("... and it writes ONE object name, so both homes share text/font/size/rung",
                re.search(r"ObjectSet\w+\(0,\s*in,", wp) is None
                and re.search(r"ObjectSet\w+\(0,\s*o,", wp) is not None))
    out.append(("... the corner row is right-aligned at the pushed slot (a LABEL, not a TEXT)",
                "OBJ_LABEL" in wp and "ANCHOR_RIGHT_LOWER" in wp))
    out.append(("... and only the LAST lines differ between the homes (time/price vs x/y)",
                "OBJPROP_XDISTANCE" in wp and "OBJPROP_YDISTANCE" in wp
                and "OBJPROP_PRICE, 0, top" in wp))
    # deinit
    out.append(("a remove / TF switch never leaves the row behind",
                "BaseKnotCornerWipe();" in strip_comments(body(src, "void BaseKnotOnDeinit(") or "")))
    return out


def main():
    rows = run_checks()
    for name, ok in rows:
        print("  %s   %s" % ("ok" if ok else "FAIL", name))
    bad = [n for n, ok in rows if not ok]
    print()
    if bad:
        print("base count: %d check(s) FAILED\n  - %s" % (len(bad), "\n  - ".join(bad)))
        return 1
    print("base count: clean — one owner, one span: the number is the base's own story "
          "(the entry candle is not counted, the exit candle is),\nthe left edge bounds "
          "nothing, the walk is capped on both the commit and the mouse path,\nthe node "
          "type IS the box' HEIGHT against the movement ability (that TF's own ATR) of "
          "the TF it is SEEN ON — the same type on every chart TF (bands at the midpoints, P-BK-76: "
          "FTR < trig|pat · ETR < pat|str · CTR <= str · OTR above),\nthe base's OWN EXIT CANDLE "
          "names the trade's side and it is FIXED (it closed above the ceiling -> Buy, below "
          "the floor -> Sell,\nthe four pattern names are GONE, and the walk starts at that "
          "candle so no drag and no chart TF can move it - read on the past market too), "
          "the size class is confirmed on the "
          "rung's own candles,\nand while "
          "the user draws a BAND decides the base - an edge that slides inside the run it "
          "already found reuses that one reading,\nand the knot's own two legs are the "
          "plan's, CAPPED by the node's own power (one owner, one rule, one unit, both "
          "inside the box by construction - P-BK-52),\nand the CHART's own label is a "
          "NAME (node EngSL) while the hover keeps the proof that sized it (P-BK-53),\n"
          "and the NOTE is a glance - the risk with its source and the base's own story, "
          "no target field and no unit word (the legs are ticks + the hover, P-BK-54),\n"
          "with the box' OWN height in pips beside the risk, bare and written once "
          "(named in its hover - P-BK-57),\n"
          "its TYPE is answered by the same length rule while the box is being sized "
          "(P-BK-55), and it wears the label family's own font, size grid and text rung "
          "(P-BK-56),\nand the note has TWO HOMES the user picks between (the box' corner "
          "or the label family's own column - P-BK-58), with ONE decision owner, ONE "
          "object at a time, and the slot PUSHED IN by the label module,\n"
          "and EVERY number it draws is read AS OF the box' own bar - one row per "
          "(TF, anchor), the anchor being the story's own last candle, so a box keeps "
          "the type and the levels ITS market gave it (P-BK-79)")
    return 0


def selftest():
    """every check must be able to fail: doctor the source and prove it fires."""
    cases = []

    def with_source(old, new, path=KNOT):
        _PATCHED[path] = read(path).replace(old, new, 1)

    def reset():
        _PATCHED.clear()
        _BUDGETS.clear()          # the model's budgets are source-derived

    def fires(check):
        return [n for n, ok in check() if not ok]

    walk_old = ("   int s = (sh1 < sh2 ? sh1 : sh2);")
    with_source(walk_old, "   int s = (sh1 > sh2 ? sh1 : sh2);   // the old LEFT-edge anchor")
    cases.append(("a left-edge anchor is caught", bool(fires(check_anchor))))
    reset()

    with_source("   if(anchor <= 0 || oldest <= 0) return 0;   // no base inside the walk's own budget",
                "   if(anchor < 0) return 0;   // a guard that never fires")
    cases.append(("a walk that can invent a base out of nothing is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("   int total = Bars;",
                "   int hi = (sh1 > sh2 ? sh1 : sh2);   // the old left-edge bound\n"
                "   int total = Bars;")
    cases.append(("a left-edge bound inside the walk is caught", bool(fires(check_anchor))))
    reset()

    with_source("      while(t < total && n + probe < BK_BASE_MAX)",
                "      while(t < total)")
    cases.append(("an uncapped walk is caught", bool(fires(check_break_and_budget))))
    reset()

    with_source("#define BK_LIVE_COUNT_MS 120", "#define BK_LIVE_COUNT_MS")
    cases.append(("a missing live cadence budget is caught", bool(fires(check_break_and_budget))))
    reset()

    with_source("   int n      = 0;   // base candles counted (drives the cap and the confirmation)",
                "   double probe2 = iOpen(_Symbol, 0, s);   // a second band test\n"
                "   int n      = 0;   // base candles counted (drives the cap and the confirmation)")
    cases.append(("a re-spelt band test in the walk is caught", bool(fires(check_owner))))
    reset()

    # P-BK-32's own teeth: the step-over, the count, the confirmation, the scale
    with_source("            gap++;", "            gap = gap;   // the retired P-BK-31 stop")
    cases.append(("a poke that cuts the base again is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("if(gap == 0)", "if(gap >= 0)")
    cases.append(("counting the tolerated body is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("               if(probe >= BK_BASE_MIN_BARS)",
                "               if(probe >= 1)")
    cases.append(("dropping the re-entry confirmation is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("   int gap    = 0;   // consecutive bodies outside the band since the last one inside",
                "   double tol = (top - bot) * 0.05;   // a band margin — P-BK-32 forbids it\n"
                "   int gap    = 0;   // consecutive bodies outside the band since the last one inside")
    cases.append(("a price margin smuggled into the walk is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    # P-BK-33: the model takes the budget from the source, so shrinking it back
    # under the break the user's box covers must show up as a failed promise
    with_source("#define BK_BASE_SKIP 300", "#define BK_BASE_SKIP  30")
    cases.append(("a step-over budget under the user's break is caught",
                  bool(fires(check_model))))
    reset()

    # P-BK-34: an anchor left on the forming candle must be caught
    with_source("   if(s == 0) s = 1;", "   if(s == 0) s = 0;   // the forming candle again")
    cases.append(("counting the forming candle is caught", bool(fires(check_anchor))))
    reset()

    # P-BK-42: the number is the base's own story (entry out, exit in), never the
    # count of in-band bodies and never a span that reaches to the box' edge
    with_source("   sp.life   = oldest - end;", "   sp.life   = n;")
    cases.append(("reporting the body count instead of the base's story is caught",
                  bool(fires(check_anchor))))
    reset()

    with_source("   sp.life   = oldest - end;", "   sp.life   = oldest - edge + 1;")
    cases.append(("counting the ENTRY candle (or the box' reach) again is caught",
                  bool(fires(check_anchor))))
    reset()

    with_source("   int end = (head > 1 ? head - 1 : head);",
                "   int end = edge;   // the box' right edge again (the 38)")
    cases.append(("ending the number at the box instead of the base's exit is caught",
                  bool(fires(check_anchor))))
    reset()

    with_source("   int edge = s;   // the box' right edge, off the forming candle (P-BK-34)",
                "   int edge = 0;   // a span measured from nowhere")
    cases.append(("a span not anchored on the box' edge is caught",
                  bool(fires(check_anchor))))
    reset()

    # P-BK-75/76/78: the HEIGHT owns the type, against the LADDER's three ATRs — every way
    # back to the retired read, and every way to a knife-edge boundary or a band out of
    # thin air, is caught
    with_source("   nd.kind = BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor);",
                "   if(nd.crossed)        nd.kind = BK_NODE_OTR;\n"
                "   else if(rebreaks > 0) nd.kind = BK_NODE_CTR;\n"
                "   else                  nd.kind = BK_NODE_ETR;")
    cases.append(("the retired level read setting the type again is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   nd.kind = BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor);",
                "   nd.kind = BK_NODE_FTR;   // the type, guessed")
    cases.append(("a type that is not read from the box' height is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   if(h <= (trig + pat) * 0.5) return BK_NODE_FTR;   // midpoint of trigger | pattern",
                "   if(h <= trig) return BK_NODE_FTR;   // back to the knife edge")
    cases.append(("a boundary moved back onto the ability itself (P-BK-76) is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-77/78: the ASK side carries the node's own time AND the two rungs above it — the
    # Get reads rows the pump never pushed otherwise, and every box answers BK_NODE_NONE.
    with_source("      asked[0] = tf;",
                "      asked[0] = chartTF;   // the open chart again")
    cases.append(("an ask list that drops the node's own time for the chart is caught",
                  bool(fires(check_node))))
    reset()

    with_source("      asked[1] = BaseKnotNextTFMin(tf);",
                "      asked[1] = tf;   // the rung above never asked for")
    cases.append(("an ask list that drops the rung above the class is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-78: the three abilities are the ladder's own ATRs — a push that scales, and a Get
    # that stops climbing, are both caught.
    with_source("   double v = (atr > 0.0) ? atr : 0.0;",
                "   double v = atr * 0.25;   // a ratio at the push site (a second owner)")
    cases.append(("a ratio hardcoded at the push site (a second owner) is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);            // the structure time",
                "   int up2 = up1;   // the structure time = the pattern time")
    cases.append(("a Get that stops climbing the ladder (pattern == structure) is caught",
                  bool(fires(check_node))))
    reset()

    with_source("      return (atr > 0.0);",
                "      return (atr >= 0.0);")
    cases.append(("a cold ATR becoming a threshold of zero is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return BK_NODE_NONE;",
                "   trig = trig; pat = pat; str = str;   // a band out of thin air")
    cases.append(("a TF whose ATR was never pushed getting a band is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   if(h <= str)                return BK_NODE_CTR;   // the structure ability itself",
                "")
    cases.append(("a node LONGER than the structure ability losing its OTR ceiling is caught",
                  bool(fires(check_node))))
    reset()

    with_source("BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor)",
                "BaseKnotNodeKindOfLength(Period(), nd.height, nd.anchor)")
    cases.append(("counting the height against the CHART's TF instead of the node's own is caught",
                  bool(fires(check_node))))
    reset()

    with_source("BaseKnotNodeRead((sp.tLast > 0 ? sp.tLast : t2), top, bot, baseTF,",
                "BaseKnotNodeRead((sp.tLast > 0 ? sp.tLast : t2), top, bot, Period(),")
    cases.append(("counting the length from the CHART's TF instead of the node's time is caught",
                  bool(fires(check_node))))
    reset()

    with_source("g_bkBoxes[k].nodeSide = ndDir;", "")
    cases.append(("a Sync that never publishes the side is caught (the pump would miss it)",
                  bool(fires(check_node))))
    reset()

    # P-BK-81: the side is the BASE'S OWN EXIT CANDLE and it is FIXED — every way back to a
    # price-rewrites-the-side read is caught, and every way back to the drawn rectangle is too.
    with_source("   return nd.side;   // P-BK-81: the base's own EXIT CANDLE's close vs the band (ONE bit, FIXED)",
                "   if(nd.returned) return -nd.side;   // the return's side again\n"
                "   return nd.side;")
    cases.append(("a side a RETURN can flip again is caught", bool(fires(check_node))))
    reset()

    with_source("   if(sX >= 1) start = sX;",
                "   if(sX >= 1) start = s2 - 1;   // the exit candle read but never used")
    cases.append(("a walk that reads the exit candle and then starts at the box anyway is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   int start = s2 - 1;\n"
                "   if(tExit > 0)\n"
                "   {\n"
                "      int sX = iBarShift(_Symbol, CompatTF(tfRead), tExit, false);\n"
                "      if(sX >= 1) start = sX;\n"
                "   }",
                "   int start = s2 - 1;")
    cases.append(("a walk that IGNORES the base's exit candle is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   g_bkBoxes[k].exitT  = sp.tExit;", "")
    cases.append(("a Sync that never publishes the exit candle is caught (the pump would "
                  "read a different bar)", bool(fires(check_node))))
    reset()

    with_source("                          g_bkBoxes[i].exitT, g_bkBoxes[i].storyT, ndNow);",
                "                          g_bkBoxes[i].storyT, g_bkBoxes[i].storyT, ndNow);")
    cases.append(("a pump reading the direction off the base's RIGHT SIDE is caught",
                  bool(fires(check_node))))
    reset()

    with_source('   return "\\nDirection: " + (nd.side > 0 ? "BUY" : "SELL") + " — the base\'s own EXIT candle closed " +',
                '   return "\\nPattern: RBR";')
    cases.append(("putting the four names back into the hover is caught",
                  bool(fires(check_node))))
    reset()

    with_source("BaseKnotBaseTag(still, t1, t2, top, bot) + BaseKnotNodeTag(nd) + \"]\");",
                "BaseKnotBaseTag(still, t1, t2, top, bot) + BaseKnotNodeTag(nd) + "
                "BaseKnotPatternTag(nd) + \"]\");")
    cases.append(("re-printing a pattern name in the note is caught",
                  bool(fires(check_node))))
    reset()

    with_source('#define BK_TAG "_BK_"',
                '#define BK_PAT_RBR  1   // the four names, back\n#define BK_TAG "_BK_"')
    cases.append(("putting a pattern define back is caught",
                  bool(fires(check_node))))
    reset()

    with_source("// P-BK-81: the DIRECTION's own sentence",
                'string BaseKnotPatternName(const int pattern) { return "RBR"; }\n'
                "// P-BK-81: the DIRECTION's own sentence")
    cases.append(("putting a pattern function back is caught",
                  bool(fires(check_node))))
    reset()

    with_source("   return nd.side;   // P-BK-81: the base's own EXIT CANDLE's close vs the band (ONE bit, FIXED)",
                "   if(nd.crossed) return 0;   // P-BK-48: the orders are SPENT\n"
                "   return nd.side;")
    cases.append(("zeroing a CONSUMED node's direction again is caught",
                  bool(fires(check_node))))
    reset()

    with_source("if(g_bkBoxes[k].nodeSide != 0) return false;",
                "if(g_bkBoxes[k].nodeKind != BK_NODE_NONE) return false;")
    cases.append(("freezing the live price on a TYPE instead of a SIDE is caught",
                  bool(fires(check_node))))
    reset()

    with_source("the type is the HEIGHT", "")
    cases.append(("a hover that hides that the type is a length is caught",
                  bool(fires(check_node))))
    reset()

    with_source("if(c < bot) nd.crossed = true;", "if(c < bot) nd.crossed = false;")
    cases.append(("dropping the far-edge read is caught", bool(fires(check_node))))
    reset()

    with_source("the same on every chart TF", "")
    cases.append(("a hover line that hides the TF-invariance is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-38: the story belongs to the base's TF, not to the chart that drew it
    # R-TF-UNIT moved the enum crossing in front of `tfRead` (CompatTF(tfRead));
    # the seed names the site as it is written now and still removes the CLASS
    # from it - the chart's own series is the fault either way.
    with_source("iBarShift(_Symbol, CompatTF(tfRead), t2, false)",
                "iBarShift(_Symbol, 0, t2, false)")
    cases.append(("reading the story on the chart's own series again is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-77: the class search is the WHOLE ladder, TOP-DOWN, on MINUTES — every way back
    # to the open chart deciding the node's time is caught.
    with_source("   for(int i = n - 1; i >= 0; i--)   // the HIGHEST rung first",
                "   for(int i = 0; i < n; i++)   // the chart's own rung first")
    cases.append(("a class ladder walked BOTTOM-UP (a lower rung would win) is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("   if(unread > 0) return unread;   // nothing stood still and a series was unreadable: the ladder stands",
                "   if(unread > 0) return Period();   // the open chart again")
    cases.append(("a class fallback that is the chart's TF again is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("   if(BaseKnotRungHoldCount(tf, b1, b2, top, bot) < BK_BASE_RUNG_MIN)",
                "   if(false)   // the sentence claims the rung's candles for free")
    cases.append(("a fallback sentence that names a rung without re-reading it is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("   int baseTF = BaseKnotBaseTFMin(still, t1, t2, top, bot);   // P-BK-80: the node's time, from the box' own geometry",
                "   int baseTF = 0;   // the chart's story again")
    cases.append(("a Sync that never publishes the class is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-80: the class' span is the BOX' own two anchors — every way back to the CHART-read
    # story span is caught.
    with_source("   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0));",
                "   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0)) + unit;")
    cases.append(("putting the chart's candle width back into the span is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("BaseKnotBaseTFMin(still, t1, t2, top, bot)",
                "BaseKnotBaseTFMin(still, sp.tStart, sp.tExit, top, bot)")
    cases.append(("classing the base on the CHART-read story span again is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0));",
                "   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0)) + Period();")
    cases.append(("letting the OPEN CHART widen the span is caught (the «H4 says FTR» bug)",
                  bool(fires(check_rung))))
    reset()

    # P-BK-82: M1 IS THE LADDER'S FLOOR. The walk that names the class starts at the HIGHEST
    # rung and comes down, so a floor at M5 leaves a base standing still on M1 with no rung to
    # name it — every rung is refused and the fallback names the SPAN's own rung instead,
    # which is exactly the «M15 base» the user reported.
    with_source("if(tfMin < 1)     return 1;", "")
    cases.append(("a class ladder whose floor stops at M5 is caught (the «M15 base» bug)",
                  bool(fires(check_rung))))
    reset()

    with_source("g_bkBoxes[i].baseTFMin,", "0,")
    cases.append(("a pump comparing a DIFFERENT story is caught",
                  bool(fires(check_node))))
    reset()

    with_source("story read on", "")
    cases.append(("a hover line that hides the story TF is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-40/41/42: one walk, one span — the two answers must stay distinct, and the
    # class, the node's read and the note must all ride the SAME record
    with_source("   sp.still  = n;", "   sp.still  = oldest - end;")
    cases.append(("swapping the stand-still count for the story's span is caught",
                  bool(fires(check_one_value))))
    reset()

    with_source("BaseKnotBaseTFMin(still, t1, t2, top, bot)",
                "BaseKnotBaseTFMin(bars, t1, t2, top, bot)")
    cases.append(("classing the base from its LIFE instead of its stand-still candles is caught",
                  bool(fires(check_one_value))))
    reset()

    with_source("   if(bars == s_bkRungBars && b1 == s_bkRungB1 && b2 == s_bkRungB2 &&",
                "   if(bars == s_bkRungBars && b1 == s_bkRungB1 && b2 == s_bkRungB2 && Period() > 0 &&")
    cases.append(("keying the class memo on a chart term again is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("band -> entry candle ", "band -> entry ")
    cases.append(("a hover that hides the ENTRY end is caught", bool(fires(check_one_value))))
    reset()

    with_source("-> exit candle " + chr(34), "-> exit " + chr(34))
    with_source("no exit candle inside it yet", "no exit yet")
    cases.append(("a hover that hides the EXIT end is caught", bool(fires(check_one_value))))
    reset()

    with_source("BaseKnotBaseTag(still, t1, t2, top, bot)",
                "BaseKnotBaseTag(bars, t1, t2, top, bot)")
    cases.append(("classing the NOTE from the life (and not the stand-still count) is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("BaseKnotSpan &sp)\n{\n   BaseKnotSpanClear(sp);",
                "int &sp)\n{\n   // no span record")
    cases.append(("a walk that stops handing out the span record is caught",
                  bool(fires(check_one_value))))
    reset()

    with_source("   int bars = BaseKnotBarCount(t1, t2, top, bot, sp);",
                "   int bars = BaseKnotBarCount(t1, t2, top, bot, sp);\n"
                "   bars = BaseKnotBarCount(t1, t2, top, bot, sp);   // a second walk")
    cases.append(("a second walk in Sync is caught", bool(fires(check_one_value))))
    reset()

    # P-BK-36/77: the class must be confirmed on the rung's own candles, top-down
    with_source("      if(held >= BK_BASE_RUNG_MIN) return rung;",
                "      return rung;   // the ladder alone")
    cases.append(("naming a rung without its own candles is caught",
                  bool(fires(check_rung))))
    reset()

    with_source("      if(o >= bot && o <= top && c >= bot && c <= top)",
                "      if(o >= bot - (top - bot) * 0.1 && o <= top && c >= bot && c <= top)")
    cases.append(("a margin in the rung read is caught", bool(fires(check_rung))))
    reset()

    with_source("   if(older - newer + 1 > BK_BASE_RUNG_MAX) older = newer + BK_BASE_RUNG_MAX - 1;",
                "   // an unbounded rung read")
    cases.append(("an unbounded rung read is caught", bool(fires(check_rung))))
    reset()

    with_source("#define BK_BASE_RUNG_MIN 3", "#define BK_BASE_RUNG_MIN 1")
    cases.append(("a rung confirmed by a single candle is caught",
                  bool(fires(check_rung)) and bool(fires(check_rung_model))))
    reset()

    # P-BK-44: the run must extend NEWER as well - the user's «36 not 20»
    with_source("         int fup = s - 1, fgap = 0, fprobe = 0, fn = 0;",
                "         int fup = 0, fgap = 0, fprobe = 0, fn = 0;   // no forward walk")
    cases.append(("a run that never looks NEWER past the box' edge is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("      int t = head;   // P-BK-44: the older walk starts at the run's head, so BOTH sides\n"
                "                      // of the box' right edge are inside the number and the class",
                "      int t = s;")
    cases.append(("a run walked from the box' edge again is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("         while(fup >= 1 && fn + fprobe < BK_BASE_MAX)",
                "         while(fup >= 1)   // an uncapped forward walk")
    cases.append(("an uncapped forward walk is caught", bool(fires(check_break_and_budget))))
    reset()

    with_source("               fgap++;\n               if(fgap > BK_BASE_GAP) break;",
                "               fgap++;\n               if(false) break;   // no tolerance forward")
    cases.append(("a forward walk with no tolerance is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    # P-BK-43: a stray body must not anchor the answer, and the budget must cover the
    # WHOLE search (a candidate that fails costs candles like any other)
    with_source("      if(n >= BK_BASE_MIN_BARS && oldest > 0) break;",
                "      break;   // the first body anchors it again")
    cases.append(("a stray body anchoring the answer again is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("      s = t;                                           // a stray body: look behind it",
                "      anchor = 0;   // never look behind a stray body")
    cases.append(("a search that stops behind a stray body is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("   while(s < total && s - edge < BK_BASE_SKIP)",
                "   while(s < total)")
    cases.append(("an anchor search with no budget again is caught",
                  bool(fires(check_break_and_budget))))
    reset()

    with_source("   if(tfMin < 60)    return 60;      // P-BK-43: 30 is NOT in our ladder",
                "   if(tfMin < 30)    return 30;\n   if(tfMin < 60)    return 60;")
    cases.append(("M30 creeping back into the base's ladder is caught",
                  bool(fires(check_rung))))
    reset()

    # P-BK-41: the story's own right side must reach the pump (one story, one candle)
    with_source("g_bkBoxes[k].storyT = sp.tLast;", "")
    cases.append(("a Sync that never publishes the story's right side is caught",
                  bool(fires(check_one_value))))
    reset()

    # P-BK-45: the live preview's window — the four ways it could lie
    with_source("top == s_bkLiveTop && bot == s_bkLiveBot && lastClosed == s_bkLiveBar &&",
                "lastClosed == s_bkLiveBar &&")
    cases.append(("a live reuse that ignores the BAND is caught (the base moves with the band)",
                  bool(fires(check_live_reuse))))
    reset()

    with_source("lastClosed == s_bkLiveBar &&", "")
    cases.append(("a live reuse that survives a NEW closed candle is caught",
                  bool(fires(check_live_reuse))))
    reset()

    with_source("s_bkLiveHi = (old > 0 ? old : head);",
                "s_bkLiveHi = iBarShift(_Symbol, 0, t2, false);   // the box' own edge again")
    cases.append(("a window bounded by the BOX' edge instead of the run is caught",
                  bool(fires(check_live_reuse))))
    reset()

    with_source("if(BaseKnotBarBodyInside(e, top, bot)) { lo = e + 1; break; }", "")
    cases.append(("a window that runs past a NEWER base is caught (it would reuse across it)",
                  bool(fires(check_live_reuse))))
    reset()

    with_source("if(head > BK_BASE_SKIP) lo = head - BK_BASE_SKIP + 1;", "")
    cases.append(("a window with no anchor budget is caught",
                  bool(fires(check_live_reuse))))
    reset()

    with_source("else { s_bkLiveLo = 0; s_bkLiveHi = -1; }", "{}")
    cases.append(("a cache that keeps a window after finding no base is caught",
                  bool(fires(check_live_reuse))))
    reset()

    with_source("g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : t2", "t2")
    cases.append(("a pump reading the story from the box' edge again is caught",
                  bool(fires(check_node))))
    reset()

    # P-BK-52: the ceiling — the pair, its unit, its gate and the retired unbounded path
    with_source("   offPips  = BaseKnotLegPick(planO, hunt ? BaseKnotNodeHuntPips(top, bot) : capE);",
                "   offPips  = planO;   // the plan's leg, unbounded again")
    cases.append(("an entry sized off the plan with no ceiling is caught",
                  bool(fires(check_leg_fit))))
    reset()

    with_source("   double p = BaseKnotLegPick(BaseKnotEngPips(tfMin, anchor), BaseKnotNodeEngPips(top, bot));",
                "   double p = BaseKnotEngPips(tfMin);   // the R, off the plan again")
    cases.append(("a printed R that ignores the ceiling is caught", bool(fires(check_leg_fit))))
    reset()

    with_source("   if(BaseKnotLegCapped(plan, cap)) return BaseKnotCapTag(false);", "")
    cases.append(("a name that stops following the pick is caught", bool(fires(check_leg_fit))))
    reset()

    with_source("#define BK_NODE_POWER_DIV 4.266666", "#define BK_NODE_POWER_DIV 1.2")
    cases.append(("a node divisor that leaves the box' far edge reachable is caught",
                  bool(fires(check_leg_fit))))
    reset()

    with_source("#define BK_NODE_HUNT_NUM  5.0", "#define BK_NODE_HUNT_NUM  8.0")
    cases.append(("a node Hunt leg that stops being the plan's own unit is caught",
                  bool(fires(check_leg_fit))))
    reset()

    with_source("#define TRADEPLAN_ENG_DIVISOR  4.266666",
                "#define TRADEPLAN_ENG_DIVISOR  4.0", path=PLAN)
    cases.append(("drift on the PLAN's side of the shared divisor is caught",
                  bool(fires(check_leg_fit))))
    reset()

    with_source("   if(pip <= 0.0 || BK_NODE_HUNT_DEN <= 0.0) return 0.0;",
                "   if(pip <= 0.0) return 0.0;   // the divisor unguarded")
    cases.append(("an unguarded node divisor (a Zero Divide) is caught",
                  bool(fires(check_leg_fit))))
    reset()

    with_source("   // BKATRLEG-OFF: double risk = BaseKnotEngPips(mtf) * pip;",
                "   // the retired pair is gone, not restorable")
    cases.append(("a retired unbounded pair that was rewritten away is caught",
                  bool(fires(check_leg_fit))))
    reset()

    # P-BK-79: every number is read AS OF the box' own bar — the pair, the read, the pump
    # and the call sites. Each way back to a TF-keyed (live) read is caught.
    with_source("         for(int j = 0; j < n; j++) if(mins[j] == asked[a] && anchors[j] == an) { dup = true; break; }",
                "         for(int j = 0; j < n; j++) if(mins[j] == asked[a]) { dup = true; break; }")
    cases.append(("an ask list that dedups on the TF alone (two boxes, one row) is caught",
                  bool(fires(check_asof))))
    reset()

    with_source("      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor) return s_bkEngPips[i];",
                "      if(s_bkEngTF[i] == tf) return s_bkEngPips[i];   // the TF alone, live again")
    cases.append(("a reader that matches on the TF alone is caught", bool(fires(check_asof))))
    reset()

    with_source("      if(!TradePlanCompute(mins[i], plan, anchors[i]))",
                "      if(!TradePlanCompute(mins[i], plan))   // the LIVE row again", path=EVENT)
    cases.append(("a pump that computes every row at the live bar is caught",
                  bool(fires(check_asof))))
    reset()

    with_source("   nd.anchor = (anchor > 0 ? anchor : 0);",
                "   nd.anchor = 0;   // the anchor, re-derived from nowhere")
    cases.append(("a read that drops the anchor it was handed is caught",
                  bool(fires(check_asof))))
    reset()

    with_source("   BaseKnotCalcLevels(top, bot, dir, nd.kind, baseTF, entry, sl, nd.anchor);",
                "   BaseKnotCalcLevels(top, bot, dir, nd.kind, baseTF, entry, sl, 0);")
    cases.append(("a committed box drawn off the LIVE row is caught", bool(fires(check_asof))))
    reset()

    with_source("      if(tfNew[i] != s_bkEngTF[i] || anNew[i] != s_bkEngAnchor[i] ||",
                "      if(tfNew[i] != s_bkEngTF[i] ||")
    cases.append(("a moved anchor that no longer re-arms the gate is caught",
                  bool(fires(check_asof))))
    reset()

    with_source("#define BK_ENG_ROW_MAX 48",
                "#define BK_ENG_ROW_MAX 48\n#define BK_ENG_TF_MAX 10")
    cases.append(("the half-renamed TF-only bound coming back is caught",
                  bool(fires(check_asof))))
    reset()

    # P-BK-53: the chart's own label is a NAME — the proof belongs to the hover
    with_source('   return (isHunt ? "node HuntSL" : "node EngSL");',
                '   return (isHunt ? "the node\'s own HuntSL (its height x 5/8)"\n'
                '                  : "the node\'s own EngSL (its height / 4.2667)");')
    cases.append(("the formula smuggled back onto the chart's label is caught",
                  bool(fires(check_label_short))))
    reset()

    with_source('   return " — CAPPED by " + BaseKnotCapWhy(isHunt) + " = " '
                '+ DoubleToString(cap, 1) + " pips";',
                '   return " — CAPPED by " + BaseKnotCapTag(isHunt) + " = " '
                '+ DoubleToString(cap, 1) + " pips";')
    cases.append(("a clause that prints the short name where the proof belongs is caught",
                  bool(fires(check_label_short))))
    reset()

    with_source("   if(BaseKnotLegCapped(plan, cap)) return BaseKnotCapTag(false);",
                "   if(BaseKnotLegCapped(plan, cap)) return BaseKnotCapWhy(false);")
    cases.append(("a note that prints the proof instead of the name is caught",
                  bool(fires(check_label_short))))
    reset()

    # P-BK-54: the note is read at a glance — the target field and the unit word stay out
    risk_and_height = "+ DoubleToString(hPips, 1) + BaseKnotHeightTag(top, bot, riskTag) + barsPart"
    with_source(risk_and_height,
                "+ DoubleToString(hPips, 1) + \" Pips\" + BaseKnotHeightTag(top, bot, riskTag) + barsPart")
    cases.append(("a unit word smuggled back onto the note is caught",
                  bool(fires(check_note_fields))))
    reset()

    with_source(risk_and_height,
                "+ DoubleToString(hPips, 1) + tpTag + BaseKnotHeightTag(top, bot, riskTag) + barsPart")
    cases.append(("the plan's targets printed on the note again are caught",
                  bool(fires(check_note_fields))))
    reset()

    with_source("const double hPips, const string tpTip,\n",
                "const double hPips, const string tpTag, const string tpTip,\n")
    cases.append(("a note writer that takes a target field again is caught",
                  bool(fires(check_note_fields))))
    reset()

    with_source("   string tpTip = BaseKnotTPPlanTip(baseTF, entry, dir, hPips, nd.anchor);",
                "   string tpTip = \"\";   // the hover lost the legs")
    cases.append(("a hover that dropped the plan's own legs is caught",
                  bool(fires(check_note_fields))))
    reset()

    # P-BK-57: the box' own height on the note — bare, one owner, written ONCE
    with_source('   return " | " + DoubleToString(p, 1);',
                '   return " | " + DoubleToString(p, 1) + " pips";')
    cases.append(("a unit word back on the note's own height is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source('   return " | " + DoubleToString(p, 1);',
                '   return " | (box) " + DoubleToString(p, 1);')
    cases.append(("a NAME back on the note's bare second number is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source('   if(riskTag == BaseKnotBoxHeightTag()) return "";   // the risk already IS this height',
                '   if(riskTag == "never") return "";   // a guard that never fires')
    cases.append(("the box' height printed beside a risk that already IS it is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source("   double p = BaseKnotToPips(top - bot);",
                "   double p = (top - bot) / BaseKnotPipSize();   // a second spelling")
    cases.append(("a second owner of the box' height is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source('   return BaseKnotBoxHeightTag();', '   return "box height";   // the name, spelt again')
    cases.append(("a fallback name the height field cannot test itself against is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source("box height (top - bottom) = ", "")
    cases.append(("a hover that left the note's second number unnamed is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source('          (riskTag == BaseKnotBoxHeightTag()\n'
                '           ? "and it IS the risk above: the note prints it once"\n'
                '           : "the note\'s own second number, in pips");',
                '          "the note\'s own second number, in pips");   // the fallback test, gone')
    cases.append(("a hover whose second copy stopped testing the fallback risk is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source("BaseKnotHeightTip(top, bot, riskTag) +   // P-BK-57",
                "\" pips\" +   // the writer spells it itself again")
    cases.append(("a note writer that spells the height's arithmetic itself is caught",
                  bool(fires(check_note_height))))
    reset()

    with_source("+ DoubleToString(hPips, 1) + BaseKnotHeightTag(top, bot, riskTag) + barsPart",
                "+ DoubleToString(hPips, 1) + barsPart")
    cases.append(("a note that dropped the box' own height again is caught",
                  bool(fires(check_note_fields))))
    reset()

    # P-BK-58: the note's two homes — every silent breakage has its own mutant
    with_source("   if(BaseKnotNoteInCorner()) return false;   // P-BK-58: the note's home is the family's column",
                "   // seed: the box-side note stays in the corner mode too (two copies)")
    cases.append(("a mode that leaves TWO copies of the note is caught",
                  bool(fires(check_note_home))))
    reset()

    with_source("   BaseKnotNoteCornerRefresh();\n", "")
    cases.append(("a row nobody keeps is caught", bool(fires(check_note_home))))
    reset()

    with_source("   if(g_bkState == BK_PREVIEW)\n   {\n      s_bkCornerDirty = true;",
                "   if(false)\n   {\n      s_bkCornerDirty = true;")
    cases.append(("a keeper that re-decides nothing after a cancelled band is caught",
                  bool(fires(check_note_home))))
    reset()

    with_source("   if(id == s_bkCornerId && !s_bkCornerDirty)\n",
                "   if(false)\n")
    cases.append(("a per-round row rebuild is caught", bool(fires(check_note_home))))
    reset()

    with_source("      if(id == \"\" || ObjectFind(0, nm) >= 0) return;\n", "")
    cases.append(("a row that never heals after a chart cleanup is caught",
                  bool(fires(check_note_home))))
    reset()

    with_source('      if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED)) return g_bkBoxes[i].id;   // clicked = the answer',
                '      // seed: the user\'s own selection is ignored')
    cases.append(("a row that ignores the user's selection is caught",
                  bool(fires(check_note_home))))
    reset()

    with_source("   ObjectSetInteger(0, o, OBJPROP_XDISTANCE, MathMax(8, s_bkCornerX));",
                "   ObjectSetInteger(0, o, OBJPROP_XDISTANCE, MathMax(8, inpLabelsMarginLeft));")
    cases.append(("a module that guesses the column's margin is caught",
                  bool(fires(check_note_home))))
    reset()

    with_source("      if(ObjectFind(0, in) >= 0) ObjectDelete(0, in);   // the box-side copy goes with the mode that wanted it",
                "      // seed: the box-side copy is left behind (two objects hold one note)")
    cases.append(("a writer that leaves the other home filled is caught",
                  bool(fires(check_note_home))))
    reset()

    with_source("   bool atCorner = BaseKnotNoteAtCorner(id);",
                "   bool atCorner = BaseKnotNoteInCorner();   // the decision owner is bypassed")
    cases.append(("a caller that decides the home for itself is caught",
                  bool(fires(check_note_home))))
    reset()

    # P-BK-55/78: the sizing note stops answering the type again (a class with no type)
    with_source("   ndLive.kind   = BaseKnotNodeKindOfLength(liveClass, ndLive.height, ndLive.anchor);",
                "   ndLive.kind   = BK_NODE_NONE;   // the sizing note claims no type again")
    cases.append(("a sizing note that answers no type is caught",
                  bool(fires(check_note_life))))
    reset()

    # P-BK-55: the live half starts claiming a STORY it never read
    with_source("   ndLive.baseStep = 0.0; ndLive.breakStep = 0.0; ndLive.retStep = 0.0; ndLive.storyTF = 0;",
                "   ndLive.baseStep = 0.0; ndLive.breakStep = 0.0; ndLive.retStep = 0.0; ndLive.storyTF = Period();")
    cases.append(("a sizing note that claims an unread story is caught",
                  bool(fires(check_note_life))))
    reset()

    # P-BK-56: the note goes back to its own font / size rung / box art rung
    with_source("   ObjectSetString(0, o, OBJPROP_FONT, inpFontName);   // P-BK-56: the label family's own font",
                '   ObjectSetString(0, o, OBJPROP_FONT, "Arial");')
    cases.append(("a note that drops the family's font is caught", bool(fires(check_note_life))))
    reset()

    with_source("   return ClampSettingInt(inpFontSize, 4, 24);         // P-BK-56: the label family's grid",
                "   return ClampSettingInt(g_bkTextSize, 8, 24);   // the box' own text size again")
    cases.append(("a note sized off the box' text again is caught", bool(fires(check_note_life))))
    reset()

    with_source("   ObjectSetInteger(0, o, OBJPROP_ZORDER, Z_CHART_LABEL);",
                "   ObjectSetInteger(0, o, OBJPROP_ZORDER, Z_BOX_INFO);")
    cases.append(("a note dropped under the chart art again is caught",
                  bool(fires(check_note_life))))
    reset()

    # the model's own teeth: the old rules must be caught by the same promises
    sc = model_scenes()
    base = sc["base"]
    extended = base + [True] * 60          # an older ranging stretch inside the band
    v2 = lambda flags, left, right: sum(1 for i in range(left, right + 1) if flags[i])
    cases.append(("the old body-in-box rule fails the drag promise",
                  v2(extended, 40, 58) != v2(extended, 40, 129)))
    cases.append(("the anchored walk keeps it", walk(extended, 40) == 19))
    cases.append(("the retired reach rule counted the box (38 for this nine-candle base)",
                  walk_v37(sc["zone"], 1) == 38 and walk(sc["zone"], 1) == 9))
    cases.append(("the retired anchor rule printed «1 bars» for the congested box",
                  walk_v41(sc["crowd"], 0) == 1 and walk(sc["crowd"], 0) == 9))
    cases.append(("the retired edge-bound end lost the base's newer half (the 20 vs 36)",
                  walk_v43(sc["base"], 50) == 8 and walk(sc["base"], 50) == 19))
    cases.append(("the retired strict rule cuts the base on ONE poke",
                  walk_v31(sc["poked"], 40) == 10))
    cases.append(("... while the tolerant walk keeps the base's whole story (the poke is inside it)",
                  walk(sc["poked"], 40) == 19))
    cases.append(("the tolerance WITHOUT the confirmation inflates the entry side",
                  walk_gap_only(sc["entry"], 40) == 20 and walk(sc["entry"], 40) == 19))
    cases.append(("the left-edge sweep is clean (positive control)",
                  check_invariance()[0][1]))

    for name, ok in cases:
        print("%-56s %s" % (name, "caught" if ok else "MISSED"))
    missed = [n for n, ok in cases if not ok]
    if missed:
        print("\nselftest FAILED: %d fault(s) went undetected" % len(missed))
        return 1
    print("\nselftest: %d/%d faults caught - the audit is not vacuous" % (len(cases), len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
