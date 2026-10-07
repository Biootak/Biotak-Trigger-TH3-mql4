# Performance audit — what is heavy, what caused it, and what was fixed

Companion to [th3-ui-placement.md](th3-ui-placement.md). Every number below is either
**measured** (quoted from a live terminal log / the code's own recorded measurements) or
**counted** (a grep over the tree). Nothing here is an estimate presented as a fact.

## 1. Fixed in this pass

### 1.1 The shipped `.ex4` was a DEBUG build — `P-LOG-3` was never closed

`Biotak/BuildConfig.mqh:28` carried `#define DEBUG_BUILD` since 2026-10-01
(«TEMPORARY — for the gear-panel hunt»). Everything downstream of it was live in the
build the user runs:

| compiled in | count | measured by |
| --- | --- | --- |
| `#ifdef ENABLE_DEBUG_LOGS` blocks | 302 | `grep -rn` over `Biotak/**` |
| `DEBUG_PRINT*` call sites | 356 | `grep -rn` over `Biotak/**` |
| `ASSERT(` sites | 16 | `grep -rn` over `Biotak/**` |

The hot ones are not rare paths: `EventHandlers_Calc.mqh:96,335,338,365` print on every
**teardown** (that is the switch the user named), and `EventHandlers_Objects.mqh:397` →
`LogRedrawDecision` (`EventHandlers_Tail.mqh:153`) sits on the per-frame redraw decision.
MT4's `Print()` is a formatted file write with a flush, not a buffer append.

**Fixed**: the flag is commented out; the build is a PRODUCTION build again.
**Evidence**: `Biotak Trigger TH3.ex4` 3,862,830 → **3,770,896 bytes (−91,934, −2.38%)**;
`EXIT_BUILD=0`, 22 compiles at `0 errors`, all 7 gates PASS.

**The measurements survive the flip.** `_LOG_GATE_W` is `Logger.mqh:381`
`if(g_runtimeLogLevel <= LOG_LEVEL_WARN)` — always active — so every `[W][PERF]` /
`[W][UI]` line this project relies on still prints. Only acceptance logs go away.

### 1.2 The ring was re-applied on every scroll and zoom, not only on a resize

`CHARTEVENT_CHART_CHANGE` is **not** "the window resized" — MT4 raises it on scroll, zoom
and every scale change, so with auto-scroll on it lands many times a second. The branch
that answers it (`BiotakPanels_Life.mqh:247`) called `UpdateCircularMenuPosition()`, which
re-applied the whole ring through `CircApplyMenuPosition()`. One such apply, driven by
`CircMoveItem`/`CircCreateItem` (`BiotakMenu_C.mqh`), costs:

| element | terminal calls per apply |
| --- | --- |
| orb bg | 1 `ObjectFind` + 2 `ObjectSetInteger` |
| each of `RING_COUNT` = 9 items | 2 `ObjectFind` + 4 `ObjectSetInteger` |
| badges, per lit feature | 2 `ObjectFind` + 4 `ObjectSetInteger` |
| tools row when open | `SubChromeMove` + `TOOL_COUNT` = 5 × `ToolsMoveItem` |

→ **roughly 60–100 terminal calls, every one re-writing a number that had not changed.**

`CircLayout(i,x,y)` is a **pure function of `(i, menuX, menuY, cw, ch)`** — `CircFitRadius`
beside it already caches on the same four — so that write set is a derivation of exactly
those four plus what is on screen.

**Fixed (P-PERF-55)**: a guard in `UpdateCircularMenuPosition()` returns before the apply
when `(menuX, menuY, cw, ch, menuVisible, g_ToolsOpen, chrome generation)` are still the
values the last apply wrote. The clamp above the guard still runs every call (arithmetic
on the live pair). `SubRelayoutIfNeeded()` still runs on the skip path, because the
sub-panel keeps its own shape key and a settings change can re-shape it with no move. The
chrome generation is bumped by `CreateMenu`/`DeleteRing`, so a rebuild can never inherit a
"still applied" verdict.

**No behaviour change**: the drag path applies unconditionally (it is a different call
site); `CircCreateOrb`/`CircCreateItem` position objects at birth, so no create path
depends on a later apply.

### 1.3 The placement pass costs two reads per quarter second, nothing else

`CircHomesRefresh()` (`Biotak/BiotakMenu_C.mqh`) is the whole added cost of
[P-UI-140](th3-ui-placement.md): two `ChartGetInteger` reads, two integer compares, and
the work only when the chart box really changed. On the common path it returns on the
second compare. No allocation, no terminal write, no redraw.

### 1.4 A leaked own-name delete re-armed the whole ~900-object rebuild — `P-DEL-COALESCE`

`EventHandlers_Router.mqh:58` is the path a user delete and our own bulk wipe share. The
bulk paths set a 250 ms suppression deadline (`g_suppressDeleteEventsUntilMs`), and the
code's own `P-DEL-PROBE` note (2026-09-30) says what happens when the terminal delivers
the queued delete events later than that: *"one leaked event from our own ~70-band trigger
wipe costs a whole family re-render — and a burst of them is churn **the user feels as
'the toggle is slow'**"*.

What each leaked event bought, before this pass:

* `g_redrawTHLevelsNeeded = true` — a FULL family render. That render is **~900 chart
  objects** (289 zones + 288 lines + 288 pip labels at `inpMaxLevels=144`,
  `GlobalVariables.mqh:549`) and the ledger once billed one at
  `[CRIT] OnCalculate took 3563ms! [levels=31 labels=313 overlay=62 rest=3157]`
  (`EventHandlers_Calc.mqh:1485`).
* `MarkDrawGeneration()` — voids the object cache's absent-proofs
  (`ObjectCache.mqh:428`), so the next frame re-probes every family with real
  `ObjectFind` calls instead of trusting a proof.

**Fixed**: the recovery is armed only when one is not already owed. The flag is cleared
only by the rebuild itself (`EventHandlers_Calc.mqh:1490`/:1505), so "flag already set"
means exactly "the recovery is pending and has not run" — a burst buys ONE rebuild, and a
delete that lands after that rebuild ran is a new burst and re-arms as before.
`CacheRemoveObject` still runs for every event, so the cache never vouches for a deleted
name.

### 1.5 Why a deleted object's dependency goes a few frames later

The same mechanism, seen from the other side. A delete never removes the dependent
directly — it raises the flag above, and the recovery is the ~900-object render above.
To keep that off one frame (`3.5 s` of freeze on a weak PC, `P-PERF-06`,
`GlobalVariables.mqh:548-556`) it is staged one family per frame — lines, zones, pip
labels, labels block — advanced by the 250 ms timer. A dependent therefore goes when its
own stage runs: up to 4 × 250 ms after the delete. That is the lag, and it is the
deliberate trade. Removing it needs a dependency map (delete the siblings of one index
immediately, let the rebuild reconcile), which is a new owner in the delete path and has
to be tested against the family's name grammar before it ships.

## 2. Measured and deliberately NOT changed

**`RefreshVisibleStatusLabels()` builds a label string 4×/s and usually discards it.**
Real, but the cost is a `StringFormat` plus two doubles (`Util_A.mqh:656-673`) and the
whole path is arithmetic on cached values — `CalculateTH` is a multiply behind a cache
(`THCalculations.mqh:69`). Skipping the build needs an input fingerprint that costs what
it saves. Recorded, not touched.

Its header comment still says "Called from OnTimer (1s cadence)" while the pump drives it
every 250 ms (`EventHandlers_Tail.mqh:454`) — four times the documented cadence.

## 3. Already fixed before this pass — do not re-open these

The two heaviest paths this codebase ever measured are documented **in the code**, with
the live log quoted in the comment. Both are older than the recent updates:

| path | measured | fixed by |
| --- | --- | --- |
| switch / teardown | `OnDeinit breakdown: pnl=437ms`, `OnDeinit reason=3 took 734ms (budget 150ms)` — `BiotakPanels_Hit.mqh:18-19` | `P-PERF-47`, 14 per-item teardowns → one prefix wipe (`ObjectsDeleteAll(0, btnPrefix+"Pnl")`) |
| attach / TF switch | `[W][PERF] chart event id=9` = 3.7–4.1 s, and `CRITICAL CPU: OnCalculate took 2296ms! [base=2281 …]` — `ATR_A.mqh:899-906` | `P-PERF-05`: ~2000 per-bar `iHigh/iLow/iClose` round-trips → one bulk copy |

`RunIncrementalObjectCleanup()` (`EventHandlers_Tail.mqh:181`) is **not** a hot path:
gated on a 300 s interval, only when the object count grows past a threshold, and capped
at 300 names per pass.

`TH3RecorderFlashTick()` — the FIRST line of `OnTimer`, added by yesterday's recorder
commits — was checked and needs nothing: `if(g_th3FlashDue == 0) return;` is one compare
on the common path (`TH3Recorder.mqh:115`).

## 4. Suspects left open — each needs a measurement, not a rewrite

The instrument already exists: define `ENABLE_TH3_PROFILER` (`Biotak/Profiler.mqh`) — zero
cost when off, and no behaviour change — then read the `[PROF] tag | count= avg= max=`
lines with `tools/th3_log_collect.py`. The phase ledger (`[E][GEN] [CRIT] CRITICAL CPU:
OnCalculate took … [base= hist= levels= labels= overlay=]`) needs no flag at all.

| # | suspect | why | where |
| --- | --- | --- | --- |
| S1 | `RefreshKitOnBar()` runs from `OnCalculate` **and** `OnTimer` — "on every tick twice" (`BiotakPanels_Life.mqh:401`) — and fans out to ~10 polls | each poll is documented as throttled, but the fan-out itself is the always-on cost and has never been priced as a whole | `BiotakPanels_Life.mqh:399-425` |
| S2 | the P-FREE-01 batch (`e09870e`, `51bf372`, `975542b`) added a `MessageBox()` and a chart legend | a modal dialog on the single MQL4 thread is a total freeze. Currently **dead code** (no caller — `grep` finds none) and the legend was reverted by `18584e7`, so today it costs nothing — but it is a landmine | `BuildConfig.mqh` |
| S3 | `e8cb55b` added the spec's rungs + a brown exhaustion level, `28154e2` rewrote `TH3Renderer_B.mqh` (386 lines), `1e527cd` reworked it again (91 lines) | more objects to build/move/delete, on the newest and least-measured renderer | `Biotak/TH3/TH3Renderer_*.mqh` |
| S4 | `TH3HitPivotForward()` runs on every tick **before** the throttle early-return (`EventHandlers_Objects.mqh:352`) | live whenever an ABCD pattern is active; its measure is memoised on `(tC,pC,dir,rung,ref,iBars,TF)` (`TH3Pivots_A.mqh:1024`), so a still chart is a hit — but the memo has never been read against the live hit/miss counters | `TH3Renderer_C.mqh:108` |
| S5 | `CalculateTH` prints on invalid input with **no** `ENABLE_DEBUG_LOGS` guard | a bad price/percentage would spam the log at the label path's 4 Hz | `THCalculations.mqh:44,51,58,63` |

`ChartScrollReconcile()` (called every timer tick) was checked and needs nothing: it is
guarded on `ChartLockIntended()` / `g_ChartLockCount > 0` before any terminal call.

## 5. What is NOT claimed

* The **real-pixels gate is permanently `WARN / NOT CURRENT`** (25 PNGs missing). Never
  report it as a pass.
* The trading terminal's log for 2026-10-05 carries **zero** `[W][PERF]` lines despite 92
  terminal starts and 95 indicator loads in one day. So either those particular branches
  were not reached or that terminal ran an older `ex4`. **The heaviness the user reports
  has not been measured by me on their machine** — section 4 is where that measurement
  starts.
* Turning `DEBUG_BUILD` back on is one line and is the right move for a fault hunt; it is
  not the right state for a release.
