# Placement — a place is a FRACTION of this window, never a pixel

The contract behind `P-UI-131e` / `P-UI-140` / `P-UI-165`. Read this before touching
`Biotak/BiotakHomes.mqh`, the `CHART_CHANGE` branch, or the `OnTimer` pass.

## The report

«این دوتا موقع ریستارت ترمینال چرا از جاش تکون میخوره» — the orb (bottom-left) and the
chip (the pinned Persian banner, top-right) came back somewhere else after a terminal
restart. Resizing, maximize/restore and a monitor move did the same thing.

## The cause

Both homes were stored as **absolute pixels** (`BIOMENU_HOME_<id>X` / `_Y`). A restart
re-lays the terminal window out, so the same number is painted into a box of a different
size:

* a chart that came back **smaller** clamped the surface against a wall — and the clamp
  was then saved back as the home, so the drift was permanent (`P-UI-131e`);
* a chart that came back **larger** left the surface where the old, smaller window had
  put it, i.e. in the wrong relative place;
* a stored pair that happened to equal the chart's centre was adopted as a real home on
  a chart that had never been placed at all, because every chart's first init wrote that
  pair (`P-UI-118`).

## The rule

One rule answers every scenario — restart, resize, maximize/restore, another monitor's
DPI, another symbol or another chart:

| form | owner | key |
| --- | --- | --- |
| the STORED place | `BIOMENU_<SYM>_HOME_<id>_FX` / `_FY`, a fraction of the chart box | chart-free, PAIR-scoped (P-UI-165); the pre-165 `BIOMENU_HOME_<id>_*` key is a read-only migration source |
| the PAINTED place | re-derived from the fraction against the **live** metrics | never stored |

`(0.5, 0.5)` is the centre of every window, which retires the old centre heuristic. A
surface let go of in a corner comes back in the corner; one let go of in the middle comes
back in the middle.

* **One pair's hand never moves another pair's surface** (P-UI-165): the key carries
  `_Symbol` (`PnlFracKey` for the panels, `GVHomeName`/`GVHomeFracName` for the three
  surfaces), because several instances on different pairs are several minds. `P-UI-131e`'s
  chart-free key made one pair's place land on ALL of them. `GVHomeLoadFrac()` snapshots
  the shared pre-165 pair into the pair's own key once, in a measured window, and no
  writer ever writes or deletes the shared keys — every other pair still needs them.

* **Read**: `GVHomeLoadFrac()` — fractions first; a legacy pixel pair is migrated **once**,
  in the window it is read in, and the pixel keys are deleted in the same breath.
* **Read, no write**: `GVHomeFracRead()` — the only reader the 250 ms pass may use. A read
  that repairs the store is a write under the user's hand, which is the ratchet
  `P-UI-131e` removed.
* **Write**: `GVHomeSaveFrac()` — only from a **real** hand move: the orb's drag release
  (`BiotakMenu_C.mqh`), the chip's drag (`BiotakMenu_B.mqh`), and the two slot guards in
  `SaveUIStates`. A clamped value is never a stored value.
* **Re-derive**: `CircHomesRefresh()` (`BiotakMenu_C.mqh`) — updates the **HOME**, never
  the live pair (the pair is a *derivation* of the home). Called from the `CHART_CHANGE`
  branch immediately, and from the 250 ms `OnTimer` pass as the safety net for a missed
  notification — the exact shape of `P-PERF-16`'s metrics invalidation beside it.
  Cost in the steady state: two terminal reads per quarter second and two compares.
* **Stand off**: a live drag owns its surface — `g_OrbDragging`, `CircTipDragging()`.

## Why the file split

`BiotakMenu_A.mqh` reached 1532 lines in this change. Contract §7 says a file over the
1500-line ceiling never grows — touch it = split it by owner — so the homes moved out to
`Biotak/BiotakHomes.mqh`, included **above** `BiotakMenu_A.mqh` (MQL4 resolves a call
top-down; every reader of a home lives below the cut).

## Not yet covered

**One class was open, and it was the POPUPS** — found 2026-10-31 by reading the tree, not
by a report (P-UI-222). Every surface that OWNS a home re-derived it on a resize; the two
popups that hang off a surface did not:

* **The palette** was placed by `PalComputePos` from exactly one caller, `PalOpenKind`.
  A chart that shrank under an open popup left `g_PalX` outside the new width, where MT4
  clips the whole family — swatches, Done button and TR track gone, Esc the only exit. A
  DPI change healed it (`UIRebuildForMetrics` re-opens the kind); a plain resize did not.
  Fixed by `PalReclampOpen()` — the same owner, called from the `CHART_CHANGE` branch, so
  the place is RE-DERIVED from its home (a hand spot clamps from `s_palMX/MY`, a card or
  drawing spot re-anchors to its live parent) instead of a clamped value being stored.
* **The Box Settings panel** was re-placed by `DrawStripPlaceGear`, which runs inside
  `DrawStripPaint` — and `DrawStripHomeClamp` returned BEFORE that paint whenever the
  strip's own plate needed no move. A chart that shrank under a panel whose plate fitted
  kept the panel at its old y, its foot and Done button below the chart edge (P-UI-188's
  law, one surface over). Fixed in the clamp's early-return branch: the placer is asked,
  and the paint runs only when its answer moved.

The general answer is contract §10: a UI surface is a row in `tools/ui-scenarios.js`, and
`tools/ui_scenario_check.js` fails on a painter file that belongs to no row, on a `popup`
with no resize answer, and on an answer whose call site is gone. A comment is not a call.

**The case a clamp cannot answer.** Every law above is about *where* a surface goes. None
of them answers the window that is smaller than the surface: the clamp pins it to the
top-left and the overflow runs off the bottom-right, so the Done pill and the header `.x`
can both be outside the chart. Nothing places a 520 px card inside a 380 px window — the
arithmetic runs out. What makes that survivable is Esc dismissing inside-out: palette,
then the open dropdown, then the card; the strip takes its gear before its picker before
its plate (P-DRAW-13); the knot's draw session ends on Esc too. That ladder is now axis
**S13** and rule **P-UI-223**, because it had no register rule and no mutation — one
deleted line would have removed the only exit from every stranded surface in the product
with nothing red anywhere.

Two smaller rules came with it, both about the gate's own honesty rather than the UI:
the `SHARED` whitelist is now checked (an entry that names no file, or a file that creates
no control type, fails), and a note about a shared owner prints as `[note]` instead of
`[OPEN]` — the tag that must never be skimmed had been appearing on non-problems.

## The second tree (P-UI-224)

The matrix began MT4-only, and that was the same mistake one level up: a rule asked of one
tree is not a rule. MEASURED when the gate went per-platform — **27 of 89 MT5 sites
resolved**, `PalReclampOpen` did not exist in the MT5 tree at all, and `DrawStripHomeClamp`
still returned before re-placing its gear panel. So both P-UI-222 defects were live on MT5
while the MT4 tree carried the fix, and nothing was red anywhere.

Two things followed, and they are different in kind:

* **The port.** `PalReclampOpen` and the clamp's re-place branch now exist in
  `Biotak-Trigger-TH3-mql5/Biotak/BiotakPanels.mqh` and `…/DrawStrip.mqh`, identical in
  logic to MT4. Both MT5 entries compile 0 errors / 0 warnings with them.
* **The question.** The matrix declares both trees, each row names its files on each
  (`files` / `filesM5`), and the gate reports them apart. 89 of 89 sites now resolve on
  MT5 — 71 of them through the unit, because MT5 is still unsplit. Those 71 are printed as
  `mapped`, which is the honest label: the code is there, in a different file.

The MT5 build runs the gate scoped to its own tree (`--platform=mt5`) after a clean
compile. The MT4 build runs both. Neither can go green while the other is broken.

What was open when this page was written, and when each half landed:

* **The strip's home was stored in pixels and saved a clamped value back as the home**
  (`DrawStripOpenAt`, `DrawStripHomeClamp`). Fixed 2026-10-13 (P-UI-144/146): the home
  is written ONLY by a fresh placement or by the hand's drag release, the live pair is
  clamped for the paint and never re-stored, so a window that comes back smaller cannot
  ratchet the place inward. `docs` law: *the value that paints (clamped) is never the
  value stored* — contract §4.
* **A chart id in the object name made every previous session a ghost.**
  `BiotakMenuV2_<ChartID>_*` is session-scoped, and MT4 saves chart objects into the
  chart's own profile and restores them at their ABSOLUTE pixels — so a restart or a
  chart reopen put the previous session's orb/panel/controls back on the chart at stale
  places, beside the fresh family the home painted. Measured: `chart03.chr` carried
  `BiotakMenuV2_134342075006101685_CircOrbBg` at x=70,y=79 (P-UI-144). One prefix walk
  per attach — `BiotakMenuGhostSweep()` in `Biotak/BiotakHomes.mqh`, called from
  `InitializeUIStates` — removes every foreign spelling; the same shape
  `DrawStripSweepStale` took for the chart-id-free strip family.
* **A shaky press dragged a control off its seat.** Every card/palette control is born
  selectable for the name router, and the terminal grabs a selectable object on the
  press that lands on it (P-UI-48). Fixed 2026-10-13 (P-UI-145): a seat registry filled
  by the one button factory, kept in lockstep by the one mover, spent by the terminal's
  own `CHARTEVENT_OBJECT_DRAG` — the control is put back and its selection dropped in
  the same event.
* **The strip's open state was never restored** (the panels had a snapshot/restore since
  P-UI-142; the strip shut at every attach). Fixed 2026-10-13 (P-UI-146): five keys per
  symbol+period — open · the served drawing's hash pair · the gear tab · its collapse ·
  the pin — written at teardown start, restored once on the first tick after a fresh
  attach under `PnlRestoreSaved`'s own gate. The pickers, the colour board and the
  palette popup are deliberately NOT in the record: they are popups of a surface, not
  surfaces.

What stays derived and is not a stored place: the ring's shape (arc / train / grid,
re-derived from the live geometry every pass), the cards' width (row-count derived),
and the strip's width (per-kind derived). A resize therefore re-derives a shape and
keeps a place — which is the whole separation this page asks for.
