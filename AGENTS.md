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
| New icon/glyph/surface art | Generate with `node tools/gen-th3-icons.js` (glyphs, circ, badge, knobs, switches, panel cards) → `Files/Icons/`; center-orb art via `tools/make-orb-bow.ps1` ingest (see P-ICONS-04). `tools/gen-icons.ps1` / `gen-cards.ps1` are legacy — do not use |
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
  now 7 items), settings card 5, hotkeys (V/3/4/Backspace/ABCD routing), the
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

- **COLOR rows have inline quick-pick swatches** (2026-09-04 — color picking
  without opening the popup: preview block + 6 curated swatches
  (`PNL_QSW_*`, `QuickPalColor()` in `BiotakPanels.mqh`) + PICK button for
  the full palette popup. One tap applies live (`PaletteApplyColor` +
  `PushPalRecent` + `PnlUpdateRow`), selection ring marks the active color.
  New widget suffixes (`Q0..Q5`, `PK`) MUST be added to `PnlDestroy`
  (P-UI-02 leak lesson).

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
