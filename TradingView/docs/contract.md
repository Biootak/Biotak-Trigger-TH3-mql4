# contract.md — the rules of the TradingView build

One page. A rule here is not advice: a build that fails a line is a bug.
Every claim carries a number (file, count) or it is not a claim.
A note that no longer matches the code is DELETED, not kept.

The MQL4 contract at `../docs/contract.md` still governs the product's *meaning*
(what a step is, what a rung is, what "locked" means). This page governs the port.

## 1. Ownership (one owner, never a second copy)

| value | owner |
| --- | --- |
| every literal the product reads | `src/10_const.pine` |
| settings read by more than one surface | `src/20_settings.pine` |
| settings read by exactly one surface | that surface's module |
| the master step, the K tables, the ladder arithmetic | `src/30_math.pine` |
| the anchor / step / direction model | `src/40_levels.pine` |
| the drawn ladder, and the sweep that removes it | `src/50_draw.pine` |
| the readout table | `src/60_panel.pine` |
| the build, and the include graph | `tools/build.js` |
| the oracle the numbers are judged against | `tests/fixtures/step-fixtures.json` + `../Samples/TH3_Dataset/Dataset.csv` |

Pine resolves top-down and has ONE flat namespace, so **include order IS ownership**
(`10_const → 20_settings → 30_math → 40_levels → 50_draw → 60_panel`). A name
declared twice is a hard error at attach, and `check-structure.js` catches it at build.
A second JS copy of a `30_math` formula is forbidden, not merely discouraged: the
parity harness executes the Pine, so a JS twin could only ever drift.

## 2. What Pine cannot do (and the answer this build ships)

- **no chart-click event, none at all**: every MQL4 control becomes `input.*`; the
  panels become a readout. A table cell can never answer a click.
- **no file write**: there is no recorder here. Samples come from the MQL4 side; the
  TradingView side can only raise an alert.
- **`table.new` fixes the position at creation** and there is no `set_position`, so a
  position change needs the indicator re-added. Say so; do not design around it.
- **one compiler, and it is on TradingView**: the last mile is a paste. Every offline
  gate exists to make that paste cheap, not to replace it.
- **hard caps**: 64 plot-family outputs, 40 `request.*()`, 500 lines/labels/boxes.
  `check-pine-limits.js` counts them on the generated artifact.
- **`//@version` must be line 1** and the declaration is the first code line, so the
  caps reach it as `{TH3_MAX_LINES}` placeholders substituted by the build.
- a script is either `indicator()` or `strategy()`, never both.

## 3. Parity (the acceptance criterion, in one line)

**Same numbers, same levels — not same pixels.** The measure:

1. every branch of `30_math.pine` against the MQL4 build's own test labels
   (`tests/Biotak_TH3_Test.mq4`), exact to `1e-9`;
2. the seven-rung law `{1,3,5,7}` against the recorded `Target_*` prices, read from
   the least-rounded columns a dataset row carries;
3. the drawn ladder: `N` rungs, uniform spacing, rungs numbered `1..N`, each caption
   equal to the seat it labels, targets solid and shelves dotted.

A tolerance is derived, never chosen: the CSV's own rounding is the only slack the
dataset is read with (§ `tools/check-parity.js` `toleranceFor`).

## 4. Settings and state

- One `input.*` per value, at the top of the module that READS it. An `input` nothing
  reads is an owner without a caller and `check-structure.js` fails the build.
- State that survives a bar is `var`; state that must survive a re-attach does not
  exist in Pine — there is no equivalent of a `GlobalVariable`, so nothing is designed
  to depend on it.
- `nz()`/`na()` guards run at the read, not at the write: a missing anchor must read
  as "no answer", never as a zero that paints.

## 5. Performance (a still frame costs zero writes)

- The ladder surface rebuilds only when the model MOVED (anchor bar, step or
  direction changed). A tick that changes nothing writes nothing.
- The readout rewrites only when its content key changes.
- Nothing whose cost scales with history enters a per-bar path; every loop is bounded
  by a stated count (`TH3_LADDER_N`, `TH3_SET_RUNGS`).
- The parity harness may be expensive; the dev loop may not. `npm run dev` runs
  build + structure + limits + validator. Parity is its own gate.

## 6. Gate (definition of done)

1. `npm run build` → `BUILD OK`, and every entry names its modules, its line count and
   its `sha256`. **A green build that rewrote nothing changed nothing** — the script
   says so out loud.
2. `node tools/check-structure.js` passes: every module reachable from an entry, one
   owner per constant, no duplicate name, no orphan setting, `dist/` matches a fresh
   assemble.
3. `node tools/check-pine-limits.js` passes: every platform cap counted, not assumed.
4. `node tools/pine-validate.js` passes: 0 errors.
5. `node tools/check-parity.js` passes: 0 divergence across the fixture oracle, the
   dataset oracle (when rows exist), and the drawn ladder.
6. `node tools/fixtures-derive.js --check` passes: the frozen fixture file still
   matches its generator. A fixture edited by hand is a moved goalpost.
7. `node tools/check-parity.js --selftest` passes: the dataset checker still FAILS on
   every mutated row. **A rule is gated only if its INVERSE fails a gate.**
8. The report names the file, the number and the measurement.

## 7. Report (what a finished change looks like)

- the file, and the line count before/after;
- the number the change moved, measured, with the command that produced it;
- the dependents: every module that reads what changed, as `file:line`;
- the gate output, verbatim, including any gate that could not run — a gate that did
  not run is reported as not run, never as a pass;
- and, if the change touches `30_math.pine`, the parity numbers.
