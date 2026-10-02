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
11. `node tools/check-shot-freshness.js` says CURRENT — the real pixels. A mirror
   (`tools/sim-*.py`, `tools/before-after.html`'s middle column) rebuilds the panel
   from the same literals and is right about the arithmetic and blind about what the
   blit does; only the PNGs `tests/Biotak_StripShot_Test.mq4` writes by the REAL paint
   path are evidence of what a user sees. Exit 0 = every state the harness asks for
   has a PNG at least as new as the newest source it shows (`fresh`); 2 = NOT CURRENT
   (`stale` = a previous build's pixels, or `missing`), which the build prints as
   `[WARN]` and never caches — a green `[PASS]` there is how a mirror gets read as
   reality; `--strict`, run automatically after `-Shot -RestartTerminal`, exits 1, so
   a capture that left a stale or partial set FAILS the build (P-DRAW-119).
12. No owner without a caller, and no painted layer without a re-assertion
   (P-DRAW-120). P-DRAW-85's `DrawStripSweepStale()` was written for «no orphan
   survives a reattach» and documented its ONE call as "from the entry's OnInit beside
   the teardown's own `DrawStripClose()`" — and the tree held the definition and no
   call: `DrawStrip_Paint.mqh` reached its `DrawStripOrphanSweep()` only BELOW the
   `!s_dsOpen` gate, so the reattach that needs it (a reload with nothing open, every
   static reset while `PnlDrawS_*` stays) painted nothing and swept nothing. A rule
   whose only call never existed is prose; `tools/check-regressions.js` §37 asserts the
   entry's call, the sweep's position above the gate, the layer every painted face and
   caption re-asserts each paint (P-DRAW-48's law, which only the buttons had) and the
   census fields (`back=/fnt=/tf=/bmp=`) that name why an object reading correct in the
   census does not paint.
   P-DRAW-122 (2026-10-01) turns that into a LAW instead of a list of sites. The heal
   had gone to the painters a shot convicted, and five more wrote `OBJPROP_ZORDER`/
   `OBJPROP_BACK` inside their birth block and never again: the panel's rect, the gear's
   edit field, the board's hex field, the skin's underlayer and the strip's flat plate —
   plus a sixth OUTSIDE the strip, the TH3 renderer's ABCD point, which is MOVED on every
   pass and had its rung written once. Equal z is settled by creation order, so such an
   object reads correct in the census and paints UNDER the plate: the same «متن‌ها ناقص
   است» report, as a paint ORDER rather than a missing object. The set is now DERIVED by
   `tools/object_lifecycle_check.js` from every painter in `Biotak/**` — one regex pass in
   the walk it already makes, so the next painter is covered the day it is written — and
   it fails on a birth-only layer write (`layers: 12 re-assert …, 0 write the layer only
   at birth`). §39 of `tools/check-regressions.js` keeps both halves alive: the five healed
   sites and the rule in the gate.
13. **One symptom, one narrowing run (P-DRAW-121).** A hunt that starts before the
   faulty STAGE is named is a hunt that ends on a screenshot: on 2026-10-01 a band's
   `.cnt` pill read `4` for a two-setting group, the screenshot proved it, and the
   number was measured by NO gate — `tools/sim-gear-panel.py` rendered the pill and
   `check-gear-panel.py` never asserted the digit, so the defect could only be SEEN.
   `python tools/debug-doctor.py` is the loop's own instrument: it reads one symptom
   (`--symptom count|missing|stroke`, or a tab name), runs ONE probe per stage of the
   panel's pipeline — S1 the literals (with their `PNL_*`/expression aliases RESOLVED,
   because an int-only reader compares 5 of 13 and calls the other eight checked),
   S2 the accordion's layout, S3 the count RULE evaluated over the mirror's own rows,
   S4 the paint's ops per block, S5 every painter's birth-only layer write, S6 the
   terminal's own PNGs — and DELETES every stage that agrees, so the first diverging
   stage is the core gap and it is named as `file:line`. Two rules ride it: **a stage
   that cannot see the symptom is a FINDING, not a pass** (S6 is `BLIND` whenever no
   PNG exists — a mirror is never evidence, §6.11), and **a rule no artefact asserts
   is reported as such** (the doctor prints the gate coverage of the rule by name).
   A fix is not finished until the stage that DIVERGED for its symptom has a probe
   that would fail on the old tree — the probe is the proof, and the screenshot is
   only the report.
   P-DRAW-121 is the worked example. The fix is ONE filter — the pill's row loop skips
   `DSTRIP_GRK_GROUP` (`DrawStripGearSectionCount`, `Biotak/DrawStrip_GearB.mqh`) — and
   it ships with three owners, because a rule with one owner is a rule one edit can
   drop: `tools/sim-gear-panel.py` owns the count and parses the rule's flag out of
   that function's own body (`count_rule_excludes_nav` / `band_counts`),
   `tools/check-gear-panel.py` asserts the flag AND that the as-written number equals
   the members-only one (remove the filter and the two split: `LAYER reads 4 but owns
   2`), and `tools/check-regressions.js` §38 keeps the other two from being quietly
   deleted. MEASURED on the reverted tree before restoring it: `[FAIL] gear panel gate:
   6 problem(s)`, each one naming the band, the number and the nav rows that leaked.

14. **A rule is gated only if its INVERSE fails a gate.** A green check proves nothing
   on its own: on 2026-10-01 the band's `.cnt` read 4 for a two-member group while every
   gate was green, because none of them measured the number — the check existed, the
   assertion did not. The inverse of that asymmetry is mutation testing, and
   `python tools/mutation_gate.py` is the project's own: it puts a fixed defect BACK by
   literal string (one rule per mutation, the defect's exact spelling), runs the gate
   that owns the rule, and requires that gate to fail WITH ITS OWN MESSAGE naming the
   rule — `KILLED`. A gate that passes with the defect back is `SURVIVED` (the rule is
   not gated), an anchor that no longer matches is `STALE` (the check stopped running),
   and either one fails the run; the evidence printed is the gate's own failing line.
   Safety is part of the contract here because the tool MUTATES the tree: every file is
   restored in a `finally` and every touched file's sha256 is verified against its
   pre-run hash before the tool reports anything (`(tree restored, N file(s)
   byte-identical)`), it never uses git, and it is a HAND command, never inside the
   build. Its coverage line is the honest number to quote in a report: `register
   entries: 33, covered by a mutation: 4` — an entry without a kill witness is a rule
   nobody has proven is enforced, and the list is printed by name.

15. **A diagnostic may never move a pixel the product would not (P-DRAW-125).**
   The 2026-10-01 hunt for «متن‌ها ناقص است» ended where it should: in the terminal's
   OWN Experts journal, read as a fact instead of a screenshot. The instrument built
   for it (`[dsdiag] EXPECT` at every writer + `[drawstrip] TABCENSUS` after the paint,
   diffed by `python tools/diag-diff.py`) immediately found a frame in which twenty
   declared objects — `GHTB..GHXI` and `GF0..GF2T`, the panel's head and foot — stood
   with NOTHING between them, while the census after it held no grid, no section and no
   row of the panel: `DrawStripGearDiagDump()` was called from the GEAR button's tap,
   and that path runs on the CLOSE too. With `s_dsGear == 0` the unguarded
   `DrawStripGearPaint()` ran against `s_dsGRN = s_dsGGN = s_dsGearSecN = 0`: it deleted
   the whole body and — because the head and the foot paint unconditionally — left the
   head and the foot of a SHUT panel standing on the chart at the stale origin. The
   diagnostic itself was the last reporter of incomplete text.
   Two rules follow, and both are gated. (a) The dump repaints ONLY an open, laid-out
   panel (`if(s_dsGear != 0 && s_dsGearH > 0)`); a shut dump is the census alone.
   (b) Every writer asks the object's own TYPE, not its name: `ObjectFind(0, nm) >= 0`
   alone reuses whatever type an older build left there, which is exactly
   `DrawStripSweepStale`'s recorded hazard — "an object that exists, answers
   ObjectFind, and paints NOTHING". `DrawStripForeign(nm, type)` (`DrawStrip_Base.mqh`)
   is that reader; a foreign name is deleted and the writer's OWN `ObjectCreate` — kept
   in the writer, so `tools/object_lifecycle_check.js` still reads birth and layer from
   one block — rebuilds it. §41 of `tools/check-regressions.js` asserts both, and
   `python tools/mutation_gate.py P-DRAW-125` proves the assertion bites: 2/2 KILLED.
   The same read also corrected the diff tool: the census's `tf=` column is NOT a
   verdict (this panel never writes `OBJPROP_TIMEFRAMES`, so every object reads `tf=0`),
   a face's `txt` is its RESOURCE and is compared by basename against the terminal's
   resolved `bmp=`, and a label's measured ink top carries a 1px tolerance. The census
   printed `ink` for `OBJ_LABEL` only, which left BUTTON captions unverifiable — the
   swatch row's `1px`..`5px` / `Solid`..`D-Dot` are button text, so a lost caption and
   a healthy face both read `ink=-` (P-LOG-5, fixed: `DrawStripCensusInk` in
   `DrawStrip_Base.mqh` answers a button the way it answers a label, and `TEXT` now
   covers both roles). `--sample` self-tests all six verdicts.

16. **The terminal's own journal is a CACHE, not a channel (P-DRAW-126).**
   MEASURED 2026-10-01 20:15:20: the running terminal (`AMarkets - MetaTrader 4`, data
   folder `A1660DA4...`, one process up since 15:10:36) showed a full `20:03:44` frame
   in its Experts window, while `MQL4\Logs\20261001.log` still ended at `20:01:38.319`
   and had not grown in fourteen minutes — a probe for `20:03:44` counted ZERO. MT4
   buffers its journal in RAM and flushes on its own schedule, so **a reader that opens
   only that file is always behind the tab it is meant to witness.**
   Three rules follow.
   (a) The diag channel owns its bytes. `[dsdiag] EXPECT` and `[drawstrip] TABCENSUS`
   go through `DrawStripDiagEmit` (`DrawStrip_Base.mqh`), which mirrors every line into
   `<data folder>\MQL4\Files\biotak_diag_<SYMBOL>.txt` and calls `FileFlush` after it.
   A flushed file is current the moment the line exists; the Experts log is a fallback,
   never the oracle. `python tools/diag-live.py` reads the flushed file first.
   **And the handle must SHARE (P-LOG-3).** MEASURED 2026-10-01 21:52:50: the file was
   written and flushed (`62,965` bytes) while every reader failed on it — Python `open()`
   raised `PermissionError 13`, `cp`/`head` said "Device or resource busy", `Get-Content`
   said "being used by another process". A `FileOpen` grants no share by default, so the
   flushed bytes were current and unreachable at once: the channel could not be read by
   the very tool built to read it. `FILE_SHARE_READ` is the flag that lets another
   process open the handle the terminal holds (the stock `MQL4\Scripts\PeriodConverter.mq4`
   uses it); `FileFlush` still makes it current. §P-LOG-3 of `tools/check-regressions.js`
   asserts both halves of `DrawStripDiagEmit`.
   (b) The diag writer lives in `DrawStrip_Base.mqh`, not `DrawStrip_GearB.mqh`: the
   latter runs at 1497 of the 1500-line ceiling (`P-SIZE-1500`).
   (c) The build's runtime snapshot no longer picks its terminal by the mtime of an
   `MQL4` FOLDER — a folder stamp moves when a file is added beside it, not when a log
   is appended, and it returned `0727F3F8...`, whose newest log was `20260920.log`,
   eleven days stale. `Get-LiveTerminalDirs` (`compile-th3.ps1`) scans every terminal
   and takes the one whose newest `.log` — Experts or Journal — is newest;
   `Append-RuntimeLogs` and `Watch-RuntimeLogs` both consult it FIRST.

17. **A diag frame belongs to ONE attach, so the old frames are deleted (P-LOG-2).**
   The flushed frame is truncated only when a NEW attach emits its FIRST line, so
   between a restart and the first panel open the PREVIOUS session's
   `biotak_diag_<SYMBOL>.txt` is still on disk and, by mtime, still outranks every
   other source a reader looks at — a stale frame that reads exactly like a live one.
   Both halves therefore say the same thing: newest wins, the rest go.
   (a) The BUILD deletes every `biotak_diag_*.txt` while `terminal.exe` is STOPPED.
   `Clear-StaleDiagFiles` (`compile-th3.ps1`) runs inside `Restart-TradingTerminal`
   after `Stop-TerminalProcesses`, and inside `Invoke-StripShot` the same way, so no
   handle can hold the file open and the only frame that can appear afterwards is
   THIS session's. Deleting while a terminal holds the handle would fail silently on
   Windows, so the ORDER is the point.
   (b) The READER ranks every source by mtime (`tools/diag-live.py`), reads the top
   one, calls a frame `STALE` when it is older than `--stale-after` (default 900s) or
   when a newer journal proves no panel has opened since the restart, and with
   `--prune` deletes every frame except the one it reads (or all of them when the
   newest source is a journal, i.e. no frame is current). A file a terminal still
   holds open is reported as `locked`, never silently skipped.
   §42 of `tools/check-regressions.js` asserts both halves.

18. **A diag FILE carries many FRAMES — and it belongs to one CHART, not one symbol
   (P-LOG-3).** Two facts MEASURED 2026-10-01 21:52..21:58 on `biotak_diag_EURUSD.txt`
   with the panel open on EURUSD,M1 AND EURUSD,H1:
   (a) **A flush is not a read.** The frame WAS written and flushed (62,965 bytes,
   mtime 21:52:50) and every reader failed on it anyway: `open(path,'rb')` →
   `PermissionError 13`, `cp`/`head` → "Device or resource busy", `Get-Content` →
   "being used by another process". A plain `FileOpen` in the terminal grants no
   share, so the bytes were current and unreachable at once. `FILE_SHARE_READ` is the
   flag that lets another process open the handle the terminal holds (the constant
   MT4's own `MQL4\Scripts\PeriodConverter.mq4` uses); `DrawStripDiagEmit`
   (`DrawStrip_Base.mqh`) opens with it.
   (b) **The name is per CHART.** `Symbol()` names both charts the same, so each
   instance opened its OWN handle to ONE path and wrote it from its own position: the
   file stopped growing (62,965 bytes at 21:52:50 and again at 21:58:51) while two
   charts emitted whole frames, and the two frames the bytes actually held were both
   the M1 chart's (221 and 230 lines, matching the journal's `EURUSD,M1` at
   21:52:49/21:52:50) — the H1 frames the screen was showing were nowhere in it. The
   name carries `ChartID()` now: `biotak_diag_<SYMBOL>_<CHARTID>.txt`.
   (c) **The unit a reader may diff is a FRAME, never the file.** The writer appends a
   whole frame per panel open and never truncates, so a file holding two opens carries
   two declarations and two censuses. Diffing them as one document pairs the first
   open's intent with the last open's reality: MEASURED — the mixed read reported
   `DIVERGED: 53 of 187 (SEAT 38, TEXT 15)`, and the LAST frame alone reported
   `declared 91 / held 139, PASS, 0 divergences`. Same bytes, one boundary.
   `split_frames()` + the default "last frame" now live in BOTH readers
   (`tools/diag-live.py`, `tools/diag-diff.py`), and `--frames` / `--frame N` make the
   choice explicit. §42 of `tools/check-regressions.js` asserts (a) and (b), and its
   P-LOG-4 block asserts (c) — the writer half and the   reader half are gated
   separately so neither can be dropped for the other.

19. **A panel open flushes its own frame (P-DRAW-127).** MEASURED on the 22:10/22:13
   frames of `biotak_diag_EURUSD_134342075006101685.txt`: the WIDE (624px) accordion
   open declared all 91 objects correct, at their declared seats, with no intruder in
   the panel's rect and no object outranking them that covered them — and the SCREEN
   showed that same panel's left column empty. **The object LIST was right and the
   PIXELS were one frame behind.** The asymmetry is in the code: `DrawStripPaint`
   flushes with `if(dirty) ChartRedraw()`, and `DrawStripGearDiagDump` — which repaints
   the body LAST, after that line (P-DRAW-125a) — **discards its return value**. So an
   open whose geometry moved without any write reporting `dirty` kept the previous
   frame, and a second click "fixed" it because that one did write. `DrawStripActTap`'s
   GEAR branch (the ONE path that opens the panel) now ends with an unconditional
   `ChartRedraw()`: a user action gets one flush, a paint pass never does. §44 of
   `tools/check-regressions.js` asserts the flush comes AFTER the dump.

20. **Debug mode stays ON until development ends, and the unit is the LAST frame.**
   Two standing rules, not session choices. (a) `DSTRIP_DIAG` is **1**
   (`Biotak/DrawStrip_Head.mqh`): every open declares what it painted and the census
   answers beside it. Commented out = silent, and a silent build cannot be diagnosed.
   (b) The diag file carries one WHOLE frame per open and never truncates, so a reader
   compares the **last FRAME**, never the file — `tools/diag-live.py --diff` is the one
   command (newest file, last frame, its own verdict). §44's P-LOG-4 block asserts the
   frame half; the plate's own admission to the census is P-LOG-6 (the walk now tests
   the object's OWN box: a bitmap label's box came from `DrawStripResW/H` of its
   resource, which reads 0 for a name that table does not carry, so the plate's box
   collapsed to a point at `gx-14, gy-14` — 14px outside the panel rect — and every
   tile was skipped. The largest object the panel owns was the one object the census
   could never print).

21. **The census walks the WHOLE chart inside the panel rect, not a prefix (P-LOG-7).**
   MEASURED on the wide gear frame the report's screenshot belongs to: 40 declared
   left-column objects hold correct `xywh/z/back` AND `win=0 corner=0` while the screen
   shows a bare plate under them — the model is right and the pixels disagree, so the
   only question left is "who is on top", and every net the census had worn could not
   answer it. P-DRAW-124 widened `PnlDrawS_G*` to `PnlDrawS_`, which still threw away
   every object that is NOT this family — and a cover that hides this panel's ink is,
   by definition, not this panel's. The name filter is GONE; the type gate is gone too
   (a foreign rectangle/track object is walked through `DrawStripCensusSize`, which
   answers 0 for what it does not know and still logs the line); the walk is bounded by
   the panel rect as before. Two columns join every line: `win=` (the subwindow the
   name really lives in — `ObjectsTotal(0,-1)` already enumerated them) and `corner=`
   (an `x_distance` measured from the right edge draws at `chart_width-x-w`, a
   different pixel with every other column correct), plus a one-line
   `[drawstrip] CENSUS rect=... chart=WxH` so a reader can do that arithmetic.
   `tools/diag-diff.py` grows the **CORNER** verdict (non-zero corner = the defect
   itself) and its SEAT rule for faces is two-way: a raster may be SMALLER than its
   cell (the paint insets the art) or LARGER (`pnl_sw_off.bmp` is 52x34 around a 40x22
   seat — the pill lives inside the sprite's own padding), so *contained OR centred*
   proves the seat; containment alone called all four switches defects on the 22:51
   frame. §44's P-LOG-7 block asserts the writer half and the reader half separately.

22. **The census is a snapshot; the AFTER-frame is the delta (P-LOG-8).** MEASURED on
   the wide gear frame the 23:09 report's screenshot belongs to: `91/91 PASS` (seat,
   layer, text, `back`, `win`, `corner`), the whole-chart walk named **no cover** inside
   the panel rect — the one foreign object it found was
   `BiotakMenuV2_<chart>_CircTipArt` at `1580,10` on rung **1302**, UNDER the plate and
   on the far side of the panel — and the screen STILL showed the left column bare
   after a click. When the model is right, the net is wide and the pixels still
   disagree, the only question left is **whether the state the census saw is still the
   state on the chart when the user screenshots it** — and no snapshot can answer that
   about itself. So `DrawStripGearDiagDump` stores what the census saw (name, x, y, w,
   h, z, back, and the panel rect), and the NEXT `DrawStripPaint` pass re-walks that
   same name list and prints only the delta through the flushed channel:
   `AFTER GONE obj=` (a later purge ate it), `AFTER MOVED obj= was=… now=…` (a later
   writer moved or re-rung it), `AFTER NEW obj=` (a later cover arrived inside the
   panel rect) and `AFTER done snap=… gone=… moved=… new=… chartObjs=…`. `gone=0
   moved=0 new=0` is the positive witness that the object list is STILL the screen's
   state — which is the moment the hunt stops reading the object list and starts
   reading MT4's own draw rules (and the census now carries `font=`/`anch=`/`xof=`/
   `yof=`/`bord=` beside `win=`/`corner=`, the properties a draw needs that no earlier
   column read). §44's P-LOG-8 block asserts the writer half and the hook half.

23. **Paint order is creation order; `OBJPROP_ZORDER` rules clicks alone (P-LOG-10).**
   P-LOG-9's probe build settled the bare-left-column case the census never could: the
   user's screenshot showed P1 (the content rung) and P2 (rung 1600) at the LEFT seat
   and P3 at the right — every seat paints — while the left column stayed bare, and the
   touch test's same-pixel write raised nothing. Two user facts had already fenced the
   field: clicks on the bare seats still fired, and the wide × existed in the census at
   its moved seat (`1490,183`) yet never showed after the narrow→wide write. So the
   raise MT4 honours is CREATE: the wide plate's tiles were born after the narrow-phase
   content, and every object born before them painted under the card while every click
   still landed (P-DRAW-83's own wording, now a general law). The law lives where the
   plate is born (`DrawStripGearPlate`): when the plate is about to (re)appear while
   family content predates it — entering the composed branch, a body whose `pairN`
   changed, or returning to the bake after a wide phase — `DrawStripGearObjectsPurge()`
   runs once, the tiles land first, and the `DrawStripGearPaint()` that follows
   recreates every control above them. MEASURED 00:07 frame + the user's screenshot:
   both columns draw, the head and × are back, `AFTER done gone=0 moved=0 new=0`.

24. **The hold's flags die with its gesture; a drawing in motion is never held
   (P-UI-130).** Two user reports, one mechanism.
   *«هولد بعضی وقتها درست کار نمیکنه و باز نمیشه»* — MEASURED (EURUSD,M1
   00:12:57.036→00:13:01.481, one box): one latch (`hold latch at 697,226
   hit="Rectangle 49028"`) armed the press cycle, the box walked out from under the
   finger 513 ms later (the hand was DRAGGING it, `hold dropped: hit changed …
   now=""`), the drag's release never arrived on the click channel — and the cycle
   went on refusing FIVE real presses in a row (`press refused: cycle live obj=…` at
   :57.931, :58.451, :58.939, 00:13:00.370, 00:13:01.481), with the next latch only at
   00:14:41. The cycle's life was `DSTRIP_OPEN_PRESS_MAX_MS` — the OPENER WINDOW's own
   ten seconds — while its one job (refusing the flap that re-times the 500 ms clock,
   P-UI-115c) needs milliseconds: the flaps it was measured against are 179/252/488 ms
   apart. So the cycle now lives on its own constant (`DSTRIP_PRESS_CYCLE_MS`, 2 s),
   `DrawStripHoldForget()` clears the clock with the object (a dropped latch must not
   read as a live gesture at the release — the stale clock is what sent the release
   down the window path and kept the cycle armed), and the poll's TTL backstop ends
   the cycle with the hold (one fact, one clear).
   *«موقعی که باکس جابجا میکنم یا ری‌ساز میکنم نوار استریپ بالا میاد و مزاحم میشه»* —
   the press that STARTS a drag is a press on the drawing, so it armed the latch
   exactly like a hold, and the 500 ms clock knew nothing about where the hand was
   going: the strip came up on the drawing the user was about to move (and, P-UI-113f,
   left it natively selected while the anchors were being aimed at). The witness is the
   terminal's own: `CHARTEVENT_OBJECT_DRAG` is fired for the user's gesture only — the
   trait P-BK-19a made the base box's owner (`BK_DRAG_OWNER_MS`) and TH3Tool_C's band
   lock measured for the resize half («MT4 fires CHARTEVENT_OBJECT_DRAG continuously
   while the user resizes»). `DrawStripDragWitness` stamps a heartbeat and, while the
   strip is shut, kills the latch and clears the cycle; `DrawStripDragLive()` forbids
   the next latch and gates BOTH fire paths (move step + poll) for the 400 ms its own
   events renew. Gate: P-UI-130 (constant, clear, four readers, wiring + placement).

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
