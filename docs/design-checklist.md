# Design checklist — Biotak TH3 (MQL4 chart UI), 0 → 100

**What this is.** The measuring stick for every drawn surface in this indicator: the
settings cards, the drawing strip, the gear panel, the ring menu, its tip, the
catchers, the readout. It is the *why* behind `AGENTS.md`'s UI laws, expanded into a
list an agent can walk line by line and a reviewer can falsify.

**Its force.** A rule here is not advice. A surface that fails a line is a bug even
if it looks fine, and a fix that violates a line is not a fix. Where a rule conflicts
with a quick hack, the rule wins; where a rule conflicts with a measurement, the
measurement wins and the rule is corrected *in this file*.

**How to use it.** Never read it top to bottom on every change. Use it three times:

1. **Before** — Parts A–E decide the design (owners, grid, hierarchy, ink, states).
2. **While** — Parts F–H are the implementation traps (MT4's own limits).
3. **After** — Part I is the bug hunt, Part K is the gate, Part L is the report.

**Persian note for the user.** The contract documents in this repo are English so
that code names, constants and greps stay exact; the answers to you are Persian.

---

## LEVEL 0 — THE FIVE OWNERS (never create a sixth)

A second copy of anything is the root cause of most UI drift in this repo's history.
Every rule below has exactly one home. **If you are about to write a colour, a pixel,
a z-order or a font size at a call site, stop: name it in the owner instead.**

| Rule | One owner | Faces (readers) |
|---|---|---|
| A-01 **The palette** | `BioPal(i)` + `BIOPAL_N` (16), `ConstantsAndEnums.mqh`. First 8 = the panel's quick row, in order | `QuickPalColor`, `DrawStripPal`, `DrawStripSwatchAt` |
| A-02 **The z ladder** | `Z_*` in `ConstantsAndEnums.mqh` — paint order **is** click priority | every `OBJPROP_ZORDER` write |
| A-03 **The text metrics** | `PnlPt` / `PnlTextW` / `PnlLineH` / `PnlFit` / `PnlDpi` (`UtilityFunctions.mqh`) | every caption, pill, tab, badge |
| A-04 **The geometry grid** | the card arithmetic `312 / 624 / 42 / 56 / 48` (`BiotakPanels.mqh`), the plate law `48 + 42k` (`DrawStrip.mqh`) | both surfaces |
| A-05 **The ink tokens** | `BIO_CLR_*` (`ConstantsAndEnums.mqh`) — `PNL_CLR_*` and `DSTRIP_CLR_*` are aliases, never a second literal | the cards and the strip |
| A-06 **The swatch legibility floor** | `BioSwatchBorder(fill, backdrop)` + `BIO_SWATCH_MIN_CONTRAST` | quick row, preview block, palette matrix, recents, colour cells, strip grid |
| A-07 **The caption family** | `TH3Renderer.mqh` — MT4 truncates object text at **63 chars**, so one logical line is a family of ≤63-char objects | the readout |
| A-08 **The UI claim** | `UIPointerOverSurface` (WHERE) + `UIPeekClickClaim` (WHOSE) — one rule, two halves | the domain half |
| A-09 **The lock intent** | `ChartLockIntended()` — a gesture that takes the view lock names itself the day it is born | `ChartScrollReconcile` (250 ms) |

- **A-10** A *face* (an alias, a wrapper, a reader) is allowed and expected. A second
  *owner* (a second table, a second threshold, a second swatch rule) is the defect.
  `QuickPalColor` is a face; a panel-local colour table would be an owner.
- **A-11** Never invent a literal at a call site. If no name fits, add one to the
  owner. "It was only one number" is how a ladder stops being provable.
- **A-12** Include order is part of ownership. `ConstantsAndEnums` (26) → `UtilityFunctions` (47)
  → `DrawStrip` (97) → `BiotakMenu` (115) → `BiotakPanels` (116). A module may only read
  owners **below** it. If a lower module needs a higher owner's rule, the rule moves
  down (this is exactly what P-UI-34 did for the text metrics) — never copy it up.
- **A-13** The claim's **scope** is what a surface DRAWS, not its bounding box. A plate is
  a surface → the whole rect is claimed (the card: `PnlPointInside`; the grid panel:
  `SubPanelRect` inside `CircPointOnMenu`). A ring's transparent gaps and its inner hole are
  nobody's → a click that hits no control IS a chart click. The whole menu test is gated on
  `g_UI.menuVisible` (P-BK-02: during a draw session the tool must not lose the patch of
  chart the orb sits on). One test per surface, composed by `UIPointerOverSurface`.

---

## LEVEL 10 — THE GEOMETRY GRID AND THE SPACING BUDGET

The user's order: «فواصل خیلی زیاد و خیلی کم نباشه» — spacing neither too generous nor
too tight, and «جمع و جور باشه از فضا بهترین استفاده رو بکنه» — compact, every pixel
earned. That is not taste; it is this arithmetic.

### The scale (4px base)
| Step | Value | Use |
|---|---|---|
| micro | **4** | gap between swatches, icon-to-ink |
| tight | **6–8** | chip gap, control padding, plate padding |
| base | **14** | card shadow margin (baked) |
| content | **16** | card side padding (`PNL_PAD_X`), gear padding |
| row | **42** | one row pitch, one section band, one popover option, one baked mid band |
| head | **56** | card header, gear header |
| foot | **42–48** | card footer 48, gear footer 42 |

- **B-01** New spacing must land on this scale. A 10px or 13px gap is either a 8 or a
  14 that has not been decided yet.
- **B-02** Ink never touches a border. Side padding ≥ **8** between a caption and the
  edge it lives against; label → control gap ≥ **10**.
- **B-03** **Rows are one pitch.** Every row is 42; a label at +14; a single-line
  control at +9, h **24**; a slider track at +27, h **7**; a checkbox at +11, 20×20.
  A row that needs more than 42 becomes two rows, not a taller one.
- **B-04** **Plates obey `48 + 42k`.** The gear panel's height is `48 + 42k` **on its
  own** (head 56 + tabs 42 + foot 42 + air 34 = 174 ≡ 48 mod 42), not the strip's 28
  air. A height off that grid silently falls back to the flat legacy rect
  (`DrawStripSkinKFor` refuses it) — a plate that "looks a bit off" is usually this.
- **B-05** **Hit targets.** Desktop minimum is 24×24. Measured today: checkbox
  **20×20**, quick swatch **22×22**, gear swatch **28×28**, gear chip **32×48**,
  strip cell **32×32**, panel control **24** high, buttons **28** high, strip buttons
  **36**. Two faces are under the floor; a face smaller than 24 is acceptable **only**
  when the hit band around it is ≥ 24 (as the colour row's add button does: 26/30
  band for a 22px cell). Never shrink a target to make the arithmetic fit.
- **B-06** **Content is measured, never guessed.** `StringLen * 6` is banned (it was
  the P-UI-30 bug: an 81px ink in a 67px reservation). `PnlTextW` + `PnlFit`.
- **B-07** **Fitted means fitted.** A pill, tab, badge or chip sizes itself from
  `PnlTextW(txt, pt) + 2*pad` with a real pad from the scale — never from a magic
  number that happens to fit one language's string today.
- **B-08** **Two columns at > 10 rows**, never before: one column is 312, two are 624,
  the right column starts at +312, and the split is the contiguous boundary that
  minimises the taller column while keeping reading order and never orphaning a header
  from its rows.
- **B-09** **Safe areas.** Keep the bottom **30** clear of the date-scale bar
  (`PNL_BOTTOM_SAFE`). Never place a surface where the chart's own axes, the symbol
  name or the one-click panel sits.- **B-10** **Fresh surfaces open on the work, not on the cursor.** A strip opens on
  its drawing's corner; it never covers the drawing or the open card it belongs to.
- **B-11** **A face may be small; a TARGET may not.** Every *interactive* face on a
  live chart — a drag handle, a marker, a badge you can click — needs a hit ≥ 24 even
  when its art is smaller (the handset markers measure 15 px and 19 px of art:
  `HANDSET_HANDLE_HALF 7`, `CP_HANDLE_HALF 9`). Art buys beauty, the hit buys the
  gesture. This is where B-05 stops being advisory: the user grabs it with the chart
  moving under the mouse.

---

## LEVEL 25 — HIERARCHY AND FLOW (what one hand does 20× a day)

- **C-01** **Depth is a budget of three.** (1) the at-hand row, (2) the popover, (3)
  the settings panel. A fourth level means the design is wrong, not that the user
  needs to click again. Paging inside level 2 is not a new level.
- **C-02** **Frequency orders the surface.** What one hand does 20×/day is one tap;
  what it does once a week is one tap deeper. If a frequent action sits behind the
  gear, the gear is on the wrong side of the split.
- **C-03** **One accent.** `BIO_CLR_ACCENT` (#FFC247) means "this is the active one".
  Nothing else may use the accent ramp: not a warning, not a decorative bar, not a
  hover on something that is not selected.
- **C-04** **A control that cannot act is not shown.** Greyed-out is reserved for
  "you could, but not yet" (a master switch off); genuinely impossible is hidden.
  A control that draws, hovers and then does nothing is the worst of the three.
- **C-05** **Label left, value right, unit in its slot.** One reading direction per
  row. Never centre a control in a row that has a left label.
- **C-06** **Group with bands, not with boxes.** A section band (42) at full width in
  wide mode; separators (`BIO_CLR_HAIRLINE`) between rows of the same group.
- **C-07** **The current value is always visible** without opening anything: colour
  face, width sample, style sample, glyph sample. The word goes in the tooltip.
- **C-08** **Every surface answers "what did I just do?"** The caption/tooltip names
  the action in the user's words, not the code's (`Apply this colour`, not `QC`).
- **C-09** **Flow improvements are said out loud.** If a different arrangement makes
  the whole flow easier — a gesture that replaces two picks, a row that removes a
  popover, a value that can be dragged instead of typed — say it (Part L) instead of
  silently shipping the old flow.

---

## LEVEL 40 — TYPE, COLOUR, LEGIBILITY

- **D-01** **One family.** Arial / Arial Bold on every panel caption
  (`PnlTextW` measures Arial Bold's real advances). No second face, no per-surface font.
- **D-02** **The type scale** is nominal design px → points: 9 title · 9 row label ·
  8 value/control/nav/foot · 7 section/caption · 6 sub/key/ver · 5 colour-cell key.
  The conversion is the ladder in D-03; the floor is `PNL_PT_MIN 4`.
- **D-03** **Points are integers, so the scale is a LADDER, never a formula.** The
  retired `pt = round(n*96/dpi)` merged adjacent sizes — 7 == 8 at 125%, four sizes
  alike at 200%, every size alike (4pt) from 250% up: twenty equal pairs across seven
  scales. The shipped rule (`PnlPtAt`, P-UI-69e) has three properties, asserted by
  `tests/Biotak_TypeScale_Test.mq4` over every scale from 96 to 288 DPI:
  **identity at 96** (the shipped design does not move a pixel), **never equal until
  the row cap** (each rung is the smallest point size still above the one below), and
  **never taller than the row** (`PNL_PT_FIT_PX 24` — `42 − 14 − 4`; the cap is
  floored, never rounded, or the em lands at 25px for a 24px budget). Above ~240 DPI
  the cap merges the top rungs, and there hierarchy must come from **weight, colour or
  position** — a 42px row cannot hold six sizes when one point is 4px.
- **D-04** **DPI is a measurement, not a latch.** Re-probe through `PnlDpiPoll()`
  (one terminal read per `PNL_DPI_PROBE_MS 2000`) and rebuild the surfaces from the new
  metrics. Never read the DPI inside a per-caption call.
- **D-05** **The contrast floor for a swatch is `BIO_SWATCH_MIN_CONTRAST 1.7`**, and it
  is measured, not chosen: over the 198 colours the panel can paint, eleven were
  indistinguishable from their own backdrop (1.05:1 … 1.68:1) and the first genuinely
  visible tone was 1.72:1. Under the floor the swatch keeps its colour and gains the
  muted outline, so an affordance can never read as an empty slot.
- **D-06** **Do not "fix" the hairline.** `BIO_CLR_HAIRLINE` (#222832) on the card
  (#1D222C) is ~1.04:1 **by design**: the subtle border is the design language for
  panel chrome and row separators, and raising it re-outlines half the palette. Text
  is the exception: label/value inks measure 5.3:1 (muted) and 11:1+ (label/value).
- **D-07** **Truncate, never overflow.** `PnlFit` clips to the room the control leaves.
  A caption that overruns its row is a bug at *some* DPI even if it fits at 96.
- **D-08** **63 characters per object.** One logical line = a family of ≤63-char
  objects written by one owner. Never assume a long string will draw.
- **D-09** **Uppercase for bands and headings only.** Mixed case for values, labels
  and tooltips — the language the user speaks.

---

## LEVEL 55 — STATES AND THE INTERACTION CONTRACT

- **E-01** **The state set is closed:** rest · hover · press · armed · set · selected ·
  open · pinned · disabled. A new state needs a name here first.
- **E-02** **Hover is a one-event preview.** Hit-test the *already laid-out* cells in
  `CHARTEVENT_MOUSE_MOVE`, apply there, and write **nothing** while the pointer stays
  on the same cell. Leaving restores the stored value without learning it. No timer,
  no object-list walk, no full repaint — ever — for hover.
- **E-03** **A press is a press until the release proves otherwise.** Click slop is
  **8px**; a release past the slop is a drag and must not also fire the click. The
  drag's own click echo sets nothing.
- **E-04** **Single click SETs, double click re-arms** on hand-set lines; ARMED is
  draggable, SET is inert. A gesture never means two things on two surfaces.
- **E-05** **No dead zones.** Every drawn, actionable pixel has a hit test. A cell you
  can see but cannot hit is a bug — and the reverse (a hit that draws nothing) is worse.
- **E-06** **Keyboard contract:** Esc cancels/closes, Enter commits an edit. Long lists
  page; they never scroll off an edge with no way back.
- **E-07** **A text edit commits on `ENDEDIT`** (that is the only event MT4 gives), and
  an empty capture falls back to a named default — never to `My 1`.
- **E-08** **Persistence of intent.** A panel/popover/strip reopens where the user left
  it (same tab, same section). Closing a card must not lose the tab the user was on.
- **E-09** **Pinned means pinned.** A pinned surface ignores outside clicks; an
  unpinned one dismisses on them. A tap on a sibling surface is not an outside click.

---

## LEVEL 65 — WHAT MT4 CANNOT DO, AND THE WORKAROUND WE USE INSTEAD

The user's order: «چیزه که متاتریدر پشتیبانی نمیکنه به شکلی دیگر حل بشه از روش های دیگه».
This is that table. Each row is a limit, a wrong turn, and the shipped answer.

| MT4 will not | The wrong turn | The answer in this repo |
|---|---|---|
| **scale** a bitmap label — it crops at the file's native size | stretching a 1px-wide strip, or a bitmap that "looks empty" | **bake every size** and 9-slice: top cap 58, mid bands 42, bottom cap 18, baked wide (660) and cropped narrower (`DSTRIP_SKIN_*`) |
| draw a **rounded corner, radius, drop shadow or gradient** on a native rect | a square corner under a rounded skin | bake the skin (`pnl_glass*`, `ds_*`), fill the object beneath with exactly the footer ink so no square peeks through a radius |
| composite **real translucency** reliably | a rectangle label with a semi-transparent fill | bake the glass into the BMP; a solid underlayer (`Z_STRIP_BG`) below the skin for the alpha fill |
| honour **`OBJPROP_TIMEFRAMES`** on `OBJ_RECTANGLE_LABEL` / `OBJ_BITMAP_LABEL` (it is a LABEL-only property) | setting it and hoping | **visibility by existence**: delete the plate to hide it, create it to show it. Never a period mask |
| deliver a **mouse wheel** event — `CHARTEVENT_MOUSE_WHEEL` is MQL5; MQL4 has 9 events and no wheel | a wheel gesture in the help text | explicit +/− affordances, paging, or a drag. Never document a gesture the platform cannot send |
| report a **double click** | waiting for a second `OBJECT_CLICK` that never comes | measure the interval ourselves (and keep the two clicks meaningful on their own) |
| give a **right click** without the terminal's own context menu | right-click as a primary gesture | left-hold / left-click only (P-UI-113/114 deleted the right-click era for this reason) |
| route a click to **two overlapping objects** — only the highest ZORDER receives `CHARTEVENT_CLICK` | two controls stacked and both "live" | one target per pixel; the z ladder decides which, and a face drawn above a control is non-selectable (a button stays under its skin, `Z_PANEL_BASE`/`Z_PANEL_SKIN`) |
| raise an object **over the candles** with ZORDER alone | a panel that disappears behind bars | `CHART_FOREGROUND` (`PnlLockForeground`) for the panel; the z ladder only orders screen objects against each other |
| **style** `OBJ_BUTTON` (no radius, no face art, one font) | a native button in a modern card | bitmap label + OBJ_BUTTON or rect beneath it: the icon is a face, the button is the control, the router accepts either name |
| **wrap or align** multi-line text in `OBJ_LABEL` | a long caption with `\n` | measure with `PnlTextW`, stack lines by `PnlLineH`, one object per line |
| keep the object list **clean** for the user | 400 named objects in the list | `OBJPROP_HIDDEN` on chrome; the object count is a user-facing feature |
| carry **state across a timeframe change / restart / reattach** | assume live memory survives | `GlobalVariables.mqh` for indicator state, `RuntimeSettings.mqh` for panel-editable settings, and the object **DESCRIPTION** channel for what must ride the object itself |
| give **DPI changes** for free | a `static` DPI read once per instance | `PnlDpiPoll` + `UIRebuildForMetrics` |
| stay cheap with **thousands of objects** | one label per value per frame | bake a family into one bitmap; write only what changed |

- **F-01** **Extras ride the DESCRIPTION.** `[BX50]`, `[BXE1]`/`[BXE2]`/`[BXE3:N]` and
  friends survive reattach, TF switch and restart because they live in
  `OBJPROP_DESCRIPTION`. Any new datum that must survive beside an object goes there,
  and its **deletes cascade both ways** — an object deleted by the terminal must not
  leave a ghost bit of state, and a state cleared must not leave a tagged object.
- **F-02** **The description channel is also the tooltip channel.** Native
  `OBJPROP_TOOLTIP` works and is used, but the terminal's own tooltip can be turned off
  and behaves differently across builds: anything the user *must* be told is drawn.
- **F-03** **A workaround is named where it is used.** A future reader must not have to
  guess why a plate is deleted rather than hidden.
- **F-04** **Never add a DLL for what MQL4 can do.** The rule that produced the RC
  bridge is the same rule that keeps the UI: PATTERN-FIRST. The bridge exists only for
  the one thing MQL4 truly cannot do (an RC blocker), never for layout.

---

## LEVEL 75 — MOTION, REALTIME AND COST

- **G-01** **REALTIME is the same event.** A follower writes in the event that moved its
  owner. No follow channels, no timers for follow.
- **G-02** **At rest it costs nothing.** No polling, no repaint, no tick handler work
  for a surface that did not change. A steady-state frame is zero writes.
- **G-03** **Drag frames are exempt from deferral.** A deferred drag frame *is* the lag
  (`!g_s1DragLive`, `!g_customPriceLineDragging`).
- **G-04** **The mouse stream is O(cells on screen).** Never a full repaint, never an
  object-list walk, never a terminal property read inside a hit test (P-PERF-16).
- **G-05** **Write once per frame.** Batch property writes and let `ChartRedraw` land
  after the calculation; the indicator thread redraws once per `OnCalculate`, not per
  property. Per-property redraw is the flicker the user sees.
- **G-06** **Animation only where it carries state** (an open, a hover face, a drag
  follow). No decorative motion; nothing longer than the gesture it belongs to.
- **G-07** **A gesture that takes the view lock names itself in `ChartLockIntended()`**
  the day it is born, and releases through the one ender. The 250 ms
  `ChartScrollReconcile` rebuilds the lock from ownership intent, so an unlisted owner
  is read as a leak and force-released inside the first quarter second — the user
  experiences that as the chart jumping under their hand.

The user's order (2026-09-25): «باید حتی برای ضعیفترین کامپیوتر هم پرسرعت باشه و
راهکار سرعتی انتخاب بشه». G-01…G-07 say what must never cost anything; G-08…G-12 say
what a design has to prove before it ships.

- **G-08 — THE TARGET IS THE WEAKEST SUPPORTED MACHINE.** A build is judged on the
  slowest hardware and the slowest terminal the user actually runs it on, never on the
  machine it was written on. A number measured on a fast box is an upper bound, not the
  promise.
- **G-09 — WHEN TWO SOLUTIONS BEHAVE THE SAME, THE CHEAPER ONE SHIPS.** Cost is a
  decision input, and it is written down as a **number** (the measurement), not as a
  feeling; a change that raises the steady-path cost states by how much.
- **G-10 — EVERY WORK SLICE STATES A MILLISECOND BUDGET.** The owners exist:
  `CPU_WARNING_MS 50` / `CPU_CRITICAL_MS 200` for `OnCalculate` (paired with
  `pfLedgerPrint`, which prints a phase breakdown **only when the frame overruns**),
  and `COOP_WARN_MS 40` for a scheduled frame or a coop job. A path that cannot name its
  budget has not been designed, it has been hoped for.
- **G-11 — A FIXED RATE MUST JUSTIFY ITSELF; A MEASURED WINDOW IS PREFERRED.** Where
  the right rate depends on the machine, adapt to the measurement instead of pinning a
  constant — `PNL_MOVE_FRAME_MIN_MS 16` / `PNL_MOVE_FRAME_MAX_MS 50` /
  `PNL_MOVE_SLACK_MS 8` (P-UI-75b: "a weak machine may back off here") is the model. A
  constant that survives must say what it costs on the weakest machine.
- **G-12 — NOTHING UNCAPPED IN THE STREAM.** Every walk is bounded by a count
  (viewport, cells on screen, levels, objects) and every per-event path states that
  bound; a sweep that cannot be bounded runs STAGED (P-PERF-06's frame budget) or it
  does not ship.

---

## LEVEL 85 — CONSISTENCY (one thing, used everywhere)

The user's order: «یکپارچه باشه هر جا از یک چیز که قبلا هستش استفاده بشه».

- **H-01** **A new surface is not born.** It is assembled from the existing plate, row
  pitch, control kinds, state faces and palette. If it needs a new component, that
  component is added to the shared set and both surfaces get it.
- **H-02** **The same setting looks the same everywhere.** A colour on a card row and
  the same colour in the strip: one swatch rule (Part A-06), one palette (A-01), one
  legibility floor. Two surfaces disagreeing about one setting is the visible form of a
  duplicated owner.
- **H-03** **One gesture, one meaning, on every surface.** Left-hold opens. A tap
  applies. Esc closes. Nothing re-binds a gesture locally for convenience.
- **H-04** **Every surface is measured with THIS list.** There is no "small surface"
  exemption: the hover tip is audited like the settings card.
- **H-05** **Two surfaces that can overlap treat each other's published rect as a hard
  rule.** The strip and the gear panel publish via `DrawStripPublishRect` /
  `g_UIStripR*` / `g_UIPanelR*`, and the placers read them. A placer that only avoids
  the one it knows about will drop a fresh strip on the open panel.
- **H-06** **When a face and an owner drift apart, delete the face's copy.** Not
  "keep both in sync".

---

## LEVEL 86 — THE COMMENT BUDGET (C-01 — C-06)

The user's order (2026-09-25): «یک قانون هم بزار که کامنت ها باید خلاصه باشه و زیاد هر
جای کامنت نباشه». A comment is the **WHY**, in a few lines, at the place that needs
it. The long investigation — every trap's measurements, every user quote — belongs in
`docs/history.md`, not pasted where the code lives.

- **C-01 — A comment states the WHY, and stops.** The **target is 6 lines**; the hard
  ceiling is **16** for any one block (file header included). Longer than that is a
  document, not a comment.
- **C-02 — No run of comment lines over 16.** Measured by the check below. A block at
  the ceiling that needs more becomes the ID + the one-line law + a pointer.
- **C-03 — One home per story.** The investigation moves to `docs/history.md`; the code
  keeps the ID and the law. Compressing is not deleting: git holds the old text.
- **C-04 — No comment on a self-evident line.** `i++` needs no note; a comment that
  restates the code is noise that will drift away from it.
- **C-05 — The file's comment share is ≤ 25 %.** Measured by the check below. A file
  over it has runs to compress, not a rule to bend.
- **C-06 — One fact, one home.** A rule written in the code AND in a doc is the
  two-voices defect (catalogue 22) one layer up: cite the owner instead.

**The check** (bounded, no script — P-TOOL-04):

```bash
for f in Biotak/*.mqh Biotak/TH3/*.mqh *.mq4; do t=$(wc -l <"$f");
  c=$(grep -cE '^[[:space:]]*//' "$f");
  run=$(awk 'BEGIN{m=0;r=0} /^[[:space:]]*\/\//{r++; if(r>m)m=r; next}{r=0} END{print m}' "$f");
  printf "%-42s %6s %6s %3s%% run=%s\n" "$f" "$t" "$c" "$((c*100/t))" "$run"; done
```

Exit condition: every file `run <= 16` and share `<= 25 %`. The before/after numbers
are recorded in the **Audit log** (row 10).

---

## LEVEL 90 — THE DIRTY-LOOK CATALOGUE (hunt these proactively)

The user's order: «باگ های ظاهر که باعث کثیف شدن ظاهر میشه حتی اونایی که کاربر یا خودم
نمیگم رو هم باید خودت پیدا بکنی». These are the known ways this UI gets dirty. Run the
list against any surface you touch; each one has a proof you can do without a chart.

| # | The dirt | How it happens | The check / the proof |
|---|---|---|---|
| 1 | A swatch reads as an **empty hole** | a face whose colour ≈ its backdrop and a hairline border (near-black `#141414` on `#1D222C` = 1.16:1) | route the border through `BioSwatchBorder`; compute the ratio |
| 2 | A caption **runs into its control** | a hand-guessed width, or a size read at the wrong DPI | `PnlFit` everywhere; `PnlTextW` never `StringLen*6` |
| 3 | **Hierarchy collapses** on a scaled monitor | two sizes 1px apart quantise to the same integer point (D-03) | compute `PnlPt` for 96/120/144/192 |
| 4 | A **hairline crosses ink** | a separator drawn full-width under a label | the label owns its band; separators stop at the ink |
| 5 | A **ragged or flat plate edge** | a bitmap cropped below its cap width, or a height off `48 + 42k` | check `DrawStripSkinKFor` returns ≥ 0 for the height |
| 6 | A **shadow fringe is eaten** by a neighbour | plate gap < `SKIN_BOTT 18` + `SKIN_M 14` | `DSTRIP_GEAR_GAP 20` is exactly this law |
| 7 | An **empty dark bar** over a readout | a plate object created *after* the text it should sit under (equal ZORDER = creation order) | plate rung 62 < ink rung 63, at create time |
| 8 | A **ghost surface on the wrong timeframe** | a rect/bitmap carrying `OBJPROP_TIMEFRAMES` | labels obey it, rects and bitmaps do not: existence instead |
| 9 | A **stale surface after a TF switch** | nothing rebuilt on `CHARTEVENT_CHART_CHANGE` | reattach/TF switch are in every acceptance test |
| 10 | A **hover face left painted** | no restore on leave, or a restore that writes the wrong border | restore reads the stored value; leaving leaves no ink |
| 11 | A **visible control that does nothing** | a face without a target, or a hit test off by the pad | E-05, both directions |
| 12 | The user's **object list is polluted** | chrome without `OBJPROP_HIDDEN`, or a leaked widget name | every created suffix is deleted in the same surface's destroy |
| 13 | A control is **clipped by the card edge** | content-fitted width computed before `PnlFit` | fitted width uses the measured ink + pad |
| 14 | **Flicker on every tick** | per-property redraw, or a repaint in `OnCalculate` | the paint is idempotent and only on change |
| 15 | The **chart jumps under the hand** | a gesture that takes the view lock and never names itself | `ChartLockIntended()` |
| 16 | The **wrong object gets the click** | two overlapping targets, or a face above a control that is selectable | one target per pixel; faces non-selectable |
| 17 | A **surface opens on the cursor** covering the work | placement from the mouse instead of the drawing's corner | P-DRAW-20 |
| 18 | **Two surfaces overlap** | a placer that ignores the other's published rect | H-05 |
| 19 | A colour **"does not work"** to the user | the value applied fine, but the face never showed it (the P-UI-69 class) | the face and the border both follow the value, at create **and** on every later write |
| 20 | A caption/tooltip in **two languages or two voices** | a string written at a call site | one name per action, from the owner |
| 21 | A **dead rung** | a face's owner was deleted and its `Z_*` name stayed, unexplained | grep the rung name: ONE hit (its own definition) means dead. Keep the NUMBER, write the retirement — `Z_MENU_CELL` died with the right-click era (P-UI-113/114), kept + annotated (P-UI-69c) |
| 22 | The UI speaks with **two voices** | a pasted value instead of the owner, or two verbs/spellings for one act | one owner per value; one spelling and one verb per act, decided once. Measured 2026-09-25: `colour` 4 UI sites vs `color` 7 (aligned to `color`), `tap to …` 28 vs `click …` 6 — both closed the same day (1 `tap` left, inside a quoted historical note); and the palette's own cell 0 `C'255,171,0'` was pasted at **five** live UI sites beside `BIO_CLR_BRAND` (now aliased), while the readable-foreground rule itself was written twice with two copies of its arithmetic (now `BioChartBgIsLight()`) |
| 23 | **A rule that lives only in prose** — its owner has no reader | the owner is written for a rule, the rule is then rewritten elsewhere/inline, and nobody ever calls the owner | for every `*At()` test that answers a UI question, count its callers: **1 hit = its own definition = nobody asks it**. Measured 2026-09-25: `CircPointOnMenu` ("which pixels does the menu own?") had **zero** callers in every commit since birth (`git log -S`), while `UIPointerOverSurface`'s header promised the ring's pixels and its body tested everything but them |
| 25 | The comment is an **essay**, or there is a comment on every line | the whole investigation of a trap pasted where the code lives; narrative where the WHY belongs | **C-01..C-06** (LEVEL 86): the check is the run length + the file's share, and the fix is compress-in-place to the ceiling (the ID and the law stay, the story goes to `docs/history.md`). Measured 2026-09-25 at the rule's birth: **392** runs of ≥ 13 comment lines repo-wide (9563 lines), **40** of them ≥ 40 lines, the worst a **220-line** file header (`BaseKnotTool.mqh`) and a **48 %** share in the same file |
| 24 | **A phantom owner in a comment** | a comment cites a function as a LIVE reader ("X hit-tests it") that was never written, or was deleted — the reader hunts a hit test that cannot be found | for every identifier inside a comment, grep the **whole tree** (not the one file), then drop the ones whose comments say they are retired (`was X`, `X-OFF`, `restore by …`) — those are documents, not lies. Measured 2026-09-25 over `BiotakMenu.mqh`: 77 comment identifiers → 13 candidates → 12 legitimate cross-file names, **1** phantom cited as a live third reader (`SubPagerAt`); the repo-wide re-run lists ~20 names, and nearly all are the retired-but-documented kind |

---

## LEVEL 95 — LIFECYCLE AND PERSISTENCE

- **J-01** Four events must be survivable by every surface: **reattach**, **TF switch**,
  **terminal restart**, **template re-apply**. Nothing may depend on live memory alone.
- **J-02** Nothing is left **advertising a state that did not happen** (the TH3 rule,
  generalised): a badge that says recalibrated, a cap that says saved, a plate that
  says a step exists. If the action did not complete, the mark is deleted, not dimmed.
- **J-03** Panel-editable settings live in `RuntimeSettings.mqh` and nowhere else;
  indicator-wide state in `GlobalVariables.mqh`. The description channel is for what
  must ride an *object*, not for settings.
- **J-04** A restore path never invents a plausible default for an unmeasurable value.

---

## LEVEL 100 — THE DELIVERY GATE (definition of done)

A UI change is done when all of these are true. **No item may be skipped by calling
something "cosmetic".**

1. **Compiler is the one gate** — every `.mq4` prints `Result: 0 errors`:
   the two entries **and** the seven harnesses in `tests/`. `-Project all` builds only
   the main entry; every harness needs its own `-SourceFile` run. A harness needs
   the icon link beside it (`tests/Files` -> `Files`, **gitignored**, auto-created by
   `-SourceFile`): MetaEditor resolves `#resource` against the SOURCE file's own tree,
   so without it every icon-bearing module in the chain dies with 325 x `error 310`
   while the same modules compile green from the root (P-BUILD-03, 2026-09-25).
2. **`node tools/submenu_geometry_check.js`** passes.
3. **Owners:** no new literal for a colour, pixel, z-order or font size; no second table.
4. **Grid:** every new number lands on the 4px scale; every plate on `48 + 42k`.
5. **Ink:** every caption measured with `PnlTextW`/`PnlFit`; every swatch through
   `BioSwatchBorder`.
6. **The 20 items of Part I were walked**, and each one is either clean or listed.
7. **A new raster** has both its `#resource` line and its `SLICED` entry in
   `tools/icon-manifest.txt` (written by `node tools/gen-th3-icons.js`). A bitmap that
   is not embedded draws nothing — that is the "ghost icon" class.
8. **Lean:** `AGENTS.md` is not the place for the detail; it points here.
9. **The report** names the file, the number and the measurement (Part L).
10. **Performance has a number (G-08…G-12).** Every new path states what it walks (the
    bound, in objects/cells/bars) and its millisecond budget; the target is the weakest
    supported machine, not the dev box. Nothing whose cost scales with the chart enters
    the mouse stream or the tick path, and a fixed cadence has to justify itself
    against a measured window.

**Visual verification, honestly.** This repo has no chart renderer: a rendered frame
cannot be produced from the compiler, and the manual tools that once did were deleted
under P-TOOL-04. So a visual claim is proven one of three ways, and the proof is named:
(a) **arithmetic** off the constants (contrast ratios, DPI quantisation, grid
membership, the `48 + 42k` test); (b) a **user screenshot** at a named DPI and
timeframe; (c) a **static sim** page served in the preview tab when a layout question
needs looking at rather than counting. What is never acceptable is "it looks fine" —
that is the phrase that has shipped every bug in Part I.

**Rules that lost their tooling did not lose their force.** `verify.plan.json`, the
`*-audit` scripts and the two root generators are gone by user order; the rules they
pinned are pinned by the compiler and by reading now. No rule below is contingent on a
script that no longer exists.

---

## LEVEL L — WHEN A BETTER WAY EXISTS, SAY SO

The user's order: «اگر در هر جای از پروژه راهکار بهتر و معماری بهتر وجود داره حتما
استفاده و اپدیت بکنه … و به کاربر بگه راهی دیگه هستش که مثلا با این کار میشه فلو جریان
کامل کار رو راحت تر کرد».

- **L-01** When the current implementation is not the best available, the report says
  so in four lines: **the current flow → the proposed flow → what it costs → what the
  user gains.** Then it is applied, or it is offered.
- **L-02** Apply it when it is contained and proven (a duplicated owner, a proven
  contrast hole, a hand-guessed width). Offer it when it changes how the user works.
- **L-03** Never present a rewrite as a bug fix. Say which one it is.
- **L-04** An upgrade that touches a shared owner moves the rule **down**, not sideways
  (A-12). Duplicating the rule to avoid an include-order edit is the defect, not the fix.
- **L-05** The measurement comes before the claim, in the report and in the code
  comment: *what was measured, on what, and what it read.* Comments in this repo that
  say "measured" must stay true, so never write "measured" for arithmetic you did not do.

---

## Appendix — the measured numbers this list quotes

| Number | Value | Home |
|---|---|---|
| palette | 16 (first 8 = quick row) | `BIOPAL_N` |
| swatch contrast floor | 1.7 (11 of 198 indistinguishable; first visible 1.72) | `BIO_SWATCH_MIN_CONTRAST` |
| card column / wide | 312 / 624 | `PNL_WEL`, `PNL_WIDE_WEL` |
| card head / row / foot | 56 / 42 / 48 | `PNL_HEAD_*`, `PNL_ROW_H`, `PNL_FOOT_H` |
| card side padding / shadow margin | 16 / 14 | `PNL_PAD_X`, `PNL_MARGIN` |
| control height / top in row | 24 / 9 | `PNL_CTL_H`, `PNL_CTL_Y` |
| checkbox | 20×20 at +11 | `PNL_CB_SZ`, `PNL_CB_Y` |
| quick swatch / gap / preview | 22 / 4 / 46 | `PNL_QSW_*` |
| plate law | `48 + 42k` (gear air 34) | `DSTRIP_GEAR_AIR` |
| strip cell / pad / gap | 32 / 8 / 4 | `DSTRIP_CELL`, `DSTRIP_PAD`, `DSTRIP_GAP` |
| gear width / wide / column | 312 / 624 / 312 | `DSTRIP_GEAR_W*`, `DSTRIP_GEAR_COL` |
| gear swatch / chip | 28 / 48×32 | `DSTRIP_GEAR_SWATCH`, `DSTRIP_GEAR_CHIP` |
| skin caps / margins | cap 28, top 58, mid 42, bottom 18, margin 14, max width 660 | `DSTRIP_SKIN_*` |
| click slop | 8 | `DSTRIP_CLICK_SLOP` |
| min point size | 4 | `PNL_PT_MIN` |
| DPI probe cadence | 2000 ms | `PNL_DPI_PROBE_MS` |
| bottom safe | 30 | `PNL_BOTTOM_SAFE` |
| text object cap | 63 chars | MT4 |
| chart events in MQL4 | 9 — **no mouse wheel** | MT4 |
| type ladder | nominals 5..14; distinct until the cap `PNL_PT_FIT_PX 24` (`42 − 14 − 4`) | `PnlPtAt` |
| comment ceiling | target 6 lines, hard ceiling 16 per run (a file header included); file share ≤ 25 % | LEVEL 86 / C-01..C-06 |
| frame budget | 50 ms warn / 200 ms critical (`OnCalculate`); 40 ms (`COOP_WARN_MS`, a scheduled frame or coop job) | `ConstantsAndEnums`, `EventHandlers` |
| adaptive window | 16 ms floor / 50 ms ceiling / 8 ms slack — a weak machine backs off | `PNL_MOVE_FRAME_*`, P-UI-75b |
| cadence constants vs measured windows | **80** fixed `*_MS/_SECONDS/…` constants against **1** measurement-driven window (2026-09-25) | Audit log row 11 |

---

## Audit log — which surfaces have been walked

A surface counts as walked only when every rule above has been run against it and
every finding is either fixed or recorded here with its measurement. This table is
the honest answer to «چک لیست تموم شد یا نه»: the document is done, the sweep is
this list.

| # | surface | walked | findings |
|---|---|---|---|
| 1 | palette + every swatch family (quick row, preview block, matrix, recents, colour cells) | 2026-09-25 | **fixed:** the strip's own gear grid and colour popover painted near-black through the hairline (1.04:1) — `BioSwatchBorder` moved to `ConstantsAndEnums` (reachable at last) and wired to 3 sites; nine duplicated `DSTRIP_CLR_*`/`PNL_CLR_*` literals aliased to `BIO_CLR_*` |
| 2 | ring menu + hover tip + every tooltip | 2026-09-25 | **fixed:** `SUB_CLR_HDR`, `SUB_CLR_ACCENT` and `CLR_CIRC_BADGE_BG` were pasted literals (`#8C96A6`, `#FFC247`, and the palette's own cell 0) — aliased to the owner; the orb skin's `C'30,22,10'` call-site literal named (`CLR_CIRC_ORB_SKIN`); user-visible `colour` → `color`; `tap` → `click` (measured after: **1** `tap` string left, inside a quoted historical note, 0 `"Colour"`). **fixed (2nd pass):** the ring's own pixels were absent from the UI claim — `CircPointOnMenu` had **no caller in any commit** while `UIPointerOverSurface`'s header promised them; composed now (P-UI-116) and the claim's scope written down (A-13). **accepted, with the measurement:** the hover tip may cover a neighbouring ring item (it is a rectangle 12px off the item with a 1500ms dwell) — it can never sit under a live cursor (it parks the moment the hovered feature changes, and on the press edge), so no click is eaten; the only layout where it covers its OWN item needs a chart < 166px tall (`ch − 60 < ay + 34` with `ay < 72`) |
| 3 | handset markers (custom price + step-1 handles) | 2026-09-25 | **measured:** art is 15 px / 19 px (B-11); hide is a park, not a TF mask (correct — F-01/F-02, rects and bitmaps ignore `OBJPROP_TIMEFRAMES`). **open:** the hit-size decision |
| 4 | settings cards, row by row (14 items) | — | not walked |
| 5 | TH3 readout (caption family + leg box + its plate) | 2026-09-25 | **fixed:** the caption's per-pattern SLOT PITCH was the one real dirt here (P-TH3-INFO-14). Since INFO-10 only the ACTIVE family carries a plate, so a second slot can never be occupied: the pitch could only push the one visible caption down by `patIdx × (TH3ROPlateH(3) + 8) = 64 px` (pt 9 @ 96 dpi) over an empty slot and jump it when the active pattern changed. It was also sized on 3 rows while the wrap budget is 6 — `TH3ROPlateH(4) = 73` and `(6) = 107` against a 64 px pitch, i.e. the "two plates never overlap" note was 9–43 px false. Its helpers (`TH3InfoCaptionBlockH`, `TH3InfoCaptionTopY`) had no other reader; retired, number kept. **fixed (leg box):** both window fits could undo P-LM-19/23 and land the plate ON the tip it labels — the X clamp (`bx = right - bw`) reaches the tip whenever the head sits in the last `bw` px, which is exactly where the newest bars are — so placement is now CHOSEN (preferred side → its mirror across the tip → above/below the tip's row) around a `LEG_INFO_CLEAR 8` box, still a pure function of the anchors (P-LM-24). **measured clean:** plate measured from the final wrapped lines, not guessed; rows rebuilt after their plate (INFO-12); the 63-char cliff handled by the wrap; safe-Y mirrors the mode rows' `+45` (INFO-02) |
| 6 | BaseKnot pills (hint + badge) + the mini Base Box strip | 2026-09-25 | **fixed (one rule, two copies):** the readable-foreground gate for chart-anchored text existed TWICE — `BaseKnotFgForBg()` and `RuntimeSettings.GetBKTextRenderColor()` each carried the 299/587/114 luminance arithmetic and the literal `C'150,70,0'`, the second annotated "same luminance gate as the INFO label". One owner now: `BioChartBgIsLight()` + `BIO_BG_LUM_THRESHOLD 128` + `BIO_CLR_ON_LIGHT`, in `ConstantsAndEnums` (included before `RuntimeSettings` (43) and before every UI file, so A-12 holds). **fixed (the palette's own cell 0, pasted):** `C'255,171,0'` stood at five live UI sites (`BaseKnotFgForBg`, `DefBoxFillColor`, `CIRC_TIP_BD`, the Base Box style default `p.fill`, the view-anchor line) → all `BIO_CLR_BRAND`; the two that stay literals are documented (`PropertiesAndInputs`' input default — that file is included at 25, BEFORE its owner, A-12; and the mirror's seed). **fixed (one value, three names):** `C'18,22,33'` → `BIO_CLR_DEEP`, aliased from `CLR_CIRC_BADGE_TXT` and `TH3RO_FILL`, and used in the retired box badge so a one-line restore cannot reintroduce the literal. **measured:** `Z_BOX_HINT 1400` has a live writer (the corner hint label); `Z_BOX_BADGE 1410`'s only writer is the NOBKDEL-retired `BaseKnotMakeBadge` — kept, annotated. The mini strip's 8 slots tile the 380 px plate with 4 px gaps (36/36/36/68/74/32/32/24 wide), every hit rect ≥ 24 px, and the strip is a real claimed surface (`BkMiniStripPointInside`). **measured, accepted for now:** the row leaves 8 px on the left and 6 px on the right — off the 4 px grid by 2, and fixing it means re-baking `bk_strip.bmp` at 382 px (P-DRAW-33: MT4 crops, never scales), so the 2 px waits for the next skin regeneration |
| 7 | palette popover + mixer, dropdowns, pager, badges | 2026-09-25 | **fixed:** the grid panel's plate was not claimed either — its header strip, padding and the pager arrows read as chart (`SubPanelRect` added to `CircPointOnMenu`, A-13); the pager's geometry comment promised a hit test, `SubPagerAt`, that no commit ever contained — corrected to name the two real readers (draw + translate) and the real click route (object name). **retired, recorded:** ring badges are globally off (NOBADGES, user decision 2026-09-04: `CircHasBadge()` returns false and gates every create/show/move path) — so the 16px plate is never drawn with text, and the 6-char values (`144.0x`, `2650.5`) cannot spill today. **Latent, one line away:** the day badges return, the value must go through `PnlFit` (the tip right beside it already does — P-UI-34) |
| 8 | the type scale itself (D-02/D-03, every DPI) | 2026-09-25 | **fixed:** the retired `round(n*96/dpi)` merged 20 adjacent pairs across seven scales (7 == 8 at 125%, four sizes alike at 200%, one size at 250%+). The ladder + row cap replaced it: identity at 96, distinct until the cap, never taller than the row. `tests/Biotak_TypeScale_Test.mq4` asserts all four properties and keeps the retired formula as a witness |
| 9 | the mini Base Box strip's own plate + its grip | 2026-09-25 | **found, NOT fixed here (CLOSED by row 12):** `DrawStripGripAt` is defined (`DrawStrip.mqh:4587`) and cited twice as the answer to "which of the two gestures is this press?" (lines 487, 2797) — and has **no caller**. Same shape as catalogue 23; it belongs to the strip's own walk |
| 10 | **every comment in the repo** (the C-rule sweep, pass 1) | 2026-09-25 | **rule + check born** (catalogue 25 / LEVEL 86): target 6 lines, hard ceiling **16**, file share ≤ 25 %. **fixed in pass 1 (22 blocks):** the two worst single blocks repo-wide are gone — `EventHandlers`' 95-line P-LEVEL-FOREIGN-01/02 essay and `DrawStrip`'s 59-line P-DRAW-08 banner — plus `EventHandlers` (P-UI-56, P-PERF-34/35, P-UI-61, P-UI-98), `BiotakPanels` (P-UI-74/75/81/83/92, PANELDRAG-OFF), `DrawToolbar` (P-DRAW-01), `FractalTimeframes` (P-TH-01), `UtilityFunctions` (P-UI-69e), `GlobalVariables` (P-UI-90), `BaseKnotTool` (P-BK-31/32/39). **measured (HEAD `435c91b` → worktree):** comment lines **24 503 → 23 868** (−635), total lines 75 357 → 74 754, runs over the 16-line ceiling **260 → 253**, share per file: `EventHandlers` 44 → 42 %, `BiotakPanels` 31 → 29 %, `DrawStrip` 20 → 19 %, `DrawToolbar` 28 → 26 %, `FractalTimeframes` 28 → 21 %. **still over the ceiling — pass 2, worst first:** `BaseKnotTool.mqh` alone owns 11 of them (its **220-line** ASCII file header at lines 1-220, then runs of 96/86/77→done/57/56/48/46/45/41/40 at lines 3248/5711/2931/1868/698/3075/4785/6317/1042), then `LevelPipeline:1528` (63), `TH3Pivots:1482` (50), `TH3Math:151` (48), `HTFCandles:434` (47) and `:308` (42), `TH3Tool:1657` (44), `TH3Pivots:1` (43), `TradePlanFormulas:1` (42), `TH3Renderer:81` (41), `ObjectCache:380` (40), `FrequencyOptimizer:659` (40), and ~230 more of 17-39 lines. **Why they are pass 2:** every one is an ASCII-bordered block whose `//|` padding was hand-broken (measured inside the 220-line header: line widths 70…121), so it cannot be `str_replace`d byte-exactly without guessing the padding — the plain-comment blocks were done first because they match exactly. The check above reports the rest in one command. |
| 11 | **performance** (LEVEL 75, G-01…G-12) | 2026-09-25 | **rule completed:** G-08…G-12 added — the WEAKEST supported machine is the target, the cheaper of two equal solutions ships and its cost is written as a number, every slice states a millisecond budget, a measured window beats a fixed rate, nothing uncapped enters the stream — plus gate item 10 and the budget rows in the appendix. **measured clean (the witnesses exist and are wired):** `CPU_WARNING_MS 50` / `CPU_CRITICAL_MS 200` fire on an `OnCalculate` overrun and print the phase ledger only then (`pfLedgerPrint`, `g_p3Ms*`); `COOP_WARN_MS 40` covers a scheduled frame or a coop job; P-PERF-01…50 are the change guards themselves (P-PERF-02 write guard, P-PERF-16 no terminal read inside a hit test, P-PERF-06 staged rebuild, P-PERF-42 one probe per gesture, P-PERF-43/45 self-measured drag with the `starved` counter). **measured open:** **80** fixed cadence constants against **1** measurement-driven window, and ONE gesture class rides **seven** repaint/follow cadences — `CIRC_DRAG_REDRAW_INTERVAL 30`, `BK_DRAG_CURSOR_MS 30`, `DSTRIP_GRIP_MS 30`, `DSTRIP_FOLLOW_MS 50`, `DRAG_REDRAW_THROTTLE_MS 50`, `UI_DRAG_HEAVY_MS 120`, `CHART_REDRAW_THROTTLE_MS 100`. Only `PNL_MOVE_FRAME_MIN/MAX/SLACK_MS` (P-UI-75b) adapts to the measured batch cost, so the drag is the one gesture that already answers "weak machine". **next (pass 2):** collapse the seven cadences onto one owner with a measured window, and give `REDRAW_THROTTLE_SECONDS 10`, `CLEANUP_INTERVAL_SECONDS 300` and `CIRC_TIP_DELAY_MS 1500` their weakest-machine numbers before G-11 is called met. |
| 12 | **the drawing strip + its settings panel — the whole press → hold → open → use → dismiss flow** | 2026-09-25 | **fixed (the reported close, thrice-reported):** «موقع که ابجکت سلکت هستش ... استریپ باز میشه ولی رها که میکنم بسته میشه ... اگر ابجکت سلکت نباشه درست کار میکنه». Two defects in the release witness. (1) ownership was re-derived from the terminal's LIVE selection: `DrawHitSelectedHandle` (P-UI-113h) is consulted only for objects `OBJPROP_SELECTED` at that instant, and MT4 commits its selection change around the click — so a release on the selected drawing's own control resolved to `""` = outside click, while an unselected drawing is only ever grabbed on its BODY (the one test a non-selected object passes) and therefore never took this path. (2) the opening window was disarmed by a LATE press edge — a selected drawing is dragged by MT4 under a resting hand, so the move stream reports edges inside one press — and the release then arrived unarmed. **Fix:** the hold latch NAMES the press's own drawing (`s_dsPressCycleObj` — the hit test the latch already paid for, P-DRAW-04, bounded by the press cap) and the release asks it before any pixel or selection state; a cycle already named is never re-declared, so a flapping edge keeps the owner, the press point, the travel (now measured from the true press point: a still press is a click, a drifting one a drag) and the opening window. Selection is not a branch in the flow any more. **fixed (P-DRAW-37, the same walk's architecture):** a re-open of the SAME object deleted and re-created the whole ~40-object family at the drawing's 50 ms drag cadence — a ride is now one anchor projection + layout/paint (`DrawStripRide`), the P-UI-113e/g snapshot-and-restore across `DrawStripClose` is deleted (nothing crosses a close any more), and an object that cannot project keeps the strip open (J-02). **fixed (P-DRAW-38, catalogue 23/24):** `DrawStripGripAt`, caller-less in every commit, deleted — both citations now name `DrawStripGripWhich()` (closes row 9). **read clean, unchanged:** `DrawStripPointInside` covers plate + panel (A-13/H-05), the panel's header carries the panel (P-DRAW-32), an unpinned strip still dismisses on a right-click or any outside click (E-09). **gate:** two entries + all seven harnesses `Result: 0 errors` (main 912 ms / Lite 293 ms), `node tools/submenu_geometry_check.js` green. **open:** DIAG-113's three log lines stay until the live chart confirms the fixed gesture. |

Seven rule families (B-11, A-13, catalogue 21–24, C-01…C-06 with catalogue 25, and
G-08…G-12 with gate item 10) were
**added by** these walks. Two of them exist because a rule was written in a comment and
never compiled — the ring's claim (23) and the pager's hit test (24) — which is this
repo's recurring shape: the sentence ages better than the code. Catalogue 25 is the same
shape one layer up: the sentence was never *edited*, and reading the code for facts
nobody needs costs every reader who comes after. An audit that finds nothing new is
usually an audit that did not read the code.
