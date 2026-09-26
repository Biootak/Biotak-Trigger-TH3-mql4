# docs/references.md — SOURCES AND THE DESIGN LOGIC BEHIND A FLAWLESS TOOL

User order (2026-09-26): «از مرجع کد ها بروز هم میتوی استفاده بکنی هر چی منبع هست در یک داک
بزار … ولی اینکه حتما اخرین نسخه باشه … من اون فکر ها و منطق ها پشتش میخوام که چطوری یک
ابزار بی نقص طراحی کردن».

This file is the ONE place the outside sources live. It holds four things and nothing else:

1. **the source table** — what each source is for, whether we use it, and its verdict;
2. **the design logic** the authors paid for, mapped to the law that already owns it here
   (or marked as a candidate);
3. **the portrait of a flawless tool** — the questions a tool must answer before it ships;
4. **the traps ledger** — the defects this repo has already paid for, one line each, each
   POINTING at its owner so a reader meets the minefield before writing the code.

**Rules this file is under, so it cannot drift into a copy-paste pile:**

- **R-01 — THE NEWEST VERSION WINS.** A source is cited by its MQL5 article id and its own
  series part. Before any code is taken from a source, its page is re-opened and the version
  checked: a newer part of the same series supersedes an older one (MQL5 numbers articles in
  order of publication), and a candidate we already rejected for a measured reason is NOT
  re-tried because a newer part exists.
  **Measured 2026-09-26:** the Tools Palette series (S-2/S-5) runs Part 18 → **Part 35** and is
  still open, so Part 19's palette is NOT the current shape — read the newest part first. That
  series moved onto a full-chart `CCanvas` at Part 34, which is MQL5-only here (R-03), so its
  CODE is not adopted at any part; only its LOGIC is read. The map:
  18 `21271` · 19 `21275` · 20 `21303` · 30 `22193` · 33 `22303` · 34 `22786` · 35 `22838`.
  The other live series this file reads — S-1's *Automating Trading Strategies* (Part 30 `19442`) —
  is now at **Part 53 (`23576`, → S-9)**, measured 2026-09-26: check that part first on any re-read of
  S-1's rows (T-9).
- **R-02 — WHAT WE ADOPT MUST STATE ITS COST** (G-09). A technique carried in from outside is
  written with its number (`creates per open`, `writes at rest`, `reads per event`).
- **R-03 — COMPILABILITY IS A GATE, NOT A PREFERENCE** (P-TOOL-04). MQL5-only machinery does
  not enter this repo: `CCanvas`, `OBJPROP_ANCHORS`, MQL5-only handles, `.py` tooling. A
  source that teaches a rule in MQL5 is read for the RULE; the rule is then re-implemented in
  MT4's own vocabulary or it stays out.
- **R-04 — A RULE AN OUTSIDE AUTHOR PROVES IS NOT A REASON TO RE-OPEN OUR OWN.** Where the
  source agrees with a `P-*` law we already measured, it is recorded as **confirmation**
  (cheap, useful evidence), never as a reason to rewrite the law.

---

## 1. The sources

| # | source | what it is | verdict |
|---|---|---|---|
| S-1 | [MQL5 article **19442** — *Automating Trading Strategies in MQL5 (Part 30): Price Action AB=CD Harmonic Pattern with Visual Feedback*](https://www.mql5.com/en/articles/19442) | a full worked pattern tool: pivot detection, ratio validation with a tolerance, drawing helpers, trade levels, and an explicit **anti-repaint lock** | **read for its LOGIC** (the user's own link). The AB=CD/XABCD/Cypher tool family is RETIRED here by user order (P-DRAW-58) — the logic below is what we keep. |
| S-2 | [MQL5 article **21275** — *MQL5 Trading Tools (Part 19): Building an Interactive Tools Palette for Chart Drawing*](https://www.mql5.com/en/articles/21275) | a draggable/resizable tool palette with theme switching, active-tool and instruction lines. **Part 19 of a LIVE series now at Part 35 (`22838`)** — read the newest part first (R-01); by Part 34 the palette lives on a full-chart `CCanvas`. | **read for its LOGIC only**; the `CCanvas` implementation is MQL5-only (R-03). The palette's LOGIC is what we keep; the canvas is never adopted. |
| S-3 | [MQL5 article **19834** — *The MQL5 Standard Library Explorer (Part 2)*](https://www.mql5.com/en/articles/19834) | `CChartObject*` interfaces: the standard library's own object wrappers | **reference for naming/state vocabulary only.** Our object layer (`ObjectFunctions`, `ObjectCache`, `ExtendedDrawingFunctions`) already owns this in MT4 idiom; a wrapper library is not adopted (it would be a second owner). |
| S-4 | [MQL5 article **23818** — *Why the terminal needs its own 2D-renderer*](https://www.mql5.com/en/articles/23818) | the case for a custom 2D renderer above the terminal's own drawing | **candidate evidence for P-DRAW-50** (the magnifier / stage-5 UI). Read again when that probe is taken. |
| S-5 | [MQL5 article **22786** — *MQL5 Trading Tools (Part 34): Replacing Native Chart Objects with an Interactive Canvas Drawing Layer*](https://www.mql5.com/en/articles/22786) (its forum thread is `510758`) | the path from native objects to a full-chart bitmap canvas: per-pixel hit test, handles, rubber-band preview, per-tool style memory, whole-object drag | **read for its LOGIC; the code is MQL5-only** (R-03). This is the article form of what the thread `510758` described — cite the ARTICLE, not the thread (R-01). Its cost shape (one full-chart bitmap, repainted per frame) is what item 10 of the delivery gate exists to police. |
| S-6 | [MQL4 documentation — `enum_object`, `enum_object_property`, `visible`](https://docs.mql4.com/constants/objectconstants/enum_object) | the terminal's own contract: property names, value ranges, and the `OBJPROP_TIMEFRAMES` mask | **THE authority.** Used verbatim for the Visible tab (P-DRAW-63) and the `OBJPROP_ANGLE`/anchor-count traps (P-DRAW-60/61). Where an article and this page disagree, this page wins. |
| S-7 | [MQL5 article **21271** — *MQL5 Trading Tools (Part 18): Rounded Speech Bubbles/Balloons with Orientation Control*](https://www.mql5.com/en/articles/21271) | a speech bubble = a rounded body + a pointer triangle, with the pointer facing up/down/left/right (`BUBBLE_ORIENTATION`), supersampled fills, and a border extension ratio for seamless joins | **read for its LOGIC** — it is the chip/callout face family, and its `BUBBLE_ORIENTATION` is exactly the TURN our chip must not take (P-UI-126). Canvas-only code (R-03). |
| S-8 | [MQL5 article **21303** — *MQL5 Trading Tools (Part 20): Canvas Graphing*](https://www.mql5.com/en/articles/21303) | a canvas-based statistical graph (correlation / linear regression) | **not adopted** — a chart surface this product does not need, on a canvas (R-03). Recorded so the queue's own item is closed, not left dangling. |
| S-9 | [MQL5 article **23576** — *Automating Trading Strategies in MQL5 (Part 53): Double Top and Double Bottom Reversal Model*](https://www.mql5.com/en/articles/23576) | the newest part of **S-1's own series** (Part 30 `19442` → **Part 53**): a double top/bottom detector written as a strict contract — confirmed swing pivots, a peak tolerance expressed as a **percent of the pattern height**, spacing and leg-balance filters that REJECT a shape rather than fit it, and a three-state setup machine whose every stage ages | **read for its LOGIC; the code is MQL5-only** (R-03 — `CTrade`, `Trade\Trade.mqh`, live order flow, which this product does not have). What we are here for is the tolerance-as-a-share-of-height and the reject-don't-fit filters; the trade half belongs to `TradePlanFormulas` and is never re-computed. |

**Mining queue — read 2026-09-26:** S-2's Part 18 (→ **S-7**) and Part 20 (→ **S-8**) are done,
and Part 19's tail (the mouse-state machine `prev_mouse_state` and its single-click tool
classification) needed no row — both already have owners here (P-DRAW-17's press edge, per-tool
`clicks`), so the read was a cross-check, not a port. S-1's own series (`19442`) is now at **Part 53**
(`23576`, → **S-9**), read 2026-09-26 for its tolerance and reject-don't-fit contract; the
series' trade-execution half stays out (R-03).

**Still open, in the order worth reading:**

- The series' canvas line (Part 34 `22786` → Part 35 `22838`) — re-read whenever the magnifier
  (P-DRAW-50) is taken; for its FRAME COST, never its code (R-03).
- The MQL5 article series on a **standard-library GUI panel** (`CAppDialog`) — read for the
  focus/state vocabulary only; a toolbar/text-field library is MQL5-only (R-03).

---

## 2. The design logic, source by source

Each row is a rule the author paid for with a real defect. The right column says where that
rule already lives here — this repo has solved most of these independently, and where it did
the source is confirmation, not news.

### 2.1 S-1 (AB=CD, id 19442) — the pattern tool

| the author's rule (their words, condensed) | where it stands here |
|---|---|
| **"Avoid trading on repaint": the pattern is LOCKED to the bar it formed on, and only a LATER bar may act on it** (`g_patternFormationBar`, `g_lockedPatternA`), and the same formation bar is re-printed as *"Pattern is repainting"* when it is still live | **already the law here, harder.** `ATR(structure)` reads COMPLETED daily bars only (P-TH3-STEP-01, shift 1), an unmeasurable pattern carries `valid == false` / `key == -1` and is never filled with a plausible default, and the live re-measure is a MEMO that re-answers rather than fitting (P-DRAW-… / `TH3HitPivotForward`). Their lock answers *"did the pattern change?"*; ours answers *"is the pattern measurable at all?"* — the second is the stronger question. |
| **A ratio match is declared with a TOLERANCE, not fitted** (`Tolerance = 0.10` next to the ratio arrays) | **already the law.** Momentum bounds are fixed numbers in R units (`1.00 / 1.30 / 1.60`), the third a LABEL only; a bound that is not met selects nothing. Same shape: the tolerance is published, so a reader can argue with it. |
| **ONE naming prefix per drawing** (`AB_<A.time>_Triangle1`, `_TL_CD`, `_Text_Center`) so every part of a drawing is found from one root and deleted as one thing | **confirmation of P-DRAW-61** (independently arrived at): our group owner uses `<master>#k` plus the `[GRP:<master>|k/n]` tag on the DESCRIPTION, and membership is a NAME CONVENTION so nothing walks the object list. Theirs stores the grouping in the name's *prefix*; ours must survive reattach and a TF switch, which is why our tag rides the description instead — same idea, one layer deeper. |
| **Drawing helpers are separated from logic** (`DrawTriangle`, `DrawTrendLine`, `DrawDottedLine`, `DrawTextEx`) and each sets colour/style/width/anchors in ONE place | **already the law** (P-DRAW-35/37 layer split): `ExtendedDrawingFunctions`/`LabelFunctions` own the create+props, the product layer owns the geometry. |
| **Text anchoring depends on the pivot's own kind** (`ANCHOR_BOTTOM` above a high, `ANCHOR_TOP` below a low) so a label never sits on its own point | **already the law** (INFO-02 and the plate/clearance rules: a label's safe zone is computed from the thing it labels). |
| **Trade levels are DERIVED from the pattern** (TP1/TP2/TP3 = Fib levels of the CD range) with the entry as the live price | **the rule is right, the owner is ours.** Trade-plan maths has ONE owner here (`TradePlanFormulas`, R-TRADEPLAN) and nothing else may compute it — which is exactly why the preview's R:R chip was NOT re-implemented in the position boxes (P-DRAW-62). |
| **Pivots are found with a symmetric window** (`PivotLeft`/`PivotRight` = 5/5) and the whole array is rebuilt on each new bar | **partly ours:** `TH3Pivots` owns pivot detection; the symmetric window is its own parameter. **Not to copy:** rebuilding every pivot on every bar is a full-history walk — our ATR/memo design exists to avoid exactly that (G-04/G-12). |

### 2.2 S-2 (Tools Palette, id 21275) — the palette itself

| the author's rule | where it stands here |
|---|---|
| **The palette is a SURFACE with its own state**: dragging, resizing (bottom/right/corner with a minimum size), minimized, hovered, active tool | **already the law, with MT4's own answers.** Our strip/panel carry, the width steps (312/624), the fold, and the hover/active faces are the same state set; MT4 has no per-pixel cursor and no edge-resize, so a *discrete* width step is the substitute (LEVEL 65). |
| **A tool is classified by how many clicks it needs** (`IsSingleClickTool`), and the palette carries an instruction line + an `Active: <tool>` status line | **already the law, and already shipped**: every tool carries its own `clicks`, the caption line is one owner (`ChartToolsTipOf`), and the mode names itself on the chart (`ToolsStatusSync`, P-DRAW-56). One difference worth noting: their status line is INSIDE the palette; ours has to be on the chart, because the ring that armed the tool is gone by then. |
| **The header is the drag handle; the body is not.** Buttons, theme, minimize and close are separate hit areas inside the header | **already the law.** Our grip/corner grip is the drag handle; the body holds controls (H-03: one gesture, one meaning, on every surface). |
| **Theme switching = TWO complete colour tables** (`GetHeaderColor()` … `GetActiveBtnColor()` each resolve a dark/light pair) | **REJECTED HERE, and this is the most useful row of the table.** A second table is a second palette — A-01's own defect (`BioPal()` is the single owner; `QuickPalColor`/`DrawStripPal` are faces), so a theme switch here is a change of the OWNER's values, never a parallel table. Their 13 getters are the shape we must never grow. |
| **Mouse state is tracked as a transition** (`prev_mouse_state`) rather than queried | **already the law** (P-DRAW-17: the press edge is a STORE, not a comparison — the measured bug that made every move under a held button read as a fresh press). |
| **Everything is repainted onto a canvas per frame** (`Erase` → fill → draw → `Update`) | **not ours, on purpose** (R-03): `CCanvas` is MQL5. Our surfaces are objects with change guards, so a steady-state frame is ZERO writes (G-02). A canvas design must state its per-frame repaint cost before it is considered — that is gate item 10. |
| **The panel's own opacity is an input** (`BackgroundOpacity = 0.8`) drawn through ARGB | **MT4 cannot** (the fourth hard limit, LEVEL 65): no alpha on a chart object. Our substitute is the three-step tone of the same hue plus `FILL=false`; a bitmap's baked alpha is the only true transparency available. |

### 2.3 S-3/S-4/S-5 (vocabulary and the canvas path)

- **S-3** is a reminder, not a source of code: the standard library's value is its NAMING
  discipline (one wrapper per object type, one set of accessors). We already have that in MT4
  idiom; adopting the wrapper itself would create a second owner of object creation.
- **S-4/S-5** are the two ends of one argument (own renderer vs full-chart canvas). Both cost
  a repaint path that native objects do not have. They stay CANDIDATES behind P-DRAW-50's
  probe, and if either is ever taken it enters through gate item 10 with a measured frame.

### 2.4 S-7 (Rounded Speech Bubbles, id 21271) — the chip face

| the author's rule (their words, condensed) | where it stands here |
|---|---|
| **The pointer's DIRECTION is a 4-value enum** (`BUBBLE_ORIENTATION`: `ORIENT_UP/DOWN/LEFT/RIGHT`), and the body is laid out relative to it | **REJECTED HERE — the useful row of this table.** MT4 draws an object's TEXT at its own angle, but a `OBJ_BITMAP_LABEL` cannot be rotated at all, so a turned face is sideways calligraphy — the defect a screenshot named. Our chip opens ABOVE the orb or at its OWN place and never turns (P-UI-126). Their enum is the shape we must not grow. |
| **The pointer's apex is a rounded ARC** (`bubblePointerApexRadiusPixels`, `ComputeBubbleTriangleRoundedCorners`), and the border joins are extended by a ratio (`borderExtensionMultiplier = 0.23`) so no seam shows | **bought as ART, not maths.** Our rounded edge and seamless join are baked into `tip_face.bmp` (the bake is the only way MT4 gives real alpha and a real round edge), and the size is a contract the regen gates (`TIP_FACE_W/H`). No runtime geometry, no per-frame canvas. |
| **The fill/AA is supersampled on a private canvas** (`bubbleCanvas`, `bubbleHighResCanvas`, scale-then-downsample) | **not ours** (R-03): there is no runtime canvas in MQL4. The substitute is a bitmap baked at 1:1 (MT4 crops, never scales), which is why every size gets its own baked frame (P-DRAW-33). |
| **The bubble's opacity is a 0–100 % input drawn through ARGB** (`bubbleBackgroundOpacityPercent`) | **MT4 cannot** (LEVEL 65): a chart object has no alpha channel. Our substitute is a baked alpha step (the plate's 30/60/90 sets) or a label's own opaque plate — never a slider over one file. |

### 2.5 S-5 (Interactive Canvas layer, id 22786) — the engine we already built on native objects

| the author's rule | where it stands here |
|---|---|
| **Point at the object's own pixels:** replace native objects with a full-chart bitmap so hit testing is pixel-precise | **we kept native objects and got the same interaction another way.** Our hit test is geometric and BOUNDED (a resolve per family, P-DRAW-61's name convention), the drawings stay the terminal's objects, and steady state has NO repaint path (G-02). Their engine is the reason gate item 10 exists. |
| **Per-tool STYLE memory, selection, whole-object DRAG, handle manipulation, a rubber-band preview, a one-click delete** | **all already owned here, one owner each:** style memory rides the create (P-DRAW-53/54), the view lock + group drag are `ChartToolsPressClaim`/`ChartToolsDragStep` (P-DRAW-55/61), the rubber-band is F-04, and the delete is two-way (P-DRAW-61). Their engine proves the FEATURE LIST; the mechanism is ours. |
| **Handles and in-place text are drawn and hit per pixel** | **two of these were CLOSED by measurement here, not built** (P-DRAW-63): MT4 already draws DRAGGABLE anchor squares on a selected object (F-09), and MT4's own double-click opens a full text editor that code cannot suppress (F-13) — so a second handle/editor would be a control for a job already done (C-04). A canvas engine has to build what the terminal gives free. |
| **One colour per object is not the model** (a canvas paints each pixel as it likes) | **not ours** (LEVEL 65): MT4 paints fill and border with ONE colour, so a separate border is a CHILD edge object, and for the nine single-colour kinds the border cell is not drawn at all. |

### 2.6 S-9 (Double Top/Bottom, id 23576) — the newest part of S-1's series

| the author's rule (their words, condensed) | where it stands here |
|---|---|
| **A pivot is confirmed only after N closed bars each side** (`InpSwingLength = 5`) — the pattern is read from CONFIRMED pivots, never from the live bar | **already the law** (P-TH3-STEP-01): `ATR(structure)` reads COMPLETED daily bars only (shift 1). The same anti-repaint shape as S-1's own row, one part later. |
| **The tolerance is a PERCENT OF THE PATTERN HEIGHT** (`InpPeakTolerancePercent = 10.0`), so one setting means the same thing on a tall pattern and a shallow one | **confirmation of Q-2, one unit over.** Our bounds are published numbers too, but in **R units** (`1.00 / 1.30 / 1.60`) — the momentum BANDS, not a share of the shape. Same discipline (a number a reader can argue with), different ruler; the ladder's own ruler stays the pattern TF's ATR (`TH3PatternStepRung`), never `THAbilityPrice`. |
| **The filters REJECT a shape instead of adjusting it** — minimum spacing (`InpMinPatternBars`), leg balance (`InpLegBalancePercent`, shorter leg ≥ X % of the longer), optional prior trend | **already the law, and it is the same sentence:** an unmeasurable pattern is never filled with a plausible default (`valid == false` / `key == -1`); a bounce shallower than a full step is SKIPPED, not fitted; no vote at all → the proof is DELETED. |
| **A three-state machine whose every stage AGES** (`STATE_IDLE`/`STATE_ARMED`/`STATE_RETEST`, `barsInState`, `InpMaxConfirmBars` / `InpMaxRetestBars`) | **confirmation of P-DRAW-56** (a state that outlives its gesture is the defect). Our states end on the event that owns them — the press's release latch, the mode's own status line — rather than on an age counter; a stage that never ended would be the same defect here. |
| **One id per pattern, derived from the second peak's time** (`DTB_LegA_<id>`, `DTB_Neck_<id>`), so the whole drawing is found and deleted from one root | **confirmation of P-DRAW-61.** Ours rides `[GRP:<master>|k/n]` on the DESCRIPTION instead of a name prefix, because it must survive reattach, a TF switch and a restart — the same idea, one layer deeper. |
| **Stop, target and lot are DERIVED from the pattern** (measured move or R:R, buffered stop, min stop) | **the rule is right, the owner is ours** (R-TRADEPLAN): `TradePlanFormulas` is the ONE owner of trade-plan maths and nothing else may compute it — which is why the preview's R:R chip was NOT re-implemented in the position boxes (P-DRAW-62). |

---

## 3. The portrait of a flawless tool (distilled, ours to keep)

Written as the questions a tool must answer before it ships. Every question below came from a
real defect in a source or in this repo; the answer column says who owns it.

| # | question a flawless tool answers | owner |
|---|---|---|
| Q-1 | **Does it repaint, and does the user SEE the answer?** A live formation is re-answered (never fitted), and a value that cannot be measured is INVALID rather than plausible. | P-TH3-STEP-01, the memo (P-DRAW-…), `valid == false` |
| Q-2 | **Is its tolerance declared?** Every threshold is a published number a reader can argue with — never a fitted constant. | momentum bands, `DSTRIP_HOLD_MOVE`, `TOLERANCE`-style constants |
| Q-3 | **Can one part of it be found from one root?** A multi-object drawing has ONE name convention and one resolver, survives reattach/TF/restart, and deletes in both directions. | P-DRAW-61 (`[GRP:…]`), P-DRAW-21 |
| Q-4 | **Does it own its state and only its state?** Active, hovered, minimized, pinned are states, not leftovers; a state that outlives its gesture is the defect. | P-DRAW-56, catalogue (dirty-look) |
| Q-5 | **Does the pointer's press belong to it?** A press that names it takes the view, MT4's own native drag is neither fought nor rewritten, and the release hands the view back exactly once. | LEVEL 76 (D-01…D-11) |
| Q-6 | **What does a tap do, and is that visible?** One gesture means one thing everywhere; the mode names itself where the user is looking. | H-03, `ToolsStatusSync`, `ChartToolsTipOf` |
| Q-7 | **Is every control it shows real?** A cell that paints an option but changes nothing is a defect even if it looks right. | C-04, P-DRAW-63's two measured closures |
| Q-8 | **What does it cost on the weakest machine?** Steady state zero writes, a bounded walk, and a number for anything that repeats. | G-02/G-04/G-08…G-12, gate item 10 |
| Q-9 | **Can it be removed cleanly?** Objects, GVars and persisted state leave with the instance, for every teardown reason. | `CleanupAllGlobalVariables`, `ChartViewLockForceRelease` |
| Q-10 | **Is its behaviour the SPEC's, or my memory's?** Geometry, click counts and glyphs come from the prototype or the terminal's documentation — never from what the code "should" do. | `docs/tool-parity-plan.md`, P-DRAW-60/61/62 |

---

## 4. The traps ledger — what this repo has already paid for

**This is a POINTER, never a second copy.** Every line names a defect that was MEASURED here and
the owner that holds the rule (`docs/design-checklist.md`'s catalogue row, or the code's own
`P-*`). The rule stays at its owner; this table exists so a reader meets the minefield BEFORE
writing code — which is the whole point of this file.

| # | the trap (measured here) | the owner that holds the rule |
|---|---|---|
| T-1 | **A control that paints an option but changes nothing** — an angle line the user drew opened no strip because `DrawKindOf` had no `OBJ_TRENDBYANGLE` case (`DK_NONE` ⇒ served never); same shape as a border cell for a single-colour kind. | P-DRAW-60 (catalogue 33) · P-DRAW-63 / C-04 (catalogue 36) |
| T-2 | **A state that outlives its gesture** — a finished drawing that leaves the tool armed, a star's mark parked off-page, a mode that never names itself. | P-DRAW-56 (catalogue 31) |
| T-3 | **A second owner of a claim / a palette / a rule** — a second UI hit test, a second colour table, a colour grid drawn beside the one picker. | A-01 · A-13 · P-DRAW-53 (catalogue 13/19/28) |
| T-4 | **An ownership/release witness re-derived from LIVE state** — the strip closed on release because ownership was read off the terminal's instant selection instead of the press's own latch. | P-DRAW-04 (catalogue 12) |
| T-5 | **Rebuilding a whole family per frame** — a re-open deleted and re-created ~40 objects at a 50 ms cadence; the menu toggle rebuilt the orb and chip under the cursor once per click. | P-DRAW-37/40/41 · P-UI-120 (catalogue 15/18/22) |
| T-6 | **A delete that takes the tiles and leaves the underlayer** — a bare dark rectangle beside the colour popover. | P-DRAW-35/36 (catalogue 16) |
| T-7 | **A hardcoded size that fits one string today** — every footer pill built at a fixed width clipped "Reset". | B-07 (catalogue 21) |
| T-8 | **A fixed-order placement that always overflows** — four sides "below first", clamped to candidate 0, so a tall tab opened downward off a short chart. | B-10 · P-DRAW-31 (catalogue 14/20) |
| T-9 | **An older part of a live series taken as current** — the palette's shape is Part 34/35, not Part 19. | R-01 (this file) |
| T-10 | **A plan read as law** — the parity plan listed retired tools as pending work and fixed defects as live. | P-DRAW-59 (catalogue 32) + the plan's own three-verdict rule (catalogue 35) |
| T-11 | **A bit-mask renumbered by an insert** — a star mask is bits of ENUM INDICES and so is the `[CTn]` tag, so a new roster member is APPENDED, never inserted. | P-DRAW-58/60 (catalogue 30/33) |
| T-12 | **A comment block that grows past its ceiling** — a 220-line file header and ~230 runs over the 16-line cap. | LEVEL 86 (catalogue 25, pass 2 open) |
| T-13 | **A surface that re-places itself beside the work it serves** — when the drawing fills the window every candidate lands on it; the answer is a HOME, not a chase. | P-DRAW-40/41 (catalogue 14/15) |
| T-14 | **A native tooltip left beside the drawn chip** — the same sentence shown twice on one hover. | P-UI-120 (catalogue 18) |
| T-15 | **A live formation read as a finished one** — the defect S-9 is built against: pivots taken from the live bar, so the same shape appears and disappears with the tick. | P-TH3-STEP-01 (shift 1 only) · `valid == false` · S-1/S-9 |

---

## 5. How to add a source here (for whoever comes next)

1. Read the page (not a mirror), note its **article id and part**, and confirm it is the newest
   part of its series (R-01).
2. Write the row with its **verdict**: read-for-logic · reference-only · candidate (with its
   gate) · rejected (with the measured reason).
3. Extract the author's RULES, not their code; map each to the law that owns it here, or mark
   it a candidate with the question it would answer (Q-1…Q-10).
4. If something is adopted: state its cost (R-02) and say in `docs/history.md` which source
   taught it — an audit that finds nothing new is usually an audit that did not read the code.
