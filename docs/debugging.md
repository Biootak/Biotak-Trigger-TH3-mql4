# Debugging — the system

One page. The companion to [contract.md](contract.md), which carries the rules; this file
carries the METHOD.

## 0. The rule this file exists for

**No symptom without a STAGE.** Before reading code, name the stage the fault can enter.
A hunt that starts before a stage is named ends on a screenshot — MEASURED, 2026-10-01: a
band's `.cnt` pill read `4` for a two-member group, every gate was green, and the defect
could only be SEEN, because no artefact measured that number.

## 1. The six stages, and the one owner of each

Run `python tools/debug-doctor.py --symptom <word>` and it prints this table filled in.
The doctor DELETES every stage that agrees; the first one that diverges is the core gap,
named as `file:line`.

| stage | the question | owner | can it be measured offline? |
|---|---|---|---|
| S1 constants | do the literals agree (aliases resolved, not skipped)? | `check-gear-panel.py` + doctor | yes |
| S2 layout | where does every row land, in which column, on which pitch? | `sim-gear-panel.py` | yes |
| S3 rules | what does the rule PRINT (the count, a fitted width, a mask)? | the mirror + the gate that owns it | yes |
| S4 paint ops | does every block push its own ops — label, digest, face? | `sim-gear-panel.py` | yes |
| S5 layers | does every painter re-assert its rung every pass? | `object_lifecycle_check.js` | yes |
| S6 terminal | what does MT4 actually hold and show? | `diag-diff.py` + `check-shot-freshness.js` | **no — only the terminal** |

A stage that cannot see the symptom is a FINDING, not a pass. S5 was blind until
`object_lifecycle_check.js` derived it; the count was blind until S3 existed.

## 2. The three proof layers — and what each one may claim

1. **The source** — `Biotak/**/*.mqh`. Proves text, never behaviour. A green compile
   proves only that names resolve (AGENTS.md, "Touch rule").
2. **The model** — the mirrors (`tools/sim-*.py`) and the gates. Proves ARITHMETIC and
   structure, and is only worth its green line when its INVERSE fails a gate:
   `python tools/mutation_gate.py` puts a fixed defect back and requires the owning gate
   to die (`KILLED`). `SURVIVED` = the rule is not gated; `STALE` = the check stopped
   running. **A mirror is never evidence of pixels** (P-DRAW-119).
3. **The terminal** — the only layer that can say what the user sees. Two instruments:
   `compile-th3.ps1 -Shot -RestartTerminal` writes PNGs of the real paint path
   (`check-shot-freshness.js` says whose code they are), and `DSTRIP_DIAG` makes the
   panel declare every object it paints beside the chart's own object list, which
   `python tools/diag-diff.py <log>` diffs.

## 3. The loop

```bash
python tools/debug-doctor.py --env                  # 0.3 s — is the loop's own gear working?
python tools/debug-doctor.py --symptom count        # narrows, prints CORE GAP as file:line
#   ...fix the stage that diverged, then:
python tools/mutation_gate.py                       # the inverse must FAIL a gate (KILLED)
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all -Gates full
#   terminal-only symptom (paint order, invisible ink, missing text)?
#   DSTRIP_DIAG is 1 in Biotak/DrawStrip_Head.mqh: open the panel, switch the group, then:
python tools/diag-diff.py <the terminal's Experts log>   # names the object, the class, why
```

Measured costs: doctor 0.4 s · mutation gate ~3 s (7 mutations) · all six gates ~2 s ·
one compile ~1 s. The diagnostic dump costs ONE print per painted object, on a user
action only — never per paint.

**The diagnostic is a product path, and it is gated like one (P-DRAW-125).** The dump
calls the panel's real painter, so an unguarded call runs on a SHUT panel too: with
`s_dsGRN = s_dsGGN = s_dsGearSecN = 0` it deletes the whole body and — because the head
and the foot paint unconditionally — leaves the head and foot of a closed panel standing
at the stale origin. MEASURED on the terminal's own log: one frame declared exactly
`GHTB..GHXI` and `GF0..GF2T`, twenty objects, head then foot, nothing between. A probe
must therefore repaint ONLY the state it claims to describe (`if(s_dsGear != 0 &&
s_dsGearH > 0)`), and §41 + `mutation_gate.py P-DRAW-125` keep it that way.

## 4. Adding a probe (the recipe, for any surface)

1. **Find the choke point.** Every object of a surface goes through a handful of writers
   (`DrawStripLblAt`, `DrawStripFaceZ`, `DrawStripRect`, `DrawStripBtnZ` for the panel). A
   probe belongs THERE — never a second copy of the geometry, or the probe becomes the
   bug it is looking for.
2. **Two halves.** The writer prints what it PLACED; the census prints what the CHART
   HOLDS. One without the other cannot be diffed — that asymmetry is why the 2026-10-01
   reports took hours.
3. **Bound it.** One line per object, one dump per USER ACTION (open, switch, commit),
   behind a `#define` that compiles the calls away when it is 0. Never per paint, never
   per tick.
4. **Then gate it.** Add the rule to a gate and a mutation to `tools/mutation_gate.py`,
   or the next edit removes it in silence.

## 5. The failure modes this prevents, by name

| class | what it looks like | where it was caught |
|---|---|---|
| a green gate over an unmeasured number | the pill reads the wrong digit, every gate green | P-DRAW-121 |
| the heal went to the SITES, not the RULE | five more painters with the old spelling | P-DRAW-122 |
| a mirror read as evidence | a render with the same bug in it | P-DRAW-119 |
| correct in the census, empty on screen | every property right, nothing painted | P-DRAW-120 |
| a probe that can never fire | a detector that returns nothing, and an assertion that passes for the wrong reason | P-DRAW-121 (the nav self-test) |
| an anchor that no longer exists | the check quietly stops running | `mutation_gate.py` `STALE` |
| a census scoped to its own names | the intruder is the family the filter threw away | P-DRAW-124 |
| a cell that changed ROLE keeps its old faces | a stale face at the ink's own rung, at the old tab's seat | P-DRAW-124 |
| the probe moved the pixels it measured | the depth of the hunt was its own report | P-DRAW-125 |
| a name of another type answers `ObjectFind` | the object exists and paints nothing | P-DRAW-125 (`DrawStripForeign`) |
| a verdict the census cannot support | `tf=0` read as `OBJ_NO_PERIODS` on every object | `diag-diff.py` (P-DRAW-125) |

## 6. Three laws the 2026-10-01 hunt cost hours to learn

**1. The terminal's own log is a FACT, and it is already on disk.** Before asking the user
for a new run, read what the terminal already wrote — it is the fastest oracle this
project has and it costs nothing:

```bash
# the LIVE data folder (not the old one recorded in build-logs/.runtime-log-state.json):
#   %APPDATA%\MetaQuotes\Terminal\<id>\MQL4\Logs\<yyyymmdd>.log
# find the folder that is being written NOW, then read the log as cp1252 (it mixes
# Persian text with ANSI, so utf-8 fails on the first non-UTF byte):
python - <<'EOF'
p = r"C:/Users/<you>/AppData/Roaming/MetaQuotes/Terminal/<id>/MQL4/Logs/20261001.log"
t = open(p, 'rb').read().decode('cp1252', 'replace')
print([l for l in t.split('\n') if 'TABCENSUS' in l][-5:])
EOF
```

A compile log is 130 lines and has no `[drawstrip]` in it; the Experts log has the census,
the PLATE line and every press. One read of it answered what four attempts at asking
the user did not.

**2. Equal z is settled by the terminal's LIST ORDER — so z can never name the winner.**
Two objects on the same rung with the same seat are both "correct" in every property
the census printed before P-DRAW-124: the ink and the thing on top of it read the same
`z`, the same `back`, the same `fnt`. The discriminator is the index the walk is
standing on, which is why the census prints `idx=` now, and why a rule that lives only
in `z` ("our ink re-asserts Z_STRIP_OVER") is not a proof. And an UNSET property reads
`0`: the whole strip family reads `tf=0` — including the objects the screen SHOWS — so
`tf=0` is "never written", never `OBJ_NO_PERIODS`.

**3. The terminal's own journal is a CACHE, and it lags the tab (P-DRAW-126).**
MEASURED 2026-10-01 20:15:20: the Experts window showed a full `20:03:44` frame while
`MQL4\Logs\20261001.log` ended at `20:01:38.319` and had not grown in fourteen minutes.
So the diag channel writes a file it owns and flushes it per line —
`<data folder>\MQL4\Files\biotak_diag_<SYMBOL>.txt`, written by `DrawStripDiagEmit`.
And the handle must SHARE (P-LOG-3): MEASURED 2026-10-01 21:52:50, the file was written
and flushed (`62,965` bytes) while `open(path,'rb')` raised `PermissionError 13`,
`cp`/`head` said "Device or resource busy" and `Get-Content` said "being used by another
process" — a `FileOpen` grants no share by default, so the flushed bytes were current and
unreachable at once. `FILE_SHARE_READ` is the flag; a writer that omits it has a channel
only it can read. Read THAT, and read it first:

```bash
python tools/diag-live.py            # newest flushed diag file, tail 220
python tools/diag-live.py --all      # every source, newest first
python tools/diag-diff.py <that file>
```

Law 1 still holds once the terminal flushes — but never ask the user for another run
before reading the flushed file, and never trust a snapshot that came from a different
data folder than the one the running `terminal.exe` is using.

**4. A diag frame belongs to ONE attach — delete the old ones (P-LOG-2).** The flushed
frame is truncated only when a NEW attach emits its FIRST line, so between a restart and
the first panel open the PREVIOUS session's `biotak_diag_<SYMBOL>.txt` is still on disk
and still the newest diag file by mtime — a stale frame that reads exactly like a live
one (measured 2026-10-01 21:35: after a restart the terminal's journal was fresh but the
diag file was simply absent; the next restart would have found the last one still
sitting there). Read newest-first, and delete the rest:

```bash
python tools/diag-live.py            # newest source; prints STALE when a frame is old
python tools/diag-live.py --prune    # delete every stale diag frame, then read
```

`compile-th3.ps1` does the same while `terminal.exe` is stopped (`Clear-StaleDiagFiles`,
inside `Restart-TradingTerminal` and `Invoke-StripShot`), so after a restart the FIRST
frame that appears is provably this session's. A file the terminal still holds open
cannot be removed on Windows; the reader reports it as `locked` rather than pretending.

**5. A flush is not a read, and the file carries many frames (P-LOG-3).** MEASURED
2026-10-01 21:52:50: `biotak_diag_EURUSD.txt` was written and flushed (62,965 bytes)
and every reader failed on it — `open(path,'rb')` → `PermissionError 13`, `cp`/`head`
→ "Device or resource busy", `Get-Content` → "being used by another process". A plain
`FileOpen` grants no share, so the writer opens with `FILE_SHARE_READ`. Two more things
that cost an hour the same night: the name is per CHART, not per symbol
(`biotak_diag_<SYMBOL>_<CHARTID>.txt`) — two charts of one symbol share a symbol, not a
file, and each opened its own handle to one path and overwrote the other (size frozen
at 62,965 bytes while frames were being emitted); and the unit a reader may diff is a
FRAME, never the file — the writer appends a whole frame per panel open and never
truncates, so reading the file whole pairs the FIRST open's declaration with the LAST
open's census. MEASURED: the mixed read said `DIVERGED: 53 of 187 (SEAT 38, TEXT 15)`;
the last frame alone said `declared 91 / held 139, PASS`. Always read the newest FILE,
then the LAST frame in it:

```bash
python tools/diag-live.py                 # newest file, last frame (--frames/--frame N)
python tools/diag-diff.py <that file>     # diffs the LAST frame unless --frame says otherwise
```

## The paint-order case file (P-LOG-9 → P-LOG-10, 2026-10-01→02)

The bare wide panel's left column survived FOUR layers of proof (census 91/91, no
screen cover, no chart-object cover, AFTER delta 0) because the object model was
RIGHT and a draw RULE was wrong. The facts that fenced the field, in order:

1. clicks on the bare seats still fired → ZORDER (click priority) intact; only paint missing;
2. the wide × existed in the census at its MOVED seat yet never showed → a write raises nothing;
3. probe labels born LAST showed at BOTH seats → the seat was never the problem;
4. a same-pixel touch raised nothing → CREATE is the only raise.

THE LAW (now a gate, P-LOG-10): MT4 paints in creation order; `OBJPROP_ZORDER` rules
clicks alone. A plate is born before the content it hosts, and any plate that can be
REBORN (branch flip, `!fits` purge, spec/geometry change) purges its family at the
rebirth. Owners: `DrawStripGearPlate` (pairN guard), `DrawStripSkinPaintAt`
(`s_dsSkinPlateDied`) answered at the top of `DrawStripPaint`, and `PnlCreate`
(geometry-flip purge for the dynamic cards 9/12). When pixels disagree with a
PASSing census, stop re-reading the object list — probe the screen.

## The hold's two windows case file (P-UI-130, 2026-10-02)

Two user reports — «هولد بعضی وقتها درست کار نمیکنه و باز نمیشه» and «موقعی که باکس
جابجا میکنم یا ری‌ساز میکنم نوار استریپ بالا میاد و مزاحم میشه» — and the DIAG-116
lines that were already in the running build named both, in one 4-second window
(`MQL4\Logs\20261002.log`, EURUSD,M1, one box `Rectangle 49028`):

```
00:12:57.036  press edge at 697,226 bit=1
00:12:57.036  hold latch at 697,226 hit="Rectangle 49028"      <- latch + press cycle SET
00:12:57.473  press edge at 698,226 bit=1                       <- the same press's flap
00:12:57.473  press refused: cycle live obj="Rectangle 49028"   <- refused 437 ms in
00:12:57.549  hold dropped: hit changed ... now=""               <- the BOX moved: a drag
00:12:57.931  press refused — 00:12:58.451 refused — 00:12:58.939 refused
00:13:00.370  press refused — 00:13:01.481 refused               <- FIVE presses lost
00:14:41.739  hold latch at 619,191 — 00:14:42.352 hold opened   <- the user came back
```

THE LAW (now a gate, P-UI-130): a gesture's flags die with the gesture, and a drawing
the terminal is MOVING is never held.

1. The press cycle's life was the OPENER window's cap (10 s). Its one job — refusing
the flap that re-times the 500 ms clock (P-UI-115c) — needs milliseconds (measured
flaps 179/252/488 ms), so it lives on `DSTRIP_PRESS_CYCLE_MS` (2 s) now.
2. A latch the position test had already DROPPED still had its clock running, so
`DrawStripHoldGestureLive()` read it as live at the release and the release stamped a
window instead of clearing the cycle. `DrawStripHoldForget()` clears the clock with
the object; the poll's TTL backstop clears both.
3. The press that starts a drag is indistinguishable from a hold by clock alone — the
terminal's own `CHARTEVENT_OBJECT_DRAG` is the witness (P-BK-19a's owner trait,
TH3Tool_C's resize measurement). It kills a live latch, clears the cycle, and gates
the latch + both fire paths for the 400 ms heartbeat its events renew.

DIAG reading for the next session: a drag must print one `hold cancelled: native drag
obj=…` (or `latch blocked: native drag`) and NO `hold opened` for that gesture; a
press on a stopped drawing must still reach `hold opened` inside ~500 ms.
