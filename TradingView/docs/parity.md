# Parity — the same numbers, in every state

`node tools/check-parity.js` · `--selftest` · `--tol <abs>` · `--dump-draw`

The requirement is one sentence: **the port must give the same values and draw the
levels at the same prices, in every state.** This page says how that is measured, and
which parts of it are measured *right now* rather than intended.

## Why the numbers cannot be checked by reading code

`src/30_math.pine` is a re-statement of `Biotak/TH3/TH3Pivots_B.mqh` in another
language. Two re-statements of one formula agree by inspection exactly until they do
not, and the failure mode is quiet — a boundary that flips from `<=` to `<` moves the
K band on 0.85 by a whole tier and nothing crashes.

So the formula is EXECUTED, and it is compared against numbers the port had no part in
producing. There is no JavaScript copy of the formula anywhere in this repo, because a
JS twin would be a second owner that can drift silently — the exact defect the MQL4
contract's §1 forbids.

## The engine

`tools/lib/parity-engine.js`:

* `LocalProvider extends BaseProvider` — a deterministic offline data source. No
  network, no API key, and `getSymbolInfo()` supplies `mintick`, which matters: the
  `pinets-cli` binary leaves `syminfo` null on an offline dataset, and any script that
  reads `syminfo.mintick` then dies with `Cannot read properties of undefined`. The
  library path fills it. That is why the harness uses the library, not the binary.
* `runPine({code, bars})` — runs a real Pine source through PineTS and returns the
  context; `plotValues(ctx, title)` reads a plot's per-bar values.

`tools/lib/parity-probe.js` generates a Pine script that calls the REAL `30_math.pine`
functions once per bar, one bar per fixture row, and plots every intermediate —
`Ratio`, `K`, `KClosed`, `StepMother`, `StepPattern`, `Step`, `StepClosed`, and all
seven rungs. The probe is generated, never committed, never edited. A change to
`30_math.pine` is exercised by the very next run.

## Oracle 1 — the other build's own test file

`tests/fixtures/step-fixtures.json` is frozen by `tools/fixtures-derive.js` from
**`tests/Biotak_TH3_Test.mq4`** (lines 262-333 and 636-655). Every case carries the
`Check(...)` label it came from as `wording`, and its expected value is either that
line's literal or that line's own expression evaluated once — `Math.sqrt(50.4*51.0)`
becomes `50.69911064741696`, and the fixture records both.

51 cases / 90 checks (33 `mql4-test-label`, 18 `source-derived`), covering - the counts
are printed by every run, so read them there:

| family | what it pins |
| --- | --- |
| 7 × `k` | the unified table's bands, both edges (`0.85`, `1.20`, `1.80`, `2.50`) |
| 8 × `step` | the macro mother (`36 → 20.0`), the knot mother, `CD rides the mother rung`, the absent-mother and dead-rung fallbacks, empty inputs, and the major-extension guard |
| 9 × `closedK` | the legacy table, pinned ON the boundary (`0.74 → none`, `0.75 → 2.5`, `1.81 → 1.666`) |
| 5 × `closedStep` | `78/100 → 0.00312`, the `K=3.0` case, and the shallow leg that must go SILENT |
| 2 × `ratio` | the P-TH3-INFO-05 leg map: `CD/BC` is the closing leg, `AB/BC` is not |
| 2 × `ladder` | all seven rungs up and down from `D`, one step apart |

`node tools/fixtures-derive.js --check` fails the build if that file was edited by
hand — a fixture changed without its oracle is a moved goalpost.

## Oracle 2 — the recorder's own output

`../Samples/TH3_Dataset/Dataset.csv` is what `Biotak/TH3Recorder.mqh` wrote on a real
MQL4 chart. Nothing in the port took part in producing it, which makes it the strongest
evidence this project can have.

Each row is reconstructed through the same executed Pine core and compared against the
recorded columns. The tolerances are **derived from the CSV's own rounding**, never
chosen:

| compared | slack |
| --- | --- |
| `Ratio`, `K` (3dp) | `6e-4` |
| `Step_Mother` (1dp) | `0.05` |
| `Step_Pattern` (1dp, from a 1dp leg) | `0.06 + 0.001·Leg_CD` |
| `Step_Pips` against `Pine` | `0.05 + 6e-4·Leg_CD` |

and then the part with no rounding in the way at all — the ladder:

```
stepPrice = |Target_1 − D_Price|            // the step the recorder really used
Target_3  == D_Price ± 3·stepPrice          // slack: 0.06 · Pip_Size
Target_5  == D_Price ± 5·stepPrice
Target_7  == D_Price ± 7·stepPrice
Step_Pips · Pip_Size == stepPrice
```

That is the rung law `{1,3,5,7}` read straight off the MQL4 build's drawn output, and
it depends on no rounded intermediate column.

**Status today: 0 rows.** `Dataset.csv` carries only its header, so this half has
nothing to compare. It is honest to say it is unverified against real data — and it is
*not* unwritten: `--selftest` feeds it one row consistent with the formula (must pass,
10/10 checks) and five mutated rows, each of which must FAIL:

```
[selftest] PASS  the consistent row was accepted (10/10 checks)
[selftest] KILLED  SELFTEST-BAD-STEP      (Step_Pips 99.9)
[selftest] KILLED  SELFTEST-BAD-K         (K 2.500)
[selftest] KILLED  SELFTEST-BAD-RATIO     (Ratio_CD_BC 0.500)
[selftest] KILLED  SELFTEST-BAD-LADDER    (Target_5 1.09000)
[selftest] KILLED  SELFTEST-BAD-MOTHER    (Step_Mother 10.0)
```

A mutation that SURVIVES is not a rule, it is a comment.

## The end-to-end comparison — what the fixtures did NOT cover

A green fixture gate is not a port. The fixtures cover the ARITHMETIC of a handful of
named functions; they say nothing about the parts no MQL4 test label reaches. So the
Pine source was read against the MQL4 source, function by function, and **four real
divergences were found and fixed**. Each one is now gated, and each gate is in the
regression register (`tools/check-structure.js`) or in the fixture set.

| # | the divergence | the MQL4 witness | the fix, and its gate |
| --- | --- | --- | --- |
| D1 | the pip size returned `mintick` on a 2-digit METAL | `PerformanceOptimizations.mqh:168-215` gives a metal `point x 10` — 0.1 on XAUUSD against the port's 0.01, a silent **10x** error | the whole table is ported, including the metal list; gated by **11 pip cases** that run on every `check-parity` (`pip size: 11/11 symbol shapes match`) |
| D2 | the owner rung was a fixed 40-pip setting | `TH3PatternStepRungTF` (`TH3Pivots_B.mqh:23-37`) is `close(tf,1) x pct / 100` off `MODIFIED_FRACTAL_PERCENTAGES` — **not a constant**, and it decides whether the mother is a macro span | the professor's table is ported and the rung is derived from `close[1]`; the setting became a 0-defaulted **override**; gated by 5 rung cases + the chart-TF lookup (a regression assertion fails the build if the default is not 0) |
| D3 | the lock **applied** its verdict — it averaged base and derived | `TH3Renderer_B.mqh:130-137` passes `lockedUnit` and **discards it**; P-TH3-STEP-16 calls the lock "a SECOND OPINION, never the decider" | `th3LockVerdict` returns the words and never a step; gated by 4 lock cases + a regression assertion on the averaged form |
| D4 | the seed chain stopped at the rung | `TH3Renderer_B.mqh:80-90` has a third fallback, `leg x frequency/100`, and `GetCurrentTH3Frequency` has its own 0 < pct <= 120 bounds | both ported, with the frequency validated before it reaches the chain; gated by 5 seed + 4 frequency cases |

Their expected values are labelled `oracleKind: source-derived` and the counts are
printed on every run (`oracle kinds: mql4-test-label=33, source-derived=18`), so nobody
can mistake a rule read out of the source for a label the MQL4 build itself asserts.

**What this comparison still does NOT close** (each is named in the plan):

| # | open | why it matters |
| --- | --- | --- |
| O1 | the owner-TF walk-up (`TH3ClosedOwnerTF`, `3..7` then the chain) | the rung is read off the CHART's timeframe, where MQL4 reads it off the OWNER's. On a chart where the leg spans more than 7 bars the two differ; the dataset's `Owner_TF` / `Rung_Pips` columns are the oracle for it |
| O2 | `TH3RetraceBestStep` (the 8-state retrace) | MQL4 quantises the hand-typed base through eight candidate steps before the lock sees it; the port feeds the raw base |
| O3 | the anchor source | still a fractal swing ring, not the course's six-condition pivot — `40_levels.pine` says so at the top |
| O4 | the dataset oracle | **0 rows**; `--selftest` proves the checker can fail, but no real sample has judged it |

## Oracle 3 — the drawn ladder

The values can all be right while the chart is wrong, so the BUILT artifact is also
executed (`dist/BiotakTriggerTH3.pine`, 400 synthetic bars) and its own drawing objects
are read:

* 4 rung lines and 4 captions — the count the settings ask for;
* the seats are evenly spaced: **measured `step=0.0059457283`** over 4 seats, worst
  deviation `< 1e-9`. (That number is a DERIVED rung's output, so it moves when the
  rung moves - read the current one off `npm run parity`, never off this page.)
* the captions are numbered `1..N` and **each caption's stated number equals the seat
  it labels** — a caption that disagrees with its line is a level nobody can read;
* odd rungs are solid (the impulse targets) and even rungs are dotted (the shelves);
* the family never grows past one generation — the purge is a real sweep, not a hope.

It also pins the shape of the MQL4 lifecycle law: on 400 bars the surface wrote once.
A still frame costs zero writes, and the object count is the evidence.

## What is NOT claimed

* **Pixels.** Pine renders differently from MT4. Parity here is numbers and level
  prices, not appearance.
* **A real chart.** Nothing in this repo can run on TradingView; the last mile is a
  paste into the Pine Editor.
* **The pivot engine.** `35_pivot.pine` now ports `TH3SixPivotsScanTF` whole, and
  `tools/check-mql4-consts.js` proves its eleven constants equal that header by value.
  What is NOT claimed is that it ever declares a pivot — see the section below, where
  the measurement says it cannot, in this build, on any data.

## The six-condition detector: ported, and measured silent

`35_pivot.pine` is the course's detector (`TH3Pivots_A.mqh:295-434`), walked as an
incremental forward state machine. It was instrumented on a 400-bar random walk and
counted 133 cond-3 confirmations — the dial that starts a candidate — and **zero
declarations**. The two arms of `TH3P6RunOk` peaked at `runExt = 0.99` against a floor
of `2.40`, and `stdRun = 2` against a floor of `3`.

That is not tuning, it is arithmetic, and it is in the MQL4 source:

1. The bar after the extreme either makes a new high (the extreme **moves**), or its
   range is `< 0.80 ATR`, or its range is `>= 0.80 ATR`.
2. In that last case `extP - low >= 0.80 ATR` and cond 3 fires, ending the candidate.
3. So any bar cond 2 could count as a *standard* candle is a bar that already ended the
   candidate, and `stdRun` can never reach 3.
4. The other arm measures the closes **beyond** the extreme (`runStart = extIdx -
   runBars` is newer, not older), where 2.40 ATR is unreachable because cond 3 halts
   the candidate at about 1 ATR.

This is reported, not worked around. `40_levels.pine` therefore chooses its anchor
source, and `th3SrcName` puts the choice on the readout (`P6 pivot` vs `fractal (P6
empty)`) — a silent fallback would look exactly like a working detector. The port is
faithful; the finding is about the source it was ported from.
* **The dataset half against real samples.** Zero rows exist (§ Oracle 2).
