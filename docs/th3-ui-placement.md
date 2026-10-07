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

The strip's own home (`DrawStripHomeSet`, `Biotak/DrawStrip_Paint.mqh`) is still stored in
pixels and, worse, still saves a **clamped** value back as the home
(`DrawStripOpenAt`, `DrawStripHomeClamp`). It is the same defect class and the next
surface owed this contract.
