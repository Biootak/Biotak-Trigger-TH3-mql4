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
| A-01 **The palette** | `BioPickColor(r,c)` / `BioPickAt(i)` + `BIOPICK_COLS/ROWS/N` (8 x 8 = 64) and `BioPickColor`'s own row 1 through `BioPal(i)` + `BIOPAL_N` (8), `ConstantsAndEnums.mqh` — the USER'S OWN palette chart (P-DRAW-46, 2026-09-26; the Material 19×10 matrix and its hue/shade mapping are deleted with it) | `QuickPalColor`, `BioPal` (the quick row IS the table's first row), `DrawStripPickPal`/`DrawStripPickPalN` (the strip's picker; `DrawStripPickSwatchAt`/`DrawStripRecentExtra`/`DrawStripPickPalIndex` were DELETED by P-DRAW-47, 2026-09-26, when the recents got their own band; the gear's at-hand 16 grid went with P-DRAW-44), `PalPickColor` (the cards' own face). The cells' four bakes — `ds_cell32`/`ds_ring32` (strip) and `pal_cell20`/`pal_ring20` (cards) — are the palette's own faces, one pair per plate tone (MT4 crops a bitmap label, never scales it) |
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
  control at +9, h **24**; a slider track at +**29**, h **7**; a checkbox at +11, 20×20.
  A row that needs more than 42 becomes two rows, not a taller one.
  **P-UI-131d — the MIDDLE of a two-part row (measured 2026-09-25).** This rule's
  own B-02 wants 10px between a caption and its control; the shipped gaps inside a
  row were **3** (card header: title→subtitle), **8** (slider: caption→track),
  **1** (text: caption→field) and **4** (colour: caption→strip), and every one of
  them read as "glued" in the user's crops («از وسط چسبیده»). They are 3→**11**,
  8→**11**, 1→**4** and 4→**5** now. The text and colour rows STILL miss B-02 and
  cannot reach it inside 42: caption 11 + gap 10 + control 22 = **43 > 42**. That is
  exactly this rule's "two rows" case, and it is owed — the fix is a split (a
  caption row + a control row) or a taller pitch, which amends this line first.
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
| 26 | An **embedded asset nothing draws** | a `#resource` whose filename is built at runtime, so a literal grep cannot see it, and whose producer's range no longer reaches it | expand the CONSTRUCTION before believing a zero (law **I1**): the stem table, the accent list, the index range, the suffix variants. Measured 2026-09-27 (`docs/history.md` P-ICONS-01): **42** of 325 files, **35.09 MB = 71.6 %** of the payload, with no runtime path — `pnl_cardW{1..12}[f]` 25.4 MB (superseded by the composed wide body), `pnl_card{11..16}[f]` 11.4 MB (the `!wide` lookup can only ever see ≤ 10), `pnl_glass{28,32}` (last caller deleted by catalogue 19), `orb_word`, `gl_magnet_*`, `gl_reset_gold`. **The trap is the clamp reading as headroom** (law **I2**): `PNL_CARD_ROWS_MAX 16` looked like margin while the branch that consumed it could never see more than 10. After the diet, and after the `.fade` overlay (row 10 below), the payload is **9.24 MB / 275 files**, every survivor **byte-identical** |
| 27 | A **restore hint that keeps its payload alive** | a call site commented out "for a one-line restore" while its `#resource`, its manifest entry and its baked file all stay — the artifact ships in every `.ex4` for a line nobody runs | the hint names the BUILDER, not the asset. Measured 2026-09-27: `orb_word.bmp` had been commented out for two weeks (ORBWORD-OFF, 2026-09-12) and still cost **20 KB** in every build; `make-orb-word.ps1` and the generator's builder stay, the declaration and the file went. Law **I4**. The same shape in miniature: `gl_reset_gold.bmp` (954 B) existed only because the glyph table emits an accent face for every name, and the Reset button is created with `primary=false` — one muted-only entry (`NO_ACCENT_GLYPHS`) closed it |

---

## LEVEL 95 — LIFECYCLE AND PERSISTENCE

- **J-01** Four events must be survivable by every surface: **reattach**, **TF switch**,
  **terminal restart**, **template re-apply**. Nothing may depend on live memory alone.
  **P-UI-131e — three of the four were broken (measured 2026-09-25).** `BiotakMenu` keyed
  its whole saved block by `_Symbol` **and** `ChartID()` (a restart, a re-opened chart or a
  new window found nothing → the version check failed → wipe → re-seed), and
  `CleanupUIStates(REASON_REMOVE)` called `ClearAllGVs()`, so **removing the indicator
  deleted every key** — the orb's place, the strip's and the chip's homes, the panel
  positions, the card overrides. Third: a CLAMP was written back into the live orb pair and
  then saved, so one narrow chart ratcheted the place inward for good. **The rule now:** a
  placed surface's home lives under a key with **no chart and no symbol** in it
  (`GVHomeName`), the value that paints (clamped) is never the value stored, and a remove
  SAVES like any other teardown. The HTF block keeps its own prefix and writer.
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
   **Bidirectionally** (law **I5**): every manifest entry has a file on disk AND every
   file on disk has a manifest entry. The generator writes the manifest but never prunes
   stale files, so one direction is not a check — measured 2026-09-27, disk held **326**
   against a 284-line manifest. A file outside the manifest is dead weight; a manifest
   entry with no file is a compile error at the next full build.
8. **Lean:** `AGENTS.md` is not the place for the detail; it points here.
9. **The report** names the file, the number and the measurement (Part L).
10. **Performance has a number (G-08…G-12).** Every new path states what it walks (the
    bound, in objects/cells/bars) and its millisecond budget; the target is the weakest
    supported machine, not the dev box. Nothing whose cost scales with the chart enters
    the mouse stream or the tick path, and a fixed cadence has to justify itself
    against a measured window.
11. **"No quality loss" is a HASH, not a compile** (law **J1**). Any change to a
    generated asset set hashes the whole set first and diffs it after: every untouched
    file must be **byte-identical**. A green build says nothing about pixels — measured
    2026-09-27, 273/273 identical across the ICON-DIET and the `.fade` overlay, with the
    2 added files named individually.
12. **A byte claim names BOTH numbers** (law **J2**). When assets are deleted, report
    the on-disk payload AND the shipped `.ex4`, and explain the gap if they disagree:
    measured 2026-09-27, **35.09 MB** off disk moved the `.ex4` only **398 KB**, because
    the packer compresses these gradients ≈ 88:1. Reporting the flattering one alone is
    a lie of omission. A destructive list asserts its own **count** and a known-live
    sentinel before it runs (law **I7**) — a range written `1..16` where `11..16` was
    meant built a 62-item delete list and would have taken 20 live files with it.

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
| palette | the user's own 64, 8 x 8, row-major (P-DRAW-46). The quick row IS its first row (8) | `BioPickColor`/`BioPickAt`, `BIOPICK_COLS/ROWS/N`, `BIOPAL_N`, `BioPal` |
| hover chip | ONE line, Tahoma 11pt, pad 14/6, 15 % tone-blend; box measured, not fixed (27px at 96 dpi); a caption rides the four sides of its own item (above → below → right → left) and never sits on it | `CIRC_TIP_PT/FONT/PAD_X/PAD_Y/TINT`, `CircTipLine`, `CircTipPlace` |
| chip placement (the face) | TWO answers, never a rotated one: ABOVE the orb while the whole box fits in the window, otherwise the chip's OWN PLACE — the hand's (a drag) or the chart's middle. A side is not a place a bitmap can wear: MT4 crops a bitmap label and turns none (a label takes no angle — error 230), so a rotated face is SIDEWAYS calligraphy, not a second orientation | `CircTipFaceAbove`, `CircTipHomeBox`, `CircTipPlace` |
| chip home | `-1` = the hand has never placed it (a state, not a reset): the chart's middle answers, measured live; stored as the box's CENTRE, clamped by its own owner, persisted as `TIPX`/`TIPY` on the menu's UI-state block (no version bump) | `CircTipHomeGet/Set`, `s_TipHomeX/Y`, `LoadUIState`/`SaveUIStates` |
| chip mode | `g_UI.tipPin`: OFF = hover only (the default, «با موس»), ON = «همیشه فعال» — the banner kept up at its place, one compare per tick and a write only when the box really moved | the Hover Chip card's ALWAYS SHOWN row (card 4), `CircTipTick`, `CircTipModeChanged` |
| chip drag | pinned is the one state where the banner stands still, so the grab lives there: the box it is WEARING is the hit test, 2 object writes per real move, one save on release, ended by the button-up net too, and named in `ChartLockIntended()` (P-DRAW-19/A-09) | `s_TipBoxX/Y/W/H`, `CircTipGrabStart/DragTo/DragFinalize`, `CircTipDragLive` |
| chip face hug line | row 57 of the 76 px face = the calligraphy band's OWN lowest line (measured on `tip-face-master.bgra`: the side ornaments hang on to row 75, so placing the BOX off the orb left a 31 px gap while the code said 12); the box therefore rides `INSET` (18) px past the gap | `CIRC_TIP_FACE_HUG`, `CIRC_TIP_FACE_INSET`, `CircTipFaceAbove` |
| chip face art | ONE face, ONE orientation, 200x76: `tip_face.bmp` from `tip-face-master.bgra` (`tipFaceArt()`) — derived sides, mirrors and the crown-down bowl are deleted with the shapes that needed them (P-UI-126) | `CIRC_TIP_FACE`, `tipFaceArt()` in `tools/gen-th3-icons.js` |
| chip face art (orb only) | 200x76 px baked from the user's 1343x510 banner (real alpha: its painted checkerboard keyed out, 1 132 534 px); source art 1694x928 | `tools/orb/tip-face-src.png` → `tools/orb/make-tip-face.ps1` → `tip-face-master.bgra` → `Files/Icons/tip_face.bmp`; `CIRC_TIP_FACE_W/H` |
| picker palette | 64 = the user's own 8 x 8 chart, read left to right then top to bottom; both pickers (the strip's popover and the cards' popup) iterate it | `BIOPICK_N`, `BioPickAt` |
| swatch contrast floor | 1.7 (11 of 198 indistinguishable; first visible 1.72 — re-measured on the user's 64, P-DRAW-46: 10 under the floor, worst 1.61 on the card face #1A2029 and the first visible 1.75, so the boundary still sits in the gap) | `BIO_SWATCH_MIN_CONTRAST` |
| card column / wide | 312 / 624 | `PNL_WEL`, `PNL_WIDE_WEL` |
| card head / row / foot | 56 / 42 / 48 | `PNL_HEAD_*`, `PNL_ROW_H`, `PNL_FOOT_H` |
| card side padding / shadow margin | 16 / 14 | `PNL_PAD_X`, `PNL_MARGIN` |
| control height / top in row | 24 / 9 | `PNL_CTL_H`, `PNL_CTL_Y` |
| slider track / ticks in row | +29 / +37 | `PNL_TRK_Y`, `PNL_TICK_Y` |
| palette cell hover | geometry RECORDED BY THE PAINT (`PalHoverRegionAdd`, tab-tagged) → 0 chart reads per move; a crossing REACHES THE OBJECT (the sweep is a gesture on the shared heavy-pass budget, so ≤1 pass per `UI_DRAG_HEAVY_MS` 120 ms and the tail flushes on leave), none on a still pointer; leave = restore, click = commit; previews never enter RECENTS | `PalHoverCellAt/ColorAt/Preview/Restore/Commit`, `PAL_HOVER_REGIONS 2`, `UIDragBudgetBegin/End` |
| palette TR track | ONE channel, TWO faces: the mixer's fourth slider and the footer mini track (`PaletteMixHit` code 4/5) — both drag through `PaletteMixFromX`, both write `PaletteApplyTransparency`, the footer measured on its own `PAL_FOP_DX/LW/TW` | `PaletteMixHit/MixFromX`, `PAL_FOP_*`, `opg`/`opf`/`opv` |
| AUTO opacity text | any slider whose own range starts below 0 prints its negative end as INFERRED state, not a number (`v < 0 && minV < 0` → `AUTO`); never an item/row list — those rows speak DISPLAY rows while the addresses are 4/16/17 | `PnlFormat` |
| zone edge half (a surface) | colour + opacity each, one row pair per half: `clrNONE` = AUTO (derived tone), `-1` opacity = AUTO (follow the shared edge opacity `ZBT`, whose own row P-UI-131k retired); LEFT follows TOP | `PAL_ZONE_EDGE_TOP/BOTTOM` (26/27), card 1 rows 14..17, `ZCT/ZCB/ZPT/ZPB` |
| a setting that loses its row | the ADDRESS stays, the DISPLAY row goes — `PnlSetDef`/`PnlCurrentSet`/`PnlApplySet` keep their branch, the input and the `OV_` key keep their meaning, and Reset no longer walks it (it walks display rows) | card 1 address 7 (`ZBT`), card 1 address 9 (MIDPOINT), `PnlResetItem` |
| trigger label (a surface) | the pip label on a TRIGGER level: `clrNONE` = AUTO (the unified Lines look, P-UI-66), `-1` opacity = AUTO (the Lines TR) — structure levels' labels keep the Lines colour whatever this says | `PAL_TRIGGER_LABEL` + its TR channel, card 0 setting row 4, `GetTriggerLabelRenderColor`, `TLT` |
| zone edge bevel | each tone = the WEAKEST that READS against the surface it lies on (chroma first, then white/black; floors 1.40 lit / 2.00 shade), then the halves are pulled apart on the free side — three existing objects, memoised per colour pair | `BIO_EDGE_CONTRAST/LIT_MIN/CHROMA`, `BioZoneEdgeTones`, `ZoneEdgeColorChanged` |
| card header title / subtitle | +12 / +35 (11px of air between) | `PnlHead` |
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
| 23 | **the whole embedded-asset set** (every `#resource`, every manifest entry, every file in `Files/Icons`) | 2026-09-27 | **found and fixed (P-ICONS-01, catalogue 26/27):** a four-way reachability ledger over 325 files (disk / manifest / `#resource` / runtime) put **42** at 35.09 MB — **71.6 %** of the payload — with no runtime path, and a 5th state found the inverse defect: `gl_template_i_gold.bmp` was **constructed** at runtime (`PnlMarkIcon(14)` → `template`) and emitted and declared **nowhere**, so the GENERAL card had been drawing no `.mark` at all (law **J6** — a byte pass misses the bugs in the same table). **Fixed:** the 42 deleted (2 of 3 groups family-bound and taken whole or as a range, law **I3**); `bolt` out of `INK_GLYPHS` / `template` in, a swap at 13-for-13 (law **I6**) — and `orb_word`'s commented-out branch deleted rather than parked (law **I4**). **Then the `.fade` overlay:** the 10 `pnl_card<n>f` skins were 4.71 MB — a further 34 % of what was left — differing from their plain twins in exactly 26 rows; they now overlay one `pnl_cardfade.bmp` (340×26), the same move the wide body already makes with `pnl_cardWfade`. **measured:** payload **49.00 → 9.24 MB**, files **325 → 275**, `.ex4` **3,826,082 → 3,344,450 B (−12.6 %**) — the gap is the packer (law **J2**); **273/273** untouched files byte-identical, 2 added files named. **cost:** +1 object, on the 5 `PnlCardFade` cards only, one card open at a time; `PnlSkinHit` and the destroy prefix are unchanged. **rejected, with the measurement:** composing the NARROW body the way wide does (`pnl_cardWtop/mid/bot`) would have saved ~9 MB more, but `cardGrad(cy/H)` is height-dependent — sampled from the real rasters, the same card-local `y` reads `23,28,38` on a 3-row card and `27,33,43` on a 10-row one, so one fixed `mid` band lands 2–5 units dark and the 1–2 row cards (Hover Chip, Step in TH mode) are hit worst. That is a quality loss, not a trade. **open:** the WIDE body still carries that ~2-unit error; fixing it costs zero bytes and is a gradient reconstruction, not a deletion |
| 2 | ring menu + hover tip + every tooltip | 2026-09-25 | **fixed:** `SUB_CLR_HDR`, `SUB_CLR_ACCENT` and `CLR_CIRC_BADGE_BG` were pasted literals (`#8C96A6`, `#FFC247`, and the palette's own cell 0) — aliased to the owner; the orb skin's `C'30,22,10'` call-site literal named (`CLR_CIRC_ORB_SKIN`); user-visible `colour` → `color`; `tap` → `click` (measured after: **1** `tap` string left, inside a quoted historical note, 0 `"Colour"`). **fixed (2nd pass):** the ring's own pixels were absent from the UI claim — `CircPointOnMenu` had **no caller in any commit** while `UIPointerOverSurface`'s header promised them; composed now (P-UI-116) and the claim's scope written down (A-13). **accepted, with the measurement:** the hover tip may cover a neighbouring ring item (it is a rectangle one `CIRC_TIP_GAP` off its own surface with a 1500ms dwell) — it can never sit under a live cursor (it parks the moment the hovered feature changes, and on the press edge), so no click is eaten. It can no longer cover its OWN surface (P-UI-121: the four sides of that surface are measured, above first, and only a window with no side that holds the chip whole falls back to a clamped side — **130 px** tall for a live 27 px caption around an item, **105 px** of window above the orb for its 76 px face — which is now placed by its own ink line, with no orb-reserved crown band at all (P-UI-122)) |
| 3 | handset markers (custom price + step-1 handles) | 2026-09-25 | **measured:** art is 15 px / 19 px (B-11); hide is a park, not a TF mask (correct — F-01/F-02, rects and bitmaps ignore `OBJPROP_TIMEFRAMES`). **open:** the hit-size decision |
| 4 | settings cards, row by row (14 items) | 2026-09-25 (the press→drag half only) | **changed (P-UI-127):** the card is a handle from every pixel again (user order «پنل رو هم بشه درگ کرد»), at a price it can afford: the 12-family claim sweep became two compares (X/Done, an open dropdown), the longer control proof is raised by `UIPressAct` instead of a second hit test, and `PnlDragPoll` stays uncalled on its own measurement (197 event-armed drags vs 0). Deleted as caller-less: `PnlNameControlAt`, `PnlPressClaimCode`, `PnlPointOnControl`. The arm still pays ONE forced `PnlMoveListBuild` per press (bound: the card's own object count) — G-11 wants that number from the next live ledger before the deferred-build variant (L-01) is shipped. **Still not walked:** the 14 cards' rows one by one |
| 5 | TH3 readout (caption family + leg box + its plate) | 2026-09-25 | **fixed:** the caption's per-pattern SLOT PITCH was the one real dirt here (P-TH3-INFO-14). Since INFO-10 only the ACTIVE family carries a plate, so a second slot can never be occupied: the pitch could only push the one visible caption down by `patIdx × (TH3ROPlateH(3) + 8) = 64 px` (pt 9 @ 96 dpi) over an empty slot and jump it when the active pattern changed. It was also sized on 3 rows while the wrap budget is 6 — `TH3ROPlateH(4) = 73` and `(6) = 107` against a 64 px pitch, i.e. the "two plates never overlap" note was 9–43 px false. Its helpers (`TH3InfoCaptionBlockH`, `TH3InfoCaptionTopY`) had no other reader; retired, number kept. **fixed (leg box):** both window fits could undo P-LM-19/23 and land the plate ON the tip it labels — the X clamp (`bx = right - bw`) reaches the tip whenever the head sits in the last `bw` px, which is exactly where the newest bars are — so placement is now CHOSEN (preferred side → its mirror across the tip → above/below the tip's row) around a `LEG_INFO_CLEAR 8` box, still a pure function of the anchors (P-LM-24). **measured clean:** plate measured from the final wrapped lines, not guessed; rows rebuilt after their plate (INFO-12); the 63-char cliff handled by the wrap; safe-Y mirrors the mode rows' `+45` (INFO-02) |
| 6 | BaseKnot pills (hint + badge) + the mini Base Box strip | 2026-09-25 | **fixed (one rule, two copies):** the readable-foreground gate for chart-anchored text existed TWICE — `BaseKnotFgForBg()` and `RuntimeSettings.GetBKTextRenderColor()` each carried the 299/587/114 luminance arithmetic and the literal `C'150,70,0'`, the second annotated "same luminance gate as the INFO label". One owner now: `BioChartBgIsLight()` + `BIO_BG_LUM_THRESHOLD 128` + `BIO_CLR_ON_LIGHT`, in `ConstantsAndEnums` (included before `RuntimeSettings` (43) and before every UI file, so A-12 holds). **fixed (the palette's own cell 0, pasted):** `C'255,171,0'` stood at five live UI sites (`BaseKnotFgForBg`, `DefBoxFillColor`, `CIRC_TIP_BD`, the Base Box style default `p.fill`, the view-anchor line) → all `BIO_CLR_BRAND`; the two that stay literals are documented (`PropertiesAndInputs`' input default — that file is included at 25, BEFORE its owner, A-12; and the mirror's seed). **fixed (one value, three names):** `C'18,22,33'` → `BIO_CLR_DEEP`, aliased from `CLR_CIRC_BADGE_TXT` and `TH3RO_FILL`, and used in the retired box badge so a one-line restore cannot reintroduce the literal. **measured:** `Z_BOX_HINT 1400` has a live writer (the corner hint label); `Z_BOX_BADGE 1410`'s only writer is the NOBKDEL-retired `BaseKnotMakeBadge` — kept, annotated. The mini strip's 8 slots tile the 380 px plate with 4 px gaps (36/36/36/68/74/32/32/24 wide), every hit rect ≥ 24 px, and the strip is a real claimed surface (`BkMiniStripPointInside`). **measured, accepted for now:** the row leaves 8 px on the left and 6 px on the right — off the 4 px grid by 2, and fixing it means re-baking `bk_strip.bmp` at 382 px (P-DRAW-33: MT4 crops, never scales), so the 2 px waits for the next skin regeneration |
| 7 | palette popover + mixer, dropdowns, pager, badges | 2026-09-25 | **fixed:** the grid panel's plate was not claimed either — its header strip, padding and the pager arrows read as chart (`SubPanelRect` added to `CircPointOnMenu`, A-13); the pager's geometry comment promised a hit test, `SubPagerAt`, that no commit ever contained — corrected to name the two real readers (draw + translate) and the real click route (object name). **retired, recorded:** ring badges are globally off (NOBADGES, user decision 2026-09-04: `CircHasBadge()` returns false and gates every create/show/move path) — so the 16px plate is never drawn with text, and the 6-char values (`144.0x`, `2650.5`) cannot spill today. **Latent, one line away:** the day badges return, the value must go through `PnlFit` (the tip right beside it already does — P-UI-34) |
| 8 | the type scale itself (D-02/D-03, every DPI) | 2026-09-25 | **fixed:** the retired `round(n*96/dpi)` merged 20 adjacent pairs across seven scales (7 == 8 at 125%, four sizes alike at 200%, one size at 250%+). The ladder + row cap replaced it: identity at 96, distinct until the cap, never taller than the row. `tests/Biotak_TypeScale_Test.mq4` asserts all four properties and keeps the retired formula as a witness |
| 9 | the mini Base Box strip's own plate + its grip | 2026-09-25 | **found, NOT fixed here (CLOSED by row 12):** `DrawStripGripAt` is defined (`DrawStrip.mqh:4587`) and cited twice as the answer to "which of the two gestures is this press?" (lines 487, 2797) — and has **no caller**. Same shape as catalogue 23; it belongs to the strip's own walk |
| 10 | **every comment in the repo** (the C-rule sweep, pass 1) | 2026-09-25 | **rule + check born** (catalogue 25 / LEVEL 86): target 6 lines, hard ceiling **16**, file share ≤ 25 %. **fixed in pass 1 (22 blocks):** the two worst single blocks repo-wide are gone — `EventHandlers`' 95-line P-LEVEL-FOREIGN-01/02 essay and `DrawStrip`'s 59-line P-DRAW-08 banner — plus `EventHandlers` (P-UI-56, P-PERF-34/35, P-UI-61, P-UI-98), `BiotakPanels` (P-UI-74/75/81/83/92, PANELDRAG-OFF), `DrawToolbar` (P-DRAW-01), `FractalTimeframes` (P-TH-01), `UtilityFunctions` (P-UI-69e), `GlobalVariables` (P-UI-90), `BaseKnotTool` (P-BK-31/32/39). **measured (HEAD `435c91b` → worktree):** comment lines **24 503 → 23 868** (−635), total lines 75 357 → 74 754, runs over the 16-line ceiling **260 → 253**, share per file: `EventHandlers` 44 → 42 %, `BiotakPanels` 31 → 29 %, `DrawStrip` 20 → 19 %, `DrawToolbar` 28 → 26 %, `FractalTimeframes` 28 → 21 %. **still over the ceiling — pass 2, worst first:** `BaseKnotTool.mqh` alone owns 11 of them (its **220-line** ASCII file header at lines 1-220, then runs of 96/86/77→done/57/56/48/46/45/41/40 at lines 3248/5711/2931/1868/698/3075/4785/6317/1042), then `LevelPipeline:1528` (63), `TH3Pivots:1482` (50), `TH3Math:151` (48), `HTFCandles:434` (47) and `:308` (42), `TH3Tool:1657` (44), `TH3Pivots:1` (43), `TradePlanFormulas:1` (42), `TH3Renderer:81` (41), `ObjectCache:380` (40), `FrequencyOptimizer:659` (40), and ~230 more of 17-39 lines. **Why they are pass 2:** every one is an ASCII-bordered block whose `//|` padding was hand-broken (measured inside the 220-line header: line widths 70…121), so it cannot be `str_replace`d byte-exactly without guessing the padding — the plain-comment blocks were done first because they match exactly. The check above reports the rest in one command. |
| 11 | **performance** (LEVEL 75, G-01…G-12) | 2026-09-25 | **rule completed:** G-08…G-12 added — the WEAKEST supported machine is the target, the cheaper of two equal solutions ships and its cost is written as a number, every slice states a millisecond budget, a measured window beats a fixed rate, nothing uncapped enters the stream — plus gate item 10 and the budget rows in the appendix. **measured clean (the witnesses exist and are wired):** `CPU_WARNING_MS 50` / `CPU_CRITICAL_MS 200` fire on an `OnCalculate` overrun and print the phase ledger only then (`pfLedgerPrint`, `g_p3Ms*`); `COOP_WARN_MS 40` covers a scheduled frame or a coop job; P-PERF-01…50 are the change guards themselves (P-PERF-02 write guard, P-PERF-16 no terminal read inside a hit test, P-PERF-06 staged rebuild, P-PERF-42 one probe per gesture, P-PERF-43/45 self-measured drag with the `starved` counter). **measured open:** **80** fixed cadence constants against **1** measurement-driven window, and ONE gesture class rides **seven** repaint/follow cadences — `CIRC_DRAG_REDRAW_INTERVAL 30`, `BK_DRAG_CURSOR_MS 30`, `DSTRIP_GRIP_MS 30`, `DRAG_REDRAW_THROTTLE_MS 50`, `UI_DRAG_HEAVY_MS 120`, `CHART_REDRAW_THROTTLE_MS 100`. (`DSTRIP_MID_MS 50` — was `DSTRIP_FOLLOW_MS` until P-DRAW-41 — is retired by P-DRAW-64d: the mid rides the hand's own cadence now, so the drag answers "weak machine" with one cadence fewer.) Only `PNL_MOVE_FRAME_MIN/MAX/SLACK_MS` (P-UI-75b) adapts to the measured batch cost, so the drag is the one gesture that already answers "weak machine". **next (pass 2):** collapse the seven cadences onto one owner with a measured window, and give `REDRAW_THROTTLE_SECONDS 10`, `CLEANUP_INTERVAL_SECONDS 300` and `CIRC_TIP_DELAY_MS 1500` their weakest-machine numbers before G-11 is called met. |
| 12 | **the drawing strip + its settings panel — the whole press → hold → open → use → dismiss flow** | 2026-09-25 | **fixed (the reported close, thrice-reported):** «موقع که ابجکت سلکت هستش ... استریپ باز میشه ولی رها که میکنم بسته میشه ... اگر ابجکت سلکت نباشه درست کار میکنه». Two defects in the release witness. (1) ownership was re-derived from the terminal's LIVE selection: `DrawHitSelectedHandle` (P-UI-113h) is consulted only for objects `OBJPROP_SELECTED` at that instant, and MT4 commits its selection change around the click — so a release on the selected drawing's own control resolved to `""` = outside click, while an unselected drawing is only ever grabbed on its BODY (the one test a non-selected object passes) and therefore never took this path. (2) the opening window was disarmed by a LATE press edge — a selected drawing is dragged by MT4 under a resting hand, so the move stream reports edges inside one press — and the release then arrived unarmed. **Fix:** the hold latch NAMES the press's own drawing (`s_dsPressCycleObj` — the hit test the latch already paid for, P-DRAW-04, bounded by the press cap) and the release asks it before any pixel or selection state; a cycle already named is never re-declared, so a flapping edge keeps the owner, the press point, the travel (now measured from the true press point: a still press is a click, a drifting one a drag) and the opening window. Selection is not a branch in the flow any more. **fixed (P-DRAW-37, the same walk's architecture):** a re-open of the SAME object deleted and re-created the whole ~40-object family at the drawing's 50 ms drag cadence — a ride is now one anchor projection + layout/paint (`DrawStripRide`), the P-UI-113e/g snapshot-and-restore across `DrawStripClose` is deleted (nothing crosses a close any more), and an object that cannot project keeps the strip open (J-02). **fixed (P-DRAW-38, catalogue 23/24):** `DrawStripGripAt`, caller-less in every commit, deleted — both citations now name `DrawStripGripWhich()` (closes row 9). **read clean, unchanged:** `DrawStripPointInside` covers plate + panel (A-13/H-05), the panel's header carries the panel (P-DRAW-32), an unpinned strip still dismisses on a right-click or any outside click (E-09). **gate:** two entries + all seven harnesses `Result: 0 errors` (main 912 ms / Lite 293 ms), `node tools/submenu_geometry_check.js` green. **open:** DIAG-113's three log lines stay until the live chart confirms the fixed gesture. |
| 13 | the strip's colour popover + the cards' colour popup (one picker palette) | 2026-09-25 | **fixed:** «چرا پالت از همون های قبلی نیستش ... همون که قبلا در جاهای دیگه هستش باشه» — the popover read `BioPal`'s 16 (quick row + retired strip hues) while the cards' popup read `PalMatColor` (19×10) through `PalQHue`/`PalQShade` (12×5): TWO colour owners, which A-01 forbids. The owner moved DOWN to `ConstantsAndEnums.mqh` (include #1): `BioMatColor` (the 190 literals, verbatim), `BioPickHue`/`BioPickShade`, `BioPickColor(row,col)`, `BioPickAt(i)`/`BIOPICK_N 60`; the panels' names are faces and `PAL_ROWS`/`PAL_COLS` are aliases, so not one of their call sites moved (A-12, the same move as P-UI-34 and P-UI-69b). The strip's popover is `BIOPICK_COLS` wide over the SAME `DSTRIP_PICK_ROW 42` — one mid band per swatch row, so the plate stays on `48 + 42k` (6 rows of 60 + recents = 300 px, `DrawStripSkinKFor` = 6) — and its caps grew 24/48 → 72 (60 swatches + 5 recents; both were buffers the old 16 could never fill). **measured:** one table, two grids, 60 cells; hit target `DSTRIP_PICK_CELL 32` ≥ 24 (B-05) unchanged; width 12×32 + 11×8 = 472 + 2×8 = 488 ≤ `DSTRIP_SKIN_MAXW 660` and inside the skin's own 668 limit. **left open, with the reason:** the gear's Style grid still shows `BioPal`'s 16 — 60 swatches at `DSTRIP_GEAR_SWATCH 28` in the 312 px panel is 8 columns × 9 rows ≈ 378 px of swatches, i.e. the B-08 two-column (or a smaller gear swatch) decision plus its own height check, not a one-line repoint. **Updated by P-DRAW-46 (2026-09-26):** the two grids are ONE table again and it is the user's own 8 x 8 chart — the popover shows 8 columns x 9 bands (64 + 5 recents, plate `48 + 42*9`), the cards' popup is the same 8 x 8 through `PAL_QCOLS/PAL_QROWS` aliases, and the family/shade captions are gone with the Material matrix (a cell's caption is its hex). **Updated by P-DRAW-47 (2026-09-26):** both boards now read like the reference board — header (grip + name + close), the 8 x 8 grid, a labelled RECENT band, then the HEX field; the selected cell wears the ring bake (`ds_ring32` / `pal_ring20`) instead of the glass one, and the cards' board grew `PAL_HX 30` for the shared hex row, so `pal_card.bmp` was re-baked at the live `PalW() x PalH()` = 201 x 408. **And the strip's own cells follow the preview** (same day, second report): the colour cell is a `DSTRIP_SWATCH 24` rounded swatch with its hairline (`ds_swatch24`, the preview's `.swcell`) inside its 32px cell, and an ON toggle wears the accent ink + accent hairline on the accent wash — the toggles' dark-ink twins (`BK_DARKINK`) read as NO glyph on a translucent wash (`.scell.on` says accent ink). **Updated by P-DRAW-48 (2026-09-26):** the colour board is its OWN card (its own 9-slice family + rect + header), and the drawn board is the strip's plate's **single** owner — `DrawStripBoardSkinName` for family 2, the mid band on the PLATE's z (see row 16), and the hover reading the board's bands from the board's own origin. **Updated 2026-09-27 (the OPACITY bar's own day):** the band under the HEX field is a CONTROL now, not a readout — `DrawStripOpTrackX()/W()` is its one geometry owner (`328 - 2*8 - 52 - 38 = 222` px on the live board), `DrawStripOpBarAt` takes the whole 42 px row as its target with the readout seat excluded, `DrawStripOpValueAt` is the exact inverse of the knob's own span, and the drag takes the view lock and names itself in `DrawStripViewOwned()` (A-09/G-07) so the chart behind the board cannot pan under the hand. A colour pick is **multi-stay** (P-DRAW-11 amended for the colour board alone: the bar lives on that board, so a pick that shut it took the bar away — «روی رنگ کلیک میکنم بسته میشه نمیزاره شفافیت تنظیم بکنم»), and the board's own plate is DEAD SPACE (`DrawStripIsBoardPlate`) so a near miss in the 8 px gap between two cells no longer reads as a plate tap and shuts the board. **Updated by P-DRAW-64 (2026-09-27) — the SECOND COLOUR:** the strip carries TWO colour cells now, the border's (`DRAW_SLOT_COLOR`) and the interior's (`DRAW_SLOT_FILLCLR`), and `DrawStripIsColorSlot`/`DrawStripColorRead`/`DrawStripColorFace` are the three questions every surface asks, so no site names one of them alone. The colour board is ONE board with two roles — `s_dsPicker` names the role for its header (`BORDER`/`FILL`), its grid, its recents, its HEX field and its opacity bar (which is role-aware in the owner: `[OPnn]` vs `[FTnn]`). **The chart PREVIEW on hover is RETIRED (same day, second report: «شفافیت تنظیم میکنم موس میره روی بقیه رنگه ناخواسته شفافیت [از دست میره]»):** the cell under the pointer used to be written onto the drawing (`DrawSlotPreviewColor`, P-DRAW-27) and that write went straight to `OBJPROP_COLOR` — the PURE colour, outside the render owner — so the tone the user had just tuned under the bar fell back to full strength the moment the hand crossed a cell on its way to the ✕. A hover now lights the CELL's own rim and writes nothing on the chart (also the cheaper path, G-09) — the chart preview exists again only as the **press-drag SCRUB** (hold the button on a cell, drag across the palette, RELEASE applies; a release off the grid cancels), and its writes go through the render owner (`DrawSlotPreviewColor`/`DrawSlotPreviewFillColor` → `DrawSlotRenderColor`/`DrawSlotRenderFillColor`) so the tone the bar set survives the gesture. The scrub is the strip's fifth view-lock owner (`s_dsPalGrab`, named in `DrawStripViewOwned`), its re-ink is one write per member per CELL CROSSING (never per frame), and either release channel applies while the other only clears the highlight (`DSTRIP_PAL_TAIL_MS` — one release, one undo step). The bar's row label is the short one (`Opacity` / `Fill`) because `DSTRIP_PREC_LW 52` is the seat the track starts after, and the board's ✕ and pin seats are 26 px, not 22, so B-05's 24 px floor holds on the two ends of a transparency edit. The interior's own cell shows the colour AT its tone (the pixel the chart wears), the quick cap is 7 so the pair fits beside the fill toggle (`+38 px` of plate, worst case ≈ 590 px ≤ `DSTRIP_SKIN_MAXW 660`), the settings panel's Style tab carries two hex fields (`COLOR` = border, `FILL` = interior), and the more-popover carries "Fill 50%" for the five filler kinds. MT4 gives a drawing one colour, so the interior is a `<drawing>_FL` CHILD (`_BX50`'s pattern) or, for the six level kinds, the real `OBJPROP_LEVELCOLOR`. **Updated by P-DRAW-64 addendum 3 (2026-09-27) — the interior's SCOPE, and its cost order:** the split belongs to the objects the STRIP serves, so the product's own drawings (they carry `inpObjectPrefix`) are refused at every entry point — `DrawIsIndicatorObject` is asked FIRST in `FillChildEnsure` and `FillChildSync` (one string-prefix compare, no terminal call) and `FillIsChild` refuses a child just as cheaply, because the hook rides `CHARTEVENT_OBJECT_DRAG`, which MT4 fires for EVERY dragged object: the report «من اینو که جابجا میکنم اون یکی جا میمونه» was one of the indicator's own boxes growing a `_FL` child. Order: an indicator object = 1 compare per dragged frame, a user line ≈ 3 calls, a user FILLER kind ≈ 12 guarded reads (writes only when something really moved). A stray an earlier build of this split left behind heals itself — the pump's `_FL` sweep deletes a child whose parent is an indicator object and restores that parent's own `OBJPROP_FILL`, within one 2 s pass or on the next new bar. **Updated by P-DRAW-64 addendum 4 (2026-09-27) — the interior's own ride:** the interior's sync rode the drag event BEHIND the 50 ms throttle it shares with the box mid (`DSTRIP_MID_MS`) — 15 px of a normal hand and ~100 px of a flick behind the master's frame, which is the extra edge the user saw beside a frame while moving («این لبها و دور کادرها ... گاه ظاهر میشن»). It is exempt from that throttle now (every drag frame re-stamps it; a drag frame's own cadence IS the cadence, and a deferred drag frame IS the lag), and the child's own frame is the thinnest legal one (`OBJPROP_WIDTH 1`, no longer the master's width) so a sub-frame lag can show a 1 px sliver, never a lip. The cost stays bounded and stated: ~12 guarded reads per dragged frame for a user FILLER kind, 1-2 compares for a line or any other kind, 1 for the product's own drawings. **Updated by P-DRAW-64d (2026-09-27) — the LEVEL rides the same event, unthrottled:** the mid's own sync sat below the shut-strip guard, so a box dragged with the strip shut kept its pre-drag level until the pump's 2 s pass («این خط 50 درصد چند فریم عقب زمانی که باکس و جابجا میکنم»). It stands at the head of the router now, beside the interior, with no throttle of its own — the moves are guarded, so a still frame is reads and never a repaint, and the hand's own cadence IS the cadence («ریل تایم بشه و هزینه نداشته باشه»). `DSTRIP_MID_MS` and its static are deleted, not parked; the release witness and the pump stay as the net. **Updated by P-DRAW-64 addendum 5 (2026-09-27) — the interior's step is the DRAWING's business, not the open strip's:** the witness stood inside the drag branch, i.e. BELOW `if(!s_dsOpen) return false` in `DrawStripOnEvent`, so a box dragged with the strip shut kept its pre-drag interior until the pump's 2 s pass («این باکس هنوز همین طوریه … اون fill ریل تایم همراه جابجا نمیشه»); a gesture's LAST drag frame can also be coalesced away, and a resize from the terminal's own properties dialog fires no drag event at all. The interior's sync therefore stands at the HEAD of the event router, above every guard, rides `CHARTEVENT_OBJECT_CHANGE` as well, and is re-stamped on the RELEASE (`relPressObj`, the press's own object, P-UI-113i). Cost unchanged and bounded: 1-2 compares per witness for a non-filler kind, ~12 guarded reads for a user FILLER kind, a write only on a real move, the release once per gesture. **Updated by P-DRAW-64 addendum 6 (2026-09-27) — the interior rides the HAND, not the drag event:** the report that outlived three builds («این باکس که جابجا میکنه این fill ازش جا میمکون بعد چند میلی ثانیه بعدش جفت میشه») is not a missing witness — the witness is at the head of the router and stamps the child in the very event that moved the master. It is that **MT4 coalesces a run of identical event ids**, so a dropped `OBJECT_DRAG` frame is a frame the interior did not move in, and a hand at 60 Hz sees the box leave its fill behind for the rest of the gesture. The stamp therefore also rides the MOVE STREAM, keyed on the press's own object (`s_dsPressObj`, P-UI-113i — so there is no hit test to pay) and gated by a four-value memo (`FillChildStampArm`/`FillChildStamp`/`FillChildStampRelease`, one slot, one hand at a time): a still frame costs four reads and one compare, a real move pays the guarded sync, and a hand that is not down costs one string compare. The release witness stays as the last word, and the arming also rides the drag event so a gesture MT4 reports only as `OBJECT_CHANGE` is covered too. **Updated by P-DRAW-64 addendum 7 (2026-09-27) — the interior is in its box's OWN LAYER:** the one frame the user named with his own diagnosis («فقط رنگ‌کشی یک فریم عقب‌تر است», the log refused) was not a missed frame at all — it was a line of code. The child was hard-wired `OBJPROP_BACK = true` (behind the bars) while the box is in front, and MT4 paints the layer the dragged object lives in as the drag moves it, so an interior parked in the other layer is painted by the NEXT pass; no stamp can close a gap that opens after the write. The child now mirrors the box's own `OBJPROP_BACK` (one guarded compare per sync, a write only on a real layer change), so box and interior share one paint pass, and the strip's BACK cell became one honest switch for the whole drawing instead of a hidden rule. The visible consequence is deliberate and stated in history.md: a filled box in front covers the candles inside it, exactly like every filled rectangle MT4 draws. **Updated by P-DRAW-64a (2026-09-27) — ONE COLOUR SEAT, THE RING, AND THE FILL FAMILY'S TWO EXTRAS:** the border's cell and the interior's are ONE seat (`DrawStripMergedColor`: the order skips `DRAW_SLOT_COLOR`, the seat IS `DRAW_SLOT_FILLCLR`, its visibility is the OR of the two roles so a hide of one never drops a control), and the ROLE a tap means is decided by where the hand landed — the centred swatch (`ic+S`) and its skin (`ic+C2`) are the INTERIOR's, the cell's own button and its 32 px skin the BORDER's; a tap on the wrong half costs one more tap because the board's own name (`PnlDrawS_PHeadT`) is its role switch. The border's colour is the SEAT'S FRAME now, not a square in the middle («نباید وسط رنگی باشه باید دورش رنگ باشه»): the cell's button wears it, `ds_cell32` rounds it, the nested `DSTRIP_SWATCH 24` centre wears the interior's colour (and the plate tone in a kind with no interior, i.e. a ring with a hole). Two new slots, `DRAW_SLOT_BOXHALF 11` and `DRAW_SLOT_EXTEND 12` (`DRAW_SLOT_N 13`, appended), both toggles in the quick row beside FILL — `DSTRIP_QUICK_CAP` 7 → 8, measured worst case DK_RECT = 8 cells + 4 chrome = 576 px at the minimum badge, ~616 at the widest, ≤ `DSTRIP_SKIN_MAXW 660`. HALF is 50 % OF THE **BOX**, not of the fill — the user's own correction: «من منظورم این نیمه بود نه نیمه fill» — `[BXH:<seconds>]` on the box's own mark group, the FAR anchor moved to the middle of the remembered LENGTH and restored on the second tap, with `BoxHalfRecheck` (pump + release witness) dropping the mark the moment a hand gives the edge a span that is no longer half, so the payload can never go stale; EXTEND is the box's `[BXE2]` as a switch, with the cycle's other modes staying in the more-popover. Neither is a look — learned nowhere, out of the undo. `DrawStripSeatAvail` keeps the kind-level cap honest for the ONE kind whose types differ (DK_CHANNEL: the regression and standard-deviation channels have no interior, so the interior's COLOUR seat is refused there, one compare for every other kind — the 50 % is the drawing's own geometry and holds for those two types). The `[BX…]` group's one reader and one writer moved to `DrawToolbar.mqh` (a slot is read/written there; define-before-use) and `BoxMarkWrite` re-emits `[BXH]`; four new 24 px bakes (`bk_half_off/_on` — the box with a 50 % tick, ON = the box wearing its first half with the dropped half a faint dashed ghost — and `bk_ext_off/_on`, the travelling far edge; ON = the amber twin, one quiet shape) took the manifest 321 → 325. Cost: four objects per seat on the repaint path, two probes per non-colour cell, one description read per child sync. **Updated 2026-09-27 (the HALF cell's own day, two reports):** HALF is **50 % AS A LEVEL, NOT A LENGTH** — «خود باکس رو از وسط طول نصف میکنه که نباید باشه … من میخوام فقط 50 درصد مثل فیبو که 50 درصد مشخص میشه». The cell now writes the `[BX50]` MARK only: `BoxMidSync`'s `<box>_BX50` dotted line at the box's own mid PRICE, the fib's own idiom, and **no anchor of the drawing moves** (the box keeps the length the hand drew, the interior untouched). The whole `[BXH:<seconds>]` payload is therefore GONE rather than left as a second way to say "half" — `DrawBoxHalfSpan/Read/Write` and `BoxHalfRecheck` (with its pump and release call sites) are deleted, because a remembered LENGTH existed only to put back what the cell had cut, and a level has no payload that can go stale. The `[BX50]` icon keeps its bake (a solid block with a dashed midline IS "the box's 50 %"), and the 50 % and the travelling far edge no longer fight over one edge, so both can be on together. Both extras are now the RECTANGLE's alone (the cap lost `DRAW_CAP_BOXHALF` on CHANNEL/FIBOCHAN/ELLIPSE/TRIANGLE): a channel's third anchor and an ellipse's are not that mid price, and C-04 forbids a control where nothing would happen. **And the level itself is a whisper:** «خط وسط باید نازک تر ... مینمال باشه که چارت شلوغ نشه». Its frame (`OBJPROP_WIDTH 1` + `STYLE_DOT`, the thinnest MT4 draws) is written at BIRTH and never read or written again — the steady state loses a read and a compare against the old mirror-the-master's-width — and its ink is the master's own colour blended `BOX_MID_FADE 55` towards the cached chart background, the same arithmetic the interior's tone uses, so the level aims without competing with the border. No level caption and no shortened rule: a caption is a second object and a caption owner, and a line that stops short of the edges is a tick, not a level. **And the header names BOTH roles (P-DRAW-64b, 2026-09-27):** «این بوردر و fill کاربر متوجه نمیشه». The board's one caption with a secret toggle is gone; BORDER and FILL ride the same band as two legible segments, the active one in the accent and bold, each setting its own role outright (a tap on the active one costs the click family only), plus the kind's caption — and the cross-tool pass behind it (50 % no longer kills the extend, the mid line's own orphan rule, recents show the fill, every border-colour commit re-inks the level, the extend step re-stamps the interior, the learn loop skips the arrangements, toggles sync the group) is in history.md, with the pairs that were read and found clean. |
| 14 | the settings panel's placement (B-10 / catalogue 18) | 2026-09-25 | **fixed:** «پنل روی خوده ابجکت ظاهر میشه اصلا جالب نیست و تجربه کاربری بدی داره» — `DrawStripPlaceGear` tested onWin, the plate and the open card and NOT the drawing it serves, while the plate itself opens on the drawing's corner (P-DRAW-20): on a large drawing or a zoomed chart every candidate lands on the work. The drawing's box is now a hard term (P-DRAW-31's one-rule-two-rects law) and its measurement has ONE owner, `DrawStripDrawingBox`, asked by BOTH placers (PlaceFresh carried its own copy of that anchor loop — H-06). Ladder: clears plate+card+drawing → clears plate+card → clears the plate → clamped reading order. **measured:** the box costs ≤ 3 anchor projections, asked only when the panel is not hand-carried (`s_dsGearManual` returns before it), so the carry path pays nothing. **open, and it is a design decision:** when the drawing covers the window, EVERY candidate overlaps it — a floating surface cannot win that; the answer is a home (dock), which is what the next question asked. **CLOSED by P-DRAW-41 (row 15):** the plate has a home now, so the placer runs on the FIRST open of a chart only. |
| 22 | **the orb's own click (the hover chip's lifetime + the click's cost)** | 2026-09-25 | **fixed:** «روی منوی اصلی که کلیک میکنم او تریگر پرایس اکشن هم حالت پرپر میکنه که نباید باشه و هزینه مصرف بارش باید نزدیک صفر باشه کلا». `ToggleMenuVisibility()` called the `DeleteMenu()` + `CreateMenu()` pair, and that pair deletes and re-creates the ORB and the HOVER CHIP as well as the ring — the pointer is on the orb when it fires, so the banner was destroyed and re-made under the cursor once per click (the flash), and the click paid a full family rebuild (ring + badges + orb + chip) for a state change only the RING can express. **The toggle now owns exactly the two families that change sides:** `CircCreateItem` on show (plus the tools items), a new `DeleteRing()` owner plus `DeleteToolsMenu(false)` on hide — `DeleteMenu()` calls the same `DeleteRing()`, so the family delete is not written twice. The orb and the chip are never named, `s_CircTipFeat` stays valid because nothing they own was deleted, and `UIReleaseClaimReset()` is kept from the pair's CreateMenu half (two bool reads under a live press, a no-op inside the dispatch that called it). `CircRefreshOrbSkin()` is **change-guarded** (P-PERF-51): the resource is read back first, so today's call is one read and zero decodes (P-PERF-01) instead of two `OBJPROP_BMPFILE` writes forcing a decode of a picture that did not change. **the other callers of the full pair are untouched** (attach, `CircArmBaseKnot`, the metric rebuild) — a metric change still re-derives everything through `CreateMenu()`'s idempotent create path, which is why the toggle could be narrowed safely. **gate:** main (workspace + installed) + Lite + all seven harnesses `Result: 0 errors, 0 warnings`, `node tools/submenu_geometry_check.js` green (1440 cases); the live XAUUSD M1 chart took the build by itself at 20:09:25 (journal `removed` + `loaded successfully`, `.ex4` 20:09:24). |
| 21 | **the card's footer pair (Reset / Done) and what "Reset" actually did** | 2026-09-25 | **fixed (the pill) + instrumented (the action):** «دکمه ریست کار نیمکنه». Measured FIRST, because a press that never arrived and a press that did nothing are different facts: `grep -o "press acted ([a-z]*)"` over the live ledger counts **4 `(rst)`** presses (19:40:07.798 item=4, 19:40:08.350, 19:40:21.303 / .814 item=1), and the same minutes print `[W][PERF] mouse move breakdown: panel=31ms` — the branch is reached and `PnlResetItem` pays its rebuild. What the user pressed read **"Res.."** in the screenshot: every footer pill was built at the fixed `PNL_BTN_W 72` while reserving 32 of it for the icon inset, leaving 32 for the caption — fits "Done", clips "Reset" through `PnlFit`. B-07 forbids it ("sizes itself from `PnlTextW(txt, pt) + 2*pad`, never from a magic number that happens to fit one language's string today"). `PnlFootBtnW(label)` is now the ONE owner of a footer pill's width, `PNL_BTN_W` became its FLOOR so the shipped look cannot shrink, and the paint, the read-back hit rect (P-UI-79) and the Done pill's right-aligned x all ask it. The reset also answers with its EFFECT now — `[UI] panel reset item=N rows=N flags=N` — so the next report is a measurement instead of an argument. |
| 20 | **the panel's opening side ("smart for every scenario")** | 2026-09-25 | **rebuilt:** «این فضا نیست، حتما نباید به سمت پایین باز بشه، باید هوشمند باز بشه سمت راست بالا و غیره ... هر دفهه باید کاربر بگیره درگ بکنه». The old ladder was four sides in a FIXED order (below first) and clamped candidate 0 when none fitted whole — a tall tab on a short chart therefore always opened downward and overflowed, which is the reported "drag it every time". Now **8 positions** (4 sides + 4 corners) are scored by the pixel area each covers: work ×1000 (hard, B-10) > plate ×20 (P-DRAW-31) > open card ×5, with the air to the nearest window edge as the tie-break and the reading order as the last one; unfittable candidates are skipped, and only when none fits does the clamped reading order return. Height = the layout's FINAL `s_dsGearH` for the tab being opened (measured before this paint), not the previous tab's. **witness:** `[drawstrip] gear side=… pos=(x,y) size=W x H chart=cw x ch air=n`, one line per REAL move (a paint runs at pointer rate while the mouse moves). **measured:** `DrawStrip.mqh` 5236 lines, share 20 %, longest run 34; main + Lite + seven harnesses `0 errors, 0 warnings`, submenu check green. |
| 19 | **one picker (the strip's duplicate colour grid)** | 2026-09-25 | **fixed (first slice of the unification order):** «رنگ و تنظیماتِ استریپ روی همان دو مالکِ کارتها سوار شود ... که کد کمتر داشته باشیم». The Style tab's COLOUR section drew a 16-swatch grid from `BioPal` while the strip's popover already offers the 60-cell Material grid (P-DRAW-39) — the duplicate row 13 kept open. **Deleted as one unit, nothing unreachable left:** `DrawStripGearGridSwatches()`, `DrawStripSwatchAt()` (the popover has `DrawStripPickSwatchAt`), the paint's kind-0 swatch branch (colour rect + `pnl_glass28` glass) and the tap's kind-0 branch; the grid is CHIPS only now (border width / line style / ray), HEX stays (an exact typed value exists nowhere else). **measured:** `DrawStrip.mqh` **5252 → 5196** lines, `grep` for both symbols = 0, main `0 errors, 0 warnings`, Lite + seven harnesses the same, submenu check green. **still open, sized in history P-DRAW-44:** the popover (~114 sites) rides the cards' palette (palette closes the panel — user's choice) and the gear's rows (~441 sites) ride the cards' rows. |
| 18 | **the menu's hover text (one box, one owner)** | 2026-09-25 | **fixed:** the user's screenshot showed the SAME sentence twice on one hover — the menu's drawn chip (dark + amber title) AND the terminal's OS box, because `CircCreateOrb()` wrote the sentence into `OBJPROP_TOOLTIP` while `CircTipText(-1)` fed the drawn chip. The comment above the custom tip asserted "native hover tooltips do not display in this environment"; the screenshot is the measurement that falsifies it (and the fix is in the code, per the repo's own law). **Fix:** the native channel is retired on the menu's own objects (11 sites: orb, ring items, tool items, badge plates/faces — all shapes the drawn chip already covers by pointer geometry), so the menu shows ONE box; the text keeps one owner (`CircTipText`/`CircItemTooltip`/`CircBadgeTooltip`). Objects outside the menu keep their tooltips. **Also:** the title is now "Trigger Price Action" (Title Case), spelled once. **gate:** main `0 errors, 0 warnings`, Lite + seven harnesses the same, submenu check green; `BiotakMenu` share 27 %, longest run 36 (unchanged). **P-UI-120 (same day, same surface):** the chip is ONE line now — the "\nClick: … · Hold: …" tails are deleted from `CircItemTooltip` (the state fragment is the second sentence), the orb reads "Trigger Price Action" alone, and the fixed 290x56 rect became a MEASURED box (`CircTipLine`) the frame hugs, centered, Tahoma 11pt, hairline border, bg = `GetZoneRenderColor(CIRC_TIP_BG, CIRC_TIP_TINT)` (a label has no alpha channel). **the −3° tilt is impossible LIVE, with the compiler as the proof** — `OBJPROP_ANGLE` on a label is `error 230`, and a bitmap label cannot be rotated. **So the orb's own chip became BAKED ART (the user's call, 2026-09-25):** the user sent a generated calligraphy plate asking for it to be edited (Quranic phrases out, only `Trigger Price Action` with correct spelling, background right, same place) — and a 1280x698 plate can only be used for its PALETTE, because MT4 crops a bitmap label and never scales it. The palette is **measured off it** (navy `#0F1322` 191 144 px · gold `#CFA77C` 8 362 px · highlight `#FFFDC5` · ember `#9F2924` 1 879 px), and that procedural face was SUPERSEDED the same day: the user sent the Persian banner with the correct text («اینو بزار») and it is now the art itself — `tools/orb/tip-face-src.png`, committed beside its baker, with `tools/orb/make-tip-face.ps1` INGESTING it (the bow's own pattern): the measured trap is that PNG's **painted checkerboard, no alpha channel at all** (every pixel A=255, corner `251,252,252`), keyed out on its own signature (every channel ≥ 210 and spread ≤ 14) — **1 132 534 px keyed, 439 498 kept**, a 1343x510 bbox baked to **200x76** (MT4 crops, never scales), keyed RGB zeroed so the rescale cannot halo; four 1:1 crops of the ornaments were inspected first and carry **no lettering** → `gen-th3-icons.js` embeds `Files/Icons/tip_face.bmp` + lists it (manifest **308**) → `#resource` in `BiotakMenu` + one `OBJ_BITMAP_LABEL` on the chip's own box; the unused content kind is parked, never left behind. Real alpha and a real rounded edge are the two things the bake buys, which a rectangle label cannot have at all. The size is a contract the regen GATES (`TIP_FACE_W/H` vs `CIRC_TIP_FACE_W/H`) because MT4 cannot ask a bitmap how big it is. Item captions stay live text (their state is dynamic). **gate:** main + Lite + seven harnesses `0 errors, 0 warnings`, submenu check green |
| 17 | **the plate's transparency (a real % on a baked surface)** | 2026-09-25 | **built (user-chosen mechanism):** «شفافیتش هم تنظیم بشه». MT4 crops a bitmap instead of blending it and offers no runtime image API, so a % cannot be a slider over one file — the read put two options to the user (a tone blend in the cards' own `GetZoneRenderColor` language, or real alpha in baked steps) and the baked steps won. `dsSkinPiece()` now takes `t` and multiplies body/border/shadow/catchlight alpha together (the same plate, not a new design), `dsSkinFiles()` emits 30/60/90 % sets (24 BMPs, manifest-listed; level 0 keeps the shipped names), and the runtime re-points the 8 piece resources. **The subtlety:** P-DRAW-35's underlayer would have hidden the alpha, so it is the CHART'S background whenever a level is chosen (`DrawStripPlateFill()` + the cached bg read) — the white-chart fringe fix and the transparency in one owner, feeding the mid centre and every plate-toned cell (quick row, actions, gear rows, popover rows, grip) so no solid row quietly re-opaques the plate. **measured:** level 0 is byte-identical to before (every call returns `DSTRIP_CLR_PANEL`); a level change is 8 guarded resource re-points inside the paint that was owed, no purge; one gear row (kind 9, Style tab's "PLATE") steps 0/30/60/90, persists as key `PLATE` (slot 8, ledger 9). **gate:** main `0 errors, 0 warnings`, Lite + seven harnesses the same, submenu check green, manifest 307 files. |
| 16 | **the strip's plates and their underlayers (dirty delete, catalogue 18's tail)** | 2026-09-25 | **fixed (the reported rectangle):** a screenshot showed the colour popover beside a bare dark rectangle the size of the settings panel with nothing drawn on it. P-DRAW-35's permanent underlayer (`PnlDrawS_BG`/`PnlDrawS_GBG`) was created inside `DrawStripSkinPaintAt` and **never** deleted — every purge took the nine skin tiles only (`DrawStripSkinPurgeAt`). One owner now takes the whole plate (tiles + that family's bg) for both families, which also closes the same defect on a strip close. **fixed (load):** the shut-panel purge ran on every paint (10 name probes for a panel that was never there) — gated on `s_dsGearPlateLive`, so the popover's path probes nothing. **fixed (reattach):** `PnlDrawS_*` carries no chart id and nothing outside the module swept it (unlike `InitializeUIStates`' own prefix), so a family left by a killed terminal survived the reattach — one `ObjectsDeleteAll(0, "PnlDrawS_")` on the first paint of a session makes every reattach self-healing. **read clean (the hover):** `DrawStripColorHoverAt` returns on the same cell, so a still pointer writes nothing and a cell crossing is one rim + one live recolour + a redraw only on a real colour change (P-DRAW-27). **gate:** main `0 errors, 0 warnings`, Lite + seven harnesses the same, `submenu_geometry_check` green; `DrawStrip` share 19 %, longest run 34 (unchanged). **Updated by P-DRAW-48 (2026-09-26) — ONE PLATE, ONE NAME, AND THE BODY ON THE PLATE'S Z.** Reported: the board is complete on open and **empty after a drag** (measured: the grid region = 1 colour over 24,750 samples). `DrawStripSkinPiece(fam, i)` answered the STRIP's nine names for the board's family, so both plates were one set of objects: the strip's plate (48 tall, `k = 0`) DELETES the mid pieces on every paint and the board's plate re-created them — at `Z_STRIP_ICON`, the cells' own z, where a tie is settled by creation order, so the newest object (the plate's own body, a button the size of the plate) drew LAST over the 64 cells, the RECENT band and the HEX field. Fixed as a law: **a plate family's pieces are its own names** (`DrawStripBoardSkinName`, and the family's bg with them), and **the plate's mid band rides `Z_STRIP`** through the new `DrawStripBtnZ(..., z)` + a per-paint guarded `OBJPROP_ZORDER` write — the plate can never be drawn over its own contents whatever the order did, for every family (this is the same tie the gear panel and the strip carried — «حتی برای تمام پنل های دیگه»). Also: `PnlDrawS_PHeadP/PHeadPI` joined the popochrome prune list, `DrawStripClosePicker` purges family 2 (a pick used to leave the plate behind), and `DrawStripIsBg` knows the board's `PnlDrawS_BB` prefix. |
| 15 | **the strip's placement architecture (the P-DRAW-40 tail: a home instead of a chase)** | 2026-09-25 | **fixed (the architecture, not the placer):** «پنل روی خوده ابجکت ظاهر میشه ... بهترین کار چیه یا معماری ظاهری رو عوض کردن». A surface that re-places itself beside the drawing it serves cannot win — when the drawing fills the window every candidate is inside the work — so the strip STOPS CHASING. The first open measures the drawing once (P-DRAW-20) and that answer becomes the HOME (`s_dsHomeX/Y`, `-1` = none, one reader pair + one clamp owner); every later open wears it, the hand's carry rewrites it, and persistence rides the menu's own UI-state block (keys `HOMEX`/`HOMEY` under the existing per-key change guard, shadows `[8]`→`[10]`, ledger `6`→`8`, **no version bump** — an absent key means "no home yet", not a reset). **deleted with the chase (the cheaper of two equal paths, G-09):** P-DRAW-37's `DrawStripRide` (a re-open of the same object is now a re-state: mid + return), the `s_dsManual`/`s_dsAX`/`s_dsAY` offset trio, the grip-live anchor refresh, and the `DSTRIP_FOLLOW_MS` name (now `DSTRIP_MID_MS`, renamed in row 11). **measured:** a fresh open = one P-DRAW-20 placement (first open only); a ride = one `BoxMidSync` on rect kinds, **0 projections** against P-DRAW-37's projection + layout + paint (the 50 ms cap on the ride is retired by P-DRAW-64d — the hand's own cadence IS the cadence); a zoom/scroll = the clamp's **8 integer compares**, painting only when the plate really moved. **gate:** main `0 errors, 0 warnings`, Lite + all seven harnesses the same, `node tools/submenu_geometry_check.js` green (1440 cases). **left open, deliberately:** the panel's own carry (`s_dsGearManual`) is per-session — it is placed beside a plate that no longer moves, so its spot is reproducible. |

Seven rule families (B-11, A-13, catalogue 21–24, C-01…C-06 with catalogue 25, and
G-08…G-12 with gate item 10) were
**added by** these walks. Two of them exist because a rule was written in a comment and
never compiled — the ring's claim (23) and the pager's hit test (24) — which is this
repo's recurring shape: the sentence ages better than the code. Catalogue 25 is the same
shape one layer up: the sentence was never *edited*, and reading the code for facts
nobody needs costs every reader who comes after. An audit that finds nothing new is
usually an audit that did not read the code.
