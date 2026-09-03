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
| New icon/glyph/surface art | Generate with `tools/gen-icons.ps1` (glyphs, circ, orb, badge, yy, knobs, switches) and `tools/gen-cards.ps1` (panel cards) → `Files/Icons/` |
| Geometry constants for UI | `Biotak/BiotakMenu.mqh` (`#define CIRC_*`, `CIRC_*_SIZE`) and `BiotakPanels.mqh` (`PNL_*`) — keep in sync with the BMP sizes |
| Docs | Architecture/rules → `ARCHITECTURE.md`; user/feature docs → Persian `.md` files kept in sync |
| Standalone test harness | Root `*_Test.mq4`; shared audit modules under `Biotak/Tests/` |

Icon filename ↔ ring feature mapping lives in `CircIconRes()` in
`Biotak/BiotakMenu.mqh`. Geometry constants (`CIRC_ICON_SIZE 28`,
`CIRC_BG_SIZE 52`, orb 56, ...) must match the generator output sizes.

### R-ICONS — icon rules (read before touching Files/Icons)

- `Files/Icons/*.bmp` are **32-bit BGRA with a real alpha channel**. MT4
  renders them because they are loaded via `#resource` + `::Files\Icons\...`.
  Do **not** run `convert_icons_24bit.py` / `gen_icons.py` on them — that
  flattens alpha and produces opaque tiles (see P-ICONS-01).
- **Canonical regeneration: `node tools/gen-th3-icons.js`** writes all 42
  BMPs (11 ring glyphs + orb/circ/badge/yy/knobs/switches + 10 opaque panel
  cards) into `Files/Icons`, in the amber-on-glass language shared with the
  sibling ichimoku project (same rendering engine, 4× supersampling, true
  alpha). For the complete **regenerate → compile → sync-into-every-terminal
  → verify** flow run `tools/deploy.ps1` (see Build section).
- Legacy generators `tools/gen-icons.ps1`, `tools/gen-cards.ps1`,
  `convert_icons_24bit.py`, `gen_icons.py` are **deprecated** — their output
  flattened alpha or was judged not delicate/glassy enough (P-ICONS-01/02).
  Do not use them for the shipped set.

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
