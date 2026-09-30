# AGENTS.md — Biotak Trigger TH3 (MQL4)

MT4 custom indicator. MQL4 only, no Python.

Reply in Persian. Short lines. Proof (file, number, log line), no adjectives.
Test steps at the end. English only as literal code/screen names.

The rules live in [docs/contract.md](docs/contract.md) — one page, the only contract.
Anything not written there is not a rule.

## Layout

```
Biotak Trigger TH3.mq4        Full entry — thin stub
Biotak Trigger TH3 Lite.mq4   Lite entry — same, with #define BUILD_LITE
Biotak/                       All product logic (*.mqh, include-guarded, includes on top)
  EventHandlers.mqh           The composed chain both entries call
  RuntimeSettings.mqh         Single owner of panel-editable settings
  GlobalVariables.mqh         Indicator-wide state
Files/Icons/                  Runtime BMPs, embedded via #resource
tests/                        Harnesses, compiled by the gate
tools/                        Deploy, icon gen, submenu check
build-logs/                   Compile logs (gitignored)
```

## Rules

- Entries stay thin. All logic in `Biotak/*.mqh`.
- Never compile a `.mqh` directly.
- Shared modules must not call UI functions Lite does not have (breaks Lite).
- Settings live in `RuntimeSettings.mqh`; seed via `RuntimeSettingsInit()` first in init.
  `FF_` addresses never renumber.
- Indicator-wide state goes in `GlobalVariables.mqh`.
- Icons come from `node tools/gen-th3-icons.js` plus an entry in `tools/icon-manifest.txt`.
- Ownership and the MT4 traps: [docs/contract.md](docs/contract.md) §1–§2. Never copy a rule
  up into this file — the contract is the one home.
- Use file tools for reading/writing. Terminal is only for compile, git, move/delete, tests.

## Touch rule (a change is a change until its dependents are checked)

A green compile is NOT proof of unchanged behaviour. It proves the names resolve,
nothing more. Before you report any write / delete / rename / retune as done:

1. **Name the dependents.** Grep every caller of what you changed and read each one.
   Report them as `file:line` — a change with no named dependents is not finished.
2. **An object NAME, a `GV` key, a `FF_` address and a `#define` are behaviour, not
   text.** Rename one and every name a previous build wrote is now an ORPHAN: it
   survives on the chart or in the terminal and paints beside the new one. Two
   surfaces, mixed — the exact report. A rename ships with the sweep that removes
   the old spelling, or it does not ship.
3. **A layout constant is read by more than its owner.** A height, a pad, an air or
   a row pitch is arithmetic several surfaces share. Retuning it changes every
   reader, including one that only looked local. Re-derive each reader's total.
4. **A fence that returns early may be the bug.** A `return` on a "cannot happen"
   branch draws NOTHING (an invisible zero-width box, a missing plate) where the
   old code drew a fallback. Degrade to the previous look, never to nothing.
5. **Never fix a symptom you have not measured.** If you cannot name the number
   that proves the defect, say so and ask for it instead of shipping a guess.
6. **One fix, one cause.** If a symptom has two live writers, the second is the
   bug: find who else writes it and say so in the report.
7. **A control that is painted is not a control that works.** Every painter in
   `DrawStrip.mqh` is born `OBJPROP_SELECTABLE=false` (3317 / 3366 / 3413 / 3444),
   so MT4 never fires `OBJECT_CLICK` for it and a router that matches on the
   clicked object's NAME can never answer. The `Box Settings` panel shipped with
   every tab, row, switch and foot button dead on a green compile for exactly
   this reason (P-DRAW-84). The cards work because `PnlHandleClick` gives
   coordinates first refusal (`PnlClickFallback`, BiotakPanels 9488). A new
   control needs a coordinate hit test that reads the SAME seat arrays the paint
   writes — a hit test with its own arithmetic is a second grid.

## Optimize rule (cheaper is better, scope is not negotiable)

An optimisation IS allowed — and wanted. The target is the weakest machine
(contract §5). But it is only ever allowed **inside the section that asked for
it**, and it must be invisible to every other section:

- **The cheaper one ships, and its cost is a number.** "Fewer writes" is a claim;
  state what it replaced (one full pass → one probe) and what it now costs.
- **Do NOT widen the change.** No refactoring a neighbour, no "while I was here",
  no re-deriving a shared constant. A second surface touched is a second
  behaviour change, and it inherits the whole Touch rule.
- **Keep the OUTPUT byte-identical.** Same geometry, same name, same colour, same
  pixel, same object count. A caller that cannot tell the two apart by reading
  the chart is the only acceptable proof. If the output moves by one pixel
  anywhere, it is a behaviour change, not an optimisation.
- **The caller set is frozen.** If an optimisation would change a signature, a
  return type, a `#define` or a name that a caller reads, it is NOT an
  optimisation — it is Touch rule item 2, and it ships with its sweep.
- **Cheaper, then prove it.** A still frame must cost zero writes; a bounded
  walk is allowed only with the count written next to it.


## Build — ONE way, and it prints the proof

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -SourceFile "$PWD\Biotak Trigger TH3 Lite.mq4"
Get-ChildItem tests\*.mq4 | ForEach-Object { powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -SourceFile $_.FullName }
node tools/submenu_geometry_check.js
node tools/check-resources.js
node tools/check-level-continuity.js
node tools/check-regressions.js
node tools/object_lifecycle_check.js
python tools/check-gear-panel.py
```

`compile-th3.ps1` is the ONLY build. Do not hand-roll a metaeditor call, and do not
add a second script for the same job.

**Deploy is a restart, and it is opt-in.** MT4 runs what it loaded at attach; a
fresh ex4 is a file until the terminal restarts or the indicator is removed and
re-added per chart. `-RestartTerminal` closes MT4 (gracefully first, forced after
25 s) and relaunches each instance with its own path and flags, so every chart
reloads from the new ex4 in one step. It runs only on full success, only when
asked — killing the terminal also stops anything else it hosts. Without the flag,
a build ends with `NEXT: remove and re-add the indicator in MT4.`

**Both entries are built, always.** `-Project all` is the Main entry only (its
"installed" leg is the same file through the junction, so it is one build, not
two). `Biotak Trigger TH3 Lite.mq4` is a second compiling unit and has no
`-Project` target — it is built with `-SourceFile`, like a harness. There is no
`-Project lite`; asking for one fails the ValidateSet, which is the point. A
report that says "Main and Lite both compile" without the second line did not
build Lite.

What the output now guarantees, and why each line exists:

- **`ex4 before: N bytes HH:MM:SS` / `Output: … (N bytes, HH:MM:SS ±D)`** — a build
  that prints `0 errors` but leaves the ex4 alone has changed nothing the terminal
  will load. The pair is the only answer to "did it actually rebuild". A `WARNING:
  ex4 was NOT rewritten` is a failed deploy, not a clean build.
  **But `±D != 0` is NOT proof of a source change either.** Two consecutive builds
  of an unchanged tree differ (the compiler stamps the ex4): 3,435,670 → 3,434,838
  → 3,436,196 on 2026-09-29 with no edit between them. Read `±D` as "the file was
  rewritten", and get "the code changed" from the diff, never from the byte count.
- **`[PASS] resource gate`** — every raster a unit PAINTS is `#resource`d in that
  same unit, and every declared raster exists beside the source. A missing
  declaration is a **silent** runtime no-op that a green compile cannot see: the
  object is created, the property written, MT4 paints nothing. It shipped a panel
  with no plate, no foot skin and no glyphs on 2026-09-29, and the compiler named
  nothing. `tools/check-resources.js` is the gate; run it by hand after touching any
  `::Files\Icons\` string.- **`[PASS] level continuity gate`** — the six sites that make a timeframe switch a
  HANDOFF are still the six in the contract (§8, P-VIEW-06): the stamp, the chart
  witness, the two ungated probe lines, the two declared `ClearAllLevels` callers, the
  ONE writer of `g_adoptPreviousTopology`, and the fence on the reinit wipe. A change
  made anywhere ELSE that would make the switch a wipe-and-rebuild again fails the
  build here, at the name, before the terminal ever sees it. `tools/check-level-continuity.js`
  is the gate; run it by hand after touching any deinit branch, wipe site or
  `g_forceClearOnNextDraw` writer.
- **`[PASS] gear panel gate`** — the four `Box Settings` tabs are re-rendered offline from the MQL's own literals (`tools/sim-gear-panel.py`) and every tab's
  height must land on the cards' law `56 + n*42 + 48` for `n` in 1..10, or the
  plate silently falls out of the one-baked-card branch into the composed W body.
  This gate is what found the 6px double count (`DSTRIP_GEAR_AIR` on top of a
  48px foot band, P-DRAW-78b) that put all four tabs off the grid. Run it after
  touching any `DSTRIP_GEAR_*` height, pad or air. The same gate asserts every
  PAINTED control has a non-empty hit box on every tab — the dead-button class of
  P-DRAW-84, which compiles clean and looks perfect.
- **`[PASS] object lifecycle gate`** — every object name a surface PAINTS
  (`Biotak/**/*.mqh`, 125 files) must have a destroy path the same surface reaches:
  an `ObjectDelete`/`ObjectFind` site for that name, an entry in its own prune LIST,
  or a family-specific `ObjectsDeleteAll` prefix. `P DRAW-84`'s class is a name
  painted for a band that was retired; the one found on the gate's first tree-wide
  run was the colour board's two page seats and their `1/2` caption — painted
  (DrawStrip_Paint.mqh) and never listed in `DrawStripPopChromePrune`, so they stayed
  on the strip after the board closed. The gate names the file, the line and the
  family; `tools/object_lifecycle_check.js` is the gate; run it by hand after
  touching any painter's name argument or any teardown path.
- **`[PASS] regression gate`** — the register of already-fixed defects, asserted
  against the sources in every build (contract §9): the TH mask's name family
  (`<prefix>LBL_TH_*`, P-TH-02) with its `[P-LBL] TH mask mode= applied=` witness, the
  label clear still being a sweep, the T toggle's ONE owner (`SetTriggerLevelsVisible`:
  mask walk + discrete repaint, never a clear) with its `[P-KEY] T press` → `T applied
  … ms=` pair, its `TriggerFamilyWalk`, the F-show re-assert, the render's trigger
  branch being a mask (never a delete) with its `T settled … ms=` reconciliation line,
  the coalescer still owing a frame, the HTF family's single writer with its `[P-HTF]`
  look/cull probes, and the HTF card's row→flag map and captions. Every entry was once a green build, because MT4 answers
  nothing to a write aimed at a name the chart does not carry. `tools/check-regressions.js`
  is the gate; run it by hand after touching a label mask, a hotkey path, the coalescer
  or the HTF card.
- **one build, not two** — `MQL4\Indicators\BiotakProject` is a JUNCTION to this
  repo, so the "installed" source and the workspace source are ONE file and the
  "installed" ex4 is the workspace ex4. `-Project all` compiles it once and says so.
  A second `[PASS]` for the same bytes was never a second confirmation.

Deploy is still **remove & re-add** in MT4: `#resource` and indicator state are
bound at attach, and no programmatic reload exists in MQL4. A correct build with a
stale chart is a removed indicator, not a failed compile. The script now prints
`NEXT: remove and re-add the indicator in MT4.` on every successful build, because
"my change did nothing" on this panel was this line being invisible for a day.

After BMP changes: recompile, then remove and re-add.

