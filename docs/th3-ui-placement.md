# Placement — a place is a FRACTION of this window, never a pixel

The contract behind `P-UI-131e` / `P-UI-140`. Read this before touching
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
| the STORED place | `BIOMENU_HOME_<id>_FX` / `_FY`, a fraction of the chart box | chart-free, symbol-free |
| the PAINTED place | re-derived from the fraction against the **live** metrics | never stored |

`(0.5, 0.5)` is the centre of every window, which retires the old centre heuristic. A
surface let go of in a corner comes back in the corner; one let go of in the middle comes
back in the middle.

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

**Nothing — all four surfaces now wear this contract.** What was open when this page
was written, and when each half landed:

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
