# AGENTS.md — Biotak Trigger TH3 (MQL4)

MT4 custom indicator. MQL4 only, no Python.

Reply in Persian. Short lines. Proof (file, number, log line), no adjectives.
Test steps at the end. English only as literal code/screen names.

The rules live in [docs/contract.md](docs/contract.md) — one page, the only contract.
Anything not written there is not a rule.

## Layout

```
Biotak Trigger TH3.mq4        Full entry — thin stub
Biotak Trigger TH3 Lite.mq4   Lite entry — same, with #define BUILD_LITE
Biotak/                       All product logic (*.mqh, include-guarded, includes on top)
  EventHandlers.mqh           The composed chain both entries call
  RuntimeSettings.mqh         Single owner of panel-editable settings
  GlobalVariables.mqh         Indicator-wide state
Files/Icons/                  Runtime BMPs, embedded via #resource
tests/                        Harnesses, compiled by the gate
tools/                        Deploy, icon gen, submenu check
build-logs/                   Compile logs (gitignored)
```

## Rules

- Entries stay thin. All logic in `Biotak/*.mqh`.
- Never compile a `.mqh` directly.
- Shared modules must not call UI functions Lite does not have (breaks Lite).
- Settings live in `RuntimeSettings.mqh`; seed via `RuntimeSettingsInit()` first in init.
  `FF_` addresses never renumber.
- Indicator-wide state goes in `GlobalVariables.mqh`.
- Icons come from `node tools/gen-th3-icons.js` plus an entry in `tools/icon-manifest.txt`.
- Ownership and the MT4 traps: [docs/contract.md](docs/contract.md) §1–§2. Never copy a rule
  up into this file — the contract is the one home.
- Use file tools for reading/writing. Terminal is only for compile, git, move/delete, tests.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all
Get-ChildItem tests\*.mq4 | ForEach-Object { powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -SourceFile $_.FullName }
node tools/submenu_geometry_check.js
```

Success = `Result: 0 errors` in `build-logs/`. After BMP changes: recompile,
then remove and re-add the indicator in MT4.
