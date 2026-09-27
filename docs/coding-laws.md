# CODING LAWS — read before writing code

Learned 2026-09-27, in the strip's fill/level/extend session (P-DRAW-64a–d, 64b–c).
Each law is one or two lines. The WHY behind each lives in `docs/history.md`;
the code keeps the `P-*` ID. Laws marked PORTABLE hold on any machine, any
terminal, any account; the rest name their scope.

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
