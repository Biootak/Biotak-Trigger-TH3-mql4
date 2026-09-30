# contract.md — the live rules (the only contract)

One page. A rule here is not advice: a surface that fails a line is a bug.
Every claim carries a number (file:line) or it is not a claim.
A note that no longer matches the code is DELETED, not kept — a stale `OPEN`
sends the next reader after a bug that no longer exists. There is no second archive:
this page IS the whole contract.

## 1. Ownership (one owner, never a second copy)

| value | owner |
|---|---|
| palette | `BioPickColor` / `BioPickAt` / `BIOPAL_N` (`ConstantsAndEnums.mqh`) |
| z ladder | `Z_*` (`ConstantsAndEnums.mqh`) — paint order IS click priority |
| ink | `BIO_CLR_*`; `PNL_CLR_*` / `DSTRIP_CLR_*` are aliases, never a second literal |
| text metrics | `PnlPt` / `PnlTextW` / `PnlLineH` / `PnlFit` (`UtilityFunctions.mqh`) |
| geometry | card `312 / 624 / 42 / 56 / 48`; plate law `48 + 42k` |
| swatch floor | `BioSwatchBorder` + `BIO_SWATCH_MIN_CONTRAST` |
| the UI claim | `UIPointerOverSurface` (where) + `UIPeekClickClaim` (whose) |
| view lock | `ChartLockIntended()` — a gesture that locks the view names itself the day it is born |

A *face* (alias, wrapper, reader) is expected. A second *owner* is the defect.
Include order is ownership: `ConstantsAndEnums` → `UtilityFunctions` → `DrawStrip`
→ `BiotakMenu` → `BiotakPanels`. Move a rule down, never copy it up.

## 2. What MT4 cannot do (and the answer we ship)

- no bitmap scaling — it crops: bake the size and 9-slice; crop, never stretch.
- no rounded corner, shadow or gradient on a native rect: bake the skin, and fill the
  object beneath with exactly the footer ink so no square peeks through a radius.
- no real translucency: bake the glass into the BMP; a solid underlayer under it.
- **`OBJPROP_TIMEFRAMES` is a LABEL-only property** — a rect/bitmap keeps showing. Hide a
  plate by EXISTENCE (delete it), never by a period mask.
- no mouse-wheel event, no double-click event, no right click without the native menu:
  ship explicit +/− or a drag, measure the click interval, use left gestures only.
- one target per pixel: only the highest ZORDER receives `CHARTEVENT_CLICK`; a face drawn
  above a control is non-selectable (skin above, button below).
- `ZORDER` cannot lift a panel over the candles: use `CHART_FOREGROUND`.
- object text truncates at **63 chars**: wrap one logical line into a family of objects.
- the object list is user-facing: chrome wears `OBJPROP_HIDDEN`; every created name is
  deleted by the same surface's destroy.

## 3. Appearance (the dirt list, hunted proactively — not only when reported)

A swatch that reads as a hole · a caption running into its control (use `PnlFit`) ·
hierarchy collapsing at other DPI (compute the points) · a hairline crossing ink ·
an off-grid plate edge · a shadow eaten by a neighbour · an empty bar over a readout ·
a ghost surface on the wrong timeframe · a stale surface after a TF switch · a hover face
left painted · a control that draws but cannot be hit (and the reverse) · a control
clipped by the card edge · flicker on a tick · the chart jumping under the hand · the
wrong object getting the click · a surface opening on the cursor over the work · two
surfaces overlapping · a colour that "does not work" because the face ignored the value ·
one act spelled two ways · a dead `Z_*` rung · a comment that cites a function nobody calls.

## 4. Lifecycle

Reattach · TF switch · terminal restart · template re-apply: every surface survives all
four. Panel-editable settings live in `RuntimeSettings.mqh` and nowhere else;
indicator-wide state in `GlobalVariables.mqh`; what must ride an object lives in its
`DESCRIPTION`. A placed surface's home key carries no chart and no symbol; the value that
paints (clamped) is never the value stored; a remove SAVES like any teardown.
Never advertise a state that did not happen — delete the mark, do not dim it.

## 5. Performance

Realtime is the same event: a follower writes in the event that moved its owner; a
deferred frame IS the lag. At rest: zero writes, zero polling. A still frame is reads only.
Nothing whose cost scales with the chart enters the mouse stream or the tick path, and
every walk is bounded by a stated count. The target is the weakest supported machine;
when two solutions behave the same, the cheaper one ships and its cost is a number
(`CPU_WARNING_MS 50` / `CPU_CRITICAL_MS 200`, `COOP_WARN_MS 40`).

- **An update changes ONE surface; the register is what keeps the others still.**
  The change may move the behaviour of the surface that asked for it, and of nothing
  else: a shared name, mask, flag, walk or layout constant keeps every other reader's
  behaviour identical, or the change names those readers in its report (Touch rule 1)
  and the register gains their assertion. A fixed defect's shape is asserted in
  `tools/check-regressions.js` so the next edit cannot put it back — *e.g.* the trigger
  overlay, whose press paints through its own owner (`SetTriggerLevelsVisible`: state +
  key + its own mask walk + the discrete repaint, never the render's pixels), whose
  render branch is a priced mask (never a delete) and whose F show re-asserts the family
  through that same walk. Editing any of it is allowed; changing what a DIFFERENT surface
  sees is not — and the gate is a guard, not a freeze (see §9).

## 6. Gate (definition of done)

1. `compile-th3.ps1 -Project all` → `Result: 0 errors` (Full), then the same for
   `Biotak Trigger TH3 Lite.mq4` and every harness (`-SourceFile`, one run each).
2. `node tools/submenu_geometry_check.js` passes.
3. No new literal for a colour, pixel, z-order or font; no second table.
4. Every swatch through `BioSwatchBorder`; every caption measured with `PnlFit`.
5. Every new raster has a `#resource` line AND a `tools/icon-manifest.txt` entry, and
   every file on disk has a manifest entry.
6. A change to generated assets hashes the set before and after: untouched files
   byte-identical.
7. The report names the file, the number and the measurement.
8. `node tools/object_lifecycle_check.js` passes — a name a surface PAINTS must be a
   name it can DELETE: every object name in `Biotak/**/*.mqh` needs an
   `ObjectDelete`/`ObjectFind` site, an entry in its own prune list, or a
   family-specific prefix. A name a panel forgets to take down compiles clean and
   paints nothing wrong — it simply stays there, over the next tab's plate, and that
   is the class the gate names by file and line (P-DRAW-84/92).
9. `node tools/check-level-continuity.js` passes — a switch is a handoff, and that
   gate is what keeps it one (§8, P-VIEW-06).
10. `node tools/check-regressions.js` passes — the register of already-fixed defects
   (§9) is a gate, not a memory: a name that was wrong, a second writer, a dropped
   frame and a row→flag map are each asserted against the sources, so the next edit
   that breaks one fails HERE, at the name, before the terminal sees it.

## 7. Size (one file, one owner)

One file = one owner, `<= 1500` lines (`[System.IO.File]::ReadAllLines`).
A file over the ceiling never grows: touch it = split it by owner
(state / names / layout / paint / router), same names, same output,
orphan sweep included. A new file over the ceiling fails the gate.
One function over the ceiling stays whole and never grows.

## 8. The window, the level family, the switch

- **The window owns nothing.** `inViewport` is a FLAG on a built level, never a mask
  and never a `continue`. Every level the build produced is an object carrying the
  owner's mask (F / L / `IsIndicatorHidden`) and is painted; MT4 clips the rest. A
  fence that returns early is a level that can stay missing (P-VIEW-01/03).
- **A pan is not a rebuild.** The cull window is not an input of the frame signature
  (`frameCore`) and cannot drop a band. Scrolling costs zero indicator work
  (P-VIEW-02), which is why the pre-warm is a consequence and not a feature: the band
  just outside the view is already an object when the user scrolls to it.
- **The historical bound is a view margin.** `g_highestHigh/Low` stops the ladder
  `P_LEVEL_BOUND_OVERDRAW` (3) rungs PAST the extreme, never before it; the count stays
  the mode's own `maxLevelsAbove/Below`, so the margin can only spend rungs the count
  had left (P-LEVEL-BOUND-03).
- **Cache layers, in order, and what may invalidate each:** geometry
  (`PipelineGeometryKey`) → build → render (`applyRefreshFlags`). A user edit rides
  `g_renderAllNeeded`; a mask flip rides the vis-only path; a still frame compares
  strings and writes nothing.
- **A level's NAME is its identity, and one path may delete:** the sweep that compares
  the family against the list just built (P-LEVEL-FOREIGN-01/02). A timeframe switch is
  a HANDOFF through that path, never a wipe-and-rebuild.
- **One unit per chart.** Lite and Full paint the same object names, so two of them on
  one chart means two writers per name (missing bands, a countdown re-created every
  second, two owners on the card's inks). The second unit refuses to load and says so
  (P-ARCH-03).
- **A switch is a HANDOFF, and nothing outside this family may un-make it.** On a
  reinit (TF switch, template re-apply, attach) the family already on the chart is
  ADOPTED and re-priced IN PLACE: no `ClearAllLevels`, no staged rebuild, `stage=0` in
  the census of the switch frame. The verdict has TWO witnesses and both stay: the
  teardown's stamp (`SaveTopologyAdoptionStamp`) and the CHART itself
  (`LevelFamilyObjectsOnChart` — a GlobalVariable that is missing is not a licence to
  wipe; that missing case was the third report of this defect, P-VIEW-05). The pair
  `probe=handoff preexist=` / `probe=adopt preexist= adopted=1` is the proof, a plain
  `Print`, never gated, renamed or removed.
- **No other surface may delete the family.** `ClearAllLevels` has exactly two callers
  (the `shouldClearLevels` wipe and the levels-off branch); the reinit wipe stays fenced
  behind `!g_adoptPreviousTopology`; `g_adoptPreviousTopology` has ONE writer. A panel,
  label, manager, cache or new feature that adds a delete, an unfenced
  `g_forceClearOnNextDraw` or a second writer changes this behaviour without editing
  this file — which is why `node tools/check-level-continuity.js` runs in EVERY build
  and fails on all six sites (P-VIEW-06). Changed anything anywhere? That gate is the
  answer, and the runtime pair above is the number.
- **Measure before you simplify here.** The one-line census
  (`[P-VIEW] stage=census lines=… absent=… mask=min..max …`) is the arbiter: `absent=0`
  with a uniform mask means every built level is on the chart, so a hole is a DELETION
  or a second writer — never the paint.
- **A candle wider than the window is pitched to the window.** The HTF overlay
  (`HTFRefreshSlotMetrics`, `Biotak/HTFCandles_Geom.mqh`) draws a rung whose candle
  cannot fit the viewport `HTF_SLOT_MIN_CANDLES` (4) times on a slot pitch of
  `CHART_VISIBLE_BARS / 4` chart bars anchored at bar 0 — the OHLC stays the real HTF
  series, only the x pitch is schematic. A rung that already fits returns before any
  read, so its geometry is untouched. Witness: `[P-HTF] slot htf= chart= vis= ratio=
  slot=` (P-HTF-SLOT).

## 9. An edit predicts its own consequences, and the register is a gate

- **A change is not finished until its dependents are named.** Every name, mask,
  prefix, `#define`, writer and layout constant you touch has a caller set, and it is
  reported as `file:line` in the same report. "It compiles" proves only that the names
  resolve: MT4 answers NOTHING to a write aimed at a name the chart does not carry, so
  a whole release can mask `<prefix>TH_*` while every TH object is born
  `<prefix>LBL_TH_*` (P-TH-02), or address a flag a shifted row never writes.
- **A second writer is the bug.** When a symptom has two live writers, name the second
  one; the fix removes it or makes ONE owner. The TH mask has one owner
  (`SetTHLabelsVisibility`), and the relayout writes the same value for the family its
  own caller is gated on — never a second arithmetic.
- **A change anywhere must not silently change a fixed behaviour.** The REGISTER:
  `tools/check-regressions.js` runs in every build and asserts the sites the fixed
  defects are made of — the TH mask name and its `[P-LBL] TH mask mode= applied=`
  witness, the label sweep (never a bulk wipe), the T toggle's ONE owner
  (`SetTriggerLevelsVisible` — state, persisted key, mask walk, discrete repaint), its
  press-time `[P-KEY] T press` → `T applied ms=` pair, the family walk it paints
  through, the F-show re-assert, the render's trigger branch being a MASK (never a
  delete) and its reconciliation `T settled ms=` line, the coalescer that still owes a
  frame, the HTF family's single writer with its `[P-HTF]` look/cull probes, and the
  HTF card's row→flag map and captions. A new defect that was real is added to the
  register WITH its probe line, so the next regression has a number to fail on. The
  gate is a guard, not a freeze: a change that legitimately reshapes one of these sites
  updates the register in the same commit and says so in its report — what it may never
  do is move a site's behaviour while leaving the register asserting the old one.
- **Predict, then verify.** Before an edit lands, write down which surfaces read what
  changed and re-check the fixed defects that share it. A symptom with no measurable
  number is a question for the user, not a guess committed to the tree (Touch rule 5).
