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
8. **Learn automatically — apply LEARNING.md without being told.** Before
   implementing, check whether the task matches a LEARNING.md pattern (§1-§5)
   and build it that way from the start; after implementing, run the §4/§5
   checklists against the change and fix deviations in the SAME commit.
   The user must never have to demand a pattern that is already written down.
9. **Session start = `git status` first.** Never edit on a dirty tree without
   the user's explicit approval — report what is dirty and ask how to proceed.
10. **Memory-file edits must be verified immediately.** After editing
    AGENTS.md/LEARNING.md, `git diff` that file at once and confirm only the
    intended hunks changed; anchor edits on short unique substrings — never
    reconstruct long single-line table rows (a corrupted row is worse than
    a missing one).

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
- **Commit gate — all four must hold:** (1) full + lite compile
  `0 errors` (`./compile-th3-linux.sh all`); (2) `git status` and
  `git diff --ignore-cr-at-eol --name-only` show ONLY the intended files —
  never commit the P-BUILD-03 CRLF churn; (3) the memory for the change
  (R-* rule / log row in THIS file) rides IN the same commit, never alone;
  (4) the LEARNING.md §4/§5 self-check passes for the change (or the
  deviation is recorded as a new P-row the same commit).
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
   Committed-box look (TV Style tab): BORDER COLOR / WIDTH / STYLE /
  BORDER TR + FILL COLOR / FILL TR (bucket — default invisible, see below) +
  TARGET R (TP = Entry + R×N, 1-4) + ENTRY/STOP/  TARGET line COLORS + user
  TEXT (content per-box in its `TEXT` object; SIZE 10 / B|I / ALIGN Right /
  VALIGN Inside / COLOR white) live in `RuntimeSettings.mqh`
  (`g_boxBorder*`, `g_boxFill*`, `g_bkTargetR/Entry/Stop/TargetColor`,
  `g_bkText*/Bold/Italic/Align`, `g_bkVAlign`, `FF_BOX_*/FF_BK_*`,
  `OV_BXW/BXS/BXC/BXT/BXF/BXFT/BXR/BXE/BXL/BXG/BXI/
  BXTX/BXTS/BXBO/BXIT/BXAL/BXVA`, inputs `[08.5]`),
  rendered via `GetBoxBorderRenderColor()` / `GetBoxFillRenderColor()`
  (one-language bg blend, cached; line/text colors are solid), applied at
  commit + `BaseKnotSync` (incl. live sizing preview) + live via
  `BaseKnotRestyleAll()`, edited from the Base Box style card 12
  (tabbed Style|Text|Setup — row 0 TAB segments, sections delegate via
  `BkSec(RowDef|Current|Apply|DefVal|ColorKind|DefColor)` like the Step card;
  TEMPLATE Amber|Ocean|Mono|Custom = TV Template dropdown; card skins key on
  ROW COUNT, not id — tallest tab is 7 rows so existing skins suffice).
  Info label is non-intrusive by
  default (Auto): visible live while sizing + 4 s grace after commit
  (`commitMs` in the registry, `BaseKnotInfoVisible()`, hidden by the 500 ms
  `SyncBadges` pump — inherited boxes get `commitMs=0` so old charts clean
  up without a flash); full numbers always ride the box/edge hover tooltips.
  Card 12 opens from the Tools-ring box button; press-hold on a committed
  box opens the BASE BOX MINI (item 13) INSTEAD, anchored next to the held
  box — **R-BKSTRIP (2026-09-07): a compact horizontal TV-style icon strip,
  NOT a row-card**. `PnlCreate(13)` → `BkMiniStripCreate`; strip presses
  route to `BkMiniStripPress` by slot rects (`BkMiniSlot` — the icon buttons
  are OBJ_BITMAP_LABEL glyphs, which fire no OBJECT_CLICK; objects are
  head-named `Pnl13_TB*`, purged in `PnlDestroy`). **R-BKTV (2026-09-07,
  supersedes the v1 strip: cycles→▾ dropdowns, 6→8 slots, done retired):**
  `[pencil → border palette] [bucket → fill palette] [T → Text tab]
  [style ▾] [width Npx ▾] [padlock] [trash] [••• → card 12]`
  on a 380px `bk_strip.bmp` (`PNL_TB_W`; `PnlPanelW(13)` — never `PNL_WEL`).
  The glyphs are the `bk_*.bmp` TV-style set (24px: pencil/bucket/T + 5
  styles + 5 widths + lock off/on + trash + more) — all generated by
  `tools/gen-th3-icons.js`, never hand-made; style/width/lock variants swap
  at runtime like the ring `_on/_off` skins. Pencil/bucket/T carry a LIVE
  color underline bar (TV underlines, `TBbar0/1/2` recolored in
  `BkMiniRefresh`); STYLE/WIDTH open TV popovers (`BkDdOpen/Hit`,
  `bk_dd.bmp`, labels `Line/Dashed line/Dotted line…`, `1px…5px`, dark-pill
  selection) instead of cycling; outside chart click / Esc dismisses — with
  a 4-guard discipline (2026-09-07 — the release ending the opening hold
  lands on the box = outside the strip and ate its own toolbar):
  `s_BkFireReleasePending` (one-shot, set in `BkHoldFire`, consumed by EVERY
  click incl. OBJECT_CLICK, cleared on every new press) skips the opening
  release; press-down→release distance >`BK_CLICK_SLOP` (10px, read from the
  latch BEFORE `BkHoldOnBoxUp` clears it) is a drag end, never a click;
  right-clicks never dismiss; taps on the HELD box itself never dismiss
  (re-hit-test via `BaseKnotBoxAt`, visible-only). The strip FOLLOWS a
  dragged box (`BkStripFollow` — primarily on the drag EVENT itself
  (`OBJECT_DRAG` in `HandleUIChartEvent`: consumed ≠ hidden, the entry
  forwards every event to both handlers; 30ms throttle + explicit `TB*`
  move list via `BkStripMoveBy`, never a full-chart scan; per-tick heal
  stays as fallback; 4px dead band; closes ▾ + orphaned palette on
  move; full pattern: `LEARNING.md` §1), closes for TF-hidden boxes
  (`BaseKnotVisibleNow` — also guards
  `BkHoldFire` against flash-opens), and dies when arming the draw tool
  (`PnlCloseAll` in the `CIR_BASEKNOT` menu branch). Every slot uses the
  SAME mirrors as card
  12 (never duplicated) and restyles every box live via
  `BaseKnotRestyleAll`, returning `REFRESH_BUFFERS` so `OV_*` persistence
  rides `ApplyRefreshFlags`.
  The strip re-anchors next to the held box on EVERY open (above its
  top-right corner, flips below without room; `BkHoldFire` computes pixels
  via `ChartTimePriceToXY`) and ignores panel presses in `BkHoldLatch` (it
  often floats above its own box — no mid-read refire). It is NOT
  header-draggable (`PnlHeaderHit` refuses item 13) and `PnlCreate(13)`
  skips `PnlComputePosition`, so BkHoldFire's box-relative anchor always
  wins. Geometry callers go through `PnlPanelH(13)=PNL_TB_H` (58px) /
  `PnlPanelW` — never the row-card formula. Toolbar repaint =
  `BkMiniRefresh` (reached from `PnlUpdateRow(13,row)`, so palette
  color/transparency picks land there).
  LOCK is per-box (`locked` in the registry, rides the handle's own
  SELECTABLE bit — no GV, survives TF-switch/restart; `Sync` heals it,
  drag swallows locked boxes; hold still opens the mini strip so a locked
  box can always be unlocked). Strip LOCK/✕ act on `g_BkMiniBox` (set at
  hold, validated on every use; a gone box closes the strip).
  The hold is the ONE box gesture (500ms/8px — P-UI-14: 250ms fired on
  press-pause-drags, so box hold (`BK_HOLD_MS`) and ring long-press
  (`LONG_PRESS_TIME`) share one deliberate 500ms language; any >8px move
  before the delay cancels the pending hold, so drags never open it;
  `BkHoldLatch/Poll/Fire` in
  `BiotakPanels.mqh` — passive observer, never consumes; hit-test via
  `BaseKnotBoxAt()` in the domain layer so Lite stays UI-free; P-BK-03/P-BK-05).
  The card fires WHILE HELD
  (event-driven on tremor moves + KEYSTATE-free poll for zero-move presses);
  release opens nothing; Shift+click instant and the release-leg are removed
   (they raced the hold and confused taps with holds). Hollow-by-construction
  (P-BK-06): the BOX rect is only an invisible drag handle (chart-bg fill) —
  the VISIBLE border is 4 `OBJ_TREND` edges (`BaseKnotDrawEdges`, same fix as
  `ZoneFactory` — some MT4 builds render `OBJ_RECTANGLE` filled even with
  `FILL=false`), so boxes are border-only on every build; preview is dotted
  edges too (no rect). **R-BKTV (2026-09-07): the BOX rect is now the FILL
  layer too** (`BaseKnotStyleBox`: FILL true + `GetBoxFillRenderColor()` when
  fill visible, bg + FILL false when invisible — the default FILL TR=100, so
  pre-fill charts stay pixel-identical hollow); edges stay the border on
  every build. `BaseKnotSyncBadges()` (500 ms pump) re-asserts the live fill
  look (`BaseKnotFillHealed`) + rebuilds missing edges, so old boxes heal
  live without re-attach. The 250 ms poll cadence
  (`EventSetMillisecondTimer`, safe: every OnTimer callee is time-gated /
  idempotent) keeps hold-to-open snappy on tick-less (weekend) charts.
  The bottom-left hint is bg-luminance-aware (amber/brown) and the commit
  result auto-hides after 4 s (`BaseKnotHintTick` in the 500 ms block).
  `BK_IDLE→ARMED→PREVIEW→IDLE`, single-shot auto-exit
  (commit AND cancel → `IDLE` + menu restore via `BaseKnotTakeRestoreFlag()`
  in `HandleUIChartEvent`, stray clicks draw nothing). Press never commits
  (only the release / next click does), so no double-commit; `g_bkHeld`
  tracks the held button, `g_bkLiveT/P` is the off-chart-release fallback.
   Sizing preview =
  dotted `PREVIEW` edges + LIVE Entry/SL/TP + info (`<prefix>_BK_LIVE_*`,
  direction re-resolved while sizing, wiped at commit/cancel/deinit);
  same-bar/zero-height commits rejected, preview kept. Committed boxes own
  children by shared id prefix (`<prefix>_BK_<id>_`): box drag re-syncs the
   Entry/SL/TP ray-right lines (`BaseKnotSync` on `OBJECT_DRAG`), box delete
  cascades (`ObjectsDeleteAll(pfx)` via select + Delete key — `NOBKDEL`
  2026-09-06: no X badge; `Sync` purges pre-retire DEL objects, DEL clicks
  still delete during transition).
  Direction is AUTOMATIC at commit (no Buy/Sell badge — `NOBUYSELL`
  2026-09-06): box mid below live price = Buy, above = Sell; leftovers purged
  in `BaseKnotSync` + the CLICK handler. The
  session is consumed FIRST in `OnChartEventHandler` (500ms arm-guard on the
  CLICK fallback path, chart scroll locked with raw `Chart*` calls so Lite
  compiles menu-free — Lite keeps drag/delete/badges, arming is Full-only).
  Pips via `GetCachedPipSize()`, never hardcoded point math; TP = 2R.
  `TOOL_COUNT`-driven menu loops pick new tools up automatically; BK owns panel
  12 (Base Box style card — ToolPanel()==12, so ring-hold opens it like every
  other tool; click still arms drawing, guarded by `g_LongPressFired`).
  Drag-follow is ONE unified lean writer (2026-09-08, P-BK-07 — two writers
  fought: per-step `OBJECT_DRAG`→full `Sync` lagged on heavy charts while the
  `MOUSE_MOVE` cursor-delta fallback ignored MT4 magnet snap, so fill and
  border diverged mid-drag): `BaseKnotFollowDrag` moves children from the BOX
  live anchors while the terminal moves them (exact, moves-only, ~14 syscalls)
  and falls back to cursor delta only while anchors sit frozen (some builds).
  `OBJECT_DRAG` carries no trusted cursor (anchor-exact only — in-repo pattern,
  TH3Tool reads anchors there too), `MOUSE_MOVE` carries the cursor fallback;
  the shared 30ms gate dedups the channels so neither fights nor starves.
  Release does one authoritative `BaseKnotSync` — full pattern: `LEARNING.md` §1.

- **Base Box is TradingView-parity — toolbar, fill, text, tabs**
  (2026-09-07, user decision — the strip + card mirror TV's rectangle tool:
  floating toolbar, Style/Text dialog tabs, Template dropdown, 1px steps,
  `Line/Dashed line/Dotted line` language). Strip (item 13, `PNL_TB_W` 380):
  pencil = border palette (`PalOpen(13,0)`), bucket = fill palette
  (`PalOpen(12,5)` with `g_BkTab=0` forced — the palette ANCHORS to the open
  panel, so `PalComputePos` uses `g_PnlOpen`+`PnlPanelW`, never the anchor
  item's stale coords), T = card 12 on the Text tab, STYLE/WIDTH = ▾
  popovers (never cycles — the cycle code is gone), lock/trash on
  `g_BkMiniBox`, ••• = card 12 keeping the tab. Card 12 is tabbed
  (row 0 `Style|Text|Setup` segments, `g_BkTab` kept across opens like the
  Step mode; `PnlRowsCount(12)=1+BkSecRows()`, sections delegate via
  `BkSec*` — never hardcode card-12 rows; `PnlOpen(12)` clears a stale
  `g_BkMiniBox` ONLY when coming from neither strip nor itself, so TAB
  switches keep the held box). Text tab rows = TEXT edit + SIZE + B|I +
  ALIGN + VALIGN (`Top|Inside|Bottom` = TV's Inside-dropdown, `g_bkVAlign`
  default Inside, `inpBKVAlign`, `FF_BK_VALIGN`, `OV_BXVA`) + COLOR. Text
  content lives in the per-box `TEXT` `OBJ_TEXT` (no GV — strings don't fit
  doubles; `BaseKnotSetText/GetText/PlaceText` in the domain layer so Lite
  stays UI-free; delete = clear, `Sync` only moves/restyles an existing
  TEXT, never resurrects); edited via the Text-tab `OBJ_EDIT` (kind 6 —
  `PnlDestroy` `_ED`, `PnlUpdateRow` skips it), committed on
  `CHARTEVENT_OBJECT_ENDEDIT` / flushed before any other panel action + on
  close (TV Ok semantics, `BkFlushTextEdit` — same pattern as `FlushPalHex`);
  focus flag `g_BkTextFocus` lives in `GlobalVariables.mqh` so `EventHandlers`
  KEYDOWN silences letter hotkeys while typing (palette-hex pattern). Fill
  default invisible (FILL TR=100) so old charts are pixel-identical; presets
  (TEMPLATE) cover fill+text+valign.
  Coords = drag natively (TV Coordinates), visibility = automatic commit-TF
  + lower (TV Visibility) — both ride the ONE live box/edge tooltip
  (`BaseKnotBoxTooltip`: side · pips · R:R · T1→T2 · TF-scope · "text" ·
  lock). Glyph semantics (R-ICONS law) verified at byte level (ASCII dump),
  never by eyeballing previews.

- **Strip dropdowns: embedded skins, bitmap chevrons, content-fitted widths**
  (2026-09-07 — the STYLE/WIDTH ▾ popovers floated with NO white card
  (transparent), chevrons showed `?`, `Dash-Dot-Dot` truncated. Three root
  causes, all in `BiotakPanels.mqh` + `tools/gen-th3-icons.js`: (1) `bk_dd.bmp`
  had NO `#resource` line — a `::Files\Icons\*.bmp` runtime ref without it
  resolves to nothing (compile stays green, MT4 draws the bitmap blank);
  (2) text `▼` (U+25BC) is missing in MT4/Wine Arial → `?`; (3) one fixed
  176px width too narrow for the longest label. Fix: content-fitted pair
  `bk_dds.bmp` (STYLE 216) / `bk_ddw.bmp` (WIDTH 120) picked by
  `BkDdCurW()/BkDdRes()`, Z-stack BG 1560 < SEL 1566 < LBL 1568 < ICO 1574
  (backdrop above its own rows buries them), chevron = `bk_chev.bmp` bitmap.
  Law: every runtime `::Files\Icons\*.bmp` ref needs a `#resource` line;
  UI chrome glyphs outside Windows-1252 must be bitmaps, never font text.)

- **R-PANELS — settings cards are TV-white, geometry frozen**
  (2026-09-07, user decision — all settings cards speak the white-dialog
  language of the strip/dropdowns + TV dialogs, one uniform look).
  White `pnl_cardN.bmp` skins (same 312/56/50/48 geometry — never resize),
  navy `C'38,44,56'` single primary (slider fill, active segment, Done,
  swatch rings — same as the dropdown pill), kind=1 rows are left TV
  checkboxes (`pnl_cb_on/off.bmp`, label shifted right, hit-test in
  `PnlSwitchHit` follows the box), header = title + `×` only (icon chip,
  subtitle and palette `P` retired — PICK opens the palette; handlers and
  `PnlDestroy` purges stay), footer Reset(light)/Done(navy) unchanged in
  behavior (panels apply live — a TV Cancel that discards is dishonest here).
  Pill-switch skins + code are gone (`SWK` delete stays as purge). To restyle
  panels again: touch ONLY `PNL_CLR_*` + skin paint — never coordinates.

- **R-PANELMOD — panels use TV-modern elements, not repainted old ones**
  (2026-09-07, user decision — white paint over steppers/pills still read
  dated next to the TV Rectangle dialog). Single-line rows
  (`PNL_ROW_H` 42: label left · control right — except COLOR (kind=4) and
  TEXT (kind=6) rows, whose label rides above the control in the same 42px:
  a full swatch strip / edit field never fits beside its label, P-UI-11); kind=2 with 4+ options is a
  generic dropdown-select (`PnlDdOpen/Hit`, content-fitted popover,
  dark-pill selection, `PnlApplyOption` = same path as segment taps, full
  rebuild like TAB switches); (9,0)/(12,0) are underline tabs (`TU`
  object); sliders are stepper-less full-width tracks (drag + jump stay);
  color rows are preview + 6 swatches (PICK retired, preview tap opens the
  palette which has RECENTs); palette popup whitened too (card/borders only,
  mixer science untouched). New widget suffixes (`TU/DD/DDT/DDC`) MUST join
  `PnlDestroy` (P-UI-02). MQL4 needs define-before-use: dropdown helpers
  before `PnlCreateRow`, engine after `PnlOpen`. Press pipeline owns the
  popover first (`UISuppressNextClick`), outside press closes AND falls
  through; Esc closes popover before panel.

- **R-SUBLADDER — the Tools sub-menu picks its geometry from the tool COUNT,
  and NEVER shrinks a radius** (2026-09-11, user order: "more items will be
  added to this sub-menu; redesign it so adding them can't break it — it does
  not have to be a circle, use the best layout"). `TOOL_COUNT` is the only
  number the layout reads; it derives its own mode, so adding a tool can never
  make two buttons collide:
  `1..6 → FAN` (180° arc, r=min(112, fit), floor = chord radius) ·
  `7..8 → RING` (full 360°, r=100) · `9+ → GRID` (4-column panel beside the orb)
  · `count > SubPageSize() → GRID/paged`.
  Near a chart edge the arc collapses to a straight **RAIL** on the free axis
  with the most room (`SubRailAxis` — the old code mirrored ring item 1's
  direction and pointed the train off-chart at corners), and if the rail cannot
  fit either the layout **ESCALATES to the grid panel**. The radius is NEVER
  shrunk below `SubChordRadius()`: shrinking it is exactly P-UI-13's failure
  mode (items stacked on one line). `ToolsFitRadius` is deleted.
  The 6 main-ring items are HIDDEN while the sub-menu is open (the fan at
  r=112 and the full ring at r=100 genuinely cannot coexist with the ring at
  r=64 once 44px buttons + glow are counted) — which makes the ORB the only way
  back, so the orb now CLOSES the sub-menu instead of hiding the whole menu
  (orb → ring → sub-menu). Sub-menu geometry is measured from the MENU CENTRE,
  never from the Tools button, so the button can never push an item into a ring
  item. Page size is CHART-DERIVED (`SubPageRowsCap`), so a short chart pages
  EARLIER instead of pushing a row past the bottom edge.
  Two skins, one owner each: fan/rail/ring reuse the ring's circular glass disc
  (`circ_*.bmp`, 52px canvas), the grid uses the rounded-square tile
  (`cell_*.bmp`, 46px canvas). The cell canvas is DELIBERATELY equal to
  `SUB_GRID_PITCH` (46) so adjacent canvases abut with zero overlap — a larger
  canvas let an ON cell's glow wash onto its neighbour and the winner depended
  on object Z-order, i.e. it flickered. The panel backdrop is one BMP per
  visible row count (`sub_panel_r<N>[p].bmp`) because STRETCHING a rounded panel
  turns its 13px corners into ellipses and blurs its 1px border.
  `SUB_*` in `BiotakMenu.mqh`, the `SUB_*` consts in `tools/gen-th3-icons.js`
  and `tools/submenu_geometry_check.js` are ONE contract — change all three
  together or the cells stop lining up with the panel art. The proof is
  `node tools/submenu_geometry_check.js` (1440 cases: 8 chart sizes × 9 menu
  positions × counts 1..20 — no collision, no orb overlap, nothing off-chart).
  Envelope: a side placement needs `pw+ORB+gap+2*PAD` = 292px of width (a
  below/above band needs the same idea of height); below that the panel tucks
  UNDER the orb (orb Z 2000 > panel 1004 > cells 1010), which stays on top and
  clickable. Below ~300px in BOTH axes the chart is under the indicator's own
  envelope anyway (the ring needs ~192px, the cards 312px and clamp too).

- **Base/Knot is fully automatic — no Buy/Sell button, ever**
  (2026-09-06 — direction is decided at commit by
  `BaseKnotResolveDirection()` in `Biotak/BaseKnotTool.mqh`, then FOLLOWS the
  live price (P-BK-13 2026-09-08 — a frozen dir went stale the moment price
  crossed the box, so a box below the price stayed SELL forever: the 500 ms
  pump `BaseKnotSyncBadges` + drag-release now flip it via
  `BaseKnotRefreshDirection()`, persisted to the chart-scoped GV, with a
  3 s hint on flip. The BOX ITSELF is the hysteresis band — fully outside
  takes that side, inside keeps the current one — so in-box vibration still
  cannot flicker the lines. Lite has no `RefreshKitOnBar` pump, so
  `OnCalculateHandler` runs `BaseKnotSyncBadges()` throttled 500 ms under
  `#ifdef BUILD_LITE`): price above the box = Buy (Entry=top, SL=bottom,
  TP=top+2R), below = Sell (mirrored); a commit landing with the price INSIDE
  resolves by entry side (most recent of the last 128 closes outside the box:
  from below → Buy, from above → Sell; mid-vs-price fallback). `BaseKnotSync`
  only reads the registry (never recomputes — the refresh happens BEFORE the
  Sync call), so the flicker rule still holds. Box ids are `"<commitTFmin>_<tick>[rNNN]"`
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

- **ATR trade block = screenshot format, TRex stamp on top**
  (2026-09-08; bottom-right block is now 1 right-aligned row,
  `#SL:-S #TP1+T1 #TP2+T2 #TP3+T3` (blue). The `Close in : ...` countdown became
  a 2026-09-11 compact tag `19m32s` BESIDE THE LIVE CANDLE at the live price
  (`CreateLivePriceCountdown`: X = bar-0 right edge + gap, Y =
  `ChartTimePriceToXY(bid/ask mid)`, flips to the candle's left when the right
  side runs out of room; 1 Hz + `CHARTEVENT_CHART_CHANGE`). The tag is its OWN
  LAYER (P-LBL-05): own switch (`D` key / card 2 row 0, `OV_CD`), own
  color/size/gap (card 2 rows 1-3, `OV_CDC/CDS/CDG`), object name `CloseIn_Tag`
  (no `ATR_` — the ATR janitor must not eat it), and a plain left click on the
  tag opens card 2. Every one of those contracts is asserted by
  `Biotak_Countdown_Test.mq4` (`[CDTEST]` lines: name carries no `ATR_`,
  survives the ATR-off sweep, own switch deletes+invalidates, click region ==
  the painted rect, tag parks with the live bar out of view).
  top-right under the stamp: `Hunter SL: H Eng.SL: E` (red). The `Str Bond: A - B`
  row is RETIRED (R-STBOND 2026-09-10, user decision — SB1≈TP1 (20/9 vs 7/3 of
  slRaw) and SB2≈TP3 (95/9 vs 31/3), a duplicate read; engine sb1/sb2 stay for
  log + golden-test pairing, on-chart text gone, delete/visibility paths stay as
  purge). The ATR-pips row is retired (ATR stays the hidden engine only). Top-right
  TRex stamp (brand `TR` blue + `ex` red at +6pt with the pair's LIVE spread
  superscript in pips, 1 decimal + green Persian caption) rides the SAME
  ATR-trade visibility
  (`inpShowATRTradeLabels` + `g_atrLabelsVisible`; Hunter/StrBond ride the
  SL toggle, TP row rides the TP toggle in `SetATRLabelsVisibility`); all
  9 objects are `LBL_`-prefixed so
  `ClearAllLabels` + the param-change purge cover them. The small number is
  spread, never a version or TH value (the v0.5 daily-TH value row is retired
  in 3.x; `TREX_Value` purge lines stay for old charts). `TRexCaptionText()`
  builds the Persian caption from ushort codes — never a non-ASCII literal
  in source (see P-LBL-01).)
- **R-TRADEPLAN — trade-plan math has ONE owner: `Biotak/TradePlanFormulas.mqh`**
  (2026-09-09 spec, confirmed live Sep-9-2026 all 8 TFs XAUUSD: UNIFIED SL formula
  `SL(TF) = 1.20 × Eng(StructureTF)` — one constant, no per-TF table.
  Ladder: M1-M5-M15-H1-H4-D1-W1-MN; Structure = 2 rungs UP; Trigger = 2 rungs DOWN.
  Eng formula (`TradePlanEngTrue`) — SEE R-ENGPARITY below: `Eng(TF) = TR_composite(own TF) / 4.266666`
  (constant `TRADEPLAN_ENG_DIVISOR`, hard-coded — R-ENGONE 2026-09-10: not an Input,
  one formula only; the legacy single Wilder call on the trigger TF with
  period = TF_min/trig_min (shift=1) is retired/deleted).
  Trigger mapping: M1/M5/M15→M1(per=1/5/15), H1→M5(12), H4→M15(16), D1→H1(24), W1→H4(42), MN→D1(30).
  `TP = SL*(7/3, 5, 31/3)` from UNROUNDED slTrue; `Hunter = round(8*EngTrue/3)` from
  unrounded Eng; StrBond `Base=95/9*SL` + `Width=20/9*SL` (M1-D1: Width--Base,
  W1: 16/3*SL--Base, MN: rounded-sum--Base); slow legs freeze per chart bar
  (`TradePlanComputeLive`) while Eng/Hunter stay live. Symbol-free +
  `TradePlanSelfCheck()` guard. Display renders from `Period()`, never follows TF-lock.
  Full walkthrough: TRADEPLAN_FA.md.)
- **R-ENGPARITY — Eng is a LONG-horizon per-chart-TF measure, not a one-bar trigger ATR**
  (2026-09-10 evening, user order "ours must become like the professor's"; rig
  `tools/eng_own_window.js`, committed). The legacy Eng `iATR(triggerTF, TF/trig, 1)/pip`
  is a ONE-chart-bar window: it reproduced gold only because XAUUSD vol is
  persistent (P-ATR-05), and it is off by -39% on W1, -33% on D1, +128% on M15,
  -50% on EURUSD W1, -46% on EURUSD MN. The rig ruled out (a) a fixed-N own-TF
  window (gold ATR(M1,N) never drops below ~16 pips, ATR(H4,N) 350+ vs his 88)
  and (b) a fixed calendar window on the trigger TF (XAUUSD MN fits 174 days at
  0.1%, but XAUUSD W1 needs 600 and the H4 series tops out at 402 — no single
  window clears the ladder; P-ATR-05's flat optimum stands). Shipped instead:
  **`Eng(TF) = TR_composite(own TF) / 4.266666`** (constant `TRADEPLAN_ENG_DIVISOR` =
  64/15, the user's divisor) — reproduces all six SL-derived XAUUSD legs
  {M15 16.515, H1 39.854, H4 87.766, D1 252.338, W1 600, MN 982.978} within
  {+14,+4,-4,+2,-3,-10}% on the 15:31 XAUUSD `[SNAP]` (legacy: {+128,+54,-0.7,-28,-39,+5}%),
  keeps Eng(M1)!=Eng(M5)!=Eng(M15) (P-TRADEPLAN-02's structural constraint), and
  improves every EURUSD leg except the low TFs. NOT verified: his M1/M5 Eng (not
  SL-observable; gold M1 3.8 / M5 7.9 are not reproducible by ANY ATR of M1 —
  treat those two as display-only) and EURUSD M1..M15, which our parity path
  undershoots by ~45% (prof band midpoints, time-mismatched screenshots).
  **R-ENGONE (2026-09-10, user decision): the divisor is HARD-CODED — it is NOT
  an Input (no row in the MT5 Inputs dialog) and the legacy Eng path is
  deleted; this is the only Eng formula.** `[SNAP]` prints `engDiv=` in its
  header, and `Biotak_TradePlan_Golden_Test.mq4` PART B mirrors the recipe and
  guards distinctness + monotonicity. To ever change the divisor: edit
  `TRADEPLAN_ENG_DIVISOR` in `TradePlanFormulas.mqh`, from a same-minute pair
  of screenshots — the low-TF legs are the ones to watch.
  **R-ENGEURUSD (2026-09-10, user decision: KEEP 4.266666).** EURUSD low-TF
  professor screenshots (Aug-14/17, M1+M5+M15 corners, rigs `tools/eurusd_corners.js`,
  `tools/eurusd_eng_sweep.js`, `tools/eurusd_tr_window.js`) prove: (1) the whole
  SL/TP/SB chain is CORRECT on EURUSD low TFs — each block reconstructs from a
  single slTrue (M1 1.76, M5 3.13, M15 5.47) with the same 7/3·5·31/3·20/9·95/9
  multipliers; (2) our `composite/4.266666` Eng reads ~30-40% LOW on M1..H1
  (his raw Eng: M1 [0.19,0.5), M5 [0.56,0.94), M15 [1.31,1.5), H1 2.61, H4 4.56
  vs ours 0.21/0.46/0.84/1.91/4.60) while H4 matches (+1%); (3) the implied
  divisor with OUR composite is ~2.6 (M1-M15), ~3.1 (H1), ~4.3 (H4) — NO constant
  divisor fits, and no ATR(TF,N) for any N reproduces his Eng (sweep N≤2000 empty);
  (4) his strip TR is SESSION-REACTIVE (shorter window than our long-weighted
  composite): his panel M15 TR rose 4→5 between 13:44 and 21:19 the same day
  while ours stayed ~3.7 (composite is 40% weighted on the 264-bar leg).
  Open question: his real Eng window. DO NOT re-tune the divisor from
  time-mismatched screenshots — the definitive test is ONE same-second pair
  (our `[SNAP]` + his chart). Until then EURUSD M1..H1 Eng stays ~30-40% low
  by decision; gold is unaffected.
  **R-ENGSOURCE (2026-09-10, live gold screenshots D1+M5, user's M5 prediction
  test): Eng(TF) = ATR(TF, N)/4.266666 on a SHORT per-TF window — NOT the
  composite.** Evidence: on D1 the divisor 4.266666 is exact (Eng 249 =
  ATR(D1,46)=1062.3/4.266666, 0.2%); on M5/H1 his Eng source runs ~10% ABOVE
  the panel TR (M5: source 59.7p vs panel 54p; H1: 210 vs 192) — the panel TR
  is the LONG composite, his Eng feeds off a short session-reactive ATR
  (ATR(M5,3)=61.0p at 13:15 ≈ source 59.7; M5 chain bulletproof: SL 59/TP
  138/296/611/SB 131--624 all from slTrue=59.1, Hunter 37=8/3×14). The
  composite coincidentally ≈ short ATR on calm days (gold Sep-9), which is
  why R-ENGPARITY fit then; on volatile days (gold Sep-10, EURUSD low TFs)
  they diverge and composite/4.266666 reads ~10-40% low. Pinned N so far:
  M5≈3, D1≈46, MN≈16-30 (override family); M15/H1/H4/W1 UNKNOWN — do NOT
  implement a new Eng source until those are pinned (corner screenshots or a
  same-second pair), and keep the chain + divisor intact.

- **R-D1SEARCH — every fixed "percentage-of-daily" family is PROVEN dead
  (2026-09-10, user clue: "the master computed for DAILY and the rest of the
  percentages were from it"; rig `tools/d1_derive_search.js`, committed). The
  rig enumerated, in one pass: rational % tables on {D1 Eng 252.338, D1 ATR
  1066, D1 SL 1180} (dead — simplest surviving fractions are absurd like
  7/107, 107/45, 261/67, and H4/MN have NO fraction at all for the ATR/SL
  bases), power law (TF/D1)^p on 8 legs AND on M1..H4 alone (dead — per-leg p
  scatters 0.577..0.612 beyond the ±0.05% windows), log combo r^p·(−ln r)^q
  (dead), N-rules from N(D1)=46 (dead — N(MN) comes out 237/252/72 vs the
  16..30 pin), and the cross-symbol gate (dead — EURUSD M15 would be 0.72 vs
  his 2). Conclusion: his Eng is LIVE per-TF data — Eng = ATR(TF,N_TF)/
  4.266666 with N(M5)≈3, N(D1)=46; the top of the ladder is ONE macro number
  (D1/W1/MN share SL=1180 = 1.2×Eng(MN)) while the low TFs are short-window
  and volatile (M5 Eng 7.9→14 between Sep-9/10 while MN stayed 983). The ONLY
  remaining open question is the N_TF rule for M15/H1/H4/W1 — do NOT touch the
  chain or divisor. Full ledger with every clue and the same-second-pair
  protocol: `TRADEPLAN_D1_HYPOTHESIS.md`. Rig `tools/math_proof_search.js`
  (2026-09-10 night, TRex 3.2/3.4 screenshots) closed the "one formula from the
  ON-PANEL numbers" family too: the panel Th-TR-Live columns ARE TP-chain
  blocks (TR=round(Th×7/3), Live=round(Th×5)); the Sep-10 D1 block
  (1180/2752/5898/12189/663/249/2621/12451) back-solves to the SAME Eng(MN)
  window as Sep-9; and NO sqrt/pow/log/2-number/3-number combination of
  on-panel numbers reaches ≥3 ladder cells (F30 = 0 candidates) — the ladder
  is live ATR data, never on-panel arithmetic. Ledger §8.
  **R-TWOPANEL (2026-09-10 23:49, user same-moment pair): TRex 3.2 shows BOTH
  Eng sources in two panels on XAUUSD D1 — Panel A (ATR table) = CompositeATR(TF)/
  4.266666 EXACT (D1 Eng 258 = 1098.9/4.2667, Hunter 687, SL 1063 = 1.2×3778/4.2667,
  TP 2479/5313/10980; his ATR table D1/W1/MN 1098.9/2474.7/3778.0 == our composite
  to 3 decimals) and Panel B (Th-TR-Live) = long-window ATR(TF,N)/4.266666
  (Eng 249, SL 1180, TP 2752/5898/12189 — the Sep-9 golden). Divisor universal;
  the R-ENGPARITY vs R-ENGSOURCE debate is settled — they are two different
  panels, not competing formulas. Open: WHICH panel is the professor's real
  plan (SL 1063 vs 1180) — ASK the user before changing the Eng source.
  Live column = forming-bar H−L (verified twice: 1102 vs range 1101.5, 1204 vs 1204.1).
  Rig F13/F14/F15; ledger §8.6.**
  User confirmed 2026-09-10: PANEL B is the real plan → Eng source must become
  long-window ATR(TF,N)/4.266666 (NOT composite). BUT rig `tools/n_window_search.js`
  proved the Sep-9 golden moment CANNOT pin N (gold's flat optimum: every N fits
  within 0.2% — scatter 337/47/39/78/396/281/5/25; only W1≈5 and MN≈25 SMA
  candidates), and the stale .hst (ends 13:15 UTC Sep-10) does NOT reproduce the
  R-ENGSOURCE pins (M5 SMA(3) 76.2 vs 60.4, D1 SMA(46) 974.6 vs 1062.3) →
  N(D1)=46/N(M5)=3 are REOPENED until fresh data + the professor's M1/M5/M15/H4
  panels at a volatile moment (protocol: ledger §8.6.6). Do NOT change the Eng
  source until N is pinned (R-ENGSOURCE guard).**

- **R-TRADEPLAN-DIAG — the diagonal is a theorem, not input** (2026-09-09:
  `SB1(chart) == Hunter(StructureTF) == SL × 20/9` because `1.20 × 20/9 = 8/3`.
  Observed Sep-9-2026 live: H1 SB1 673 == D1 Hunter 673; M5 SB1 103 ≈ H1 Hunter 88.
  Never implement as a recipe — exogenous input stays the strip ATRs.)
- **R-ALT — experimental alt trade formulas, opt-in only** (2026-09-10, user
  order: `inpUseAltTradeFormulas` (default false, plain input like X — NOT a
  panel mirror): SL=TR×1.66666, Eng=TR/4.266666, Hunt=TR/1.66666, chart-TF
  based, TP/SB unchanged from slTrue. Default path byte-identical (verified
  XAUUSD untouched). Do NOT "fix", merge, or delete this toggle without the
  user: it is their live A/B test against the professor. (2026-09-10 note: its Eng leg
  `TR/4.266666` is now ALSO the default Eng — R-ENGPARITY — so with the alt ON
  the difference from the default is SL/Hunter only.) Exact-gate verdict
  at ship time: misses AUDUSD live on all three legs + XAUUSD catastrophically
  (SL 6296 vs 1180) — stays OFF until a regime sample confirms it.
  EURUSD 3-TF professor screenshots (Sep-10-2026, TRex M15/H4/D1): alt misses
  7 of 9 legs — H4 SL 53 vs 38, Eng 8 vs 4, Hunt 19 vs 12; D1 SL 128 vs 103,
  Eng 18 vs 11, Hunt 46 vs 30; M15 SL 13 vs 5 (only M15 Eng 2/Hunt 5 match,
  small-number rounding coincidence). The UNIFIED ladder fits every leg of all
  three charts (slTrue ≈ 5.3 / 38.1 / 102.75 pips; D1 TP3=1062 pins slTrue,
  not rounded SL) — unified formula now confirmed on a 2nd symbol (EURUSD).)

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
| P-ARCH-02 | Unifying a duplicated table between two modules fails to compile when the consumer is included BEFORE the owner (MQL4 is one translation unit: `ExtendedDrawingFunctions` cannot call `FactorMode`, which is included later) | Define-before-use across the `.mq4` include order — an earlier-included module can never see a later-included one | Put the shared table at/below the LOWEST consumer: the basis multipliers now live in `ConstantsAndEnums.mqh` (next to the enum) as `GetFactorBasisMultiplier()`, consumed by both the raw and adapted paths. Never place shared data in the upper module. | 2026-09-07 |
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
| P-TOOL-04 | `.hst` fit search silently inverts every TR (results look plausible, conclusions all wrong) | Bar layout is time/open/**high**/low/close — the fit scripts read low@16/high@24 (swapped). Swapped H/L makes `high-low` negative so TR falls back to gap terms only; outputs stay in-range and the bug is invisible without a check | Assert `high >= low` on every parsed bar (fail fast, on the real field names — a guard reading `b.h`/`b.l` when fields are `high`/`low` flags the whole file as corrupt). Re-prove any claim that came ONLY from the swapped script; terminal-log evidence is unaffected | 2026-09-10 |
| P-BUILD-02 | Linux/Bottles: `bottles-cli run -e metaeditor ... /compile:...` exits 0 but writes NO `.ex4`/log; Wine `if exist` on host paths (Z:\ or a symlink into the repo) succeeds yet open/read FAILS silently (proven: `type` through `Indicators\BiotakProject` symlink → "Failed to open"; Z:\ compile of a trivial file → nothing) | (a) Wine under Bottles/Flatpak cannot read host files (Z:\ or symlink targets) — silent no-op, exit 0; (b) `bottles-cli run -e` with a unix-path exe routes via winebridge whose `run_exe` takes NO CLI args (verified in Bottles source), so /compile flags never arrive; (c) `#resource \Files\Icons\...` resolves relative to the SOURCE dir — a build dir without `Files/Icons` fails with 45× error 310 | Use `compile-th3-linux.sh` ONLY on Linux: rsync-mirrors repo (incl. `Files/Icons`) into in-bottle `C:\th3build` AND the REAL `Indicators\BiotakProject` dir (never a symlink — Wine can't traverse it), drives metaeditor via a generated CRLF `.bat` (quoting lives in the `.bat`, never on the CLI), copies `.ex4`+log back to repo and deploys `.ex4` to the terminal. Manual MetaEditor F7 on `Indicators\BiotakProject\*.mq4` (C: real files) verified 0 errors. Never pass Z:\ paths to metaeditor. | 2026-09-05 |
| P-BUILD-03 | `git status` shows the whole tree modified (~90 files, ±40k lines) with zero real change | Line-ending churn: worktree files got CRLF-ified (repo convention is LF everywhere; BOM only where HEAD has it — e.g. `.ps1` yes, `.mqh`/`.md` no). Diagnose with `git diff --ignore-cr-at-eol --name-only` (2026-09-05: only `AGENTS.md` was real) | NEVER commit that noise: save the real hunks (`git diff <file> > fix.patch`), `git checkout -- .`, re-apply, normalize worktree (`\r\n`→`\n`, strip stray BOMs to match HEAD), and confirm `git diff --stat` shows only the real lines before staging. | 2026-09-05 |
| P-BUILD-04 | Every `./compile-th3-linux.sh` run CLOSED the running MT4 terminal (user had to reopen it) | The old script compiled INSIDE the live `Tradeing` bottle via `bottles-cli run -e <bat>`. Every `flatpak run` sandbox gets a PRIVATE `/tmp` (proven: host `/tmp` probe invisible inside) while the wineserver socket lives in `/tmp` — so the compile's sandbox started a SECOND wineserver on the SAME live prefix, which kills the terminal. Separately: passing a spaced `/compile:` path as a direct wine argv silently compiles NOTHING (BOM-only log, exit 0, no `.ex4` — verified twice); metaeditor needs the QUOTED path from a CRLF `.bat` run through `cmd /c` | `compile-th3-linux.sh` now compiles in an ISOLATED Wine prefix (`<Bottles-data>/th3build-wine`, override via `TH3_WINEPREFIX`, `wineboot --init` once, own `C:\mt4\metaeditor.exe` copy + `C:\th3build` mirror) driven by `flatpak run --command=wine ... cmd /c C:\th3build\compile.bat` (quoting lives in the `.bat`, never on the CLI). The live bottle is only touched by plain file copies (source/icon sync in, `.ex4` deploy out) — terminal stays open (same PID before/after, full+lite 0 errors). Legacy `C:\th3build` + `.bat` in the live bottle are auto-removed. Never compile inside the live bottle again. | 2026-09-05 |
| P-HTF-01 | HTF candles gone after switching to a higher chart TF until manual off/on toggle | `OnDeinit(REASON_CHARTCHANGE)` deletes all HTF objects; `OnInit` re-resolves `g_HTFPeriod` but draws nothing; per-tick updater only maintains forming candle idx0; HTF history not yet loaded right after a switch (`iBars==0`, longer on weak PCs) so even a one-shot init draw would silently miss | `HTFEnsureDrawn()` in `Biotak/HTFCandles.mqh`, called from `RefreshUIPerTick()`: per-tick TF re-resolve (O(1)), full redraw at most once/sec only when TF changed / box 0 missing / first run, data-ready gate (`iBars`+`iTime`) with automatic retry, once-only delete when hidden-by-design | 2026-09-05 |
| P-HTF-02 | Manual HTF timeframe silently reverts to auto on every TF-switch/re-attach; HTF draw paths could use a stale cached period; full draw left the forming-candle cache stale | `g_HTFIsAuto`/`g_HTFPeriod` were never persisted (`Save/Init/CleanupHTFCandlesGVs` missed them) and `UpdateHTFFormingCandle`/`DrawHTFCandles` read the cached `g_HTFPeriod` instead of the fresh `ResolveHTFPeriod()` | Persist `IsAuto`+`Period` GVs (restore in `InitializeHTFCandles`, recompute only when auto); draw paths use `ResolveHTFPeriod()`; full draw syncs the forming cache and `RefreshHTFCandles` resets it. Single engine is `HTFEnsureDrawn()` — do not add a second per-tick HTF sync. | 2026-09-05 |
| P-HTF-03 | HTF history froze one bar behind after every new HTF bar; `ShowBody=false`/doji caused a full 200-bar redraw EVERY second; opacity/width slider drags froze weak PCs (600 objects delete+recreated per step + flicker); `DeleteHTFCandles` with an empty prefix matches every chart object | Index-based history was never rebuilt on HTF bar roll; the steady probe checked only `prefix+"0"` which never exists without bodies (or a wickless doji); `RefreshHTFCandles` did a blind delete+draw; `StringFind(name,"")==0` is true for all names | Bar-roll detection via the forming-cache open time (`s_drawnBar0`, zero extra syscalls); `HTFAnyBoxesExist()` samples bars 0..2 across all name shapes; in-place upsert + trailing prune only (`Draw/Refresh` return the drawn count, `-1` = not ready, state advances only on success + `ChartRedraw`); empty-prefix guards in every HTF delete path | 2026-09-05 |
| P-UI-05 | Typing hex (A-F) fired hotkeys; TF-switch/remove with open panel killed chart scroll forever; ghost panel after TF-switch; panel draggable off-screen; blank `inpObjectPrefix` wipes the chart; news/gap fired 50 alert popups | Main KEYDOWN never checked `g_PalHexFocus`; chart-prop statics reset on reload so the watchdog couldn't restore; panel objects survive CHARTCHANGE while state resets; `PnlMoveBy` unclamped; no prefix validation; per-(bar,level) alert key has no global cap | `#ifndef BUILD_LITE` hex-focus early-return (Full-only symbol); `CleanupUIStates` drains both chart locks on every reason; `InitializeUIStates` purges orphan `Pnl`/`Pal_` objects; clamp-before-move in `PnlMoveBy` + `PnlClampOpenPanel` on CHART_CHANGE; reject empty prefix in `ValidateInputs` + guard deletes; alert governor: 10/bar max, 800ms spacing, 250ms-cached bar time | 2026-09-05 |
| P-BK-01 | BK boxes vanished on TF-switch / param change / 1h after drawing / on L or F; child-line delete left a permanent hole; TF-bearing ids broke first-underscore parsing; badge code would clobber the TF mask with plain ALL/NO; BK deletes flagged a full level redraw | `DeleteAllIndicatorObjects` blanket-wiped the prefix (BK included) on every CHARTCHANGE/PARAMETERS deinit; `RunIncrementalObjectCleanup` expiry (1h) matched BK anchors; L/F/Hide loops had no BK exclusion; child OBJECT_DELETE was swallowed as no-op; tail split at the FIRST `_` cut TF-bearing ids; `PlaceBadges` wrote raw ALL/NO; generic OBJECT_DELETE branch redrew levels for BK names | BK is an independent layer: every wipe/hide/toggle/cleanup path skips `"_BK_"` names (only REASON_REMOVE deep-wipes); child delete self-heals via `BaseKnotSync`, gone-box trails mop up by prefix; split tails at the LAST `_` (`BaseKnotSplitTail`); `PlaceBadges` ANDs the commit-TF mask with on-screen state; generic OBJECT_DELETE ignores BK names | 2026-09-06 |
| P-BK-02 | Bulletproof audit: ghost preview rect after TF-switch mid-draw; chart scroll stuck OFF after removing the indicator mid-session; mouse-move storm (rubber-band ChartRedraw per event) pins weak CPUs; menu hover/drag/long-press interfered with the draw gesture; orphan `Biotak_BK_*` GVs accumulated | Transient PREVIEW/HINT survived non-deep deinit (new instance starts IDLE, nothing owned them); scroll/context restore lived only in Cancel; rubber-band had no throttle; `HandleUIChartEvent` fed every move to the menu even with the ring hidden | `BaseKnotOnDeinit(reason)` (hooked first in `OnDeinitHandler`): restores chart props when armed-ever (`g_bkTouched`), kills transients, drops stale restore flag; `LazyInit` purges transients + sweeps chart-orphan BK GVs; rubber-band throttled 30 ms (swallow, no redraw); `HandleUIChartEvent` skips `CircHandleMouseMove` while the session is active (orb-click exit + panels untouched) | 2026-09-06 |
| P-BK-03 | Hold-on-box never opened the style card (only moves armed it); result hint stayed forever + amber unreadable on light charts | A press with ZERO mouse movement emits NO `CHARTEVENT_MOUSE_MOVE` (button flips aren't events) — pure event arming can never see a stationary press; hint text was fixed amber | Latch press DOWN-transitions (move rising edge AND `TERMINAL_KEYSTATE_LEFT` poll in `RefreshKitOnBar` — per tick + 1s timer); mid-hold fire at 250 ms like menu long-press, release leg as backup; button-UP never clears the latch (a poll tick can land between release and its `OBJECT_CLICK`), staleness dies via >8px move / new press / 30 s TTL. Hint: bg-luminance-aware color + result auto-hide 4 s via `BaseKnotHintTick()` in the 500 ms block | 2026-09-06 |
| P-BK-04 | Border-only change left old committed boxes FILLED (screenshot purple solid): commit/preview set FILL false but Sync/Restyle/LazyInit only touched COLOR/STYLE/WIDTH, so pre-change boxes stayed filled forever | Draw-style changes never retro-apply to existing chart objects — a style set only at creation is fossilized on old objects | Single source of truth `BaseKnotStyleBox()` in `Biotak/BaseKnotTool.mqh` (COLOR/STYLE/WIDTH + FILL false + BACK true) used by commit / preview / rubber-band / Sync / RestyleAll; `BaseKnotLazyInit` un-fills every scanned BOX (migration) | 2026-09-06 |
| P-BK-05 | Hold-on-box never opened WHILE held (card appeared only on release); three open paths (mid-hold poll / release-leg / Shift+click) raced and confused taps with holds | Mid-hold fire required `TERMINAL_KEYSTATE_LEFT` to report down in the poll window, and the poll re-latched (timer reset) whenever the down-flag flickered — so the 250ms never elapsed mid-hold while the pure-event release-leg always worked | ONE method: `BkHoldFire()` while HELD (event-driven on tremor moves + KEYSTATE-free poll for zero-move presses, re-hit-tested); release only clears and opens nothing; Shift+click + release-leg deleted. KEYSTATE only detects a fresh down-transition when nothing is latched — never clears/re-times. Hollow self-heals in `BaseKnotSyncBadges()` 500ms pump (read-guarded) | 2026-09-06 |
| P-BK-06 | Base box still rendered FILLED on some MT4 builds despite `OBJPROP_FILL=false` — border-only default never held | Some builds ignore `FILL=false` on `OBJ_RECTANGLE` (same trap as `ZoneFactory`); plus a half-landed edge refactor left `BaseKnotStyleBox` 1-arg vs 4-arg callers + `PrevName` vs `PrevTag` mismatches so nothing compiled | Hollow-by-construction: BOX rect is ONLY the invisible drag handle (`BaseKnotStyleBox` 1-arg, chart-bg color); the VISIBLE border is 4 `OBJ_TREND` edges via `BaseKnotDrawEdges` (commit/Sync/Press/rubber-band), `RestyleAll` delegates to `Sync`, `SyncBadges` 500ms pump re-hides handles + rebuilds missing edges, edge-delete self-heals via suffix guard in `OBJECT_DELETE` | 2026-09-06 |
| P-UI-06 | Base-Box strip dropdowns floated with NO white card behind rows (transparent); STYLE/WIDTH ▾ chevrons showed `?` in the toolbar; `Dash-Dot-Dot` label truncated | (a) `bk_dd.bmp` had NO `#resource` line — a `::Files\Icons\*.bmp` runtime ref without it resolves to nothing (compile stays green, MT4 draws the bitmap blank); (b) backdrop Z 1570 sat ABOVE row labels (1520)/pill (1500); (c) text `▼` (U+25BC) missing in MT4/Wine Arial → `?`; (d) one fixed 176px width too narrow for the longest label | (a) every runtime `::Files\Icons\*.bmp` ref needs a `#resource` line (`bk_dds`/`bk_ddw`/`bk_chev` added, dead `bk_dd.bmp` deleted); (b) dropdown Z-stack BG 1560 < SEL 1566 < LBL 1568 < ICO 1574 in `BkDdOpen`; (c) chevrons are the `bk_chev.bmp` bitmap, never font text; (d) content-fitted popover pair — STYLE 216 (`bk_dds.bmp`) / WIDTH 120 (`bk_ddw.bmp`) via `BkDdCurW()`/`BkDdRes()` + `g_BkDdW` in hit-test/clamp | 2026-09-07 |
| P-UI-07 | STYLE ▾ chevron floated 21px off its glyph — read as a separate item, not one dropdown control | Chevron was right-aligned to the 68px slot (`sx+sw-1-16`) while the glyph sits left (`sx+6`, 24px) — the dead gap between them broke perceptual grouping | Glue the chevron to its content: STYLE at `ix+PNL_TB_ICON+4` (4px off the glyph) — see P-UI-08 for the WIDTH twin; the slot rects stay as the generous hit areas — do NOT "tighten" them to the visuals | 2026-09-07 |
| P-UI-08 | WIDTH ▾ control read as three separate items — sample glyph looked like a stray "H" next to the "Npx" text + chevron | Closed control drew all three (24px `bk_wN` sample + text + chevron); at 1px the sample is two end-ticks joined by a hairline, i.e. an "H" with no visible meaning | Closed WIDTH control is text-only: centered "Npx" (`BK_WTXT_X` 16 + `BK_WTXT_W` 22 estimate, chevron glued after) + tooltip on label/chevron; thickness samples live ONLY in the dropdown rows; `TBwidth` bitmap retired but its `PnlDestroy` delete stays as purge | 2026-09-07 |
| P-UI-09 | TV-white panel restyle left white-on-light invisible texts (NAV buttons) + dark-era leftovers | `NAV` text used `ACCENT_TX` (white-on-amber) which vanishes on the light button; color-row/edit/separator literals were hardcoded dark; `pal`/`ticon`/`sub` header objects retired | Every panel-chrome color must come from `PNL_CLR_*` (one redefinition repaints all cards); retired header objects keep handlers + `PnlDestroy` purges; geometry defines never change in a visual restyle | 2026-09-07 |
| P-UI-10 | White panels still read dated vs TV dialog (two-line rows, pills for 8 options, [-]/[+] steppers, PICK button) | Repaint kept the old widget language: two-line rows, cramped 8-pill segments, stepper sliders, redundant PICK | TV-modern element language (R-PANELMOD): single-line rows ROW_H 42, generic dropdown-select for 4+ options, underline tabs, stepper-less sliders, PICK retired; MQL4 define-before-use split (helpers early, engine after PnlOpen) | 2026-09-07 |
| P-BK-07 | Mid-drag the BOX fill and the border/rays diverge (fill leads, children lag or sit offset until release) | TWO writers fought over children: per-step `OBJECT_DRAG`→full `BaseKnotSync` (~45 style/tooltip syscalls per step — lags on heavy charts) vs `MOUSE_MOVE` cursor-delta (lean but approximate — ignores MT4 magnet snap on the native BOX) | ONE writer `BaseKnotFollowDrag`: anchor-exact moves-only (~14 syscalls) while the terminal moves anchors, cursor-delta fallback only while frozen; `OBJECT_DRAG` carries no trusted cursor (anchor-exact only — in-repo pattern, TH3Tool reads anchors there too), `MOUSE_MOVE` carries the cursor fallback; the shared 30ms gate dedups the channels so neither fights nor starves; full `Sync` only on release | 2026-09-08 |
| P-BK-08 | Chart slides under the hand mid-gesture (live ticks shift the view while sizing/dragging a box) — MT4's own tools freeze the view | Draw session locked only `MOUSE_SCROLL`+`CTX_MENU`; committed-box drags locked nothing; `AUTOSCROLL` never suspended anywhere | One lock pair `BaseKnotLockChart(ctxToo)`/`UnlockChart` (first locker saves `Was`, nested only re-asserts): session locks all three, IDLE drag (from slop-exceed, taps never flicker) locks scroll+autoscroll; release/Cancel/Commit/OnDeinit unlock; stuck-lock watchdog in the 500ms pump (button up + 1.5 s event silence — KEYSTATE flicker alone must not false-trigger, P-BK-05) | 2026-09-08 |
| P-BK-09 | Rebuilt boxes (restart/TF-switch) silently become BUY when their direction GV is gone; same-bar drags die with zero feedback | `LazyInit` defaulted GV-miss to `dir=1`; `Commit` rejected `t2==T1` (corner times snap to bar opens) and point-clicks without a word | GV-miss recomputes via `BaseKnotResolveDirection` (same as a fresh commit) and re-persists via `Register`; same-bar auto-extends one `PeriodSeconds()`; true point-clicks pop a 2 s hint instead of dying silent | 2026-09-08 |
| P-BK-10 | TP draws as a ray to infinity (reads as "price will go there"); `MakeRay` callers fail to compile when a callee param turns `const` | TP shared the Entry/SL ray maker; `Commit(const datetime t2)` then assigned `t2` for the same-bar extend (MQL4 error 189) | `MakeRay(..., rayRight)`: Entry/SL pass `true`, TP passes `false` (finite one-box-width tick); old ray-TPs self-heal via the 500ms pump migration check; never assign a `const` param — copy to a local (`tc`) first | 2026-09-08 |
| P-BK-11 | TP tick must hug the chart's right edge (a tiny visible mark by the price axis), not sit next to the box — and be SHORT | Box-anchored cuts (`t2 → t2+width`, then current-bar + box-width) still floated mid-chart; scroll/zoom/new bars would strand any fixed-time marker; a 2-bar DASHED tick renders as almost nothing | `BaseKnotTPEdgeTime` (window right-edge time via `CHART_WIDTH_IN_PIXELS` + `ChartXYToTimePrice`, one conversion per pump) + `BaseKnotTPTickSpan` (tick = edge − 2 bars → edge; bar/box fallbacks only when unconvertible); tick look is `BK_TP_TICK_STYLE/WIDTH` (SOLID/2 — same size, instantly readable); `BaseKnotTPGlue` re-anchors with two `ObjectMove`s in the 500ms pump (level untouched — scroll/zoom/new bars only remap time, never a full `Sync`); `BaseKnotTPStale` migrates structural drift (ray flag, old dash/thin) → `Sync` | 2026-09-08 |
| P-BK-12 | INFO label orphans on TFs where its box is hidden (H1 box invisible on H4, label visible) | `BaseKnotPlaceBadges` overwrote the box's TF mask with plain `OBJ_ALL_PERIODS` (same trap as P-BK-01) | `PlaceBadges` takes the live `tfMask` and writes `tfVis ? tfMask : OBJ_NO_PERIODS` — never a raw ALL/NO; same sweep also: edges/rays `BACK=false` (foreground like TH lines — borders must read over candles), preview wears the user's border style/width, TEXT gets the box tooltip + fg-aware render color (`GetBKTextRenderColor`: factory-white means Auto), TP glue skips TF-hidden boxes, `Commit` stores canonical corner order, BOX `ZORDER` lives in `StyleBox` | 2026-09-08 |
| P-BK-14 | Chart still pans/slides under the hand mid-gesture (draw-sizing or box-drag) although a lock is taken — one-time lock insufficient | Separate lock mechanisms (BK raw lock vs menu refcount lock) with separate saved values: a third writer (menu modal unlock when a strip/card closes mid-gesture, panel watchdog restore, template/terminal reset) flips the props back while the button is still down | Owned locks re-assert continuously, read-guarded: `BaseKnotReassertLock(ctxToo)` (writes only on drift) called from the throttled rubber-band, `BaseKnotFollowDrag`, and the 500 ms pump while the session is armed; `ctxToo` mirrors the original locker | 2026-09-08 |
| P-BK-15 | Dragging a box to move it snaps back to the drag start, every attempt | The 500 ms pump (`BaseKnotSyncBadges`: P-BK-13 dir-flip `Sync`, fill/edge heals) rewrites the BOX mid-drag — MT4 cancels an in-progress native drag when its object is touched programmatically | Hands off the actively-dragged box: the pump loop skips `s_bkDragId` (`continue` — heals, glue, dir-flip all deferred); the release path already Syncs authoritatively with the flip, so nothing is lost. Rule: NEVER rewrite/touch a natively-dragged object except from its own drag/release handlers | 2026-09-08 |
| P-BK-16 | Relocating a whole box is impossible: lines follow the cursor but the box stays, release snaps everything back | Cursor-delta fallback moved CHILDREN only while the terminal never moved the BOX natively (frozen build / grab never engaged) — release-Sync then rebuilt children at the unmoved box | Fallback moves the BOX itself too (`ObjectMove` both anchors), absolute from the press base (never incremental): converges exactly, never drifts/double-counts; the moment the terminal moves anchors, the anchor-exact branch wins again. Both drag realities covered: native move → box untouched (P-BK-15), frozen → we carry it | 2026-09-08 |
| P-BK-13 | Box below the live price stays SELL forever (screenshot: demand box under price with SL on top) — all scenarios stale after any cross | Direction was decided ONCE at commit and FROZEN; later price crosses and user drags-across never re-evaluated it (`BaseKnotSync` only read the registry) | Direction FOLLOWS the price: `BaseKnotFollowDirection` (box = hysteresis band: outside takes that side, inside keeps — no flicker, no buffer to tune) via `BaseKnotRefreshDirection` (anchors → want → persist GV, returns flipped) called from the 500 ms `BaseKnotSyncBadges` pump (one shared `iClose`-first `BaseKnotLiveRef`, 3 s cross-hint when IDLE) + instantly on drag-release before the authoritative `Sync`; Lite has no kit pump so `OnCalculateHandler` runs `SyncBadges` throttled 500 ms under `#ifdef BUILD_LITE`; `Sync` itself still never recomputes | 2026-09-08 |
| P-UI-11 | COLOR-row label buried under its own preview swatch (label invisible, row looks headless) | Label `L` drawn at `px+PAD_X` for all kinds, but kind==4 preview `CB` starts at the same X with higher ZORDER (1520 < 1540) | kind==4 moves `L` to `ry+2` like kind==6 (label-above in the 42px row — R-PANELMOD exception alongside TEXT rows); update path never touches `L` so create-time position sticks | 2026-09-08 |
| P-UI-12 | Menu hover tooltip fires over an open settings card (phantom tip, Z1700 over panel) | `CircTipTick` (per-tick) had no panel-occlusion awareness; hotkey-opened panels never cleared a visible/armed tip; Menu is included BEFORE Panels so it cannot call `PnlPointInside` | Cross-layer flag `g_UIPanelOpen` in `GlobalVariables.mqh` (set in `PnlOpen`, cleared in `PnlCloseAll`) + `CircTipDisarm()` called from `PnlOpen`; `OnMove`/`Tick` abort while flagged; `CircTipShow` clamps bottom + tiny-chart floor | 2026-09-08 |
| P-UI-13 | Tools-ring fan stacks on one line near chart edges (46px spacing vs 52px footprint — overlap) | `ToolsLayout` clamped every item independently, destroying the ±55° spread (the ring itself uses `CircFitRadius`) | `ToolsFitRadius` (same ray-vs-bounds math over the TOOL_COUNT fan angles): shrink the radius, keep the clamp only as last-resort safety | 2026-09-08 |
| P-UI-14 | Hold-to-open fires too eagerly (250ms): strip/cards pop on plain holds and on press-pause-drags — bad UX | 250ms is below a deliberate hold; press-pause-drag always outlasted it, and move-cancel only helped pure quick drags | One deliberate hold language: box hold (`BK_HOLD_MS`) and ring long-press (`LONG_PRESS_TIME`) both 500ms; any >8px move before the delay cancels the pending hold, so drags never open it (move-cancel already existed — the delay was the whole bug) | 2026-09-08 |
| P-LBL-01 | Persian caption pasted as a literal into a .mqh renders as mojibake on chart after save/compile on another machine | Non-ASCII literal bytes depend on the file encoding; MetaEditor/MQL4 reads source per the system codepage, so the same bytes decode differently elsewhere | Never put a non-ASCII literal in .mqh source — construct the string from ushort code points via StringSetCharacter over a pre-sized ASCII string (see TRexCaptionText in Biotak/LabelFunctions.mqh); source stays pure ASCII and renders identically everywhere | 2026-09-08 |
| P-LBL-02 | Persian caption shows as `????` even though the string bytes are right | `inpFontName` is `"Arial Bold"` — not a real family name — so MT4 falls back to a font with no Arabic glyphs | Force `"Tahoma"` (ships with Windows, full Arabic cover, nothing to download) on the caption object after creation, every refresh (see `DisplayTRexTitleBlock`); leave ASCII labels on the default font | 2026-09-08 |
| P-LBL-03 | Trade-block numbers frozen until TF switch | Trade labels repaint only on relayout (`needLabels` gate); no per-tick path ever touched them (the bar-freeze assumed per-tick calls) | Throttled 2s in-place live pump `TradePlanLiveTick()` in `LabelFunctions.mqh` (Full: `RefreshUIPerTick`, Lite: 500ms block); change-guarded signature incl. countdown, no clear | 2026-09-09 |
| P-LOG-01 | `tools/fetch_tradeplan_log.ps1` showed garbled `?????` output or failed to read the live MT4 log file | MT4 writes `MQL4\Logs\*.log` as UTF-16 LE with BOM and keeps the file locked while running; `Get-Content -Encoding Unicode` fails on a locked file | Use `[System.IO.File]::Open(path, Open, Read, ReadWrite)` + `New-Object StreamReader($stream, $true)` (BOM auto-detect); fall back to `Get-Content` on error. Updated in `tools/fetch_tradeplan_log.ps1`. | 2026-09-09 |
| P-LOG-02 | Experts tab shows fresh lines but `MQL4\Logs\*.log` (and Journal) frozen for 1 h+ — looks like stale data, isn't | The terminal's own disk-flusher wedges while the process runs fine (both files stop at the same second, in-memory Experts view stays live) — local-only, nothing to do with the broker feed | Full restart first (File → Exit, reopen) so the file flows again; durable bypass: our numbers ALSO auto-export to `MQL4\Files\tradeplan-auto-<SYM>.log` (FileClose flushes immediately) — `fetch_tradeplan_log.ps1` reads it first | 2026-09-10 |
| P-TRADEPLAN-01 | EURUSD [SNAP] shows M1 SL=1 / TP1=2 — looks broken compared to XAUUSD, caused panic re-investigate | These numbers ARE correct: EURUSD M1 composite ATR ≈ 0.8 pips = 0.00008 in price, so SL=round(1.2×0.8)=1 pip is right. The formula is symbol-agnostic (uses `GetCachedPipSize()`); small pip values are expected for tight FX pairs on low TFs. Do NOT change formulas because EURUSD numbers look small — verify by checking the symbol's actual pip size first | 2026-09-09 |
| P-TRADEPLAN-02 | Eng values diverged from professor's for M15/H4/D1/W1/MN (our composite weighted ATR ≠ professor's Eng) — old code used composite ATR(triggerTF) for Eng(M15+) which depends on 6 Wilder periods and was live/volatile | The professor's Eng uses ONE stable formula for ALL 8 TFs: `Eng(TF) = iATR(triggerTF, TF_min/triggerTF_min, 1) / pip` — a single-call Wilder ATR whose period = number of trigger-TF bars per chart bar (M1:period=1, M5:5, M15:15, H1/M5:12, H4/M15:16, D1/H1:24, W1/H4:42, MN/D1:30). shift=1 means it's frozen until the NEXT trigger bar closes → very stable. Verified all 8 TFs on XAUUSD Sep-4 data (SUPERSEDED 2026-09-10 by R-ENGPARITY: that match was XAUUSD's persistent vol; the formula is a one-chart-bar window and misses W1/D1 by -39%/-33% — do NOT restore it — the legacy Eng path is deleted, R-ENGONE 2026-09-10, user decision). Fix: `TradePlanSessionEng()` in `TradePlanFormulas.mqh`, `TradePlanEngTrue` and `TradePlanCompositeEngOf` are thin wrappers. | 2026-09-09 |
| P-SNAP-01 | `[SNAP]`/`[TRADEPLAN]`/`[ATRLEGS]`/`[PROF*]` flow on their own again, change-guarded (numeric sig + 3 s snapshot / 60 s legs throttle) — professor's side arrives via screenshots, paired offline by timestamp (auto-logging restored 2026-09-10; `X` still dumps everything incl `[PROF*]` on demand) | The snapshot gate `s_snapMs` is inside `TradePlanLiveTick()` which itself requires `!IsIndicatorHidden()` and a 2s throttle + sig change; on a static D1 chart the sig never changes so neither does the snapshot | `X` (`inpLogDumpKey`) still dumps everything on demand; otherwise just `fetch_tradeplan_log.ps1` — fresh lines prove ticking. If 0 lines, the indicator isn't ticking | 2026-09-09 |
| P-BUILD-05 | `[SNAP]` trade-plan numbers still matched the OLD composite-Eng formulas although main had the correct fix (`47125bc`) — the 12:18 dump reproduced values of a build that was already reverted (see GitHub issue #1) | A STALE `.ex4`: the terminal kept running the EX4 compiled from the reverted `8ec0298` (08:24 build). `git pull` + source fix change nothing for a compiled file, and MT4 never hot-swaps a replaced EX4 into a running indicator (P-ICONS-03b) | After EVERY `git pull` touching the trade-plan chain: recompile (`compile-th3.ps1` workspace + Lite), then **remove & re-add the indicator** (or restart MT4). Prove the wiring with `Biotak_TradePlan_Golden_Test.mq4` on XAUUSD M1 → `[TPGOLD] RESULT: PASS` (deployed to terminal `MQL4\Scripts` for one-click run). Regression history: TRADEPLAN_MASTER_REFERENCE.md §5 | 2026-09-09 |
| P-PERF-01 | Idle chart churns forever (2 s full trade-block delete+recreate + 7 Prints + 8-TF snapshot every 2-3 s); N full repaints per BK pump; TF-switch lag | `TradePlanLiveTick` sig included the 1 s countdown so it never matched; `SyncBadges` raw `ChartRedraw` per box; HTF raw redraw bypassing the 100 ms throttle; `CreateATRTradeLabel` wiped `Current_*` it recreated below | Numeric-only sig + cheap in-place countdown/spread path (logs/snapshot/TopRows only on numeric change); BK `bkNeedPaint` flag, one redraw after loop; HTF via `ThrottledChartRedraw`; one-time legacy purge, no self-wipe | 2026-09-10 |
| P-ATR-01 | "Unify every ATR onto the composite" breaks the trade-plan block (SL/TP/Hunter drift off the professor) [SUPERSEDED for Eng by R-ENGPARITY 2026-09-10: Eng IS the own-TF composite ÷ divisor now; the rule below still holds for every ATR DISPLAY] | `TradePlanEngTrue` is the professor's SINGLE-`iATR` session formula (R-TRADEPLAN), not the display composite — prof Eng(MN)=983 vs composite D1=1100.8 on the same bars. Audit 2026-09-10: every live DISPLAY/volatility/step path already uses the composite (`GetATRForTimeframe`/`CalculateWeightedATR` ← `BatchWilders` legs); SMA-batch/manual-TR/hybrid/compat-shim/`TH3Math-iATR` are dead in prod (tests/retired/fallback only) | Every ATR DISPLAY goes through `GetATRForTimeframe` (never raw `iATR`/SMA); cross-check strip vs `[SNAP]` TR column (slow TFs must match exactly). Eng is no longer an exception: R-ENGPARITY (2026-09-10) put it on the own-TF composite ÷ hard-coded `TRADEPLAN_ENG_DIVISOR`; the old single-`iATR` Eng path is deleted (R-ENGONE 2026-09-10, user decision) | 2026-09-10 |
| P-ATR-02 | Professor's REAL composite is SMA, not Wilder (`TrexATR` source surfaced 2026-09-10: simple TR mean + newest-bar same-close quirk + MN1→SMA-55 branch, weights 1/1/2/3/5/8) | Our engine used Wilder `iATR` legs; on 333-bar MN history the Wilder seed (calm 2000s) drags long legs down vs SMA — that was the W1/MN gap, not weights (a same-day Wilder reweight was tried and retired for masking it). Fix: `CalculateATRBatchTrex`/`TrexSMALeg` in `ATRCalculations.mqh` replicate the source verbatim (quirk included); engine call site switched; `TradePlanEngTrue` later moved ONTO this composite by R-ENGPARITY (2026-09-10, ÷ `TRADEPLAN_ENG_DIVISOR`) — the strip and Eng now share one source, deliberately. Verify via same-minute `[PROFATR]` pairing, never by fit alone. | 2026-09-10 |
| P-ATR-03 | Exhaustive ATR search still leaves D1 +5% / MN -4% with no shippable formula (63 subsets, LSQ, shifts, divisors, best-N × SMA/Wilder/HL — `tools/atr_fit_eurusd.js`) | No TF-independent candidate clears all 8: best subset 8.8% worst-TF, LSQ only fits with meaningless negative weights, divisor bestK≈1.0, per-TF best-N scatters per family — and four different MN periods (24/30/97/204) hit simultaneously, so any single pick is lottery | Keep the current engine (joint-best in the scorecard); re-run the rig per new same-minute screenshot and ship only a 3-sample survivor — never a one-sample winner | 2026-09-10 |
| P-ATR-04 | `.hst` legs disagree with live terminal legs on the SAME closed bars (D1 subset mean 54 from boot `.hst` vs 50.2 live) — backfill revisions after boot move closed-bar history | The terminal rewrites history after boot (HistoryCenter backfill) while `.hst` files on disk are the boot snapshot; any `.hst` fit is therefore stale by construction, worst on fast TFs (30-45 min), still visible on D1 | Fit only against LIVE legs (`[ATRLEGS]` p/q/s dump, exact-minute); use `.hst` solely for period sweeps unavailable live, and never for absolute verdicts | 2026-09-10 |
| P-ATR-05 | Professor Eng = LONG-window Wilder on trigger TFs (spike-immune), NOT our short periods (RESOLVED 2026-09-10 evening by R-ENGPARITY: shipped Eng = own-TF composite TR / 4.266666; the trigger-TF window mechanism was right in spirit but our history cannot pin its length) — proven 2026-09-10: our H4/M1 engTrue tripled in the evening spike (10.21) while prof sat at 4.4; W1 iATR(H4,N) crosses his 32 between N=5000-10000 on our own history | Exact N unidentifiable (flat optimum: any N in [6k,12k] lands 30-34); MN needs pre-2019 D1 bars (our D1 starts 2019, caps at 74.4 vs 85.6 — unreproducible on young histories); XAUUSD match explained (persistent vol: short≈long there). Do NOT ship a guessed N — tonight's free test: after the 20:00 server H4 close, long predicts his H4-Eng stays ~4.4, short predicts a jump | 2026-09-10 |
| P-PROF-01 | Need the professor's numbers/formulas but only his `.ex4` exists (no source) | `.ex4` string literals are ENCRYPTED — a strings-scan finds nothing, don't retry. And MQL4 cannot read other charts' objects — our logger must run ON his chart. Fix: `TradePlanLogProfAtr()` in `Biotak/LabelFunctions.mqh` (self-discovering X-hotkey dump (`TradePlanDumpNow` → discovery scan + immediate re-read → `[PROFOBJ]`/`[PROFATR]` with timestamps; NO background scanning — user decision 2026-09-10, logs only on demand; Lite-safe literals only) + attach our Lite to every chart his indicator runs on. Fetch script captures `[PROF*]`. | 2026-09-10 |
| P-BUILD-06 | Manual remove & re-add after every compile (P-ICONS-03b/P-BUILD-05 tax) | MT4 only reads the `.ex4` at attach; a replaced file never hot-swaps. Fix: RETIRED 2026-09-10, same day — `ChartSetSymbolPeriod` re-inits from the IN-MEMORY image and never re-reads the `.ex4` from disk (proven by a 744-line `[RELOAD]` loop: the token never advanced past the running build, with full-rebuild CPU churn every 2 s). There is NO programmatic code-redeploy in MQL4 — manual remove & re-add stays mandatory (P-ICONS-03b stands). All P-BUILD-06 code reverted the same session (module, flag broadcast, BuildTag, timer/tick hooks). | 2026-09-10 |
| P-NET-01 | Terminal silent (no ticks) although process runs and a TCP socket shows ESTABLISHED — looks like a code freeze but isn't | Same demo account logged in from a second IP (Journal: `previous successful authorization from 89.198.141.27`): the sessions kick each other, the loser keeps a lingering dead socket with zero quotes. Diagnose by triple-zero-growth over 60 s (Experts log bytes + M1.hst bytes + Journal tail all frozen) — NOT by socket state. No code/API fix exists (no login API, no credentials); fix is operational: one session per account, or a second free demo (File → Open an Account) so both terminals stay green. | 2026-09-10 |
| P-BUILD-07 | Two build paths overwrite the same ex4 with different binaries (unknown provenance) | Manual MetaEditor F5-debug compiles a DEBUG ex4 over the script-built RELEASE ex4 (proven: same source, sizes 1,221,526 vs 1,220,064 + user debug habit). Rule: ONE build path only — `compile-th3-doubleclick.bat` (release); if F5-debug is used, rebuild via .bat right after. Running generation is proven ONLY by the `[BUILD] TH3 <tag>` log line after attach, never by file date. | 2026-09-10 |
| P-DEV-01 | MetaEditor Debug (green ▶) terminal closes instantly | The debugger launches its OWN terminal instance on the same data folder — two terminal.exe cannot hold one data folder (file locks), so the debug instance dies at once while the normal one (running since morning) holds it. Not a code bug. Fix: close the running MT4 completely first (File → Exit), THEN press Debug (it launches its own instance and stays). Note: MetaEditor-Debug ≠ our `DEBUG_BUILD` flag (step-through vs verbose-log production build). | 2026-09-10 |
| P-DEV-02 | One-click redeploy script is impossible in MQL4 (do not attempt again) | MQL4 has `ChartIndicatorDelete` but NO `ChartIndicatorAdd` (MQL5-only — compiler error 168 proves it), so a script can strip indicators but never re-add them. The old `ReloadBiotak.mq4` never compiled and would have left charts naked — DELETED 2026-09-10. Deploy stays: `compile-th3-doubleclick.bat` (build) + manual per-chart remove/re-add + `[BUILD]` tag as arrival proof. | 2026-09-10 |
| P-GUARD-01 | A safety guard existed but NEVER ran: `TradePlanSelfCheck` was defined (and AGENTS.md claimed "Guarded by TradePlanSelfCheck()") yet nothing ever called it — a rounding/wiring regression in the trade-plan chain would pass silently | MQL4 has no dead-code diagnostics; an unused function compiles clean, and the audit check only eyeballed the formula | Rule: every guard must be invoked from a REAL path. `TradePlanDumpNow` (X hotkey) now runs SelfCheck and logs `[SELFCHECK] OK/FAIL` (skipped under alt formulas — their Hunter leg breaks the 8/3×Eng identity by design). Before claiming a guard exists, grep for its call site. | 2026-09-10 |
| P-LBL-05 | Turning the ATR labels off (A / card-2 master) also removed the bar-close countdown, and its look was hard-coded | The countdown was a row of the ATR trade block: `SetATRLabelsVisibility` set its `TIMEFRAMES` with the block's flag, the periodic object janitor hides every object whose name contains `ATR_` while the ATR labels are off, and color/size/gap were literals | The countdown is its OWN layer (2026-09-11, user request): object `..._LBL_CloseIn_Tag` (never `ATR_`-named — that janitor stays a trap), own switch `g_showLiveCountdown`/`OV_CD` + `inpCountdownKey` = `D`, own `g_countdownColor/FontSize/GapPx` (`OV_CDC/CDS/CDG`), panel rows 0-3 of card 2 (`g_PnlRows[2]` 7→11; rows 4+ are the old ATR block rows — keep the row maps in `PnlRowDef`/`PnlDefVal`/`PnlDefColor`/`PnlCurrent`/`PnlApply` in the same order), palette kind `PAL_COUNTDOWN`, `RefreshLiveCountdown()` called from the 1 Hz pump (BEFORE the ATR gate), both label-relayout paths, the `CHART_CHANGE` hook, and the new toggle/apply rows. Clicking the tag opens card 2 via `LiveCountdownPointInside()` (rect cached at paint; the object stays unselectable). `SetATRLabelsVisibility`/`DisplayATRTradeLabels` now only PURGE the legacy `ATR_Trade_Current_CloseIn`. Lite cannot call `ClampInt` from `LabelFunctions` (P-ARCH-02) — clamp by hand there. **LOCKED BY `Biotak_Countdown_Test.mq4`** (script, `[CDTEST]`): PART 1 name has no `ATR_` (the janitor predicate), PART 2 survives the ATR-off sweep, PART 3 own switch off = object gone + rect invalidated (the old spot must not answer clicks), PART 4 click region == the painted rect (dense grid scan, no phantom area / no dead spot), PART 5 park — an invalidated rect answers nothing and with the live bar scrolled off-view there is NO click target anywhere on the chart. | 2026-09-11 |
| P-LBL-04 | `Close in : ...` countdown sat in the bottom-right corner block, far from the bar it counts, and nothing about it moved with the market | It was one of the two centered rows of the R-TRADEPLAN corner block — a screen-anchored `OBJ_LABEL` at `CORNER_RIGHT_LOWER`, refreshed on the 2 s trade-block pump | Countdown is now a COMPACT TAG BESIDE THE LIVE CANDLE at the live price (2026-09-11, user request): `CreateLivePriceCountdown()` draws `..._LBL_ATR_Trade_Current_CloseIn` as a `CORNER_LEFT_UPPER` `OBJ_LABEL` whose X = bar-0 right edge + 6 px (bar width taken from bar 1's pixel X, so the gap scales with the zoom) and whose Y = `ChartTimePriceToXY(quote)` (quote = bid/ask mid) minus half a line — so it hugs the candle, rides the price, and stays clear of the body. Flips to the candle's LEFT when `x + width` would cross the right-margin boundary (`cw - inpLabelsMarginLeft`, where the price scale starts). Refreshed at 1 Hz from `TradePlanLiveTick` ABOVE the 2 s gate AND from the `CHARTEVENT_CHART_CHANGE` hook — the label pipeline is 2 s gated itself, so scroll/zoom needs its own try (the tag would otherwise lag a drag-scroll by up to 2 s). Chart scrolled off bar 0 / quote out of range ⇒ tag parked with `OBJ_NO_PERIODS`, never drawn at a made-up level. Same object name ⇒ `SetATRLabelsVisibility` / `ClearAllLabels` wiring untouched. Type-change trap: a same-name `ObjectCreate` of another type does NOT replace the old object (corner label / candle text) — delete first. | 2026-09-11 |
| P-PANELUI-01 | The 13 redesigned settings cards rendered as BARE LABELS on the chart (old look) even though the compile reported `0 errors` and the new BMPs were on disk | **A generated bitmap that has no literal `#resource` is embedded NOWHERE.** MetaEditor only errors when a `#resource` points at a MISSING file — an ABSENT declaration compiles clean, and at runtime `ObjectSetString(...,OBJPROP_BMPFILE,...)` just does nothing. So every chip/switch/rail/glyph silently failed to load and only the text labels survived. `BiotakPanels.mqh` declared only `pnl_card1-16`, `pnl_knob`, `pnl_cb_*`, `bk_*` — the 399 `gl_*` glyph inks and all the R-PANELUI2 chrome (`pnl_rail/sw_on/dsw_on/vchip/mark/secdot/topbar/hair/actbg/add/chev/cntchip/keycap/xbtn/secband`) were never declared. | `python tools/add-panel-resources.py` appends the deduplicated declarations (idempotent — re-run freely) after the `bk_*` block. **After ANY new panel icon: regenerate → run that script → sync `Files/Icons` into the terminal → recompile.** Pre-flight proof: extract every declared name and assert the file exists in the TERMINAL's `MQL4\Files\Icons` (522/522 at the 2026-09-11 fix). | 2026-09-11 |
| P-PANELUI-02 | Cards taller than 12 display rows drew with NO card body / NO shadow behind their bottom rows and footer (transparent gap), and closing such a panel left orphan row objects on the chart | (a) `PnlCreate` clamped the skin with `MathMax(3, MathMin(12, rowsCount))` while the redesign's section bands push Zones & Levels / ATR Labels to **15** display rows → they fell back to `pnl_card12`; (b) `PnlDestroy` looped `r<13` and knew nothing about the new chrome object names | Skin clamp now `PNL_CARD_ROWS_MAX` (20) — keep it equal to the generator's `PNL_CARD_ROWS_MAX`; the destroy loop runs to `PNL_CARD_ROWS_MAX` and purges every new suffix (`_BAND _BDOT _SL _SHR _BCNT _BCNL _SECS* _CS* _CSK* _CSL* _SW* _DL* _VC _GL _CHP _QA _QAG _NAVC _NAVL _DDI _TIC0..8`) plus the header chrome (`topbar hair mark markg keyc keyl ver xbg xgl`). A display row IS a 42px row, so `PnlRowsCount` is the SPEC length, not the setting count — all hit-tests iterate it, and `PnlSetRow/PnlCurrent/PnlApply/PnlDefVal` map display→setting. | 2026-09-11 |
| P-BUILD-08 | Driving MetaEditor from an agent session: `Start-Process metaeditor.exe /compile` exits in ~0.07 s with an EMPTY exit code and writes NO log — looks like a total failure | MetaEditor is **SINGLE-INSTANCE**: a CLI `/compile` is forwarded to the already-running MetaEditor window (the user's own open editor) and the launcher returns immediately, while that window compiles ASYNCHRONOUSLY. `-Wait` therefore proves nothing. | Launch, then **POLL the log's LastWriteTime** until it advances and its text matches `Result:` — the real compile lands ~1 s later (`tools/compile-poll.ps1`). Do NOT `Remove-Item` the stale log to force freshness: the sandbox's safe-delete guard aborts the whole script (`SAFE_DELETE_BULK_GUARD_ERROR`). Never kill the user's MetaEditor (PID 1452 was theirs). | 2026-09-11 |
| P-TOOL-05 | A `.ps1` helper died instantly with bizarre parser errors (`Unexpected token 'MetaEditor'`, `Missing closing '}'`) on lines that looked syntactically fine | **Windows PowerShell 5.1 reads a `.ps1` as ANSI/Windows-1252 unless it has a BOM.** A UTF-8 em-dash (`—`) was decoded as `â€”`, whose trailing byte broke the string literal and cascaded into fake "unbalanced brace" errors at unrelated lines. Same class as P-TOOL-02. | Keep every `.ps1` **ASCII-only** (use `--` for dashes) and verify with `grep -nP '[^\x00-\x7F]' file.ps1` before running. Never trust the reported line number in a PS parse error — find the real offender by scanning for non-ASCII bytes. | 2026-09-11 |


| P-UI-15 | Header subtitle overruns the .ver badge on the two longest subtitles; dropdown chevron sits ON its own caption text; header reads ver-before-key | MT4 OBJ_LABEL has no letter-spacing and MT4 cannot measure text: 7pt subtitles end at x=256 past the badge edge at 249; dropdown width 26+6/len undercounts icon+gap+chevron+pad; .ver was placed before .key against the preview flex order | R-SUBFIT: subtitles render per-segment with 4px amber/jade dots at 6pt, greedily clipped against the .htxt box edge (badge/key aware); dropdown width 50+6/len min 72; header order key-then-ver. New header suffixes subd/sub join PnlDestroy | 2026-09-11 |
| P-TOOL-06 | A python one-liner wiped 5 source files to 0 bytes (open for write truncates before the read in the same expression is evaluated) | In a list-comp like open(f,'wb').write(open(f,'rb').read()...) the write-open runs first and empties the file, so the read returns empty; the terminal BiotakProject is a symlink to the repo so its copies died too | Never read+write the same path in one expression: read all bytes into a variable first (or write to a temp file then move); verify sizes after any bulk rewrite before staging | 2026-09-11 |
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
