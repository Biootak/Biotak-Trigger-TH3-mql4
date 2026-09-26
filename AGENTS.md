# AGENTS.md — Biotak Trigger TH3 (MQL4)

MT4 custom indicator (Prof. Khakestar's TH levels). MQL4 only. There is **no
Python** in this repo (P-TOOL-04) and there is no room for any.

The full narrative history — every `P-*` note with its measurements, the
research results and the tooling that came and went — lives in
`docs/history.md`. **What follows is the contract**; history.md is where you go
when you need the WHY behind a rule.

## Tool discipline (read this first — user order, 2026-09-25)

**Use your own tools.** The API you run on gives you file tools; a shell command
that re-implements one of them is a defect, not a shortcut. The user's words:
«از ابزار خودت استفاده بکن نه اینکه با کد و اسکریپت کدها بنویسی و ویرایش و
بخونی».

- **Read** with `read_files` (windows: `{path, offset, limit}`), **find** with
  `code_search`, `glob`, `list_directory`.
- **Write and edit** with `write_file` / `str_replace`. Never `cat`, `sed`,
  `awk`, `printf`, heredoc or a one-off script to read or write code.
- **The terminal is only for what has no tool**: compiling, `git`, moving or
  deleting files (there is no delete tool — `rm`/`mv` is the exception), and
  running tests. Say in the report which command did what.
- **Every terminal command must be bounded** (P-TOOL-03): the runner blocks on
  the command it waits for, so a long or wedged command does not fail, it HANGS.
  A gate slower than ~10 s is a gate to cut, not to wait for.
- **`code_search`: never `-l`, never `-c`.** Both are broken in this build — they
  answer `Found 0 matches` even for strings that exist (measured 2026-09-25).
  No flags, `-n`, `-i`, `-g <glob>` and `-A/-B/-C <n>` all work. A zero is
  therefore NOT proof of absence: re-ask without flags before believing it.
- **`read_files` without a window is a context bomb.** A bare path pulls up to
  2000 lines into the transcript; always pass `{path, offset, limit}` and read
  around the hit `code_search` gave you.
- **`glob`, `code_search` and `read_files` cannot see gitignored files** (a
  `tests/*.ex4` glob answers 0 files while six sit on disk; `read_files` on any
  ignored path — `build-logs/*` included — answers `[BLOCKED]`). Only
  `list_directory` can: re-measured 2026-09-25, and a **tracked** binary still
  reads (rendered as an image), so a repo screenshot is legitimate evidence.
- **Two tools in this build are dead**: `run_terminal_command` with
  `process_type: "BACKGROUND"`, and `run_file_change_hooks`. Do not plan a dev
  server, a watcher or a hook around them — there is no way to leave one running.
- **File tools cannot leave the project.** An absolute path outside the workspace
  reads as `[FILE_DOES_NOT_EXIST]`, so a cross-project file needs the terminal and
  the user's explicit say-so.
- **The compiler is the gate.** Reachability ("is this module alive?") is
  answered by the `#include` graph plus a green compile of every entry — never by
  memory, never by "it looks unused".
- **These rules are project-agnostic.** `docs/agent-tooling.md` holds the full
  measured matrix plus the fast paths, written so it can be copied into ANY
  project unchanged; keep it in sync when a tool changes.

## Reply language

User speaks Persian. Reply in Persian, answer in the first line, short lines,
proof (file, number, log line) instead of adjectives, concrete test steps at the
end. English only as literal code/screen names.

## Layout

```
Biotak Trigger TH3.mq4        Full entry — thin stub: #define + event handlers
Biotak Trigger TH3 Lite.mq4   Lite entry  — same, #define BUILD_LITE inside
Biotak/                       ALL product logic, layered bottom-up
  EventHandlers.mqh             the composed chain both entries call
  RuntimeSettings.mqh           single owner of panel-editable settings
  GlobalVariables.mqh           indicator-wide state
  TradePlanFormulas.mqh         trade-plan math — nothing else may compute it
  TH3/                          the course module: pivots, skeleton, step, render
Files/Icons/                  308 runtime BMPs, embedded via #resource
Libraries/                    BiotakRCBlock.dll (deployed to MQL4/Libraries)
tests/                        7 harnesses (contract + golden + type scale) — compiled by the gate
tools/                        the live pipeline: deploy, icon gen, submenu check
  orb/                        orb art tools (bow, word, hover-chip face) + masters
  rc-bridge/                  RC blocker sources + the scripts that build them
  research/                   12 one-off .js studies (answered; not needed to build)
docs/                         history.md + pivot_arrangement_atlas.html + media/
build-logs/                   every compile log (gitignored)
```

Rules that keep it that way:

- Entries stay at the root and stay thin. All logic lives in `Biotak/*.mqh`; a
  module may only depend on modules below it; includes at the top only; every
  `.mqh` include-guarded.
- Harnesses live in `tests/` and reach the product through `#include "..\Biotak\…"`.
  Nothing else belongs at the root: only the two entries, the three build entry
  points, this file and `.gitignore`.
- Build plumbing (`compile-th3.ps1`, `compile-th3-linux.sh`,
  `compile-th3-doubleclick.bat`) stays at the root because those are the
  documented commands. Everything else belongs under `tools/`.
- Never compile a `.mqh` directly. Never make a `.mqh` call a UI function that
  Lite does not have (P-BUILD-01).
- Icons come from `node tools/gen-th3-icons.js`; a runtime bitmap needs a
  `#resource` line in `BiotakPanels.mqh` **and** an entry under `SLICED` in
  `tools/icon-manifest.txt` (written by that same generator).
- Settings: `RuntimeSettings.mqh` is the one owner (mirrors, `#define inpX gX`,
  seeding, `OV_*` persistence). Seed via `RuntimeSettingsInit()` first in
  `OnInitHandler`; never read `inpX` in a seed below the `#define`s (silent
  no-op). `FF_` enum addresses never renumber.
- Indicator-wide state → `GlobalVariables.mqh`; anything the panel can edit →
  `RuntimeSettings.mqh`, never GlobalVariables.

## Build

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -SourceFile ".\Biotak Trigger TH3 Lite.mq4"
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -SourceFile ".\tests\Biotak_TH3_Test.mq4"
# or double-click compile-th3-doubleclick.bat (Bypass + pause, so the window stays)
```

Success = `Result: 0 errors` in `build-logs/`. `-Project all` builds only the
MAIN entry (workspace + installed) — every harness needs its own `-SourceFile`
run. After BMP changes: recompile, then remove & re-add the indicator in MT4
(icons load only at attach). Full deploy: `powershell -File tools\deploy.ps1`.

Linux: `./compile-th3-linux.sh all` — isolated Wine prefix, the live terminal
stays open, and the script is **bash + coreutils only** (no Python, P-TOOL-04).
When driving PowerShell from the agent side, set `$env:APPDATA` and null BOTH
cases of each `*_proxy` variable in the SAME invocation, via
`[System.Environment]::SetEnvironmentVariable($n, $null, 'Process')` — the `env:`
provider is case-insensitive and `Start-Process` dies with «Item has already been
added» otherwise. That FAIL is the environment, not the code.

## Verify

**P-TOOL-04 (2026-09-25) — NO PYTHON IN THIS REPO.** The whole `.py` audit suite
was deleted by user order (34 files, plus `verify.plan.json` and the two root
generators). **Nothing may reintroduce it.** A rule an audit used to pin is still
the law; it is pinned by the compiler and by reading now. Anything in this file —
or in the `tools/*.py` citations inside `.mqh`/`.mq4` comments — that names a
`*-audit`, a `--selftest` or a `.py` tool is a HISTORICAL record of what was
checked when the note was written, never a runnable gate.

**The compiler is the one gate.** Every `.mq4` must print `Result: 0 errors`, and
that means the two entries **and** the seven harnesses in `tests/`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all
Get-ChildItem tests\*.mq4 | ForEach-Object { powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -SourceFile $_.FullName }
node tools/submenu_geometry_check.js
```

**P-BUILD-03 — a harness compiles from THIS repo only.** MetaEditor resolves
`#resource "\Files\Icons\x.bmp"` against the **SOURCE file's own tree**, not the
terminal's `MQL4\Files`. A harness in `tests/` therefore looks in `tests\Files`,
and without it every icon-bearing module in its chain fails with `error 310:
resource file ... not found` (325 of them, measured 2026-09-25 — while the same
modules compiled green from the root in the same run). `-SourceFile` creates the
link on demand: `tests\Files` -> `Files`, a junction **and gitignored**, never
repo content. That is also why the Linux mirror (`Biotak/`, `Files/`, the two
entries) never compiles a harness.

**every `.mq4` must compile**: Lite is a second entry that includes the domain
half but not the UI half, so a shared module that calls a UI function compiles
green in Full and breaks Lite (P-BUILD-01 — six `error 168` sites shipped that way
once). The harnesses mirror the entry's include chain by hand — a module added to
an entry and not to them breaks them silently, which is why they are compiled
here too (P-BUILD-02).

## The laws that must not be broken

**TH3 — the course's own step and pivots.** Five measured axes (momentum, pivot
candle, cover depth, cover delay, direction) pack into `TH3SkeletonKey()` —
**4 x 4 x 4 x 6 x 2 = 768 cells**. That is deliberately not the atlas's 1440: the
atlas enumerates 8 pivot-candle arrangements and 3 momentum classes, this is the
4-and-4 measurable subset. Do not "fix" one to match the other. An unmeasurable
pattern carries `valid == false` / `key == -1` and is never filled with a
plausible default.

- `ATR(structure)` reads **completed daily bars only** (shift 1, P-TH3-STEP-01).
- Momentum bands select in **ascending** order of size — WEAK smallest, NORMAL
  middle, STRONG/EXPLOSIVE largest; `short` is the blend `0.5*(long+med)`, so it
  sits BETWEEN the other two (`3S-2P` / `2S-P`). The bounds are `1.00 / 1.30 /
  1.60` in R units and the third is a LABEL only (STRONG and EXPLOSIVE select the
  same candidate).
- `3S - 2P` going non-positive returns `false` with the output untouched — never
  a negative or zero step. A negative step is not a small step, it is no step.
- The drawn ladder's base unit is the **pattern TF's own ATR** through the one
  owner `TH3PatternStepRung()` — not `THAbilityPrice` (a different ruler).
- The course's update rule is `TH3HitPivotMeasure`: step = |C−tip|/3, k fixed at
  3 off the tip itself, and the tip is the first local extreme of the reaction
  that has travelled **one full step** (≥ 3 rungs); a shallower bounce is
  SKIPPED, not fitted. No pivot at the tip → the chain is walked UP and its rung
  adopted; no vote at all → the proof is DELETED, never left advertising a
  recalibration that did not happen.
- `TH3HitPivotForward` re-measures the live pattern's proof, and that re-measure
  is a **memo** (key = every input + the chart's own `iBars(NULL,0)` + `Period()`);
  refusals are memoised like any other answer, and arming is the ONE exit past
  each key guard.
- Multi-factor synthesis (`CalculateMultiFactorStep`): a **MACRO mother owns the
  step** (unblended mother run / 3, the lock is skipped); otherwise geometric
  mean, else 60 % pattern + 40 % rung. The hand-typed base is pips / 3, and 0 =
  OFF (then the pattern TF's ATR is the whole seed).
- The caption is a FAMILY of ≤ 63-character lines written by ONE owner
  (`TH3Renderer.mqh`) because MT4 truncates object text at 63 chars. Its plate is
  hidden by **existence** (delete it) and shown by existence — never by a period
  mask: labels obey `OBJPROP_TIMEFRAMES`, `OBJ_RECTANGLE_LABEL` and
  `OBJ_BITMAP_LABEL` do not.
- The mode rows stand a hardcoded +45 below the ATR stack; the caption's safe-Y
  mirrors it (`GetABCDInfoSafeYDistance`).

**DrawStrip / UI.**

- **`docs/design-checklist.md` IS the UI contract** (0 → 100: the five owners, the
  spacing grid, the state set, the MT4-limits table, the dirty-look catalogue, the
  delivery gate). Read it before touching a drawn surface. A surface that fails a
  line there is a bug even if it looks fine — and the fix moves the rule to its
  owner, never to a second copy.
- **ONE PALETTE, AND IT IS THE USER'S OWN 64 (P-DRAW-46).** `BioPickColor(r,c)` /
  `BioPickAt(i)` over `BIOPICK_COLS/ROWS` 8 x 8 (`ConstantsAndEnums.mqh`) is the
  single owner — the user's own palette chart. `BioPal(i)` is its FIRST ROW (the
  panel quick row) and `QuickPalColor`, `DrawStripPickPal`, `PalPickColor` are
  faces. Never add a second palette, never a panel-specific colour table.
- **REALTIME is the same event.** A follower writes in the event that moved its
  owner; no follow channels, no timers for follow, and the drag frames are exempt
  from event deferral (`!g_s1DragLive`, `!g_customPriceLineDragging`) because a
  deferred drag frame IS the lag. At rest it costs nothing.
- **PERFORMANCE IS A FEATURE, AND THE WEAKEST MACHINE IS THE TARGET** (user order
  2026-09-25). Fast on the user's slowest hardware, not on the box it was written on;
  between two implementations that behave the same, the CHEAPER one ships and its cost
  is written as a number. Every path states its bound (what it walks) and its budget
  (`CPU_WARNING_MS 50`/`CPU_CRITICAL_MS 200`, `COOP_WARN_MS 40`); nothing unbounded
  enters the mouse stream or the tick, and a fixed cadence has to justify itself against
  a measured window (`PNL_MOVE_FRAME_*`, P-UI-75b). The rules — G-01…G-12 — live in
  `docs/design-checklist.md` (LEVEL 75) and the gate is its item 10.
- **A gesture that takes the view lock names itself in `ChartLockIntended()`** the
  day it is born (P-DRAW-19) and releases through the one ender. The 250 ms
  `ChartScrollReconcile` rebuilds the lock from ownership intent, so an unlisted
  owner has its lock read as a leak and force-released inside the first quarter
  second.
- **THE HOVER CHIP DOES NOT TURN** (P-UI-126). It opens ABOVE the orb while the whole
  box fits in the window, otherwise at its OWN PLACE — the hand's (a drag, pinned mode
  only) or the chart's middle, and `-1` means "never placed", a state and not a reset.
  No rotated or mirrored face may come back: MT4 crops a bitmap label and turns none,
  so a rotated face is sideways calligraphy, which is the defect a screenshot named.
  The mode is one switch (`g_UI.tipPin`, the Hover Chip card): OFF = hover only (the
  default), ON = always up at its place — one compare per tick, a write only when the
  box really moved, and the drag states its own bound (two writes per real move).
- **The settings panel is its own surface** (P-DRAW-30/32), on the cards' own
  arithmetic: one column is 312, two columns 624, split at > 10 rows, and its
  plate height reads `48 + 42k` **on its own**. The strip stays the compact quick
  row. Both rects publish for the neighbours (`DrawStripPublishRect`), and the
  placers treat each other's rect as a HARD rule (P-DRAW-31).
- **A fresh strip opens on the drawing's corner** (P-DRAW-20), never on the
  cursor, and never covering the drawing or the open card.
- **Every colour surface wears the cards' glass** (P-DRAW-33). MT4 CROPS a bitmap
  label and never scales it, so each size gets its own baked frame.
- **Extras MT4 cannot draw ride the object's DESCRIPTION** (P-DRAW-21/22:
  `[BX50]`, `[BXE1]`/`[BXE2]`/`[BXE3:N]`) so they survive reattach, TF switch and
  restart; deletes cascade both ways.
- **Hand-set lines**: ARMED = draggable, SET = inert, a single click SETs, a
  double-click re-arms, and a drag's own click echo sets nothing. The step-1
  handle **carries itself** through the custom-price channel (P-UI-98e): its own
  press/release pair, the borrowed `SELECTABLE` taken off at the claim (P-LM-21),
  and the handle chosen by GEOMETRY — the line one step from the custom price,
  never one closer than half a step — not by ladder rung.
- The colour hover is a **one-event preview** (P-DRAW-27): hit-test the laid-out
  cells in the move event, apply there, write nothing while the pointer stays on
  the same cell; leaving restores the stored colours.

**The atlas** (`docs/pivot_arrangement_atlas.html`) is the course's own
vocabulary: 49 schematics over 10 families in the curated tab, plus a 1440-slot
census in the second tab. It is authored content and tracked; the one-image
render is derived and gitignored. Its export commands (Chrome headless) are in
`docs/history.md`. The master's `1403` is a lower bound he declines to open: it
is ODD (`23 x 61`) while any grammar with a symmetric `جهت` axis multiplies by 2,
so every legal total is EVEN — `1440` is `2 x 6!`, «۲ جهت × ترتیب قرار گیری شش
کندل». Every schematic and every axis is built from the Trex course itself; the
only outside number is Bulkowski's `103`, a ranked-set size, cited as a yardstick
and never copied from.

## Working rules (user orders)

- **NEVER ANSWER A BUG REPORT WITH "IT IS OLD". THE PROBLEM IS IN THE CODE.** A
  compile rewrites every `.ex4`, so no data folder, terminal, log or object is
  "stale" evidence. When a report depends on WHICH build is live, prove it by a
  named MEASUREMENT (the terminal log line, a trace line, a counter) — never by
  calling something old, and never as an excuse for not having measured.- **A COMMENT STATES THE WHY AND STOPS.** Target 6 lines, hard ceiling **16** for any
  one block (a file header included), never a note on a self-evident line, and a file
  stays under a 25 % comment share. The investigation (what was measured, what it
  read, what the user said) belongs in `docs/history.md` — never pasted where the code
  lives; the code keeps the `P-*` ID and the law. The ceiling, the one-file check and
  the before/after numbers live in `docs/design-checklist.md` (catalogue 25, LEVEL 86).
- **ONE PALETTE, AT-HAND LOOKS WITH USER NAMES.** Saved looks and smart/recent colours sit one tap away; a saved template carries the name the user gave it, not `My 1`.
- **REALTIME IS THE SAME EVENT, AND COSTS NOTHING AT REST.**
- **A rule that loses its tooling does not lose its force.** Deleting an audit
  deletes the automation, not the rule; the compiler and reading now pin it. Say
  so in the note so no future reader hunts a script that is gone.
- **Deletion and moves are git-recoverable; keep them as their own commit.** Bulk
  deletes need the user's approval, and a blocked delete is reported, never routed
  around.
