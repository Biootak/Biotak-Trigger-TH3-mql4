# Biotak Trigger TH3 — TradingView (Pine Script v6)

The MQL4 indicator at the repo root, rebuilt for TradingView: same formula, same
numbers, same seven-rung ladder. The port is modular like the MQL4 tree — one owner
per module — but Pine has no `#include`, no offline compiler and no mouse events, so
three things are done differently and none of them is optional here.

| the wall | what this project does about it |
| --- | --- |
| Pine has no `#include` | `tools/build.js` IS the include system: it resolves `//@includes` from an entry and emits one file per entry into `dist/` |
| Pine's only compiler is the Pine Editor | `npm run dev` assembles + runs three offline gates on every save; `tools/check-parity.js` EXECUTES the numeric core on PineTS against the MQL4 build's own numbers |
| Pine has no click events, cannot write files, cannot move a table | the MQL4 cards become `input.*`, the readout is a table, and a position change needs a re-add — see `docs/contract.md` §2 |

## Toolchain (installed, latest at the time of writing)

| package | version | role |
| --- | --- | --- |
| [pinets](https://www.npmjs.com/package/pinets) | 0.11.0 | transpiler + runtime: runs the real Pine source on Node with a deterministic local data provider |
| [pinets-cli](https://www.npmjs.com/package/pinets-cli) | 0.1.15 | the same runtime as a command, for one-off runs |
| [pinescript-v6-validator](https://www.npmjs.com/package/pinescript-v6-validator) | 0.4.3 | the validation engine behind the *Pine Script v6 IDE Tools* VS Code extension — the closest thing to an offline compile check that exists |

`npm install` restores all three. `.vscode/extensions.json` recommends the matching
editor extension, so an editor and the gate never disagree about a file.

## Structure

```
src/entry/main.pine     THIN entry: declares, includes, holds no logic
src/entry/lite.pine     the same, without the readout surface
src/10_const.pine       ONE owner for every literal (K bands, ladder, ink, caps)
src/20_settings.pine    settings more than one surface reads
src/30_math.pine        the numeric core — pure, parity-critical, no chart access
src/40_levels.pine      the ladder state: anchor, step, direction
src/50_draw.pine        the ladder surface AND the sweep that takes it down
src/60_panel.pine       the readout table (and the settings only it reads)
dist/                   the built files you paste into TradingView — generated
tools/                  build, watch, and the gates
tests/fixtures/         the frozen oracle
docs/                   contract.md · plan.md · parity.md
```

A module's header is its contract:

```
//@module 30_math
//@owner the master step and the ladder - PURE numbers, no chart access
//@includes 10_const.pine
```

## Commands

```bash
npm install
npm run build        # assemble dist/*.pine, print modules / lines / sha256 / byte delta
npm run dev          # build + structure + limits + validate on every save
npm run check        # fixtures + structure + limits + validator
npm run parity       # run the numeric core against the MQL4 oracle
npm run gate         # everything
```

## What is measured, not claimed

* `tools/check-parity.js` — **51 fixture cases / 90 checks, 0 divergence**, plus **11/11**
  pip-size shapes. 33 cases are checks that already exist in the MQL4 build's own
  `tests/Biotak_TH3_Test.mq4` (the seven K bands, the macro/knot mother cases, the closed
  table, all seven ladder rungs up and down); 18 are `source-derived` and cite the
  `file:line` of the MQL4 rule each was read from.
* **the end-to-end source comparison found four real divergences**, and they are fixed
  and gated: the pip size on 2-digit metals (a silent 10x error), the owner rung being a
  constant instead of `close[1] x pct / 100`, the lock APPLYING its verdict instead of
  captioning it, and the seed chain missing its last fallback. Details in
  [docs/parity.md](docs/parity.md).
* the built indicator, executed on 400 synthetic bars, drew **4 rung lines + 4
  captions**, evenly spaced at `step=0.0059457283`, odd rungs solid / even rungs
  dotted, and every caption's number equals the seat it labels.
* `Samples/TH3_Dataset/Dataset.csv` currently carries **0 rows** (header only), so the
  dataset oracle has nothing to compare yet. `--selftest` proves that half of the
  checker still FAILS on 5 mutated rows — it is verified, not merely written.
* **No claim of having run on a real TradingView chart.** Nothing in this repo can
  make that claim; the last mile is a paste into the Pine Editor.

## The last mile

1. `npm run gate`
2. open `dist/BiotakTriggerTH3.pine` (or `..._Lite.pine`)
3. paste into the TradingView Pine Editor → *Save* → *Add to chart*
4. after any change to a setting that is read once at load (readout position), remove
   and re-add the indicator — Pine cannot move a table
