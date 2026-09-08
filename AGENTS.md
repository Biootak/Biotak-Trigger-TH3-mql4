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
  (2026-09-08 — bottom-right block is 2 centered rows: `Close in : ...`
  countdown (red) / `#SL:-S #TP1+T1 #TP2+T2 #TP3+T3` single row (blue);
  top-right under the stamp: `Hunter SL: H Eng.SL: E` (red) /
  `Str Bond: A - B` (blue). The ATR-pips row is retired (ATR stays the
  hidden engine only). Top-right
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
  (2026-09-08 — reverse-engineered from the professor's TRex screenshots,
  all 8 TFs: plan base = ATR pips of `min(chartTF,D1)` (MN/W1/D1 show the
  daily plan); `SL/TP = base*(6,14,30,62)`; `Eng = (1|3|5)*ATR(triggerTF)`
  (M1:1, M5:3, else 5; trigger = 2 ladder steps down, M1 floor — same ladder
  as `GetTriggerDurationSeconds`); `Hunter = round(8*EngTrue/3)` from the
  UNROUNDED Eng (rounding the rounded Eng breaks H1 by 2); `StrBond2 =
  round(190*base/3)`; `StrBond1 = round(40*ownATR/3)` from the UNcapped
  own-TF ATR (the "Hunter 2-above" read was emergent, not causal — both
  equal 40/3 of the shared TF wherever both exist, so M1..D1 are
  bit-identical; NO W1/MN exception, works on fractal TFs too). Symbol-free by
  construction (only ATR + symbol-aware `GetCachedPipSize()`, no pair
  constant) + `TradePlanSelfCheck()` rounding-integrity guard for any
  symbol. Display (`LabelFunctions.mqh`) renders, never recomputes.
  Cross-symbol validated on EURUSD/D1 (SL103/TP240/514/1062 + Hunter31/
  Eng12 + StrBond228-1085 all reproduce; full walkthrough: TRADEPLAN_FA.md).)

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
