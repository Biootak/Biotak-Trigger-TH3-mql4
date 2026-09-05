# AGENTS.md — Biotak Trigger TH3 (MQL4)

> خلاصه فارسی: این فایل را هر ایجنت در شروع هر سشن (حتی سشن جدید) باید بخواند و به‌کار ببندد.
> دو قانون طلایی: (۱) هر جا چیزی اضافه/تعمیر می‌کنی، طبق «Where things go» همین‌جا بگذار؛
> (۲) هر مشکلی که حل کردی و ممکن است دوباره پیش بیاید، همین لحظه در جدول
> «Recurring Problems» پایین همین فایل ثبت کن تا هیچ سشن بعدی آن را از نو حل نکند.

**MetaTrader 4 custom indicator** implementing Prof. Saeed Khakestar's TH
(Time Harmonic) levels formula. MQL4 only — no JS/TS/Python in the product
code (Python/PowerShell live in `tools/` and `gen_*.py` for asset generation).

This file is **auto-loaded at the start of every agent session**. Follow it
even in brand-new sessions with no other context: it is the memory of this
project.

---

## 0. Golden rules (applied automatically every session)

1. **Read AGENTS.md first.** Before editing anything, skim ARCHITECTURE.md
   (layering rules) and the log table below.
2. **Never solve the same problem twice.** If you hit something already in the
   Recurring Problems table, apply the recorded fix — do not re-diagnose.
3. **Log every recurring problem immediately.** After fixing anything that
   could bite a later session (weird build, MT4 quirk, tool trap, wrong file
   location), **append a row to the Recurring Problems table right now**, with
   symptom, root cause, and the do-this fix. This is how the project learns.
4. **Place things where they belong** (section 2). New code goes in the
   correct module; never invent a new home for something that has one.
5. **Icons are 32-bit with alpha. Never flatten them** (see R-ICONS).
6. **Finished work becomes law.** Every completed section is recorded in
   these instructions as a rule (R-*) the same session — future sessions
   obey it instead of re-deciding (see R-RETIRED for the pattern).
7. **One topic per commit.** Finish → compile → commit → next (see R-COMMIT).

---

## 1. Project quick facts

| Fact | Value |
|------|-------|
| Language | MQL4 (MT4). No external libs. |
| Entry points | `Biotak Trigger TH3.mq4` (Full) / `Biotak Trigger TH3 Lite.mq4` (Lite) — thin event-handler stubs only |
| Logic | ~55 `.mqh` modules under `Biotak/`, layered bottom-up (see ARCHITECTURE.md) |
| Variants | `#define BUILD_LITE` in `Biotak/BuildConfig.mqh` selects Lite; `DEBUG_BUILD` toggles debug |
| UI icons | `Files/Icons/*.bmp` — embedded into the `.ex4` via `#resource` |
| Docs | `ARCHITECTURE.md` (en), `README.md` (en), `Biotak/DEVELOPMENT_GUIDE_FA.md` + `DOCUMENTATION_FA.md` (fa) |
| Build | `powershell -File compile-th3.ps1 -Project all` (auto-detects MetaEditor, syncs icons into every terminal hosting the project, writes `build-logs/`) |

### Build / verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1   # workspace ex4
```

Linux (Bottles/Wine, AMarkets terminal in bottle `Tradeing`) — separate path,
`compile-th3.ps1` stays untouched:
```bash
./compile-th3-linux.sh all   # full + lite; syncs terminal BiotakProject, deploys .ex4
```
The Linux compile runs metaeditor in an ISOLATED Wine prefix
(`<Bottles-data>/th3build-wine`, override via `TH3_WINEPREFIX`) — never in
the live `Tradeing` bottle — so the running terminal stays open (see
P-BUILD-04). The live bottle is only ever touched by plain file copies
(source/icon sync in, `.ex4` deploy out).
Manual MetaEditor F7 also works on Linux: open
`MQL4\Indicators\BiotakProject\Biotak Trigger TH3.mq4` (a REAL auto-synced dir,
never a symlink — see P-BUILD-02) and compile.

- Success = `Result: 0 errors` in the log. Do not compile `.mqh` files
  directly — only the entry `.mq4`.
- Icon change deploy — ONE command does everything:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1`
  (1) regenerates all 42 BMPs via `tools/gen-th3-icons.js`, (2) compiles
  workspace + installed (which first syncs `Files/Icons` into EVERY MT4
  terminal hosting the project — see `Get-TerminalMql4DirsForProject`),
  (3) verifies the `.ex4` is fresh and each terminal copy is byte-identical.
  Use `-SkipIconRegen` to only resync + recompile.
- Then, in MT4: **remove & re-add the indicator** (or restart the terminal) —
  icons are embedded in the `.ex4` at compile time and MT4 only reads the
  `.ex4` when the indicator is attached; it never hot-swaps a replaced file.
  A raw MetaEditor F7 compile is safe only AFTER a deploy run synced the
  terminals (MetaEditor resolves `#resource` against the terminal's
  `MQL4\Files\Icons`, not this repo).
- No CI/test framework. Root `*_Test.mq4` files and `Biotak/Tests/*.mqh` audit
  modules exist for manual/ad-hoc checks. Real validation happens in MetaTrader 4:
  attach the compiled indicator and inspect the Experts tab / chart.

---

## 2. Where things go (map)

| What you are adding/fixing | Where it lives |
|---|---|
| New shared function/global/state | `Biotak/GlobalVariables.mqh` for indicator-wide runtime state; **panel-editable settings / mirrors / persistence → `Biotak/RuntimeSettings.mqh`** (NOT GlobalVariables); pure logic → own module (see ARCHITECTURE.md §3 rules: include guards, includes at top only, dependency direction bottom-up) |
| Panel-editable settings (mirrors of the MT4 inputs, `#define inpX gX` redirections, seeding, OV_ persistence, `GetTriggerRenderColor`) | `Biotak/RuntimeSettings.mqh` — the single settings owner; seed via `RuntimeSettingsInit()` in `OnInitHandler`, load/save via `RuntimeSettings(Load|Save)Overrides` |
| New calculation/level/zone logic | Correct layer module in `Biotak/` (Zones → `Zone*.mqh`, levels → `LevelPipeline.mqh`/`FactorMode.mqh`, TH math → `THCalculations.mqh`, base price → `BasePriceManager.mqh`) |
| UI/menu/panel behavior | `Biotak/BiotakMenu.mqh` (ring menu) / `BiotakPanels.mqh` (settings cards) / `BiotakKit.mqh` (shared UI helpers) |
| New icon/glyph/surface art | Generate with `node tools/gen-th3-icons.js` (glyphs, circ, badge, knobs, switches, panel cards) → `Files/Icons/`; center-orb art via `tools/make-orb-bow.ps1` ingest (see P-ICONS-04). `tools/gen-icons.ps1` / `gen-cards.ps1` are legacy — do not use |
| Geometry constants for UI | `Biotak/BiotakMenu.mqh` (`#define CIRC_*`, `CIRC_*_SIZE`) and `BiotakPanels.mqh` (`PNL_*`) — keep in sync with the BMP sizes |
| Docs | Architecture/rules → `ARCHITECTURE.md`; user/feature docs → Persian `.md` files kept in sync |
| Standalone test harness | Root `*_Test.mq4`; shared audit modules under `Biotak/Tests/` |

Icon filename ↔ ring feature mapping lives in `CircIconRes()` in
`Biotak/BiotakMenu.mqh`. Geometry constants (`CIRC_ICON_SIZE 28`,
`CIRC_BG_SIZE 52`, orb 56, ...) must match the generator output sizes.

### R-COMMIT — when to commit (one topic per commit, so nothing gets mixed)

- **One user request = one commit.** Finish the request completely (code +
  compile + the AGENTS.md rule/memory entry), commit it, THEN start the next
  request. Never carry two topics in one commit, and never start new work on
  a dirty tree — the previous session's View Lock removal vs Step Mode
  unification mix-up is why this rule exists.
- **Commit gate — all three must hold:** (1) full + lite compile
  `0 errors` (`./compile-th3-linux.sh all`); (2) `git status` and
  `git diff --ignore-cr-at-eol --name-only` show ONLY the intended files —
  never commit the P-BUILD-03 CRLF churn; (3) the memory for the change
  (R-* rule / log row in THIS file) rides IN the same commit, never alone.
- **Message style:** `feat(scope): short summary`, matching the log
  (`feat(step): ...`, `feat(panels): ...`). Use `feat!:` when a feature is
  retired/removed or behavior breaks. One line, no fluff.
- **Never commit:** uncompiled work, mixed topics ("also fixed X while here"),
  or build outputs (`.ex4`, `build-logs/` are gitignored and stay out).

### R-ICONS — icon rules (read before touching Files/Icons)

- `Files/Icons/*.bmp` are **32-bit BGRA with a real alpha channel**. MT4
  renders them because they are loaded via `#resource` + `::Files\Icons\...`.
  Do **not** run `convert_icons_24bit.py` / `gen_icons.py` on them — that
  flattens alpha and produces opaque tiles (see P-ICONS-01).
- **Canonical regeneration: `node tools/gen-th3-icons.js`** writes all 48
  BMPs (11 ring glyphs + circ/badge/knobs/switches + 10 opaque panel
  cards) into `Files/Icons`, in the amber-on-glass language shared with the
  sibling ichimoku project (same rendering engine, 4× supersampling, true
  alpha). Exception: `orb_bg.bmp` is NOT procedural — it embeds
  `tools/orb-bow-master.bgra` (see P-ICONS-04) — and `yy.bmp` is transparent.
  For the complete **regenerate → compile → sync-into-every-terminal
  → verify** flow run `tools/deploy.ps1` (see Build section).
- Legacy generators `tools/gen-icons.ps1`, `tools/gen-cards.ps1`,
  `convert_icons_24bit.py`, `gen_icons.py` are **deprecated** — their output
  flattened alpha or was judged not delicate/glassy enough (P-ICONS-01/02).
  Do not use them for the shipped set.
- **Glyph semantics (law): every ring glyph must depict the actual chart
  object its toggle draws** — TH = dotted horizontal levels (`dots`), never
  a wave (waves read as "trend"). Verify a redesign at byte level (ASCII
  dump of the 28px BMP), never by eyeballing an upscaled preview.

### R-RETIRED — retired features (commented out, never deleted)

- **TH3Tool is retired** (2026-09-04, user decision — the toggle/drag-draw
  behavior was broken and the tool is unwanted). Everything is commented in
  place with the `TH3TOOL-OFF:` marker — `Biotak/TH3Tool.mqh` + `Biotak/TH3/*`
  are excluded via the entry `.mq4` includes; ring slot (`RING_TH3`, ring is
  now 6 items), settings card 5, hotkeys (V/3/4/Backspace/ABCD routing), the
  `14) TH3 TOOL` + `15) AB=CD` input groups, validators, and seeding are all
  commented. Dormant remnants left compiling on purpose: `RuntimeSettings`
  mirrors/`FF_TH3_*`, `GlobalVariables` storage, palette/log/freq-index
  infra, `custom_*.bmp`. To restore: uncomment the `TH3TOOL-OFF:` sites
  (grep the marker) and re-add the include. Full+Lite compile 0 errors
  without the tool (ex4 ~903KB).

- **Ring-button badges are OFF** (2026-09-04, user decision — no "On" /
  value badges on ring buttons, only the on/off button state itself).
  Single gate: `CircHasBadge()` in `Biotak/BiotakMenu.mqh` returns `false`
  (`NOBADGES` marker); all create/show/move/update paths obey it, delete
  paths stay to purge badges from older versions. Panels still open via
  long-press; hover tooltips untouched.

- **TF-lock is keyboard-only** (2026-09-04 — old timeframe-lock (calc pinned
  to a TF) left the menu AND card 4: ring/card UI gone, but `G`-key toggle,
  `g_timeframeLocked` engine, GV persist and lock label stay untouched.
  Slot 4 was View Lock 2026-09-04 → 2026-09-05, now retired — see next rule.)

- **View Lock is retired** (2026-09-05, user decision — the ring button +
  card shown in the screenshot are unwanted). Everything is commented in
  place with the `VIEWLOCK-OFF:` marker: `CIR_VLOCK`/`RING_VLOCK` defines,
  `RingFeature` case, `CircFeatureOn/IconRes/CardIcon/BadgeText/Tooltip`,
  ring-click handler (ring is now 6 items: `RING_HTF`=4, `RING_TOOLS`=5),
  settings card 4 (`PnlRowDef/Title/Subtitle/DefVal/Current/Apply`;
  `g_PnlRows[4]` kept =1 dormant, panel keys never reorder), `V` hotkey
  (`inpViewLockKey`), and all `EventHandlers` behavior (OnInit restore,
  OnDeinit `REASON_CHARTCHANGE` capture, OnCalculate pending restore,
  anchor-line delete/drag handlers, `CHART_CHANGE` re-anchor, Q-reset
  disable). Dormant remnants left compiling on purpose (TH3TOOL-OFF
  pattern): `GlobalVariables` state (`g_viewLockEnabled/Anchor*/RestorePending`)
  + core fns (`ViewLockCapture/Restore/SetEnabled`, `ViewAnchorLineEnsure/Delete`)
  — nothing sets the flag anymore, it stays false. Purge paths stay ACTIVE
  to clean old charts: `CleanupAllGlobalVariables` entries 20-23, the Q-reset
  `GlobalVariableDel("Biotak_ViewLock/Anchor*")` lines, and the OnDeinit
  `ObjectDelete(g_viewAnchorLineName)`. To restore: uncomment the
  `VIEWLOCK-OFF:` sites (grep the marker). Full+Lite compile 0 errors
  without it (ex4 ~914KB/521KB).

- **Step Mode is ONE setting, three writers, one language**
  (2026-09-05 — the override layer is retired, see below; `GetCurrentStepMode()`
  in `UtilityFunctions.mqh` just returns the base `g_stepCalculationMode`
  (input-seeded, OV_ `SM` persisted). The E key, the Tools-ring step item, and
  panel card 9 row 0 (STEP MODE) all write the base with the SAME
  `TH→SS-LS→Combo→Factor→TH` cycle; card 9 row 1 is MAX LEVELS; Q resets both
  rows to factory like the panel Reset does. Names are the enum names
  everywhere (`TH/SS-LS/Combo/Factor`, badge shorts `TH/SS/Co/Fa`) — the old
  `Sub/Pat/Trd/Tr` labels were dead names from a pre-history enum, never
  reintroduce them.)
- **Step override is retired** (2026-09-05, user decision — the OVERRIDE row
  was a second setting for the same thing and confused everyone). Everything
  is commented in place with the `STEPOVERRIDE-OFF:` marker: `g_stepModeOverride`
  decl, `GetCurrentStepMode` branch, `StepOverride(FromOpt|Opt)` helpers,
  panel card 9 row 0 (card is now 2 rows: STEP MODE + MAX LEVELS). Rewritten
  (not commented) to the base: E-key cycle, Tools-ring cycle, `PnlRowDef/DefVal/
  Current/Apply` card 9, and the mode-label test harness. One-time migration
  in `OnInitHandler`: a leftover `Biotak_StepMode_` GV (0-3) is adopted as the
  base, then deleted and never read again. Purge paths stay ACTIVE:
  `CleanupAllGlobalVariables` entry, Q-reset + E/Tools `GlobalVariableDel`,
  for old charts. To restore: uncomment the `STEPOVERRIDE-OFF:` sites (grep
  the marker). Full+Lite compile 0 errors without it.

- **Open panels follow external changes; every writer confirms on-chart**
  (2026-09-05 — an open Step card stayed stale when E/Tools changed the mode:
  hotkeys never refresh panels, and MQL4 layering forbids it directly
  — `EventHandlers` is included BEFORE `BiotakPanels`, so it cannot call
  `PnlUpdateRow`. Fix is panel-side: `PnlSyncOpenStepRow()` in
  `BiotakPanels.mqh`, called from `RefreshKitOnBar()` (runs per-tick + 1s
  timer), change-guarded to one int compare. And every Step writer now pops
  the chart mode label (E already did; `PnlApply` card 9 row 0 and the
  Tools-ring step branch call `UpdateStepModeLabel()` too — safe because the
  redraw after only repositions via `RepositionAllOverlayLabels`). Rule for
  new work: any writer outside a panel that changes a panel-visible value
  must (1) add a change-guarded sync in the panel tick path, (2) pop the
  on-chart confirmation label.)

- **Step card shows the selected mode's own rows inline**
  (2026-09-05, user decision — tapping a STEP MODE segment selects the mode
  AND reveals that mode's settings right below it: TH has none (its flags
  are label settings, not levels — card stays STEP MODE + MAX LEVELS);
  SS-LS → LS FIRST; Combo → MODE/PRESET/COMP1 TF+STEP/OP/COMP2 ON+TF+STEP (new
  runtime mirrors); Factor → full Factor rows incl. COLOR. Card 9 has dynamic
  row count (`PnlRowsCount(9)` = 2 + section); MAX LEVELS floats last via
  `PnlStepMaxLevelsRow()` — never hardcode card-9 rows. Section rows delegate
  to their home cards (`PnlApply/Current/DefVal` → TH:3, SS-LS:1r7, Factor:10)
  so behavior can't diverge. Segment tap, E/Tools changes (`PnlSyncOpenStepRow`
  rebuilds) and Reset (recounts after row 0) all rebuild via `PnlOpen(9)`.
  Combo mirrors live in `RuntimeSettings.mqh` like all others (`FF_COMBO_*`,
  `OV_CM/CP/C1T/C1S/CO1/C2E/C2T/C2S`, Q-reset restores from factory).
  Full+Lite compile 0 errors.

- **Tools-ring Factor button is retired** (2026-09-05, user decision — its
  settings live inline in the Step card's Factor section now, so the button
  is redundant). Commented in place with the `FACTORBTN-OFF:` marker:
  `TOOL_FACTOR_OVERRIDE`/`TOOL_COUNT 3→2` (Tools = Pin + Step, layout spreads
  ±55° automatically), `ToolFeature`/`ToolPanel` cases, tap-cycle block,
  `CircFeatureOn`/`BadgeText`/`TooltipStatus`/`ItemTooltip`/`IconRes` cases.
  Dormant remnants left compiling on purpose: the `g_factorValueOverride`
  engine (`FactorMode.mqh` reads, `AdjustFactorValue`, GV persist/restore,
  Q-reset purge), Factor card 10 (the Step section delegates to its
  `PnlApply/Current/DefVal`), `factor_*.bmp`. To restore: uncomment the
  `FACTORBTN-OFF:` sites (grep the marker). Full+Lite compile 0 errors.

- **Ring tooltips are live status readouts** (2026-09-05 — hovering any ring /
  tools button shows `Name · <live status>` + the Click/Hold hints:
  ON/OFF states, TH mode (Off/Fractal/Standard/Both), HTF TF, Step mode,
  Factor value/Auto, Pin price, Tools open/closed. `CircTooltipStatus()` in
  `Biotak/BiotakMenu.mqh` builds the status; `CircItemTooltip()` embeds it.
  Freshness rides existing rails: every state change re-runs
  `CircConfigureIcon` (icon tooltip) + `CircUpdateItemState` /
  `ToolsUpdateItemState` (bg tooltip), and the per-tick
  `UpdateMenuSyncIfChanged` fingerprint already covers all status values, so
  hotkey/panel changes refresh tooltips too. MT4 renders `\n` in
  `OBJPROP_TOOLTIP` as multi-line.)

- **Menu hover shows a custom-drawn tooltip** (2026-09-05 — native
  `OBJPROP_TOOLTIP` hover text does not display in this environment, so the
  menu draws its own: dark chip + amber title fed by the same
  `CircItemTooltip()` live text, anchored above the hovered orb/ring/tools
  item, ZORDER 1700+ (above panels + palette popup).   `CircTipOnMove()` in
  `Biotak/BiotakMenu.mqh` runs on every mouse move (same-spot repeats
  skipped) but only ARMS the tip; `CircTipTick()` (per-tick, via
  `RefreshUIPerTick`) shows it after `CIRC_TIP_DELAY_MS` (1500) of
  stationary hover, so normal navigation never flashes it — any move,
  press, drag or armed long-press hides it instantly. `DeleteMenu()` deletes
  the tip objects. `CircTipRefresh()`
  (from the per-tick menu sync) keeps visible text fresh. Native
  `OBJPROP_TOOLTIP`s stay as fallback.)

- **COLOR rows have inline quick-pick swatches** (2026-09-04 — color picking
  without opening the popup: preview block + 6 curated swatches
  (`PNL_QSW_*`, `QuickPalColor()` in `BiotakPanels.mqh`) + PICK button for
  the full palette popup. One tap applies live (`PaletteApplyColor` +
  `PushPalRecent` + `PnlUpdateRow`), selection ring marks the active color.
  New widget suffixes (`Q0..Q5`, `PK`) MUST be added to `PnlDestroy`
  (P-UI-02 leak lesson).

- **Palette popup is compact-curated** (2026-09-04 — PALETTE tab = inline
  RECENT strip (12) + 12×5 curated grid (`PalQHue`/`PalQShade` map into the
  Material matrix, so `PalHandleClick` "s{r}_{c}" parsing is untouched);
  RECENT tab removed (2 tabs now). Fewer clicks: recents need no tab
  switch, targets are 20px. `PalW`/`PalH` derive from the new defines —
  mixer hit-testing follows automatically.

- **Palette popup: header names the live target, footer has transparency**
  (2026-09-04 — APPLY TO cycles 13 targets, so the header reads
  `PALETTE · <target>` + the button has a tooltip; footer `TR` track sets
  transparency by click (`PAL_FOP_*` geometry shared by draw/update/click).
  ONE user-facing language everywhere: TRANSPARENCY (0=solid, 100=gone) —
  panel sliders, palette footer/mixer, HTF card row all speak it
  (`PaletteKindTransparency`/`PaletteApplyTransparency`; engine stores like
  `g_HTFOpacity` are converted at the UI edge, never migrated). Targets
  without transparency show greyed `--` like the mixer does).

- **Transparency is per-color-target, one language, cached**
  (2026-09-04 — every COLOR row's target (SS/LS/custom-price/factor +
  trigger/lines/HTF) is adjustable from the palette footer TR track and
  mixer (`PaletteKindTransparency`/`PaletteApplyTransparency`, persisted
  via new `OV_SST/LST/CPT/FCT` keys, default 0 = solid so old charts are
  pixel-identical). Render getters (`GetSSRenderColor()` etc. in
  `RuntimeSettings.mqh`) blend toward the chart background with per-target
  static caches — recompute only when base/transparency/background change,
  so per-frame draws cost one syscall + compares (same as the existing
  trigger/lines helpers). ONE blend per color: zones keep their own
  transparency args — never blend an already-blended color. Panel keeps
   only its existing sliders; no new rows/inputs. Trigger LABEL COLOR row
   has no draw site (pre-existing) so it stays `--`.)

- **Base / Knot Measurement Tool = Tools slot 3, native-like drag, single-shot**
  (2026-09-05 drawer; 2026-09-06 drag gesture: press = corner 1, hold + move
  = live rubber-band + Entry/SL/TP, release = commit — exactly like MT4's own
  rectangle tool. Tap-tap still works (click 1 → hover preview → click 2).
  `BK_IDLE→ARMED→PREVIEW→IDLE`, single-shot auto-exit
  (commit AND cancel → `IDLE` + menu restore via `BaseKnotTakeRestoreFlag()`
  in `HandleUIChartEvent`, stray clicks draw nothing). Press never commits
  (only the release / next click does), so no double-commit; `g_bkHeld`
  tracks the held button, `g_bkLiveT/P` is the off-chart-release fallback.
  Sizing preview =
  dotted `PREVIEW` rect + LIVE Entry/SL/TP + info (`<prefix>_BK_LIVE_*`,
  direction re-resolved while sizing, wiped at commit/cancel/deinit);
  same-bar/zero-height commits rejected, preview kept. Committed boxes own
  children by shared id prefix (`<prefix>_BK_<id>_`): box drag re-syncs the
  Entry/SL/TP ray-right lines (`BaseKnotSync` on `OBJECT_DRAG`), box delete
  cascades (`ObjectsDeleteAll(pfx)`), the X delete badge is an `OBJ_BUTTON`
  re-glued on `CHART_CHANGE` + the 500ms tick (`BaseKnotSyncBadges`).
  Direction is AUTOMATIC at commit (no Buy/Sell badge — `NOBUYSELL`
  2026-09-06): box mid below live price = Buy, above = Sell; leftovers purged
  in `BaseKnotSync` + the CLICK handler. The
  session is consumed FIRST in `OnChartEventHandler` (500ms arm-guard on the
  CLICK fallback path, chart scroll locked with raw `Chart*` calls so Lite
  compiles menu-free — Lite keeps drag/delete/badges, arming is Full-only).
  Pips via `GetCachedPipSize()`, never hardcoded point math; TP = 2R.
  `TOOL_COUNT`-driven menu loops pick new tools up automatically; panel-less
  tools return `ToolPanel()==-1` and must skip long-press arming
  (`CircHandleMouseMove` guard) or the release click gets swallowed.)

- **Base/Knot is fully automatic — no Buy/Sell button, ever**
  (2026-09-06 — direction is decided ONCE at commit by
  `BaseKnotResolveDirection()` in `Biotak/BaseKnotTool.mqh` and FROZEN in the
  registry + chart-scoped GV: price above the box = Buy (Entry=top, SL=bottom,
  TP=top+2R), below = Sell (mirrored); a commit landing with the price INSIDE
  resolves by entry side (most recent of the last 128 closes outside the box:
  from below → Buy, from above → Sell; mid-vs-price fallback). Live ticks
  never recompute it (`BaseKnotSync` only reads the registry), so in-box price
  vibration cannot flicker the lines. Box ids are `"<commitTFmin>_<tick>[rNNN]"`
  — every tail split MUST use the last underscore (`BaseKnotSplitTail`), the
  first one is inside the id. Each box carries its commit-TF mask
  (`BaseKnotTFMask`: own + lower TFs, hidden above — no hairline boxes) and
  `BaseKnotPlaceBadges` ANDs it with on-screen state (never let badge code
  overwrite the mask with plain ALL/NO). NO magnet (`BKMAGNET-OFF`
  2026-09-06, user decision — snapping pulled corners to candle shadows so
  the box never landed where clicked: `BaseKnotSnapPrice()` returns the click
  untouched, exactly like MT4's own rectangle; body kept commented for a
  one-line restore). Info badge is chart-anchored
  `"[H Pips | R:R 1:N]"`; the X is the only pixel badge. Box delete cascades
  via one `ObjectsDeleteAll(pfx)`; a manually deleted CHILD self-heals via
  `BaseKnotSync`, trailing deletes of a gone box only mop up by prefix. The BK
  layer is INDEPENDENT: `HideAllTHObjects`, the L/F toggles,
  `DeleteAllIndicatorObjects` (non-deep), emergency + incremental cleanups and
  the generic OBJECT_DELETE redraw trigger all skip `"_BK_"` names — only
  `REASON_REMOVE` (deep) wipes user drawings. Registry rebuilds from box
  anchors via `BaseKnotLazyInit` (dir from GV, TF from the id), so boxes
  survive TF-switches and parameter rebuilds.)

- **HTF boxes self-heal after timeframe switches — never rely on init-time draws**
  (2026-09-05 — HTF candles vanished on every TF switch until a manual off/on
  toggle: `OnDeinit(REASON_CHARTCHANGE)` deletes all HTF objects, `OnInit` only
  re-resolves `g_HTFPeriod` and draws nothing, and the per-tick updater maintains
  only the forming candle (index 0), so history boxes never came back; worse, HTF
  history is often not loaded yet right after a switch (`iBars==0`, seconds longer
  on weak PCs). Fix is `HTFEnsureDrawn()` in `Biotak/HTFCandles.mqh`, called from
  `RefreshUIPerTick()` (per-tick + 1s timer, so it retries with zero ticks too):
  re-resolves the effective TF every tick (O(1) steady state), full-redraws at most
  once/sec only when the TF changed / box 0 is missing / first run, draws only when
  `iBars`+`iTime` prove data-ready (else retries), deletes once when hidden-by-design
  (TF>=chart). Rule for new work: any chart-object layer that `OnDeinit` wipes must
  re-ensure itself from the tick/timer path with change-guarded, data-ready-gated
  redraws — never a draw-once at init.)

---

## 3. Recurring problems (log — append, never solve twice)

| ID | Symptom | Root cause | Fix — do THIS | Date |
|----|---------|------------|---------------|------|
| P-ICONS-01 | Panel icons look flat/weak: opaque square tiles, no rounded corners, hard edges; sibling `../ichimoku` icons (gold/glass, 32-bit) look better | The shipped icons were flattened to 24-bit (no alpha) by `convert_icons_24bit.py` / `gen_icons.py` — glyph background baked in, alpha destroyed | Regenerate the full set: `node tools/gen-th3-icons.js`, then recompile the `.mq4` (`compile-th3.ps1`). Keep BMPs 32-bit BGRA with real alpha. | 2026-09-03 |
| P-ICONS-02 | A first "premium" redo (from `tools/gen-icons.ps1`) was judged NOT delicate/glassy — coarse/harsh fills, rough shapes; indicator also felt slower | PS generator drew at native size without the 4× supersampled vector/glass engine; glass skins were heavy opaque discs | Use the JS engine port: `node tools/gen-th3-icons.js` — thin delicate glyphs, 4× AA, true alpha, glass circ/orb skins, and **opaque** panel cards (fast redraw). `gen-icons.ps1`/`gen-cards.ps1` are legacy. | 2026-09-03 |
| P-ICONS-03 | After regenerating + compiling, MT4 STILL showed the old icons on the chart | (a) The broker terminal hosts the project as `MQL4\Indicators\BiotakProject` (a symlink to this repo) but had a STALE `MQL4\Files\Icons` — compiling from that terminal's MetaEditor silently embedded old BMPs (compile-th3.ps1 only synced the compiler's own terminal); (b) MT4 loads the `.ex4` only at attach time — a replaced `.ex4` is never hot-swapped into a running indicator | (a) `compile-th3.ps1` now syncs `Files\Icons` into **every** terminal hosting the project (`Get-TerminalMql4DirsForProject`) before each compile — run `powershell -File compile-th3.ps1 -Project all`; (b) after deploying, **remove & re-add the indicator** on the chart (or restart MT4) so the new embedded resources load | 2026-09-03 |
| P-TOOL-01 | `tools/gen-cards.ps1` wrote cards into `tools/Files/Icons` (a stray folder) instead of `Files/Icons` | Its default `$OutputDir` used `Join-Path $PSScriptRoot 'Files\Icons'` while the script lives in `tools/` | Fixed (now `..\Files\Icons`). If it regresses, always call with explicit `-OutputDir`. | 2026-09-03 |
| P-BUILD-01 | After icon edits the terminal still shows the old icons | Icons are `#resource`-embedded at **compile time**; nothing is read from disk at runtime | Always recompile the entry `.mq4` after any BMP change: `compile-th3.ps1`. | 2026-09-03 |
| P-DOCS-01 | Docs drift between Persian and English copies; `DEVELOPMENT_GUIDE_FA.md` was once corrupted/unreadable and rewritten | No sync rule | Keep `ARCHITECTURE.md` the source of truth for structure/rules; update FA docs in the same change when behavior/docs change. | 2026-09-03 |
| P-ARCH-01 | God files and duplicate formula tables accumulating (`ExtendedDrawingFunctions.mqh`, `TH3Tool.mqh`, ...; `GetStepSizeForFactorBasis` vs `GetFactorModeAutoStepSize`) | Organic growth | See ARCHITECTURE.md §4 debt table — unify behind single source of truth (e.g. `FactorMode.mqh`) when touching those paths. | 2026-09-03 |
| P-SET-01 | MT4 Inputs-dialog changes to panel-editable settings (Max Levels, SS/LS/trigger/factor colors & widths, ...) had no effect on re-attach; some reads used raw inputs while others used mirrors (split-brain); Lite did not compile | Runtime mirrors + `#define inpX gX` were appended to the end of `GlobalVariables.mqh` with NO seeding from the real `input` values, so mirrors kept hard-coded defaults (inputs dead); persistence lived in `BiotakKit.mqh`; `GetTriggerRenderColor` stayed on raw inputs; `EnsureIntervalsCache` was swept under `#ifndef BUILD_LITE` breaking Lite | Mirrors/redirections/seeding/persistence live in `Biotak/RuntimeSettings.mqh` only. Seed FIRST in `RuntimeSettingsInit()` (first line of `OnInitHandler`) — never reference an `inpX` in a seed below the `#define`s (silent no-op). Set the persist prefix via `RuntimeSettingsSetPersistPrefix()` from UI init before load/save. Keep shared helpers used by Lite (e.g. `EnsureIntervalsCache`) OUTSIDE `#ifndef BUILD_LITE`. | 2026-09-03 |
| P-UI-01 | The ring menu could NOT be dragged while collapsed (hidden) — the orb grabbed nothing; plain orb clicks also intermittently did nothing (menu wouldn't open/close) | `CircHandleMouseMove` early-returned when `!g_UI.menuVisible` BEFORE the orb-grab logic (hover guard was meant to skip hover, but it also blocked press); `UISuppressNextClick()` fired on EVERY button-up — including plain clicks with no drag — so a release that emitted a final MOUSE_MOVE (cursor still moving) ate the click; same over-suppression ate ring-item clicks released before the 250ms hold | In `CircHandleMouseMove`: (a) the hidden-menu guard must pass `pressStart` through to the orb-grab logic and ring-item long-press must be guarded by `g_UI.menuVisible`; (b) call `UISuppressNextClick()` on orb release ONLY when `g_OrbWasDragged`, and on long-press release ONLY when `g_LongPressFired`. Never suppress on every button-up. | 2026-09-03 | | P-UI-02 | Settings-panel Reset did nothing for most rows; Q-key "Reset All Overrides" silently kept current trigger/lines/ATR/TH state; segment buttons W1/MN1 leaked on screen after closing the Timeframe Lock panel; MAGNET edits were lost on re-attach | After the `#define inpX gX` redirection (P-SET-01), reading `inpX` in `PnlDefVal` / the Q handler reads the CURRENT runtime copy — Reset assignments were self-assign no-ops; `PnlDestroy` only deleted segments `C0..C7` but the TF Lock row has 10 options; magnet rows return `REFRESH_NONE` so they never reach the OV_ saver (ApplyRefreshFlags is the only saver) | Reset/restore must read `FactoryDefault(FF_*)` captures from `RuntimeSettingsInit` (captured BEFORE the #define block — never read `inpX` below it); delete segments up to `C11` in `PnlDestroy`; any `PnlApply` row that changes state must persist via `RuntimeSettingsSaveOverridesThrottled()` even when it returns `REFRESH_NONE` | 2026-09-03 |
 | P-UI-03 | Toggling the trigger overlay (T / "Trigger" ring item) changed the trigger-subdivision LINES between two structure levels: trigger styling when ON, mode-fallback/SS-LS colors when OFF; a first fix made it worse by DELETING those lines with the zones, so T also hid a line | `ClassifyLevels` styled every non-structure (`isTrigger`) level with TWO palettes depending on `triggerEnabled`, and the line objects built in `BuildZonesAndLines` inherit that per-level color — so the trigger switch, meant as a ZONE-only overlay, leaked into line color (and into line visibility via the delete-guard) | The trigger switch must ONLY gate the trigger ZONES (`RenderZones` delete when `!triggerEnabled`). Trigger-subdivision levels ALWAYS take the Trigger appearance settings in `ClassifyLevels` (no fallback flip), `ClassifyLevelsAlternating` must skip `isTrigger` levels unconditionally, and `RenderTriggerLines` must never delete lines on trigger state — line visibility belongs to L / `g_linesVisible` alone. | 2026-09-03 |
 | P-UI-04 | Line appearance split across two families (trigger-subdivision lines used trigger color/style, structure-interval lines used L1-L5 colors) with the controls buried in the Trigger card — so T restyled lines and SS/LS COLOR rows did nothing (every non-structure level is `isTrigger`, the alternating override skipped them all) | Pipeline lines inherit `levelColor/Style/Width` from the classified upper level while zones use `zoneColor` — one struct, two visual channels, edited from different cards | ALL lines share the unified [08.4] settings (`g_lineColor/Style/Width/Transparency` → `GetLineRenderColor()`, Lines card 7, `inpLine*` inputs with OV_ `LNW/LNS/LNC/LNT` + upgrade fallback from `TW/TS/TC/TT`); `ClassifyLevels` sets `levelColor` unified for every level while `zoneColor` keeps family identity (structure L-colors / `GetTriggerRenderColor()`); Trigger card 0 is zones-only (TRANSPARENCY/COLOR/LABEL/SHOW); T gates only `RenderZones`. `inpTriggerWidth/Style` + SS/LS colors are legacy — do NOT rewire lines to them. | 2026-09-03 |
| P-ICONS-04 | Custom center-orb art (bow medallion) got wiped on regen, and the yin-yang overlay covered the orb center | The orb is TWO stacked objects: 56px `orb_bg.bmp` (`CircOrbBg`) + 32px `yy.bmp` (`CircOrbIcon`); `gen-th3-icons.js` regenerated both procedurally | Ingest flow only: `tools/make-orb-bow.ps1` (artwork PNG with baked checkerboard → `tools/orb-bow-clean.png` 256 straight-alpha → `tools/orb-bow-master.bgra` 56 premultiplied, the source of truth) → `node tools/gen-th3-icons.js` embeds the master into `orb_bg.bmp` and writes `yy.bmp` FULLY TRANSPARENT (overlay object stays for hit-testing, renders nothing) → `tools/deploy.ps1` → remove & re-add indicator. Never hand-edit `orb_bg.bmp`. | 2026-09-03 |
| P-ICONS-05 | آرب روی چارت تیره مربع سفید / کاشی شسته‌شده است؛ ۷۲px هیچ شباهتی به آرت‌ورک ۱۲۵۴px ندارد | ریسمپل دو مرحله‌ای (کراپ←۲۵۶←۷۲) با ماسک بدون هیچ راستی‌آزمایی خروجی؛ Lift سنگین سیاهی‌ها را می‌شست | ریسンプル تک‌مرحله‌ای مستقیم از کراپ سورس برای هر دو سایز (`Build-OrbPixels` در `tools/make-orb-bow.ps1`)، ایندکس stride-safe، خودآزمایی `Test-OrbDisc` (گوشه شفاف/مرکز مات — در غیر این صورت throw)، Lift ‏0.06. راستی‌آزمایی با اسکرین‌شات headless کروم از `tools/orb-preview.html` | 2026-09-04 |
| P-TOOL-02 | PS script throws `Method invocation failed because [System.Object[]] does not contain a method named 'op_Subtraction'` on a line that looks like plain scalar arithmetic | Windows PowerShell 5.1 misparses `-`/`+` inside a MULTI-element `@()` literal — verified: `@($H - $off, $H, $H + $off)` and `@([int]($H/2) - $off, ...)` throw, `@($lo, $mid, $hi)` of precomputed scalars works; method-call commas / `-f` / `New-Object Type(a,b)` / `+=` are all safe. Separately, `$x++` inside a function emits values into its return array, and the agent `bash` tool strips `$vars` from inline command strings | Precompute arithmetic into temp scalars, then `@($t1, $t2, $t3)`; use `$run += 1`, never `$run++`, inside functions that return values; keep ALL PowerShell code containing `$` variables in `.ps1` files and run them via `-File` — never pass `$...` inline in a `bash` tool command (it arrives stripped). | 2026-09-03 |
| P-ICONS-06 | Feeding an already-cut-out orb source (remove.bg BMP/PNG with REAL alpha, e.g. root `trigger-removebg-preview.bmp` 500x500) through `tools/make-orb-bow.ps1` silently reused the checkerboard path: `Test-Checker` ignores the alpha channel so transparent-black corners read as "dark checker", and `Build-OrbPixels` then imposed its own feathered circular mask over the artist's feathered edge | Checker-oriented ingest assumed every source has a baked background; no alpha detection existed | `make-orb-bow.ps1` now auto-detects via `Test-HasRealAlpha` (corners A<10 + center A>200) → `Find-AlphaExtent` (alpha bounding-box fit) + `Build-OrbPixelsAlpha` (GDI+ bicubic keeps source alpha, Sat/Lift touch RGB only, NO mask override). Run as `powershell -File tools\make-orb-bow.ps1 -Source "trigger-removebg-preview.bmp"`, then `tools\deploy.ps1`. | 2026-09-04 |
| P-ICONS-07 | Orb "shrink" via larger `CropPad` did NOTHING three times in a row: ingests with 1.09/1.20/1.45 produced byte-identical `orb_bg.bmp` (proven by MD5, not by eye — eyeballing previews against the viewer background fooled the check) | The source-region crop CLAMPS to the image bounds (`side=min(2*r*pad, W)`); for the tight 500px cut-out (r=236) even 1.09 already clamps to the full frame, so CropPad was a silent no-op | Visual size is controlled ONLY by `-OrbFill` (default 0.72 ≈ 52px medallion), applied AFTER resampling via `Resize-OrbToFill` (bicubic composite centered on transparent canvas). After every ingest, prove change numerically: MD5 of `orb_bg.bmp` must differ AND opaque-box measure (`verify-size` pattern: old 69px → new 50px). `CropPad` is source-region selection only. | 2026-09-04 |
| P-TOOL-03 | `New-Object Bitmap($w * $scale, $h * $scale, ...)` throws `op_Multiply` on `Object[]` — yet P-TOOL-02 claimed "`New-Object Type(a,b)` safe" | That claim only holds for PLAIN variables. Constructor-arg parens with COMMAS form an array-literal context like `@()` (P-TOOL-02), so arithmetic inside (`$w * $scale`) misparses the same way | Precompute EVERY arithmetic arg into temp scalars on their own lines (`$bw = [int]$w * [int]$scale`), then `New-Object Bitmap($bw, $bh, ...)`. Same for `DrawImage($bmp, 0, 0, $bw, $bh)`. | 2026-09-04 |
| P-BUILD-02 | Linux/Bottles: `bottles-cli run -e metaeditor ... /compile:...` exits 0 but writes NO `.ex4`/log; Wine `if exist` on host paths (Z:\ or a symlink into the repo) succeeds yet open/read FAILS silently (proven: `type` through `Indicators\BiotakProject` symlink → "Failed to open"; Z:\ compile of a trivial file → nothing) | (a) Wine under Bottles/Flatpak cannot read host files (Z:\ or symlink targets) — silent no-op, exit 0; (b) `bottles-cli run -e` with a unix-path exe routes via winebridge whose `run_exe` takes NO CLI args (verified in Bottles source), so /compile flags never arrive; (c) `#resource \Files\Icons\...` resolves relative to the SOURCE dir — a build dir without `Files/Icons` fails with 45× error 310 | Use `compile-th3-linux.sh` ONLY on Linux: rsync-mirrors repo (incl. `Files/Icons`) into in-bottle `C:\th3build` AND the REAL `Indicators\BiotakProject` dir (never a symlink — Wine can't traverse it), drives metaeditor via a generated CRLF `.bat` (quoting lives in the `.bat`, never on the CLI), copies `.ex4`+log back to repo and deploys `.ex4` to the terminal. Manual MetaEditor F7 on `Indicators\BiotakProject\*.mq4` (C: real files) verified 0 errors. Never pass Z:\ paths to metaeditor. | 2026-09-05 |
| P-BUILD-03 | `git status` shows the whole tree modified (~90 files, ±40k lines) with zero real change | Line-ending churn: worktree files got CRLF-ified (repo convention is LF everywhere; BOM only where HEAD has it — e.g. `.ps1` yes, `.mqh`/`.md` no). Diagnose with `git diff --ignore-cr-at-eol --name-only` (2026-09-05: only `AGENTS.md` was real) | NEVER commit that noise: save the real hunks (`git diff <file> > fix.patch`), `git checkout -- .`, re-apply, normalize worktree (`\r\n`→`\n`, strip stray BOMs to match HEAD), and confirm `git diff --stat` shows only the real lines before staging. | 2026-09-05 |
| P-BUILD-04 | Every `./compile-th3-linux.sh` run CLOSED the running MT4 terminal (user had to reopen it) | The old script compiled INSIDE the live `Tradeing` bottle via `bottles-cli run -e <bat>`. Every `flatpak run` sandbox gets a PRIVATE `/tmp` (proven: host `/tmp` probe invisible inside) while the wineserver socket lives in `/tmp` — so the compile's sandbox started a SECOND wineserver on the SAME live prefix, which kills the terminal. Separately: passing a spaced `/compile:` path as a direct wine argv silently compiles NOTHING (BOM-only log, exit 0, no `.ex4` — verified twice); metaeditor needs the QUOTED path from a CRLF `.bat` run through `cmd /c` | `compile-th3-linux.sh` now compiles in an ISOLATED Wine prefix (`<Bottles-data>/th3build-wine`, override via `TH3_WINEPREFIX`, `wineboot --init` once, own `C:\mt4\metaeditor.exe` copy + `C:\th3build` mirror) driven by `flatpak run --command=wine ... cmd /c C:\th3build\compile.bat` (quoting lives in the `.bat`, never on the CLI). The live bottle is only touched by plain file copies (source/icon sync in, `.ex4` deploy out) — terminal stays open (same PID before/after, full+lite 0 errors). Legacy `C:\th3build` + `.bat` in the live bottle are auto-removed. Never compile inside the live bottle again. | 2026-09-05 |
| P-HTF-01 | HTF candles gone after switching to a higher chart TF until manual off/on toggle | `OnDeinit(REASON_CHARTCHANGE)` deletes all HTF objects; `OnInit` re-resolves `g_HTFPeriod` but draws nothing; per-tick updater only maintains forming candle idx0; HTF history not yet loaded right after a switch (`iBars==0`, longer on weak PCs) so even a one-shot init draw would silently miss | `HTFEnsureDrawn()` in `Biotak/HTFCandles.mqh`, called from `RefreshUIPerTick()`: per-tick TF re-resolve (O(1)), full redraw at most once/sec only when TF changed / box 0 missing / first run, data-ready gate (`iBars`+`iTime`) with automatic retry, once-only delete when hidden-by-design | 2026-09-05 |
| P-HTF-02 | Manual HTF timeframe silently reverts to auto on every TF-switch/re-attach; HTF draw paths could use a stale cached period; full draw left the forming-candle cache stale | `g_HTFIsAuto`/`g_HTFPeriod` were never persisted (`Save/Init/CleanupHTFCandlesGVs` missed them) and `UpdateHTFFormingCandle`/`DrawHTFCandles` read the cached `g_HTFPeriod` instead of the fresh `ResolveHTFPeriod()` | Persist `IsAuto`+`Period` GVs (restore in `InitializeHTFCandles`, recompute only when auto); draw paths use `ResolveHTFPeriod()`; full draw syncs the forming cache and `RefreshHTFCandles` resets it. Single engine is `HTFEnsureDrawn()` — do not add a second per-tick HTF sync. | 2026-09-05 |
| P-HTF-03 | HTF history froze one bar behind after every new HTF bar; `ShowBody=false`/doji caused a full 200-bar redraw EVERY second; opacity/width slider drags froze weak PCs (600 objects delete+recreated per step + flicker); `DeleteHTFCandles` with an empty prefix matches every chart object | Index-based history was never rebuilt on HTF bar roll; the steady probe checked only `prefix+"0"` which never exists without bodies (or a wickless doji); `RefreshHTFCandles` did a blind delete+draw; `StringFind(name,"")==0` is true for all names | Bar-roll detection via the forming-cache open time (`s_drawnBar0`, zero extra syscalls); `HTFAnyBoxesExist()` samples bars 0..2 across all name shapes; in-place upsert + trailing prune only (`Draw/Refresh` return the drawn count, `-1` = not ready, state advances only on success + `ChartRedraw`); empty-prefix guards in every HTF delete path | 2026-09-05 |
| P-UI-05 | Typing hex (A-F) fired hotkeys; TF-switch/remove with open panel killed chart scroll forever; ghost panel after TF-switch; panel draggable off-screen; blank `inpObjectPrefix` wipes the chart; news/gap fired 50 alert popups | Main KEYDOWN never checked `g_PalHexFocus`; chart-prop statics reset on reload so the watchdog couldn't restore; panel objects survive CHARTCHANGE while state resets; `PnlMoveBy` unclamped; no prefix validation; per-(bar,level) alert key has no global cap | `#ifndef BUILD_LITE` hex-focus early-return (Full-only symbol); `CleanupUIStates` drains both chart locks on every reason; `InitializeUIStates` purges orphan `Pnl`/`Pal_` objects; clamp-before-move in `PnlMoveBy` + `PnlClampOpenPanel` on CHART_CHANGE; reject empty prefix in `ValidateInputs` + guard deletes; alert governor: 10/bar max, 800ms spacing, 250ms-cached bar time | 2026-09-05 |
| P-BK-01 | BK boxes vanished on TF-switch / param change / 1h after drawing / on L or F; child-line delete left a permanent hole; TF-bearing ids broke first-underscore parsing; badge code would clobber the TF mask with plain ALL/NO; BK deletes flagged a full level redraw | `DeleteAllIndicatorObjects` blanket-wiped the prefix (BK included) on every CHARTCHANGE/PARAMETERS deinit; `RunIncrementalObjectCleanup` expiry (1h) matched BK anchors; L/F/Hide loops had no BK exclusion; child OBJECT_DELETE was swallowed as no-op; tail split at the FIRST `_` cut TF-bearing ids; `PlaceBadges` wrote raw ALL/NO; generic OBJECT_DELETE branch redrew levels for BK names | BK is an independent layer: every wipe/hide/toggle/cleanup path skips `"_BK_"` names (only REASON_REMOVE deep-wipes); child delete self-heals via `BaseKnotSync`, gone-box trails mop up by prefix; split tails at the LAST `_` (`BaseKnotSplitTail`); `PlaceBadges` ANDs the commit-TF mask with on-screen state; generic OBJECT_DELETE ignores BK names | 2026-09-06 |
| P-BK-02 | Bulletproof audit: ghost preview rect after TF-switch mid-draw; chart scroll stuck OFF after removing the indicator mid-session; mouse-move storm (rubber-band ChartRedraw per event) pins weak CPUs; menu hover/drag/long-press interfered with the draw gesture; orphan `Biotak_BK_*` GVs accumulated | Transient PREVIEW/HINT survived non-deep deinit (new instance starts IDLE, nothing owned them); scroll/context restore lived only in Cancel; rubber-band had no throttle; `HandleUIChartEvent` fed every move to the menu even with the ring hidden | `BaseKnotOnDeinit(reason)` (hooked first in `OnDeinitHandler`): restores chart props when armed-ever (`g_bkTouched`), kills transients, drops stale restore flag; `LazyInit` purges transients + sweeps chart-orphan BK GVs; rubber-band throttled 30 ms (swallow, no redraw); `HandleUIChartEvent` skips `CircHandleMouseMove` while the session is active (orb-click exit + panels untouched) | 2026-09-06 |


> When you close a new recurring issue, add the next row above (highest
> `P-####-##`). One line per distinct trap is enough — the point is that a
> future session applies the fix, not that it re-investigates.

---

## 4. Sibling reference project

`../ichimoku` (same Desktop/Trading family) is the closest reference: same UI
geometry (identical `CIRC_*`/orb constants), same `#resource` icon approach,
and its own `AGENTS.md`. When unsure how TH3's ring/panels should look or
behave, compare against it — but keep TH3 feature icons (zone/step/factor/
tools) TH3-specific.
