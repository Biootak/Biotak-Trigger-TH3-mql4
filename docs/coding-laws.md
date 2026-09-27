# CODING LAWS — read before writing code

Learned 2026-09-27, in the strip's fill/level/extend session (P-DRAW-64a–d, 64b–c)
and the ICON-DIET session (2026-09-27: 325 → 284 runtime bitmaps, 49.00 → 13.91 MB
on disk, 42 files with no runtime path).
Each law is one or two lines. The WHY behind each lives in `docs/history.md`;
the code keeps the `P-*` ID. Laws marked PORTABLE hold on any machine, any
terminal, any account; the rest name their scope.
Sections I and J are machine-independent by construction: they are about
reachability and measurement, not about paths, shells or hashes, so they survive
a new computer, a new session and a new account unchanged.

## A. The machine you run on is not the machine you wrote on (PORTABLE)

- A1. Probe the shell before assuming it. Win32 PowerShell 5.1 has no `head`,
  no `&&`, no `Select-Object -First` substitutes for real output — write the
  command the project's documented shell runs, or test the verb first.
- A2. Proxy variables break process spawns. Null BOTH cases of each `*_proxy`
  in the SAME invocation via `[System.Environment]::SetEnvironmentVariable`
  (the `env:` provider is case-insensitive and `Start-Process` dies otherwise),
  and set `$env:APPDATA` when driving PowerShell from the agent side.
- A3. Never hardcode a terminal hash. `Terminal\<HASH>\` differs per install,
  per account, per machine. The LIVE terminal is the running `terminal.exe`'s
  own dir — find the process, then the path. The compiler's dir and the live
  dir are routinely two different hashes.
- A4. Never edit code with the shell. Use the file tools; a shell that
  re-implements them is a defect. If a bulk edit ever touches bytes, prove
  safety afterward: `git diff --numstat`, no hunk at line 1 (BOM), Persian and
  UTF-8 intact, and the gate still green.
- A5. Respect the repo's line endings. Check the convention (BOM/no-BOM,
  CRLF/LF) before any byte-level write; a whole-file rewrite that only changes
  endings is a corrupted commit wearing a diff.

## B. Realtime is the same event (PORTABLE for event-driven UIs)

- B1. A follower writes in the event that moved its owner. A deferred frame IS
  the lag. No throttle, no queue, no "next pass" between a hand and its pixel.
- B2. The hand's own cadence IS the cadence. Throttle only what the eye cannot
  see — and "cannot see" needs a number (a 1 px hairline at 50 ms is ~15 px of
  drift; the user refused it, so the throttle died).
- B3. The terminal coalesces identical event ids. Never ride `OBJECT_DRAG`
  alone: a dropped frame is a frame the follower did not move in. The move
  stream does not coalesce — key it on the press's OWN object (already
  memoized, so there is no hit test to pay) behind a geometry memo.
- B4. The terminal paints the layer the dragged object lives in. A follower
  parked in another layer is painted by the NEXT pass — no stamp can close a
  gap that opens after the write. Same layer, or accept the frame.
- B5. Every gesture's last frame can be coalesced away. The release re-stamps
  its own object, once per gesture — it is the last word, not an optimization.
- B6. A witness that must work with the UI shut stands ABOVE the open-guard.
  A follower that only follows while its panel is open is a bug report waiting
  for a screenshot.

## C. Followers are part of the master, or they are defects

- C1. ONE owner per follower: created, moved and deleted WITH the master;
  never served, never hit-tested, never learned into a preset. If a hit test
  can land on it, it is not a follower, it is a second drawing.
- C2. Every follower gets an ORPHAN RULE in the periodic sweep (parent gone ⇒
  child deleted, same pass). A line that outlives its box is the proof this
  law was skipped.
- C3. Mirror what moves, freeze what does not. The master's layer, colour
  source and style INPUTS are mirrored per sync (guarded); what never changes
  (a 1 px frame, a dot style) is written ONCE at birth and never read again.
- C4. Guides are whispers: the thinnest frame the terminal draws, the ink
  blended toward the background. Full-strength ink competes with the thing it
  guides; a leftover outline of a missing part reads as a fill.
- C5. Compare before write. A still frame is reads and never a repaint it did
  not earn. State the bound per path (what it walks) and the budget per frame.
- C6. No memo unless the read is expensive AND the invalidation is airtight.
  Coupling geometry to a tag to save microseconds is the wrong trade.

## D. Marks carry state; payloads carry staleness

- D1. The description is ONE group with ONE writer. Re-emit the group whole;
  a rewrite can never drop a sibling mark.
- D2. Prefer payload-free marks. A remembered length needs a staleness rule
  and a recheck; a level is true for every box at every size and needs none.
  When the semantics change from length to level, DELETE the payload machinery
  — never park it as "a second way to say it".
- D3. State and geometry must agree, or the state must drop. A gold button on
  a static box is the shape of every bug in this family: check whether the
  STATE is right and the GEOMETRY never moved before touching either.
- D4. Arrangements are not looks: never learned (`return` before the
  `s_dkValid` line), never undone, never inherited by a duplicate that would
  "run away", never applied to a fresh drawing.
- D5. A tap that arms a travel takes the FIRST STEP itself. A pump keeps it
  travelling; it must never be the first thing the hand waits for (on H1 that
  wait is an hour). Then the pump's own cadence is correct as it stands.
- D6. Coexisting marks share one writer and preserve each other. A write that
  silently clears a sibling mode is an interference bug, however quiet.

## E. A control that cannot be found is a bug

- E1. Name every role, highlight the active one, and let each set its own
  state outright — never a secret toggle. Tooltips are not discoverability;
  structure is.
- E2. Every path that edits a visible thing must SHOW it. Grid, hex, bar,
  recents, scrub, preset: if one of them leaves no pixel changed, it reads as
  "nothing happened" — audit the family together, because the gap is always in
  the path nobody re-read.
- E3. Test tools TOGETHER, from the code, before the user does. Pairs that
  only exist in combination (level × travel, colour × level, extend × fill,
  lock × travel, duplicate × marks, undo × arrangements) are where the bugs
  live. Read each pair; fix the real ones; write down the clean ones so no
  future reader re-tests them.

## F. Measure, then fix — with the terminal's own instruments

- F1. The Experts log buffers. It flushes on chart change/deinit, not per
  line — a Print trace can sit unread for minutes while the session keeps
  going. A file trace (`MQL4/Files`, flushed per write) answers NOW; remove it
  when the question is answered, because a write per gesture is a cost nobody
  ordered.
- F2. The terminal log IS a measurement channel: `hold latch` lines, object
  names, `uninit reason`s and timestamps tell the gesture story without asking
  the user anything.
- F3. Profiles (`.chr`) lag the live chart (they flush on save/close); the
  live chart is the objects, not the file.
- F4. Screenshots are measurements: compare pixel extents at identical axis
  scales before claiming "nothing moved".
- F5. When the user names the cause, trust it and fix that layer — not the
  witness that was already correct.

## G. Bakes are data: verify the raster, not the numbers

- G1. Art space ≠ bake size. Read the rasterizer (here: 32-space art, 24 px
  bake), and verify at 1:1 — a 24-space rect lands in three quarters of the
  face and the numbers will not tell you.
- G2. A regeneration must be deterministic: after it, `git status` shows only
  the intended bytes. Anything else is a second, unreviewed change.
- G3. A helper whose last caller is gone goes with it. Dead code is a defect
  with a pulse.

## H. The gate and the commit

- H1. The compiler is the gate: every entry (Full AND Lite — a shared module
  that calls a UI function compiles green in Full and breaks Lite) plus every
  harness, every time; then the geometry check; then the deploy that verifies
  BOTH terminals. A re-attach is required — icons and `ex4` load only at
  attach.
- H2. Deletions and moves are their own commit. Bulk deletes need approval; a
  blocked delete is reported, never routed around.
- H3. Before committing: status, diff, recent log. Stage only intended files.
  Never commit secrets, logs, binaries that rebuild, or temp.
- H4. The investigation goes to history; the code keeps the ID and the law;
  the contract doc (checklist) moves with every rule change. Comments state
  the WHY and stop (16-line ceiling).

## I. Reachability before deletion (PORTABLE)

- I1. A search that returns zero is not a zero until you have expanded the
  CONSTRUCTION. Names built by concatenation (`stem + "_" + accent + ".bmp"`,
  `"card" + n + ".bmp"`) are invisible to a literal search. Before declaring
  anything unreachable, enumerate its producers: the stem table, the accent
  list, the index range, the suffix variants. Same failure class as a search
  tool whose `-l`/`-c` flags answer "0 matches" for strings that exist — a
  tool's zero is not the world's zero, and both times the fix is to re-ask a
  different way, not to believe the first answer.
- I2. A clamp constant is a CLAIM about its producer — trace the claim, never
  read the number. `MAX 16` read as headroom; the branch that consumed it could
  only ever see ≤10, because a different predicate routed everything above that
  to a composed path. Twelve files and 11.4 MB existed to serve an index the
  producer could not produce. If you cannot name the producer's bound in one
  sentence, the constant is unverified.
- I3. Classify before deleting: PRODUCED-EMPTY (the whole family is dead — take
  all of it or none, one member is meaningless), INDEXED-BY-RUNTIME-VALUE (the
  number IS a live lookup key — deleting a member breaks the map), or ISOLATED
  (safe one at a time). Only ISOLATED may be deleted piecemeal.
- I4. A commented-out restore path still costs real bytes. `orb_word`'s only
  call site had been commented out for two weeks while its `#resource` stayed
  live: 20 KB in every `.ex4` for a line nobody runs. Keep the builder and its
  master; drop the embedded artifact and the declaration. A restore hint must
  not keep its payload alive.
- I5. A generator that writes a list but never prunes stale files is half a
  generator. After regen, disk held 326 files against a 284-line manifest. The
  gate is BIDIRECTIONAL set equality — every manifest entry has a file AND every
  file has a manifest entry. One direction is not a check.
- I6. Fix a defect with a SWAP, never an addition. A mark ink that was resolved
  at runtime but emitted nowhere was fixed by moving one dead name out of the
  ink set and the live one in: 13 files in, 13 out. A diet that grows the
  payload to fix a bug is a bad trade, and a swap stays reviewable as a swap.
- I7. Assert the COUNT and a sentinel of a destructive list BEFORE running it.
  A range written `1..16` where `11..16` was meant built a 62-item delete list
  instead of 42 and would have taken 20 live files with it. One
  `if($list.Count -ne 42){ exit 1 }` plus "are these 8 known-live files still
  listed?" is the whole difference between a diet and an outage. A range inside
  a delete path is a reachability CLAIM (I2) and gets verified like one.

## J. The number you report is the number that is paid (PORTABLE)

- J1. "No quality loss" is a HASH, not a compile. Hash every generated asset
  before touching it; after, diff the set and require untouched files to be
  byte-identical (283/283 here). A green build says nothing about pixels.
- J2. When you delete N bytes, find out what the CONSUMER's byte count did —
  and when it disagrees with your model, SAY SO. 35 MB of bitmaps left; the
  shipped binary moved 398 KB, because the packer compressed those gradients
  ~88:1. Reporting only the flattering on-disk number is a lie of omission.
  Predict, measure, report both, explain the gap.
- J3. Comparing a build artifact git does not track means restoring the WHOLE
  before-state, binaries included, and "restored" needs a count rather than a
  belief. Stashing `src` but not `assets` produced a failed compile and a
  meaningless number that looked like a result. Check the before-state's file
  count before trusting a before/after measurement.
- J4. `git stash pop` rewrites line endings: content-identical,
  byte-different. Compare normalized before concluding you lost work, or you
  will raise a phantom data-loss incident and spend a turn on it.
- J5. Set algebra over many names is not a file-tool job. Reachability across
  four states (disk / manifest / declarations / runtime) for hundreds of names
  cannot be done with read+grep inside a context window; a scripted pass is the
  sanctioned terminal use. Reading 325 files one at a time is not.
- J6. Audit the direction your cleanup did NOT. The diet's own ledger surfaced
  an inverse defect: a name constructed at runtime that was emitted and declared
  nowhere, so a card had been drawing no mark at all. A byte-counting pass
  misses the bugs sitting in the same table — reachability has two errors, not
  one, and the second one is a missing entry rather than an extra one.
