# AGENTS.md — Biotak Trigger TH3 for TradingView (Pine Script v6)

The TradingView build of the MQL4 indicator at the repo root. Same product, same
numbers, same ladder — a different platform with a different set of walls.

Reply in Persian. Short lines. Proof (file, number, log line), no adjectives.
Test steps at the end. English only as literal code/screen names.

The rules live in [docs/contract.md](docs/contract.md). The build plan lives in
[docs/plan.md](docs/plan.md). How parity is proved lives in [docs/parity.md](docs/parity.md).

## Layout

```
TradingView/
  src/                         All product logic (*.pine modules, one owner each)
    entry/main.pine            Full entry — THIN, declares and includes only
    entry/lite.pine            Lite entry — same, without the readout surface
  10_const.pine                Every literal the product reads
  20_settings.pine             The settings MORE THAN ONE surface reads
  30_math.pine                 The numeric core — PURE, no chart access, parity-critical
  40_levels.pine               The ladder state: anchor, step, direction
  50_draw.pine                 The ladder surface + its purge owner
  60_panel.pine                The readout table + its own settings
  dist/                        Built single files — GENERATED, committed, never edited
  tools/                       build, dev watch, and the gates
  tests/fixtures/              The frozen oracle (see docs/parity.md)
  build/                       Scratch output, gitignored
```

## Rules

- **Pine has no `#include`.** The build IS the include system:
  `node tools/build.js` resolves `//@includes` from an entry and emits one file.
  Never paste a module into the editor; paste `dist/*.pine`.
- **A `dist/*.pine` is generated.** Hand-editing one is the defect, and
  `tools/check-structure.js` compares its sha256 against a fresh assemble.
- **Entries stay thin.** Build fails on a non-empty entry body.
- **Pine has ONE flat namespace.** Two modules declaring the same name is a hard
  error at attach and `check-structure.js` catches it at build.
- **`indicator()` is the first code line and cannot read a module.** The caps
  arrive as `{TH3_MAX_LINES}` placeholders the build substitutes from the owner in
  `10_const.pine` — one owner, one number.
- **A number is owned by `10_const.pine`.** Respelling `0.85`, `1.20`, `1.80`,
  `1.666`, `2.5`, `3.5` anywhere else in `src/` fails the structure gate.
- **A setting is owned by the surface that READS it.** `TH3_SET_*` declared and
  never read fails the gate.
- **The parity path is `30_math.pine`.** Anything that changes a number there must
  be re-proved: `node tools/check-parity.js`.
- **No clicks, no file writes, no moving tables.** Three platform walls, in
  contract §2. Do not design a control the platform cannot deliver.

## The dev loop

```bash
npm run dev            # build + structure + limits + validate, on every save
npm run gate           # build + every offline gate + parity
node tools/build.js
node tools/check-structure.js
node tools/check-pine-limits.js
node tools/pine-validate.js
node tools/check-parity.js
node tools/check-parity.js --selftest     # prove the parity checker can still FAIL
node tools/fixtures-derive.js --check     # the fixture file matches its generator
```

**There is no offline compiler, and that is a fact of the platform.**
`tools/pine-validate.js` runs `pinescript-v6-validator` — the same engine behind the
Pine Script v6 IDE Tools extension — so the editor and the gate cannot disagree.
But a green gate is not a chart: the last mile is a paste into TradingView, and
nothing here pretends otherwise. `tools/check-parity.js` is the strongest offline
evidence this project has, because it EXECUTES `src/30_math.pine` on PineTS against
the MQL4 build's own recorded numbers.

**A rule is gated only if its INVERSE fails a gate.** Before reporting a rule as
locked, run `node tools/check-parity.js --selftest`: it feeds the dataset checker a
consistent row (must pass) and five mutated rows (each must FAIL). A mutation that
SURVIVES is not a rule, it is a comment.
