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
Samples/TH3_Dataset/          The labelled samples: one folder each,
                              Dataset.csv the index, docs/th3-dataset.md the contract
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
- **A diagnostic witness goes through `DrawStripDiagEmit` (the flushed file), never
  `Print`** — MT4 buffers the journal in RAM, so a `Print` witness can sit unread for
  minutes and reads as «nothing happened». See THE DEBUG LOOP, law 3.

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
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Tests -Project all      # every tests\*.mq4 in ONE run
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Shot -RestartTerminal -Project all   # the strip's REAL pixels, one command
node tools/submenu_geometry_check.js
node tools/check-resources.js
node tools/check-level-continuity.js
node tools/check-regressions.js
node tools/object_lifecycle_check.js
python tools/check-gear-panel.py
python tools/debug-doctor.py --env                     # the loop's own instruments
python tools/debug-doctor.py --symptom count           # one symptom -> one core gap
python tools/mutation_gate.py                          # every rule's inverse must FAIL a gate
python tools/mutation_gate.py --list                   # mutations + register entries lacking one
node tools/th3-dataset-sync.js                        # labelled samples -> the repo, index rebuilt
node tools/th3-dataset-dashboard.js                  # the dataset as one reviewable page
```

**A rule is gated only if its INVERSE fails a gate (contract §6.14).**
Before reporting a rule as locked, run `python tools/mutation_gate.py`: it puts the fixed
defect back by literal string, requires the owning gate to fail with its own message
(`KILLED`), and fails on `SURVIVED` (not gated) or `STALE` (the anchor moved). It
mutates the tree for ~0.3 s per mutation and verifies every touched file's sha256 is
back to its pre-run value, so run it when nobody else is editing — and never add it to
the build.

**Debug: name the stage BEFORE reading code (contract §6.13).**
`python tools/debug-doctor.py --symptom <word>` narrows a symptom to `file:line` in one
run: it probes the six stages (literals → layout → count rule → paint ops → birth-only
layers → real pixels), deletes the ones that agree, and prints the first divergent one
as CORE GAP. A stage with no probe for your symptom is the finding — that is where the
fault reaches the terminal unseen. `--list` prints the symptom routing table.

**The terminal's own Experts log is the S6 oracle, and it is already on disk** — read
`%APPDATA%\MetaQuotes\Terminal\<id>\MQL4\Logs\<yyyymmdd>.log` (the folder being written
NOW) before asking for another run. With `DSTRIP_DIAG` at 1 (`Biotak/DrawStrip_Head.mqh`)
the panel declares every object it paints and the census answers beside it;
`python tools/diag-diff.py <log>` names each divergence (MISSING / TYPE / NO INK / LAYER /
TEXT / SEAT). **A probe may never move a pixel the product would not** (P-DRAW-125): the
dump repaints only an open, laid-out panel, and every writer reclaims a name whose TYPE
is not its own (`DrawStripForeign`). `--sample` self-tests the verdicts.

**But the Experts log is a CACHE, not a channel (P-DRAW-126).** MEASURED 2026-10-01
20:15:20: the live terminal's window showed a full `20:03:44` frame while its
`MQL4\Logs\20261001.log` still ended at `20:01:38.319` and had not grown in fourteen
minutes — MT4 buffers the journal in RAM. So the diag channel writes its own file and
flushes it per line: `<data folder>\MQL4\Files\biotak_diag_<SYMBOL>.txt`
(`DrawStripDiagEmit`, `DrawStrip_Base.mqh`, opened with `FILE_SHARE_READ` — P-LOG-3:
without the share flag the terminal holds the handle exclusively and the flushed bytes
are unreadable; measured 2026-10-01 21:52:50: 62,965 bytes flushed, `PermissionError`
for every reader). Read that FIRST:
`python tools/diag-live.py` (newest flushed file, `--all` lists every source),
then `python tools/diag-diff.py <file>`. **Never pick the data folder by the mtime of
the `MQL4` directory** — a folder stamp moves when a file is added beside it, not when a
log is appended — `compile-th3.ps1` does it by the newest `.log` (`Get-LiveTerminalDirs`).

**And a diag frame belongs to ONE attach, so old frames are DELETED (P-LOG-2).** The
flushed frame is truncated only when a NEW attach writes its FIRST line, so between a
restart and the first panel open the PREVIOUS session's file is still on disk and still
the newest by mtime. `compile-th3.ps1` deletes every `biotak_diag_*.txt` while
`terminal.exe` is stopped (`Clear-StaleDiagFiles`, inside `Restart-TradingTerminal` and
`Invoke-StripShot`); `python tools/diag-live.py --prune` does it from the reader side and
prints `STALE` for a frame that is old or that predates a newer journal.

**A flush is not a read, and a diag file carries many frames (P-LOG-3).** MEASURED
2026-10-01 21:52: the frame was written and flushed and every reader still failed on
it (`PermissionError 13`, "Device or resource busy") — a plain `FileOpen` grants no
share, so `DrawStripDiagEmit` opens with `FILE_SHARE_READ`. And the name is per CHART
(`biotak_diag_<SYMBOL>_<CHARTID>.txt`): two charts of one symbol each opened their own
handle to one path and overwrote each other (size frozen at 62,965 bytes while frames
were emitted). Finally, the unit a reader may diff is a FRAME — the writer appends a
whole frame per panel open and never truncates, so `tools/diag-live.py` and
`tools/diag-diff.py` both split frames and default to the LAST one (`--frames`,
`--frame N`); mixing them reported `DIVERGED: 53 of 187` where the last frame alone
reports `PASS`. The writer half is gated as P-LOG-3, the reader half as P-LOG-4.

**Every caption is in the ink column (P-LOG-5).** The census wrote `ink` for `OBJ_LABEL`
only, so a BUTTON's own text was unverifiable — and the swatch row's captions
(`1px`..`5px`, `Solid`..`D-Dot`) are button text. MEASURED 2026-10-01 22:10: the panel
passed the diff 91/91 with that blind spot intact, so a lost caption and a healthy face
both read `ink=-` and «بعضی ردیف‌ها متن نداره» could not be decided from the log.
`DrawStripCensusInk` (`DrawStrip_Base.mqh`) now answers a button the way it answers a
label, and `diag-diff` tests role `btn` as well as `lbl`.

**A panel open flushes its own frame (P-DRAW-127).** MEASURED 2026-10-01 22:10/22:13: the
WIDE (624px) open declared all 91 objects correct, at their seats, with no intruder and
no occluder — and the screen showed the left column EMPTY. The object LIST was right and
the PIXELS were one frame behind: `DrawStripPaint` flushes with `if(dirty) ChartRedraw()`,
and `DrawStripGearDiagDump` repaints the body LAST (P-DRAW-125a) while discarding its
return. The GEAR branch of `DrawStripActTap` — the one path that opens the panel — now
ends with an unconditional `ChartRedraw()`. When the log says the model is complete and
the screen says otherwise, the next question is which frame the terminal drew, not which
object is missing.

## THE DEBUG LOOP — debug mode stays ON until development ends

Two things are LAW until this project ships, and no session turns either off:

1. **`DSTRIP_DIAG` is 1** (`Biotak/DrawStrip_Head.mqh`). The panel declares every object
   it paints and the census answers beside it, on every open and every group switch.
   Commented out = silent, and a silent build is a build nobody can diagnose.
2. **Read the LAST frame, always.** The diag file carries one WHOLE frame per panel open
   and never truncates, so the FILE is not the unit of comparison — the FRAME is. Both
   readers split frames and default to the last one (`--frames`, `--frame N`).
3. **A WITNESS IS THE FLUSHED FILE. NEVER `Print`.** MEASURED 2026-10-02: the Experts
   journal stood at `08:47:07` for **seven minutes** while the user's clicks went into
   MT4's RAM buffer (P-DRAW-126) — a witness written with `Print` answers
   «nothing happened» long after the tap happened, and costs the user a reproduction
   round each time. So when a defect is reported: the witness is emitted with
   `DrawStripDiagEmit` (per line, `FILE_SHARE_READ`, P-LOG-3), and it is READ with
   `diag-live.py` — never with `Print` into the journal, never by asking the user to
   reproduce and check the Experts tab. If a path has no witness and needs one, ADD it
   through the flushed channel rather than reaching for `Print`; the standing example is
   DIAG-131 in `DrawStrip_Tap` (slot, value, read-back, the description's own bytes),
   which is what finally closed the 50 % / EXTEND report after two failed string-surgery
   attempts. Gate: P-LOG-3 (flushed, shared, per line) and DIAG-131 in
   `DrawStrip_Tap.mqh`.

ONE command is the whole loop:

```bash
python tools/diag-live.py --diff      # newest file, LAST frame, its own diff verdict
python tools/diag-live.py --all       # every source, newest first (flush outranks experts)
python tools/diag-live.py --prune     # delete stale frames (run after a restart)
```

Then, in this order — and do not skip to step 3:

1. **The verdict names the bug.** Every `MISSING / TYPE / NO INK / LAYER / TEXT / SEAT`
   line carries the object's own name and the two numbers that disagree. Fix THAT name.
2. **PASS but the screen disagrees? The object model is not the screen.** The model
   cannot witness three things, so check them by hand: the PLATE (painted by
   `DrawStripGearPlate`, admitted to the census by P-LOG-6 — if it does not appear, that
   is itself the finding), object ORDER at equal `z` (`idx=`), and the frame the terminal
   actually DREW (P-DRAW-127).
3. **Only then ask for another capture — and NAME the state.** The frame count plus the
   panel's own width and section titles say which state it was (the wide 624px accordion
   and the narrow 312px one are different frames, not different moments).

   P-LOG-7 (2026-10-01): the census now walks the WHOLE chart inside the panel rect — no
   name prefix, no type gate — and prints `win=`/`corner=` with every line plus one
   `[drawstrip] CENSUS rect=… chart=WxH` header. MEASURED on the wide frame whose
   screenshot the report carries: 40 declared left-column objects hold correct
   xywh/z/back AND win=0 corner=0 while the screen shows a bare plate under them. When a
   frame reads that clean and the pixels still disagree, the model is exhausted: ask for
   a fresh `-Shot` of the SAME state, do not re-read the old one (the panel had been
   dragged since — `gx` 1087 → 846 — so the screenshot and the frame were two states).
   A face's SEAT is contained OR centred: a raster may be smaller than its cell (the
   paint insets the art) or larger (`pnl_sw_off.bmp` 52x34 around a 40x22 seat).

   P-LOG-8 (2026-10-01): the census is a SNAPSHOT and the screenshot is LATER. The dump
   now stores what the census saw and the NEXT `DrawStripPaint` pass re-walks that name
   list and prints only the delta — `AFTER GONE obj=` / `AFTER MOVED obj= was=… now=…` /
   `AFTER NEW obj=` / `AFTER done snap=… gone=… moved=… new=… chartObjs=…`. Read the
   `done` line FIRST: `gone=0 moved=0 new=0` says the object list is STILL the screen's
   state, and the hunt must move off the object list (to MT4's own draw rules) instead
   of re-reading it. MEASURED 23:09: 91/91 PASS, whole-chart walk found no cover (one
   foreign `BiotakMenuV2_*_CircTipArt` on rung 1302, UNDER the plate), and the left
   column was still bare — that frame is the case the AFTER block was built for.
   P-LOG-9 (2026-10-02, retired): with the object model fully acquitted, four probe
   labels asked MT4's own draw rule — P1 (content rung) + P2 (rung 1600) at the left
   seat, P3 at the right, plus a fresh-name P4 and a same-pixel touch test. The user's
   screenshot showed ALL FOUR while the left column stayed bare, and the touch raised
   nothing: CREATE is the only raise. Verdict + law = P-LOG-10 below and contract §6
   item 23; the labels are gone.
   P-LOG-10 (2026-10-02): MT4 paints in CREATION order; `OBJPROP_ZORDER` rules clicks
   alone (P-DRAW-83's «paint order hid them, and click order gave every pixel»). The
   wide tiles were born after the narrow-phase content, so everything born before them
   painted under the card while every click still landed. The law lives where the plate
   is born (`DrawStripGearPlate`): when the plate is about to (re)appear while family
   content predates it — entering the composed branch, a changed `pairN`, or returning
   to the bake — `DrawStripGearObjectsPurge()` runs once, tiles land first, and the
   `DrawStripGearPaint()` that follows recreates every control above them. MEASURED
   00:07 frame + the user's screenshot: both columns draw, the × and head are back,
   `AFTER done gone=0 moved=0 new=0`.
4. **A restart deletes the old frames** (`Clear-StaleDiagFiles`); the first frame after
   ensures the only frames on disk are this session's. The observer never has to wonder
   whether it is reading yesterday's panel.

THE SURFACE LAWS — every new plate/panel obeys these (P-LOG-10, 2026-10-02):

1. MT4 paints in CREATION order. `OBJPROP_ZORDER` rules CLICKS alone, and a write —
   even a move — never raises an object. Only CREATE re-orders paint.
2. A plate is born BEFORE the content it hosts, in the same paint pass.
3. A plate that can be REBORN (branch flip, !fits purge, spec/geometry change) purges
   its family at the rebirth. The three owners: `DrawStripGearPlate` (`s_dsPlatePairN`),
   `DrawStripSkinPaintAt` → `s_dsSkinPlateDied` answered at the top of `DrawStripPaint`,
   and `PnlCreate` (geometry flip for the dynamic cards 9/12). Copy an owner; do not
   invent a fourth way. Gate: P-LOG-10.
4. Close/attach purges take plate AND content together — one family, one sweep.
5. Pixels disagreeing with a PASSing census mean a draw rule is wrong: probe the
   screen (fresh-named labels, P-LOG-9 style); never re-read the object list.

THE HOLD'S TWO WINDOWS (P-UI-130, 2026-10-02) — a hold is a press AND a stillness:

1. **A gesture's flags die with the gesture.** The press cycle's life is the PRESS's
   (`DSTRIP_PRESS_CYCLE_MS`, 2 s) — never the opener window's cap. MEASURED: one latch
   on a box the hand then DRAGGED refused FIVE real presses in a row over 4.4 s
   (`press refused: cycle live`, EURUSD,M1 00:12:57.036 → 00:13:01.481; the next latch
   only at 00:14:41 after the user gave up) — «هولد بعضی وقتها باز نمیشه» IS that
   window, and no line of the log named the owner until DIAG-116 printed it.
2. **A latch the position test has already DROPPED is not a live gesture.**
   `DrawStripHoldForget()` clears the CLOCK with the object, so the release witness
   clears the cycle instead of stamping a window on a latch nobody owns (the stale
   `s_dsHoldMs` is what outlived a release that DID arrive).
3. **A drawing IN MOTION is never held.** `CHARTEVENT_OBJECT_DRAG` is the terminal's
   own voice (P-BK-19a's owner witness, TH3Tool_C's band lock): it KILLS a live latch
   and FORBIDS the next one for its 400 ms heartbeat — renewed by every drag event
   while the object moves. This is what the shortened press cycle trades its flap
   protection for: a PRESS is guarded by the press, a GESTURE IN MOTION by the motion.
   «موقعی که باکس جابجا/ری‌سایز میکنم نوار استریپ بالا میاد» was the press that
   STARTS a drag arming the latch and the 500 ms clock firing on a drawing the hand
   was about to move. Gate: P-UI-130.

TWO ICON TREES (P-UI-131, 2026-10-02) — the compiler and the chart read DIFFERENT
trees, and only one of them is the source:

1. **`#resource` is a COMPILE-time bind; `OBJPROP_BMPFILE` is a PAINT-time read.**
   MetaEditor resolves `\Files\Icons\x.bmp` against the compiling unit's own tree
   (P-BUILD-03); the terminal resolves `::Files\Icons\x.bmp` against its own
   `MQL4\Files`. A green compile and a green resource gate (which walks the SOURCE
   tree) therefore prove nothing about the pixels.
2. **MEASURED, both hosting terminals: 22 of 280 canvases drifted.** `gl_pin*`,
   `gl_layers*`, `gl_textsize*` shipped 15x15 against a source 26x26 — «این دوتا
   ایکون کوچیکه نسبت به بقیه» is those two glyphs — and `bk_w*`/`bk_style*`/`bk_ray*`
   shipped 16x16 against 24x24, which is P-DRAW-106's retirement and P-UI-132's re-bake
   invisible on screen.
3. **P-DRAFT-01 retired the delivery on a HALF measurement** («the copy was INERT» —
   true for the ex4, false for the chart). It is back, bounded by
   `tools/icon-manifest.txt`, hash-compared, and `tools/check-icon-deploy.js` fails
   the build when the two trees disagree. Both facts are gated (P-UI-131), including
   the gate's own blindness to a COMMENTED-OUT call (P-DRAW-108's lesson, proved by
   mutation).
4. **A user action flushes its own frame, and says what it wrote.** `DrawStripPaint`
   only redraws `if(dirty)` (P-DRAW-127); the pin and the cell toggles (the BACK/layers
   glyph) now call `ChartRedraw()` themselves, and their witness goes through
   `DrawStripDiagEmit` — the FLUSHED channel, not `Print`: MEASURED 2026-10-02, the
   Experts journal stood still for seven minutes while clicks went into MT4's RAM
   buffer (P-DRAW-126), so a `Print` witness answers «nothing happened» long after it
   did. The line carries the tapped slot, the value the OBJECT now holds, and the FILL
   slot beside it — because «کلیک کردم هیچی نشد» is unprovable without a read-back.
5. **A toggle is ONE shape in two inks.** BACK wore `gl_layers_m` off (grey chevrons,
   26) and `bk_back_on` on (amber rects, 24) while every other toggle wore one drawing
   in two inks. The live witness proved the write exact (`slot=9 … read=1 fill=1
   child=1` / `-> 0 read=0 fill=1`) — the defect was the seat. `bk_back_off` is the
   twin; the generator bakes it and the mock draws it.
6. **The edge a mode took is the edge it gives back (P-UI-132).** «اکستند خاموش میکنم بر
   نمیگرده به حالت اول» and «50 درصد … چرا تداخل داره» are ONE missing restore: the
   EXTEND arm wrote `[BXE2]` and the tap's first step (P-DRAW-64c) moved the box's later
   anchor onto the forming bar, so arming changed the drawing for good. The 50 % is a
   LEVEL at the mid PRICE — it does not fight the edge, it RIDES it, and two cells
   moving together read as one interfering cell. **Remember BEFORE the move, restore at
   the disarm** (`ObjectMove`; MQL4 has no indexed `OBJPROP_PRICE` setter), then re-sync
   the mid line and the interior in the same frame. File-scope ring of eight names, spent
   by the disarm, by the «…» cycle's OFF and by deletion — **zero cost per frame**, and
   NOT a descriptor tag (`BoxMarkWrite` re-emits the whole marks block). Gate: P-UI-132.
   **Addendum — ALL THREE doors, not one.** EXTEND is armed by the quick cell
   (`DrawStripTap`), the gear panel's switch (`DrawStripGearRowTap`, kind 1), and the
   picker's «…» cycle (`BoxExtCycle`). The first pass memo'd only the quick cell: the gear
   row armed the mode AND moved the edge with no memo, and the cycle ARMED without one
   while its way back to OFF already restored — so both could still stretch a box for
   good, which is how a fix reads as «sometimes works». Every door that moves the edge
   remembers first and restores at the disarm, and `BoxExtCycle`'s remember is guarded on
   the **OFF→ON transition** (an already-armed box walking its modes must keep the
   hand-drawn edge). Gate: P-UI-132 (now naming all three doors).
7. **One marks block, cut at its FIRST tag (P-UI-133).** `[BX50]` and `[BXE…]` share one
   block, so `BoxMarkWrite` must cut where the block STARTS — `StringFind(d, "[BX")`, plus
   the leading space when there is one. Cutting on `" [BX"` matched the space in front of
   the SECOND tag, so `pre` kept `[BX50]` and the 50 % cell could never be cleared:
   MEASURED, twelve taps in a row, `slot=11 … -> 0 read=1`. One use of EXTEND killed the
   50 % cell for good. **A string surgery that assumes its own output format is a second
   format** — and the witness (`-> X read=Y`) is what made it visible instead of arguable.

`compile-th3.ps1` is the ONLY build. Do not hand-roll a metaeditor call, and do not
add a second script for the same job.

**The gate layer is cheap; the loop was not.** MEASURED: all six gates together cost
1.76 s (`check-resources` 269 ms, `check-regressions` 186, `check-level-continuity`
150, `object_lifecycle_check` 309, `stale_state_check` 313, `submenu_geometry_check`
101, `check-gear-panel` 438) — so the gates were never what made a fix take an hour;
the 9 harness calls were (each one re-entered this script and re-ran them all: 54 s of
wall clock for 9 × ~4 s of metaeditor). Three switches now say what a run did:

- `-Gates scoped` (default) skips a gate only when the bytes it reads — `Biotak/**`,
  both entries, `tools/*.js|py`, `Files/Icons/*.bmp`, 444 files under one fingerprint —
  and its own script are identical to the run that PASSED last. It prints
  `[SKIP] <gate> (inputs unchanged since the last PASS)`, so no report can claim a
  check it did not run. A failure is never cached.
- `-Gates full` runs everything (use before reporting "done").
- `-Fast` is `-Gates off` for the inner loop, and it ends with `GATES SKIPPED (-Fast):
  this build proves the names resolve, nothing more.` in yellow.
- `-Tests` compiles every `tests\*.mq4` in this one process (~59 s → 42 s measured),
  and a second run of an unchanged tree skips every gate.

**`-Shot`: the strip's OWN pixels, not the mirror.** `tools/before-after.html` compares
the design mock with a render built from the same literals — a MIRROR, and a mirror can
be wrong about the one thing only the terminal knows: what the blit really does. The
third column was always meant to be `tests/Biotak_StripShot_Test.mq4`, but getting its
PNGs meant dragging the harness onto a chart by hand, and that is why the column stayed
empty and why a fix was "verified" against a render that had the same bug in it
(P-DRAW-109). One command now closes it:

```
compile-th3.ps1 -Shot                    # compile + deploy the harness, write build-logs\th3-shot.ini,
                                         # print the terminal.exe /config: line. MT4 is NOT touched.
compile-th3.ps1 -Shot -RestartTerminal   # ...and do it: close MT4, launch it on that config, wait for
                                         # `[STRIPSHOT] DONE:`, sweep build-logs\shot\, relaunch your
                                         # own instance, rebuild tools/before-after.html with the shots in it.
compile-th3.ps1 -Shot -ShotSymbol EURUSD -ShotPeriod H1 -ShotTimeoutSec 120   # the chart it opens
```

MT4's own "Configuration at Startup" is the mechanism (`Symbol`/`Period`/`Script` +
`ExpertsEnable=true`): the extra chart it opens is NOT saved to the profile, so the
running charts come back untouched. One render per state — `StripShot_panel_paint.png`,
`…_style`, `…_look`, `…_row`, `…_board`, `…_fibo_paint` — plus a census line per object
with the rect the TERMINAL built (`StripShot-census.txt`). **The harness is a script on
ONE chart:** never run it while a strip is open, and if the instance answers
`[STRIPSHOT] … SKIP` (under ~40 bars, no strip opened) that is the terminal's reason,
not a pass. A shot that produced no PNG fails the build — `-Shot` cannot report green on
an empty column.

**The mirror is not the evidence (P-DRAW-119).** `tools/check-shot-freshness.js` runs in
every gate run, uncached, and prints `fresh N · stale N · missing N` per state the
harness asks for: `[PASS] real pixels gate` only when every PNG is at least as new as
the newest source it shows, `[WARN] real pixels gate (ran; its verdict is NOT CURRENT)`
otherwise — never `[PASS]`, so a green line can no longer be read as "seen". A
`-Shot -RestartTerminal` run ends with the same gate `--strict`, and a stale or partial
capture FAILS the build (`[FAIL] real pixels gate (strict)`). MEASURED 2026-10-01, the day
it was added: `fresh 0 · stale 0 · missing 25`. `tools/before-after.html` prints the same
verdict on the shot itself (which build's pixels, and how old).

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
- **`[PASS] real pixels gate` / `[WARN] real pixels gate`** — the only pixels a report
  may call "what is on the screen": the PNGs `tests/Biotak_StripShot_Test.mq4` writes by
  the REAL paint path, compared state by state with the newest source they show. Run it
  by hand after touching any paint path — `node tools/check-shot-freshness.js` (add
  `--strict` to exit non-zero instead of reporting `NOT CURRENT`).
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

