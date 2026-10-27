# The Base Knot dataset — one row per knot, one ruler, one score

The base for tuning the knot's formula on evidence instead of memory. The TH3 dataset
([th3-dataset.md](th3-dataset.md)) is the same shape: a folder per sample, one CSV index,
one page, and a review file that keeps the human verdict out of the data.

**This file is the contract for a BK sample.** A row that does not satisfy §3 is not a
sample — it is a transient, and it is dropped before it can poison a statistic.

## 1. Three decisions, three rulers

A knot answers three questions, and today each one is measured on its own bar. They are
kept apart here because a change in one must never look like noise in another:

| # | decision | owner | ruler |
|---|---|---|---|
| D1 | **owner TF** — which rung "owns" the box | `BaseKnotOwnerTFWalk` | `h / ATR(box edge)`, must land in 2.40..3.60 |
| D2 | **type** — FTR / ETR / CTR / OTR | `BaseKnotNodeKindOfLength` | `h` against `ATR(story anchor)` of the node rung and the two above |
| D3 | **the three components** — entry, stop, TP1..3 | `BaseKnotCalcLevels`, `BaseKnotTPLevel` | entry: node rung's leg at the story anchor · stop: type rung's EngSL · TP: stop rung's legs |

D1 and D2 do **not** read the same bar. `[BK-OWNER]` prints the ATR at the **box edge**
(`BaseKnot_Owner.mqh:143`, `an`), while `[P-BK-107]` prints the ATR at the **story anchor**
(`anStory`, P-BK-115d). Measured in the four seed samples: 3 of 4 carry two different bars.

```
CTR  11:22:17.490  [BK-OWNER] atr=46.3  r=2.78  anchor=2026.10.23 17:15
CTR  11:22:17.998  [P-BK-107] ATR=43.4  type=CTR  anchor=2026.10.23 16:55
```

That is why every row stores **both** anchors. A sample sheet that keeps only one cannot
say which bar typed the knot, and a formula change cannot be attributed.

## 2. The score — what "better" means

Three candidate scores; the user picks one (or a weight) before the first 100 samples:

1. **TURN** — distance in pips from the entry line to the actual turn (`Error_Pips`, the
   TH3 dataset's own column). Cheap, objective, works without a trade.
2. **SURVIVAL** — did TP1 print before the stop? One bit per sample; the only score that
   speaks for all three components at once.
3. **R** — realised `R` at a fixed horizon (TP1/TP2/TP3 or stop).

Until a score is chosen, the dataset only **describes**; it cannot rank two formulas.

## 3. The gate — when a row is a sample

A row is written only when these hold, read from ONE capture moment:

- `[BK-OWNER]`, `[P-BK-107]` and `[BK-PIP]` carry the **same `box=` id**;
- `boxPips` on `[BK-OWNER]` equals the `h` implied by `[P-BK-107]`'s bands (±0.1);
- `[P-BK-107]` has a non-empty `type=` (a second pass wrote it);
- the `[BK-PIP]` numbers are the ones drawn (it is the ink's own read-back);
- the capture is **after** a committed sync — a row cut between a drag release and the next
  `[P-BK-107]` belongs to neither state.

The same box may appear twice (a drag changes `h`): that is two samples, not a duplicate,
and the `Box_ID` + `Capture_Clock` pair is what tells them apart.

## 4. Layout

```
Samples/BK_Dataset/
  Dataset.csv          the index — one row per sample, 34 columns
  Reviews.csv          Sample_ID,Verdict,Note,Reviewer,Reviewed_At  (the human verdict)
  journal.md           append-only history of reviews and formula versions
  Samples/<id>/        the sample's own files:
                         notes.md   the conversation about this sample (## <stamp> blocks)
                         *.png/jpg  the screenshots, as many as it takes
  dashboard.html       generated — the page (images by relative path)
```

A row may exist before its folder (the numbers come first, the screenshot follows). The
folder is named `<id>` (e.g. `BK-0005`), so the CSV's key is the folder's name and no
lookup table is needed.

## 5. The columns

| group | columns |
|---|---|
| who/when | `Sample_ID`, `Capture_Date`, `Capture_Clock`, `Symbol`, `Chart_TF`, `Node_TF`, `Box_ID` |
| the ruler | `Story_Anchor`, `Edge_Anchor`, `Box_Pips`, `ATR_Trig`, `ATR_Pat`, `ATR_Str`, `ATR_Fourth` |
| D2 | `Band_FTR`, `Band_ETR`, `Band_CTR`, `Type`, `Edge_Margin_Pips` |
| D3 | `Entry_Off_Pips`, `Stop_Pips`, `Stop_V1_Pips`, `TP1_Pips`, `TP2_Pips`, `TP3_Pips` |
| sizing | `PerPip`, `Balance`, `Risk_Pct`, `Lot`, `Risk_USD` |
| outcome | `Direction`, `Verdict` (in Reviews.csv), `Note` |
| files | `Log_File`, `Log_Lines`, `Screenshot` |

`Edge_Margin_Pips` is derived, not typed: the distance from `Box_Pips` to the nearest band
it did **not** cross. It is the first statistic to look at — a type decided by half a pip
is a coin flip, and the dataset must show how often that happens.

`ATR_Fourth` is the rung **above** `ATR_Str` (+3), read at the same anchor. It is only needed
by an OTR row — the OTR stop is `ATR_Fourth / 4.2666` — but without it `u` (the ladder
coordinate, §6) cannot be computed for exactly the rows under investigation. Empty means
"not recorded", never zero.

`u` is **not** a column. It is the position on the ladder:
`0` at `ATR_Trig`, `1` at `ATR_Pat`, `2` at `ATR_Str`, `3` at `ATR_Fourth`, interpolated in
`ln(h)` since v7 (P-BK-128), so the four type names are bands of one coordinate — FTR `u≤0.5`,
ETR `≤1.5`, CTR `≤2.0`, OTR above. The
indicator prints it at capture (`BaseKnot_Shot.mqh`, `BaseKnotLadderU`), the site re-derives
it from the same four numbers, and the two agree by construction because neither stores a
second copy. A v6 row's `u` was the linear one; the two disagree by up to ~0.05 rung and are
only comparable within one version.

`Stop_V1_Pips` is the one column that exists **only** so a decision can be made later: it is
what formula v1 would have charged for the same box, asked of the same geometry owner at the
same anchor with the name's own hop (`hop = -1`). v1 and v2 differ only near a band edge, and
the ATR rows of a closed box cannot be reproduced a week later — so without this column the
20-sample checkpoint would need a second capture session instead of a subtraction.

## 6. The loop

1. append rows (`tools/bk-dataset-check.py` validates every one);
2. read the margin distribution and the score by type;
3. change **one** rule, bump `Formula_Version` in the journal;
4. re-score the same rows against the new rule — the rows never change, the rule does;
5. keep the version that wins on the whole set, not on one sample.

Nothing in the indicator changes until a version wins on the dataset. A formula that is
better on 4 samples and worse on 400 is not better.

## 7. The words and the pictures live with the sample

A number is not a sample. The reason a knot looked right or wrong is a sentence someone
wrote while looking at the chart, and it belongs beside that knot — not in a chat log, not
in a file named after the day.

```
node tools/bk-dataset-dashboard.js note   BK-0005 "ورود دقیقاً روی چرخش نشست؛ استاپ زیر لج بود"
node tools/bk-dataset-dashboard.js attach BK-0005 shot-1.png shot-2.png
node tools/bk-dataset-dashboard.js review BK-0005 real "چرخش تمیز"
```

- `note` appends a `## <stamp>` block to `Samples/<id>/notes.md` — append-only, so the
  history of what was believed about that knot survives a change of mind;
- `attach` copies the files into `Samples/<id>/` (the page finds them by extension, so no
  column has to name them);
- `review` writes the one current verdict into `Reviews.csv` and a line into `journal.md`.

The dashboard shows, per sample: the numbers, both anchors, the log lines, every image as a
thumbnail, and the notes in order. Two to four samples can be ticked in the table and are
then compared column by column — same units, same columns, so a difference is a difference
in the knot and not in the sheet.

## 8. The routine — press, file, talk, decide

Four steps, one action each. Every handoff between them is a **file on disk**, so any step can
be re-run alone, out of order, a week later, without asking the step before it what it meant.

### 1 · Capture — press `K` on the chart

Select a knot (click its rectangle), press `K`. That is the whole interaction. The indicator
writes one folder per press:

```
<data folder>\MQL4\Files\BK_Dataset\Samples\<box id>_<yyyymmdd-hhmmss>\
    shot.png      the chart, at 1:1 chart pixels, no rescale, no crop
    sample.txt    37 `Key: Value` lines, names identical to the CSV columns
```

and prints one receipt on the flushed diag channel:

```
[BK-SHOT] id=5_999001 dir=5_999001_20260915-100012 shot=1 txt=1 type=CTR h=129.0 u=1.884 stop=31.9 off=0.0
```

The numbers in that line are **read back off the ink** — `top/bot/t1/t2` from the rectangle,
`entry/sl/tp1..3` from the `ENTRY`/`SL`/`TP` labels, `a0..a3` from the ability rows. Nothing is
re-derived from settings, so a row cannot describe a stop the chart is not drawing. That is the
one property this whole dataset depends on.

`K` is free because it is the one letter the panel's own hotkeys leave unclaimed (`F L G V C T E
R A S W Q X D P B M` and `ESC` are taken). The build refuses instead of guessing:

```
[BK-SHOT] refused: no box on the chart
[BK-SHOT] refused: box=5_999001 is not in the registry
[BK-SHOT] refused: box=5_999001 has no rectangle on the chart
[BK-SHOT] refused: box=5_999001 has no height
[BK-SHOT] refused: FolderCreate failed for ...
```

A refusal writes **no folder and no row** — an absent sample is recoverable, a wrong one is not.
The confirmation is a label drawn on the chart for **one second** — the user's order on
2026-10-27 («یک ثانیه بس هستش برای این») — sized from its own string so it never wraps, and never
slept for. It answers the press in the three facts a trader checks —
`SAVED  <type> <node TF>  <height>p  <hh:mm:ss>`, e.g. `SAVED  ETR 31m 119.9p 15:43:01` — and
says `NOT SAVED  <reason>` (or `NOT SAVED  png=0 txt=1`) when a file did not land. It is deleted
by `BaseKnotShotFlashTick()` from **OnTimer**, not from the tick, so a chart that stops ticking (a
weekend, a dead symbol) cannot keep the receipt on the screen for ever — the same debt
P-TH3-REC-04 paid for the `M` receipt. The label itself is witnessed on the flushed channel, read
back off the object it just created:

```
[BK-SHOT] flash obj=1 px=18 hold=1 text="SAVED  ETR 31m 119.9p 15:43:01"
```

`obj=0` means the label was never born (a capture that filed a sample and showed nothing), which
is a different defect from a label that exists and is not painted (P-LOG-10's class). Without that
line the two are one symptom.

### 2 · File — one command

```
node tools/bk-shot-sync.js             # file everything waiting, then rebuild the page
node tools/bk-shot-sync.js --watch     # keep it running while you work (polls every 3 s)
node tools/bk-shot-sync.js --list      # what is waiting, and why it is not filed
node tools/bk-shot-sync.js --dry       # show the would-be rows, touch nothing
```

It scans **every** terminal data folder (not just the one in the current profile), skips leaves
already in the ledger `Samples/BK_Dataset/.filed.json`, assigns the next free `BK-00NN`, appends
the CSV row, writes a `notes.md` skeleton with the numbers already in it and two empty headings
(`## روایت`, `## تصمیم`), and rebuilds the site. Two guards exist because both fired for real:

- **digits are part of a key** — `TP1_Pips` was once parsed as key `TP` with value `1_Pips`;
- **a blank column refuses the row** — an empty cell is a claim ("not recorded"), a missing cell
  is a hole, and the two are indistinguishable later. `PerPip` was filed empty once; the row is
  now refused instead.

### 3 · Talk — the note *is* the sample

This is the part that cannot be automated: the second screenshot, the sentence about why the stop
sat where it sat, the chat excerpt. Attach them to the sample, not to the day.

```
node tools/bk-dataset-dashboard.js note   BK-0005 "ورود دقیقاً روی چرخش نشست؛ استاپ زیر لج بود"
node tools/bk-dataset-dashboard.js attach BK-0005 shot-1.png shot-2.png
node tools/bk-dataset-dashboard.js review BK-0005 real "چرخش تمیز"
node tools/bk-dataset-dashboard.js --open
```

`review` is the only step that writes a verdict, and it writes exactly one current verdict per
sample — changing your mind overwrites the verdict, never the note.

### 4 · Decide — only when a version wins

A formula change is a `Formula_Version` bump plus a **re-score of the same rows**. The capture
stamps the version it wrote, so every row says which rule produced it, and two rows captured
before and after a change are never silently averaged.

v2 was applied on 2026-10-27 (`hop = round(u)`, §9) because a rule that is wrong for the
**twins** makes every sample filed under it misleading. The verdict on v2 is still open: it is
the 20-sample checkpoint, and each row carries both numbers so the comparison needs no second
trip to the chart.

### What breaks, and what it means

| you see | it means | do |
|---|---|---|
| `refused: … not in the registry` | a stale rectangle from an older session, or a box whose node index was rebuilt | click the box again; if it still refuses it is not a node of the current ladder |
| `refused: … has no height` | the two rectangle edges are equal | the box is degenerate — delete and redraw |
| `[skip] … missing keys: TP1_Pips` | the sidecar came from an older build | recompile, press `K` again; never hand-edit the txt |
| `column(s) would be blank: PerPip` | the build and the CSV disagree on a name | the sync refuses on purpose — recompile, re-capture |
| a card shows `u = -1` | no fourth rung was recorded | fill `ATR_Fourth` only if the OTR stop makes it measurable; otherwise leave it empty |
| harness: `MetaTrader is already running (…). Close it first` | an ini launch while a terminal owns that data folder is a silent no-op | close the terminal; the message names the running window |

### The harness — proving the capture, not trusting it

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-bk-test.ps1 `
    -Harness Biotak_BaseKnot_Shot_Test -Tag BKSHOT -Symbol XAUUSD -Period M5
```

`tests/Biotak_BaseKnot_Shot_Test.mq4` builds one CTR box, draws the legs at the plan's own
prices, calls the production capture, and asserts every key in the written record against the
values it drew — then deletes its own folder, because a leftover fixture would be filed as a
real sample.

### Why this order

Capture first, because the numbers must come from what is drawn. File second, because a folder
that is not in the CSV does not exist to any later step. Talk third, because a note written
before the picture is a prediction. Decide last, because a rule chosen before the data is a
guess with a version number on it.

## 9. The first formula change — v2, decided on four rows

**The call (2026-10-27).** Option 1 *now*: apply the formula and bump `Formula_Version` to
`v2`, so every sample captured from today is scored by one rule. Option 2 *at 20 samples*:
decide which version stands, on the same rows. The reasoning was the user's own — option 1
costs one compile and makes the data comparable from today; option 2 without enough samples
only adds another version nobody can call better.

**The change.** The stop's rung is `hop = round(u)` — the **nearest** rung of the ladder —
instead of the type name's fixed hop (FTR 0 / ETR 1 / CTR 2 / OTR 3). `BaseKnotMeasureHops`
now takes the hop as an argument; `BaseKnotLadderHopAt` computes it; `-1` keeps the old name's
answer for the callers that cannot know the box (the live preview, a cold ladder).
**Superseded the same day by P-BK-128 (§18): `round(u)` was still a price midpoint on the leg,
so the same 217-pip box paid 84.5 or 188.0. The rung is now the deepest leg PACKAGE that fits —
the argument, the `-1` fallback and every call site are unchanged.**

**Why it could not wait for the samples — the twins:**

| row | `u` | stop v2 | stop v1 |
|---|---|---|---|
| BK-0003 | 1.884 | 31.9 | 31.9 |
| BK-0004 | 2.003 | **31.9** | **72.9** |

Same box, four seconds apart, +7.8 pips (+6.0 %) taller. v1 charged the second one **2.28×**
the first, because the type name flipped CTR → OTR at `u = 2.0` and the stop jumped a whole
rung with it. A dataset that files both rows under v1 teaches the formula the wrong lesson;
under v2 both rows say what a trader would actually have done.

**What did not change — the knot's time.** «قبلا از چه روش برای تایم گره استفاده میکردم از
همون باشه»: the ATR row is `(TF, ANCHOR)` and the anchor is the box' own story end, never
"now" (P-BK-79). The new read had every chance to ask the live row, so it is pinned twice:

- `BaseKnotLadderHopAt` is *handed* the anchor and passes it to `BaseKnotAbilityGet`; a box with
  no story answers `-1` rather than the live row (`BaseKnotBoxHop`);
- `BaseKnotAnchorAt` is untouched — story end first, the box' right edge as the only degradation;
- the rule is **`P-BK-79`** in the gate, on its own line, checking every site at once: the
  anchor's owner, the table's `(TF, anchor)` key, `BaseKnotNodeRead` not deriving its own bar,
  the pump's ask, the committed read, the drag, the capture, and that no reader of the type or
  the ladder says `TimeCurrent()`. Two mutations (`P-BK-79-a/b`) kill it — the table losing its
  second key, and the committed read asking "now".

**What it cost.** `BaseKnot_Nodes.mqh` sat exactly on the 1500-line ceiling, so the ladder's
table and its reads moved to `Biotak/BaseKnot_Ability.mqh` (contract §7). The pump's ask list
now also carries the **fourth** rung for an OTR box — without it the ladder read would
oscillate between hop 2 and hop 3 as the row it needs appears and disappears.

**What proves it.** `tests/Biotak_BaseKnot_Shot_Test` — 33 assertions in MT4, including the
five heights on the ladder, the twins' 31.9 vs 72.9, and the read-back of every column.
`tools/check-regressions.js` **P-BK-125** pins the rule, the four call sites that must agree,
and the knot's time; two mutations (`P-BK-125-a/b`) prove the pin is alive.

**The 20-sample checkpoint.** Every capture now writes `Stop_V1_Pips` beside `Stop_Pips`, so
the comparison is a subtraction on rows already on disk. The site shows `N/20` and switches
its next-step strip to "وقتِ بازبینی نسخه" at 20. Until then, the answer is more samples —
not another version.

## 10. The knot's own time — measured, and off the ladder

**The user's definition (2026-10-27), verbatim:** «هر کدوم سه تا کندل درجا زدن داشته باشه اون
تایم تایم گره هستش ... حتی اگر در تایم های متاتریدر نباشه ... قانون سه کندل درجا زدن که نتونه
بالا و پایین هم کلوز بزنه». Three candles **stand still** when a candle cannot make a high,
cannot make a low and cannot close outside the box — `high <= top`, `low >= bot`, close
inside — three in a row. The knot's time is the **highest** timeframe on which that still
holds: the biggest grid on which the stall is still visible (the reading P-BK-77 already
states — «the biggest time in which the three candles are still visible»).

**The measurement.** `tools/bk-knot-scan.py` reads the terminal's own M1 series
(`history/AMarkets-Demo/XAUUSD1.hst`, 52 684 bars), rebuilds **any** timeframe from it, and
for each dataset row takes the three bars of a T-grid whose last bar closes exactly on the
box' `Story_Anchor` — the knot's own grid, aligned to the box rather than to the epoch. Three
candles fit a box of that height **iff** their span is `<=` the height, which is the whole of
the rule for a box that sits over them. The box' own prices are on no disk (no `THLevels_BK`
object in any saved chart, no price in the journal), so the scan works from what *is* on disk:
the height and the right edge.

| row | anchor | box | node | **knot's time** | 3-candle span | fill | breaks at | the ladder says |
|---|---|---|---|---|---|---|---|---|
| BK-0001 | 2026.10.23 20:04 | 23.8 | M1 | **2m** | 22.2 | 93.3 % | 3m @ 26.8 | 1m |
| BK-0002 | 2026.10.22 06:00 | 169.8 | M15 | **45m** | 165.4 | 97.4 % | 60m @ 187.7 | 15m |
| BK-0003 | 2026.10.23 16:55 | 129.0 | M5 | **8m** | 126.8 | 98.3 % | 9m @ 129.9 | 5m |
| BK-0004 | 2026.10.23 16:55 | 136.8 | M5 | **9m** | 129.9 | 95.0 % | 10m @ 160.9 | 5m |

**Four for four, the knot's time is not a MetaTrader timeframe** — 2, 45, 8, 9 minutes; none
of them is M1 · M5 · M15 · M30 · H1 · H4 · D1 · W1 · MN1. And four for four, `fill` is 93–98 %:
the three candles fill the box almost exactly, which is what a box drawn *around* them looks
like. `fill` is the check on the rule, not a proof of it — it says the box and the three
candles are the same object to within a few pips.

**One bound the scan does NOT carry, and the engine does.** The scan bounds the knot by the
box' **height** only. The indicator also bounds it by the base's own **time span** —
`3 × T <= bars × commitTF` — because three candles of `T` have to fit inside the base, not just
inside the rectangle. On a wide base the two agree (that is why the table above and the engine
land in the same place); on a **narrow** base the engine's answer is the lower one. BK-0001 is
the row to watch: 23.8 pips on an M1 node is a base only a few minutes wide, so 2m needs six
minutes the base may not have, and the engine may name M1 where the scan names 2m. The engine's
number is the one that counts, and the next capture's `Node_TF` is what reads it.

**Why the ladder can never name it.** `BaseKnotNextTFMin` steps `1 → 5 → 15 → 60 → 240 →
1440 → 10080 → 43200`. The steps are 3×–4×, and three candles of a rung are 3×–4× taller than
three candles of the rung below — so the moment a box is too tall for a rung, it is far too
short for the next one. The scan shows the consequence directly: the ladder's answer is the
**node's own TF on every one of the four rows** (1m, 15m, 5m, 5m). The stand-still walk never
confirms a higher rung, because there is no rung between 5 and 15 to confirm. A knot that
belongs to 8 minutes is invisible to a ladder that only knows 5 and 15.

**The two gaps in the code**, both narrower than the rule the user stated:

1. **Bodies, not candles.** `BaseKnotRungHoldCount` asks `o >= bot && o <= top && c >= bot &&
   c <= top` — the body. The user's rule also refuses a candle that **pokes a wick** out of
   the box («نتونه بالا و پایین هم کلوز بزنه»). A candle whose high clears the top has made a
   high; it is not standing still.
2. **A fixed ladder, not every timeframe.** `BaseKnotLadderAll` walks the eight rungs above.
   The rule has to be able to answer 2, 8, 9, 45 — one-minute granularity, or nothing.

**What it costs to wire in.** The knot's TF is not decoration: the type is read on it
(`BaseKnotAbilityRead(tfMin, anchor, nd)`), so a knot of 8 minutes reads a *taller* ATR than
5 minutes does, the box becomes a smaller multiple of it, and the type moves **down** a band —
BK-0003's CTR would most likely read ETR, and the stop follows the band. That re-baselines
every row on disk, which is why it is a decision and not a patch.

**The knife edge, again.** BK-0003 (129.0 pips) lands on 8m and BK-0004 — the same box, four
seconds later, 7.8 pips taller — lands on 9m. One more minute of grid for one more pip of box:
the same fragility §1 says the dataset exists to measure, now showing up in the knot's own
time instead of in the type's margin.

**What is on disk now.** The tool (`tools/bk-knot-scan.py`), re-runnable:
`python tools/bk-knot-scan.py` for the four rows, or `--anchor "2026.10.23 16:55" --box 129.0`
for one box by hand.

## 11. The knot's time, wired in — P-BK-126

**The call (2026-10-27).** «میخوام به اون برگردیم فقط این روش تایم گره رو با چیزی که گفتم
اپدیت و بس». The stand-still rule is back as the **decider** (P-BK-84 had retired it in place),
and it is widened on the two counts the user named. Nothing else in the indicator moved.

**What changed, in three places:**

1. **`BaseKnotRungHoldCount` reads the WHOLE candle, on ANY timeframe.** The body-only test
   (`o`/`c` inside) is gone; the test is `high <= top && low >= bot`, which implies the close.
   The candles are **built from M1** on the CLOCK's grid (§13) — `BaseKnotM1Window` +
   `BaseKnotStillCount` — because MQL4 has no series for 2, 8, 9 or 45 minutes — a knot the
   ladder cannot name is now a knot the read can still measure.
2. **`BaseKnotBaseTFRead` walks every minute, highest first.** `tMax = spanMin / 3`, then
   `T` from `tMax` down to 1, returning the first time whose three candles still hold. The old
   arithmetic walk (`3 * rung <= spanMin` on the eight rungs) stays underneath as the
   **fallback** for a story the M1 series cannot reach — never as the answer while the candles
   are there to be read.
3. **`BaseKnotAbilityGet` answers an off-ladder time.** The table only holds the rungs the pump
   asked for, so an 8-minute knot is scaled from the nearest rung **below** it by the project's
   own √-law (`BaseKnotRungScale`) — the same law the function already falls back on when an
   upper row is cold. A time with no rung under it still answers `false`.

**What it cost.** `BaseKnot_Nodes.mqh` 1371 → 1423 lines (P-SIZE-1500 green). The M1 read is
bounded (`BK_KNOT_M1_MAX` = one day) and the scan stops on the first time that holds, so a box
with a knot costs a handful of bucket passes; the answer is memoised on the same question as
before, so a sitting box is read once.

**What proves it.** `tests/Biotak_BaseKnot_Shot_Test` — **40 assertions, 0 failures** in MT4,
seven of them new and all seven on hand-built M1 windows, so they test the rule and not whatever
series the terminal happens to hold:

| assertion | got | want |
|---|---|---|
| a candle whose **wick** clears the box does not stand still | 2 | 2 |
| six still M1 candles → the count stops at 3 | 3 | 3 |
| the same six read at **2m** → three candles, all still | 3 | 3 |
| **3m** on the clock's grid → three buckets, all still | 3 | 3 |
| **8m** is read like any other time (never −1) | 2 | 2 |
| an edge 55 s further on cannot move the knot | 3 | 3 |
| no series → −1, never a 0 dressed up as an answer | −1 | −1 |

The 3m and 8m rows are §13's numbers: the edge-cut grid read **2** and **1** off the very same
bars, and the last row is the report itself — one band, one answer, whatever the edge does. Those
two rows were also re-derived after §12's run reset (which is what moved the wick row's count from
"any still candle" to the newest run of them).

The first row is the whole correction: the retired read asked open/close only and would have
answered **3** there. The regression gate is unchanged and green (171 PASS, 0 FAIL) — the rule
touches no gate-visible contract, which is why it needed assertions instead.

**What is NOT proven yet.** The four seed rows were measured offline (§10); the indicator has
not been re-run on them since, because their boxes have no prices on disk and no box is drawn
on the live chart. The first press of `K` on a real knot is what closes that gap — its
`sample.txt` carries `Node_TF` and the two anchors. **It does NOT carry `top`/`bot`** (the
`FileWrite` list in `BaseKnot_Shot.mqh` has no price field), so a captured row cannot be replayed
against `tools/bk-knot-scan.py`; the phase table in §13 was measured on a band taken off the
chart by hand. A price pair in the capture is the next thing that would make every row
re-runnable.

## 12. The knot's time, decided by the candles — P-BK-126b

**The report (2026-10-27).** «این گره الان توی تایم ۱۵ دقیقه دیده میشه ۳ کندل درجا زدن … پس چرا
زده برای ۵ دقیقه». The walk of §11 was wired in but had **no precedence**: `BaseKnotSync`
(P-BK-114) read the ATR owner first, so for a box with an owner — every box — `BaseKnotBaseTFMin`
was never called at all.

**Measured on that box** (`Story_Anchor 2026.10.27 08:30`, `Box_Pips 119.9`, XAUUSD M1,
`python tools/bk-knot-scan.py --anchor "2026.10.27 08:30" --box 119.9`):

| ruler | number | verdict |
|---|---|---|
| ATR band, M5 | 119.9 / 34.6 = **3.47** (band 2.40..3.60) | owner = **M5**, first try |
| ATR band, M15 | 119.9 / 66.6 = **1.80** (below 2.40) | M15 was never even considered |
| three candles, **M30** | span **119.2** pips of 119.9 = **99.4 %** | the box **is** three half-hour candles |
| three candles, **32m** | **123.4** pips | already breaks the box |
| three candles, **45m** | **252.4** pips | far outside |

Two rulers were live and they answer different questions: the class is the node's **time**
(P-BK-77/126), the ATR band is a **size**. So:

1. **The walk decides; the owner is the fallback** (`BaseKnot_Plan.mqh`, `BaseKnotSync`). A box
   whose M1 story cannot be read still names a time (P-BK-36's promise), but a box whose candles
   are there is named by them. P-BK-80 still holds: the class is read in `baseReadTF`, the box' own
   read TF (`ownerTFMin` or its commit TF), never the open chart.
2. **The run is three IN A ROW** (`BaseKnotStillCount`). A candle that poked out now resets the
   count. MEASURED on the same band: without the reset the walk answered **35..45m** (three
   scattered still candles at a coarser grid), with it **30..33m** — the three half-hour candles
   the box was drawn around, whichever phase of the grid the walk closes on (08:30, 08:33, 09:00,
   09:55, 10:30, 15:43).
3. **The pump's rows follow the class** (`BaseKnotOwnerATRPump`). The ATR owner used to override
   `baseTFMin` there, so an off-ladder class (31m) scaled its trigger from M5 — six rungs of air.
   The class wins; the owner fills in only before the first Sync.

**Formula v3.** `BK_FORMULA_VERSION` is `"v3"`: a row's `Node_TF`, its type and its stop are not
comparable with a v2 row's, and the capture's own header says so. Never mix the two in one score.

**The expected re-baseline of that box** (class ≈ 31m): `trig = ATR15 × √(31/15) ≈ 95.7`,
`pat = ATR60 = 135.2`, so the FTR ceiling is ≈ 115.5 and the ETR ceiling ≈ 227 → the type moves
**CTR → ETR**, and the stop's rung moves to H1 (`BaseKnotMeasureTFMin(ETR, 31, hop = 1)`
→ `NextTFMin(31) = 60`). A receipt may therefore carry a time MT4 has no period for
(`BaseKnotTFName(31)` → `31m`) — by design (P-BK-126).

**What proves it.** `P-BK-126b` in `tools/check-regressions.js` (walk-first precedence, the owner
fallback kept, `baseReadTF` still the box' own TF, the run reset, class-owns-rows in the pump, the
off-ladder curve) and five mutations `P-BK-126b-a…e` in `tools/mutation_gate.py` — **5 KILLED,
tree byte-identical**. P-BK-80's assertion was widened to accept `baseReadTF` with the reason
written beside it: the rule it protects is "the box' own TF, never the open chart", and
`P-BK-126b` pins that definition.

## 13. The grid is the clock's, not the box' — P-BK-126c

> **Superseded as the class' rule by §14.** The measurement and the fix below stand, and the
> count they made edge-independent is the hover's reported number now — the class reads no grid
> at all.

**The report (2026-10-27).** «تایم گره باید یکی باشه … با جابه‌جا کردن باکس عوض میشه». Two `K`
presses on ONE box (`Box_ID 15_20849875`), **10 seconds apart**, wrote two different knots:

| sample | `Node_TF` | `Story_Anchor` | `Edge_Anchor` | `Box_Pips` | `ATR_Trig` | `Type` | side |
|---|---|---|---|---|---|---|---|
| `15_20849875_20261027-164859` | **27m** | 08:40 | 08:00 | 124.2 | 66.6 | ETR | SELL |
| `15_20849875_20261027-164909` | **13m** | 13:50 | 15:15 | 112.3 | 35.6 | CTR | BUY |

**The cause, measured.** §11's walk cut its buckets **back from `s2`** —
`k = (s2 - t[i]) / step` — so the candle boundaries were phase-locked to the box' right edge:
the same band was read on a different grid for every date that edge sat on. Same band
(3999.52..4012.14, XAUUSD M1, `tMax` 31), only the close moved:

| close | 08:30 | 08:33 | 08:40 | 08:45 | 09:00 | 09:55 | 10:30 | 12:00 | 13:50 | 15:15 | 15:43 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| edge grid (§11–12) | 31m | 31m | **26m** | **27m** | 31m | 30m | 30m | 30m | **29m** | **31m** | 31m |
| clock grid (v4) | 31m | 31m | 30m | 30m | 30m | 30m | 30m | 30m | 30m | 30m | 30m |

The 31m at 08:30/08:33 is the window itself ending before the stall does, not an edge.

**The fix, one line.** `int k = (int)(t[i] / step);` (`BaseKnotStillCount`). `s2` still **closes**
the window (`if(t[i] > s2) continue;`) — it no longer decides a boundary. The ladder's own rungs
(M5/M15/H1…) are clock-aligned already, so no ladder answer moves; only off-ladder times (13m,
27m, 31m) stop following the drawing.

**Formula v4.** `BK_FORMULA_VERSION` is `"v4"`: a **v3** row's `Node_TF` is that edge read, so a
v3 time/type/stop is not comparable with a v4 one. The v3 rows already on disk stay as the
evidence v4 was chosen on.

**What proves it.** `P-BK-126c` in `tools/check-regressions.js` (the clock key, `s2` still the
window's fence, the version) and three mutations `P-BK-126c-a…c` in `tools/mutation_gate.py` —
**3 KILLED, tree byte-identical**.

**The second writer — named, NOT yet cut.** `s2` was not the only box input of the answer:
`BaseKnotClassSpan` hands the walk `bs1 = min(t1, sp.tStart)`, so a box drawn **wider to the left
than its own base** also widens the window. MEASURED on the same band with the close fixed at
15:15 and only the window start moving: **32m** (start 00:00/04:00/06:00), **25m** (07:30),
**14m** (08:00), **12m** (08:30). It fires only when the newest part of the story holds no run at
a coarse time and an older one does. Left open on purpose: it is a **different cause** (the
window's extent, not the grid's phase) and it is not what the two samples measured.

## 14. The count is the measure — no grid at all — P-BK-126d

**The order (2026-10-27), after two builds that each cut a grid over the same count.**
«به ساعت نباید ربط داشته باشه دیگه سه کندل ملاک هستش که باکس یک محدود بالا و پایین داره باید درون
این باکس، کندل ورود به باکس و کندل خروج از باکس میشه و بین کندل ورود و خروج سه کندل باشه» — then
«همون کار که تعداد کندل مشخص میکنه درست هستش دیگه از همون استفاده بکن که ببین کجا سه کندل داریم».

**The rule.** The base's own **entry..exit count** (`BaseKnotBarCount`'s `still`, P-BK-40/42/44 —
the run of candles whose body is inside the band, walked on both sides of the box' edge) is the
knot, and **one candle of the knot's time is that count's span over three**:

```
nodeTF = (still × readTF) / 3        readTF = the box' own commit/owner TF (P-BK-80)
```

One number per band. No clock, no bucket boundary, no ladder rung to round it to: a 40-minute
base reads **13m**, which is what the samples already said.

**Why every grid had to go.** A grid is a SECOND ruler laid over a count that is already exact,
so the two can only disagree — and the grid is the one that moved:

| reader | same band, eleven closes | verdict |
|---|---|---|
| buckets cut back from the box' edge (§13's predecessor) | 26, 27, 29, 30, 31m | follows the drawing |
| buckets cut on the clock (§13) | 30m for all but 08:30/08:33 | stable, but still a grid |
| the count over three (§14) | **one number per run** | the user's rule |

(§15 adds the half this table could not see: the run itself was anchored on the box' right edge,
so "one number per band" held only while the drag kept that edge off a second run.)

**The live proof the grid was not the whole story.** `15_22269312`, `Formula_Version: v4`:

| press | clock | Box_Pips | Story / Edge | `Node_TF` |
|---|---|---|---|---|
| 1 | 17:05:52 | 120.4 | 09:50 / 09:45 | 20m |
| 2 | 17:05:56 | 120.4 | 09:50 / 09:45 | 20m |
| 3 | 17:06:02 | **113.1** | 13:45 / 17:00 | 11m |

Presses 1 and 2 agree — the clock grid did stop the edge from moving the answer. Press 3 differs
because the **band** moved (120.4 → 113.1 pips), which under the user's rule is the one input that
*must* move it: «باید درون این باکس … سه کندل باشه».

**Formula v5 → v6.** `BK_FORMULA_VERSION` is `"v6"` (`BaseKnot_Shot.mqh`): a v4 row's `Node_TF`
was a grid fitted to the count, and a **v5** row's count was a run anchored on the box' **right**
edge (§15) — neither is comparable with a v6 row's.

**What proves it.** `P-BK-126d` in `tools/check-regressions.js` (the division, no `BaseKnotStillCount`
or `BaseKnotM1Window` in the class read, no ladder rounding, the clamp, the version) and three
mutations `P-BK-126d-a…c` in `tools/mutation_gate.py`. `P-BK-126b` keeps the precedence (the count
beats the ATR owner) and `P-BK-126c` now guards the **hover's** count only. Together with §15's
`P-BK-126e`: **14 mutations, 14 KILLED, 0 survived, 0 stale, tree byte-identical**.

**What is NOT proven yet.** No live sample exists under v5 or v6: the three folders above are v4.
The next `K` press on a box that has not moved is what closes it — `Node_TF` must read the same
number twice, and it must equal `(still × readTF) / 3` on the capture's own `Box_Pips` band.

## 15. The walk starts at the entry candle — P-BK-126e

**The report (2026-10-27), after §14 shipped.** «درست نشده نگاه کن من جابجا میکنم عوض میشه در
صورتی که همون گره هستش پس باید در هر حالتی حتی تایم عوض شد هم همون درست رو نشون بده». Two
screenshots of ONE knot, the box dragged:

| box | `still` | `Node_TF` | type / side |
|---|---|---|---|
| 117.6 pips | **12** | **20m** | ETR / SELL |
| 124.1 pips | **8** | **13m** | CTR / BUY |

The class formula was already `still × 5 / 3` (§14) and both numbers obey it exactly — so the
formula was not the mover. **The input was**: `BaseKnotBarCount` anchored its search on the box'
**right** edge and walked older, so of the two runs this band holds (08:55..09:50 = 12 candles,
13:15..13:50 = 8), whichever the drag brought nearest that edge became the base.

**The measurement** (XAUUSD M5, band `3999.52..4012.14`, left edge fixed at 08:45, **99 right
edges** every 5 minutes from 08:50 to 17:00, `tools/bk-knot-scan.py`'s own series):

| anchor | answers over the 99 positions |
|---|---|
| the box' right edge (before) | `12/20m` ×45, `8/13m` ×46, `5/8m` ×7, `22/36m` ×1 |
| the box' left edge (now) | **`12/20m` ×99** |

**The rule.** The walk starts at the box' **left** edge — the candle that ENTERS the box, the user's
own sentence — and steps **newer**, so the right edge (`t2`) only validates the box and decides
nothing. The run is still read WHOLE (`BK_BASE_GAP`'s tolerance, then P-BK-44's forward extension and
the older walk), so a left edge **inside** the run does not shorten it: all six left edges from
08:50 to 09:50 read the same 12 bars · 20m. The left edge only chooses **which** run — it points at
the knot, and the same pointer always names the same knot.

**What it costs.** The same walk, reversed: `BK_BASE_SKIP` (300 bars) is now measured forward from
the left edge, and the per-frame preview cache (`BaseKnotLiveBarCount`) keys its window on the left
edge's shifts instead of the right edge's — one `iBarShift` per frame, unchanged.

**What proves it.** `P-BK-126e` in `tools/check-regressions.js` (the anchor is `(sh1 > sh2 ? sh1 :
sh2)`, the scan is `while(s >= 1 && edge - s < BK_BASE_SKIP)`, the skip is `s--`, the continuation
is `s = head - 1`, and the preview cache asks `t1` and never `t2`) with four mutations
`P-BK-126e-a…d`. `tests/Biotak_BaseKnot_Shot_Test.mq4` asserts the class' own arithmetic on the two
screenshots' counts (12 → 20m, 8 → 13m) and that the box' times and prices cannot move it.

**What is NOT proven yet.** No live v6 sample exists. The test that closes it: remove and re-add,
drag **only** the right edge across the knot three times, press `K` each time — `Node_TF` and
`bars` must be the same in all three `sample.txt` files.

## 16. The sure method — one flushed line per changed reading (P-BK-126f)

**The order (2026-10-27).** «روش که مطمعن باشه رو پیدا کن پیگسل و اینا چیه» — a method that leaves
nothing arguable, and no more talk in pips or pixels.

**First, the units, because that was the question.** One **pip** here is `0.1` of price
(`BaseKnotToPips`) — a unit this project uses for the box' height, the risk and the legs, and NOT a
unit of the count. No pixel is ever counted anywhere in the read: `BMF`/PNG pixels exist only in
the screenshot harness. The knot's time is counted in **candles of the read TF** — `still` of them —
and the answer is that count × the TF's minutes ÷ 3.

**The method.** Each time a reading CHANGES, `BaseKnotSync` emits one line on the flushed channel
(`DrawStripDiagEmit`, `Biotak/BaseKnot_Shot.mqh` → `BaseKnotKnotWitness`):

```
[BK-KNOT] formula=v7 box=5_22269312 chart=M5 band=3999.52..4012.14 dg=2 boxT=08:45..10:00 still=12 bars=12 readTF=M5 nodeTF=20m cap=1440 h=125.1 type=ETR hop=1 entry=08:55 last=09:50 exit=09:55
```

(Those are the measured numbers of §15's band: the same twelve candles, 08:55..09:50, exit 09:55 —
one answer for 99 right edges. It is the line's SHAPE that is proven here; the live capture is the
last paragraph.)

| field | what it is |
|---|---|
| `still` | the candles whose **bodies** sat inside `band` between `entry` and `exit` |
| `readTF` | the TF those candles were counted on (the box' owner TF, else its commit TF) |
| `nodeTF` | the answer: `still × readTF ÷ 3`, capped at `cap` (1440) |
| `entry` / `last` / `exit` | the run: the candle that entered (not counted), its newest stand-still candle, the candle that closed outside (counted) |
| `boxT` / `band` | the **drawn** rectangle — a pointer, never the measurement |
| `h` / `type` / `hop` | v7 (P-BK-128): the height the type was cut at, the name it got, and the rung both legs were read on — the three numbers a «one time ETR one time FTR» report turns into one line |

**How it is read — the whole verification.** Two lines, field by field:

- **drag the right edge** → `boxT` moves, `still`/`readTF`/`nodeTF` do not;
- **drag the left edge away from the run** → `entry` changes, and `still`/`nodeTF` may change
  **only** when the left edge names a different run (that is the rule, not a bug);
- **switch the chart TF** → a new line appears whose `chart=` differs and **nothing else does**.
  (The chart TF is inside the change guard for exactly this: a silent switch would be
  indistinguishable from a read that was never taken.)
- **check the arithmetic** → `still × readTF ÷ 3 == nodeTF` unless `nodeTF == cap`.

**What it costs.** A still chart walks four memo slots, compares a few scalars per slot and returns:
no string, no write. The memo is **per box** (`BKWitnessMemo wm[4]`, round-robin when a fifth knot
appears), because `BaseKnotSync` is also called in a LOOP over every box on attach — one shared memo
would read that loop as "changed, changed" and print for an untouched chart. A changed reading
builds one string and writes one flushed line, in the same frame the box is rebuilt.

**What proves it.** `P-BK-126f` in `tools/check-regressions.js` (the writer is
`DrawStripDiagEmit` and carries `BK_FORMULA_VERSION`; it never computes its own count or class —
a witness with its own read is a second ruler; every field above is on the line; the guard
compares the box, its band and the run's three times, and the chart TF is in it; the memo is the
four-slot `BKWitnessMemo` table; and `BaseKnotSync` is the caller) with four mutations
`P-BK-126f-a…d` (guard removed, channel swapped to `Print`, caller removed, memo cut to one slot) —
measured 2026-10-27: **4 killed, 0 survived, tree byte-identical**.

**What is NOT proven yet.** The line has not yet been read off a live drag in this session (the
terminal must be restarted on the new ex4, or the indicator removed and re-added). The read is
`python tools/diag-live.py`: the `[BK-KNOT]` lines are not EXPECT/TABCENSUS lines, so
`split_frames` keeps them out of the panel frames (they belong to no panel open) and the reader
prints the newest four in their own `knot :` block below the frame — in FILE order, because two
lines are read as a pair.

## 17. The entry rides the stop's rung - P-BK-127 (2026-10-27)

**The rule.** `BaseKnotEntryTFMin` answers `BaseKnotMeasureTFMin`: one hop, two legs.

- FTR reads `EngSL` on its own rung; ETR reads `HuntSL` one rung up, CTR two, OTR three —
  those are the NAME's rungs, and they are the **fallback** now.
- The rung is the ladder's (`BaseKnotLadderHopAt` at the box' own `storyT`), so the entry and
  the stop both scale with the box' height and the three types cannot all answer one number
  (`«ctr , otr همه به نسبت ها درست بشه … الان همه یکی هستش»`). Since P-BK-128 (below) that
  function answers the deepest rung whose whole leg package FITS, not `round(u)` — §18.

**Why.** The user's own box - XAUUSD M15, `15_25039828_20261027-175226`: height 125.1 pips,
ladder ATRs M15 66.6 / H1 135.2 / H4 300.8, `U 0.853` → rung H1. The stop is `EngSL(H1)` =
31.7 and the box' card prints `TRex 31.7 | Trigger 84.5 | Pricicle 158 | Classic 380`
(`BaseKnotLegsTag(mTF, …)`), while the entry drew `HuntSL(M15)` = 41.6 - a Trigger cell
nothing drew. His order: `«این گره چون etr هستش باید ورود 84.5 باشه … ولی ورود ما الان 41 پیپ»`.

**How it is checked.** The card's `Trigger` cell and the entry line are ONE number:
`Entry_Off_Pips` on the next `K` sample must equal `Trigger` of the same row, and the stop
must equal `TRex`. Gate: `P-BK-127` (`tools/check-regressions.js`) with five mutations
`P-BK-127-a…e` - measured 2026-10-27: **5 killed, 0 survived, tree byte-identical**.

**What is NOT proven.** Every row captured before this date carries the BASE TF's entry in
`Entry_Off_Pips`; only rows after 2026-10-27 compare column-for-column. The `Type`, `U`,
`Box_Pips` and `Stop_Pips` columns are untouched (the stop's rule did not move).

## 18. The type is a ratio, the rung is a capacity - P-BK-128 (2026-10-27)

**The report.** Two frames of ONE box, ten seconds apart, `formula=v6`, rows
`ATR 235m:135.2 | H4:300.8 | D1:970.4` both times: `217.3 pips · FTR · TRex 31.7 | Trigger 84.5`
and `219.5 pips · ETR · TRex 70.5 | Trigger 188`. His words:
`«این یک بار etr نشون میده یک بار ftr باید مقایسه بکنه که نباید مرز اینقدر تنگ باشه باید مقایسه
باشه که بهر کی نزدیک تر بود همون برنده هستش»`.

**What was measured (v6).**

| number | 217.3 | 219.5 |
|---|---|---|
| `u` (linear) | 0.4958 | 0.5091 |
| `hop = round(u)` | 0 | 1 |
| the type's edge `(135.2+300.8)/2` | 218.0 — **0.7 pips / 0.32 %** away | 1.5 pips / 0.69 % |
| legs on that rung (`0.859 x a_k`) | 116.2 pips | 258.5 pips |

So a 2.2-pip nudge (1 %) crossed ONE boundary twice: the name AND the rung. And 258.5 pips of
legs inside a 217-pip box is not a tighter trade - it is the stop line drawn outside the box.

**The rule now.**

1. **The type** is cut at the ladder's RATIO midpoints: FTR `<= √(trig·pat)`, ETR
   `<= √(pat·str)`, CTR `<= str` (the user's own OTR edge, `«بیشتر از توان حرکتی تایم ساختار»`),
   OTR above. Measured: `√(135.2·300.8) = 201.66` (not 218.0) and `√(300.8·970.4) = 540.27`.
2. **The rung** is the deepest one whose whole leg PACKAGE fits inside the box:
   `55/64 x a_k <= h`, i.e. `off 5/8 + risk 15/64` (`BK_NODE_HUNT_NUM/DEN`,
   `BK_NODE_POWER_DIV` — `BaseKnot_Ability.mqh` `BK_AB_FIT_NUM/DEN`). Measured:
   `0.859375 x 300.8 = 258.50 > 217.3`, so the pattern rung cannot be held, and
   `0.859375 x 135.2 = 116.19 <= 217.3` stands.

**The three readings of the same box now.** 217.3 and 219.5 both answer **ETR, hop 0,
Eng 31.7, Trigger 84.5, stop 31.7** (116.2 < 217.3); the nearest flip is at 258.5 pips
(+18 % instead of 0.3 %). The earlier sample `15_25039828` does not move: `125.1` pips against
`66.6 / 135.2 / 300.8` is ETR with hop 1 (`0.859 x 135.2 = 116.2 <= 125.1`) - the check the user
already made (`84.5`).

**The type and the rung may now part**, and that is the point: the type answers "how big is it",
the rung answers "how much of it can one rung spend". MEASURED on the harness rows
(43.4 / 73.3 / 136.3): a 60-pip box is ETR (60 > 56.40) with the node's OWN rung (60 < 63.0).

**What moved with it.** `BK_FORMULA_VERSION` is `"v7"`; the sample's `U` column is the same
ratio coordinate (`u = k + ln(h/a_k)/ln(a_{k+1}/a_k)`), so `U 0.5` IS the printed FTR/ETR edge.
A v6 row's `Type`, `U` and `Stop_Pips` are not comparable with a v7 row's.

**How it is checked.** `python tools/mutation_gate.py P-BK-128` - six inverses (both type edges,
the CTR ceiling, the fit at the rung, the `U` coordinate, and the fit constant against the legs'
own arithmetic). The harness `tests/Biotak_BaseKnot_Lines_Test.mq4` nudges across the OLD 58.35
edge and asserts one type and one rung. `[BK-KNOT]` now prints `h=… type=… hop=…` on the flushed
line, so the next report of this class is one line, not two screenshots.

**What is NOT proven.** The 2.2-pip difference between his two frames is still unexplained
(the ATR rows are identical, so either the edge was nudged or the box' edge rides the forming
bar); the fix removes the class, not the cause of that one number.

## 19. The face reads a clock, the witness keeps the machine name - P-BK-129 (2026-10-27)

**The report.** On the note of §18, above the ATR row, he read
`35 bars · 700m base · FTR` / `ATR 700m:313.5 | D1:994.8 | W1:2528.8` and asked:
`«این 700 m به ساعت و دقیقه و غیره بنویس که سریع بفهمیم»`.

**What 700m is.** The box' commit TF times the base's own candle count — 35 bars x 20m — i.e.
11 h 40 m of market. It is a real row (`still x commitTF` is not a ladder rung), and the face was
the only place a reader had to make that division himself.

**The two spellings, two owners.**

| reader | helper | what it prints |
|---|---|---|
| the note's face and its hover | `BaseKnotTFHuman` (`BaseKnot_Base.mqh`) | `700 -> 11h40m`, `235 -> 3h55m`, `2000 -> 1d9h20m`, `20 -> 20m`; a ladder rung keeps its own name (`M15` / `H4` / `D1` - `4h` beside `H4` would be a second name for one rung) |
| `[BK-KNOT] readTF=` / `nodeTF=`, the sample's `Chart_TF:` / `Node_TF:`, `[BK-OWNER]`, `[P-BK-107]` | `BaseKnotTFName` (unchanged) | `700m` - the machine spelling every tool parses |

`BaseKnotTFHuman` never copies the ladder: it asks `BaseKnotTFName` and converts only an answer
that came back as `<n>m`, so a rung added there can never be spelled two ways.

**What moved with it.** Every reader-facing TF in the knot: `BaseKnotBaseTag` (the `… base`
suffix), `BaseKnotBaseLine`, `BaseKnotNodeLine` (the ATR / step / story sentences),
`BaseKnotATRTag`, `BaseKnotATRPctCell`, `BaseKnotOwnerTag`, `BaseKnotRiskTag`,
`BaseKnotEntryWhy`, `BaseKnotStopWhy`, `BaseKnotTPPlanTip`. The note's plate width follows its
ink (`BaseKnotNotePlateW`), so the longer spelling widens the plate instead of clipping.

**How it is checked.** `tools/check-regressions.js` (`P-BK-129`) asserts the clock's three terms,
that the eight display builders the note and its hover are built from ask it
(`BaseTag` / `BaseLine` / `NodeLine` / `ATRTag` / `ATRPctCell` / `OwnerTag` / `EntryWhy` /
`StopWhy` - `BaseKnotRiskTag` and `BaseKnotTPPlanTip` take the same helper), that
`BaseKnotTFHuman` is absent from `BaseKnot_Shot.mqh`, `BaseKnot_Witness.mqh` and
`BaseKnot_Owner.mqh`, and that the three machine fields are still `BaseKnotTFName`. Three
mutations (`P-BK-129-a…c`) - measured 2026-10-27: **3 killed, 0 survived, 0 stale, tree
byte-identical**. The harness executes the user's own numbers (`700m -> 11h40m`,
`235m -> 3h55m`, `H4`, `D1`, `700m` still the machine name).

**What is NOT proven.** No live frame has been captured since the rebuild, so the spelling is
proven in the harness and in the gate, not yet on his chart; and a note whose body grows past
63 characters wraps one field earlier (the row budget is 6, the note uses 4-5).

## 20. The anchor switch moves LABELS, never levels - DELIBERATE (2026-10-27)

**The report.** With the strip's `Last object` cell lit, he pressed it and the drawn levels
re-stepped: `«این دکمه روی سطوح تاثیر نداشته باشه ... الان روی سطوح تاثیر می‌زاره و باعث می‌شه که
رسم دوباره با step سایز جدید بشن»`. Then: `«یک جا قید کن که به صورت باگ نشانش ندهند و عمدی
هستش، چون قبلا درست بودش»`.

**This is not a regression being excused - it is the rule, put back.** The cell is a LABEL lever.
It exists so the ATR the labels print is read at an owner's bar (a knot, a leg ruler) instead of on
the tick. It has no business in the arithmetic that decides where a level lands, and it had none
until 2026-10-21, when the fence was moved up the funnel and the switch started re-stepping the
chart.

**The two readers, and the one that was wrong.**

| reader | entry | what the switch does to it |
|---|---|---|
| the ATR labels (`Labels_A` 769 / 894) and the knot witness (`BaseKnot_Witness` 123) | `GetATRForTimeframe` - the anchored read's ONE home | moves the NUMBER it prints (`-`, `ATR`, the `%`, the plan's readout) |
| the TH step, the fractal range, the adaptive shift, the plan's ruler | `CalculateWeightedATR` - the geometry funnel, LIVE unconditionally | nothing. Five consumers, one fence: `CalculateATRBasedStep`, `CalculateATRFractalValues`, `AdaptiveScaling.mqh:110` (all through `CalculateWeightedATR_Locked`), `CalculateHybridATR` and `TradePlanStripPips` |

The second door was `TradePlanFormulas.mqh`'s source guard, which read `CalcAnchorAt()` and so let
the switch pick the plan's ATR by itself. With `inpUseLegATR` OFF (the default) it resolved to the
same live read either way, which is why the defect only showed once a knot owned the anchor.

**As-of reads keep their own bar.** They never needed the chart-wide switch: `CalculateWeightedATRAt(tf, bar)`
is what P-BK-79 / P-BK-107 / P-BK-126 / P-LEGATR / P-LM-25 hand in, unchanged.

**How it is checked.** `tools/check-regressions.js` (`P-ANCHOR-LAST`) reads the two function bodies
by name: `CalculateWeightedATR` must be the plain `CalculateWeightedATRLive(tf)` and must contain
neither `CalcAnchorAt(` nor `CalculateWeightedATRAt(`; `GetATRForTimeframe` must still ask the
anchor and hand it to `CalculateWeightedATRAt(CompatTF(targetMinutes), fa)`; and
`TradePlanFormulas.mqh` must contain no `CalcAnchorAt(` at all. Three mutations put each defect
back by literal - `P-ANCHOR-LAST-d` (anchor at the funnel), `-e` (anchor in the plan's guard),
`-f` (labels read live). MEASURED 2026-10-27: **10 killed, 0 survived, 0 stale, tree byte-identical**
(the seven older anchor mutations ran in the same pass).

**Cost.** Two compares per call replaced by zero: the funnel is now a tail call, so the geometry
pass got cheaper, not dearer. Nothing polls the switch (P-ANCHOR-LAST-MOVE already asserts that).

**What is NOT proven.** No live frame has read the step before/after a press on the new ex4 yet; the
proof here is the source, the gate and the mutation, plus `0 errors` on both entries.

## 21. A knot's own minutes is not a rung - P-BK-130 (2026-10-27)

**The report.** His 6h FTR box read `18 bars - 6h base - FTR`, `ATR 6h:324.9 | D1:999.3 | W1:2528.8`,
`TF H1 | ATR 137.3 | Leg 272%`, legs `TRex 76.2 | Trigger 203.1 | Pricle 381 | Classic 914`. The
question: for a knot whose own time sits BETWEEN two rungs, can the entry / targets / stop shift with
how near or how far it stands.

**First, the measured defect - and it is not a question of shape.** `324.9` is EXACTLY the header's
`H4: 324.9`: the note printed one number under two names. The path is one line -
`TradePlanCompute` (`Biotak/TradePlanFormulas.mqh:428`) snapped the ask through
`TradePlanLadderMinutes(TradePlanLadderIndex(360)) = 240` BEFORE reading, so `p.ownPips` was H4's
composite. Every leg is that number times its own constant:

| leg | constant | on 324.9 |
|---|---|---|
| TRex (EngSL) | 15/64 (1/4.266666) | 76.2 |
| Trigger (HuntSL) | 5/8 (8/3 / 4.266666) | 203.1 |
| Pricle | 75/64 (5 x 15/64) | 381 |
| Classic | 45/16 (12 x 15/64) | 914 |

So a 6h knot's entry, stop and four targets were an H4 knot's, and the box' own type was compared
against `h / 324.9 = 115%` - a 6h box longer than its own time's ability.

**The fix is ONE read, not a new law.** `TradePlanATROfOwnTime` (`TradePlanFormulas.mqh:333`) asks
`TradePlanStripPips(chartMinutes)` - the minutes the caller really asked for - and falls back to the
rung below only when `CompatTF` names no series for that length (8 / 45 / 700 minutes answer
`PERIOD_CURRENT`) or that row is still cold; P-BK-131 (§22) then SCALES that fallback by the
project's √-law, so no length ever wears a neighbour's number. `TradePlanCompute`'s `ownPips` and
its `TradePlanEngTrue` both read through it, so the four legs, the entry and the stop are one ruler
(P-BK-127) on the box' own time. `p.chartMin` / `p.strMin` / `p.trigMin` stay the ladder slot -
labels, never times - so `trigMin` still names a rung.

**Why not the interpolation the question suggested.** `CompatTF(360)` already answers `PERIOD_H6`
(`BuildConfig.mqh:294`), so the 6h composite can be READ - a real number beats a model of it. The
two models, for the record, on his own rows: the project's sqrt law gives `324.9 x sqrt(360/240) =
397.9`, and the log-log (power) interpolation between H4 and D1 gives `324.9 x (999.3/324.9)^0.226 =
418.9`; the sqrt law is also what it would give at D1 (`795.8` against a real `999.3`, -20 %), which
is why P-BK-106 already prefers a REAL upper row to the law whenever the row exists.

**What is NOT proven.** No live frame after this change yet: the new `ATR 6h:` value, `EngSL` and
the entry offset are whatever the terminal's H6 composite says, and the harness' `6h read is NOT
the H4 number` case is skipped when H6 history is cold. The height-graded question (a box whose
height is `a0 + k x step`) is NOT answered here: the legs stay one number per (TF, anchor), and the
only height-driven owner remains P-BK-128's rung fit, so a live box cannot change its leg size as
its base grows.

**Cost.** An on-ladder ask pays one `switch` compare and no read (byte-identical: the ladder's round
trip returns its own minutes). An off-ladder ask pays one new cache row per (TF, anchor) - the live
path is `g_multiTFCache` keyed by TF, the as-of path `g_atrAnchorCache` keyed by (TF, anchor) - and
hits on every round after the first.

**How it is checked.** `tools/check-regressions.js` (`P-BK-130`) asserts the helper's fence, its
asked-minutes read, its rung-below fallback, that `TradePlanCompute` reads `ownPips` and the Eng
from the SAME minutes, that the trigger label stays on the ladder slot, and that the pump's type
measure still reads `plan.ownPips * BaseKnotPipSize()`; the harness runs five arithmetic cases
(`Biotak_BaseKnot_Lines_Test.mq4` §8) - the ladder has no 6h slot, `CompatTF` HAS one, a 700m time
has none, and `TradePlanCompute(360)` keeps `chartMin = 240` while `ownPips` is the own-minutes
read. Five mutations put each defect back by literal (`P-BK-130-a..e`). MEASURED 2026-10-27:
**5 killed, 0 survived, 0 stale, tree byte-identical.**

## 22. No series is not no answer - ONE continuous ruler - P-BK-131 (2026-10-27)

**The hole P-BK-130 left.** `CompatTF` names a series for the standard lengths only; 8 / 45 /
700 minutes answer `PERIOD_CURRENT`, and P-BK-130's fence left those wearing the rung below's
NUMBER - his own note's `700m` row would still have been H4's composite. Two knots of one chart
then cannot be compared: one is priced on its own time, the next jumps to a neighbour's.

**The rule.** The plan scales the rung below by the project's √-law -
`base * sqrt(chartMinutes / below)` - which is the SAME arithmetic P-BK-126 already applies to the
type's row (`BaseKnotRungScale`, `BaseKnot_Nodes.mqh`) and the same law `CalculateHybridATR`
(`ATR_A.mqh:378`) was built on. The gate asserts both spellings, so plan and table cannot scale by
two different laws. The rung itself never reaches the scale (it has a series), a time under M1
never divides upward, and a cold base still degrades to the rung's own number.

**The ruler, on his own H4 row (324.9 pips) - one continuous monotone function of the time asked**

| knot time | how it is read | ATR (pips) | TRex (15/64) | Trigger (5/8) | Pricle (75/64) | Classic (45/16) |
|---|---|---|---|---|---|---|
| H4 (240) | its own series | 324.9 | 76.2 | 203.1 | 381 | 914 |
| 6h (360) | its own series (H6) | real read | real read | real read | real read | real read |
| 700m | H4 x sqrt(700/240) = x1.7078 | 554.9 | 130.1 | 346.8 | 650.2 | 1560.6 |
| D1 (1440) | its own series | 999.3 | 234.2 | 624.6 | 1171 | 2810 |

The 6h row is the one number this table cannot fill from the source: it is whatever the terminal's
H6 composite says, which is exactly why P-BK-130 reads it instead of modelling it (the two models
would print 397.9 for the √-law and 418.9 for the log-log interpolation between H4 and D1).

**What this answers, and what it does not.** "Shift with how near or how far the knot stands" is
now a property of the TIME, continuous and monotone, identical for all four knot types - so an ETR
and an FTR of the same time are comparable, and a 6h knot is comparable with an H4 one. What it is
still NOT is a function of the box' HEIGHT: the legs remain one number per (TF, anchor), and the
only height-driven owners stay P-BK-128's rung fit (`55/64 x a_k <= h`) and the type's ratio
midpoints. A height-graded leg would make one live box change its entry as its base grows.

**How it is checked.** `tools/check-regressions.js` (`P-BK-131`) asserts the √-law expression, the
on-rung guard, the cold-base degrade, and that `BaseKnotRungScale` still spells the same ratio; the
harness (`Biotak_BaseKnot_Lines_Test.mq4` part 8) computes `TradePlanATROfOwnTime(700)` against
`H4 x sqrt(700/240)` and refuses to let a 700m knot read the H4 number, then prints the whole
comparable ladder. Mutations `P-BK-131-a..c` (no scale / inverted ratio / no on-rung guard).
MEASURED 2026-10-27: **8 killed, 0 survived, 0 stale, tree byte-identical** (the five P-BK-130
mutations ran in the same pass).
