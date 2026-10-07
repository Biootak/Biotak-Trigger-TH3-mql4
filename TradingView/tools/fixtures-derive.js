// Regenerates tests/fixtures/step-fixtures.json.
//
//   node tools/fixtures-derive.js            # writes the file, prints what it froze
//   node tools/fixtures-derive.js --check    # fails if the file on disk has drifted
//
// THE ORACLE IS THE OTHER BUILD'S OWN TEST FILE. Every case below is a check that
// already exists in tests/Biotak_TH3_Test.mq4 - the `wording` is that line's label
// and `expect` is that line's literal, or that line's own expression evaluated once
// and frozen. Nothing here was invented, and nothing here is derived from the Pine
// source: a fixture that came out of the implementation would prove nothing.
//
// Freeze, do not recompute. The harness reads this file; only this script writes it.

import fs from 'node:fs';
import path from 'node:path';
import { ROOT } from './lib/pine-build.js';

const ORACLE = 'tests/Biotak_TH3_Test.mq4';

const K = (ratio, expect, wording, line) => ({ what: 'k', family: 'unified', ratio, expect, wording, oracle: `${ORACLE}:${line}` });
const UNI = (legCD, ratio, mother, rung, expect, wording, line, gt) => ({ what: 'step', family: 'unified', legCD, ratio, mother, rung, expect, gt, wording, oracle: `${ORACLE}:${line}` });
const CLK = (ratio, expect, wording, line) => ({ what: 'closedK', family: 'closed', ratio, expect, wording, oracle: `${ORACLE}:${line}` });
const CLS = (legCD, ratio, expect, wording, lines) => ({ what: 'closedStep', family: 'closed', legCD, ratio, expect, wording, oracle: `${ORACLE}:${lines}` });
const RATIO = (priorLeg, lastLeg, expect, wording, line) => ({ what: 'ratio', family: 'unified', priorLeg, lastLeg, expect, wording, oracle: `${ORACLE}:${line}` });
const LADDER = (anchor, ladderStep, dir, expect, wording, line) => ({ what: 'ladder', family: 'unified', anchor, ladderStep, dir, expect, wording, oracle: `${ORACLE}:${line}` });

// SOURCE-DERIVED cases: the rule is read out of the MQL4 source at the named line and
// the expected value is that rule's own arithmetic, evaluated once and frozen. These
// are NOT labels from the MQL4 test file - they are labelled `oracleKind` so no reader
// can mistake one kind of oracle for the other.
const SRC = 'source-derived';
const RUNG = (price1, pct, expect, why, cite) => ({ what: 'rungFromClose', family: 'rung', price1, pct, expect, wording: why, oracle: cite, oracleKind: SRC });
const SEED = (uni, rung, legCD, legAB, freqPct, expect, why, cite) => ({ what: 'seed', family: 'step', uni, rung, legCD, legAB, freqPct, expect, wording: why, oracle: cite, oracleKind: SRC });
const LOK = (derived, lockBase, lockOk, expect, why, cite) => ({ what: 'locked', family: 'lock', derived, lockBase, lockOk, expect, wording: why, oracle: cite, oracleKind: SRC });
const FREQ = (freqPct, expect, why, cite) => ({ what: 'freq', family: 'freq', freqPct, expect, wording: why, oracle: cite, oracleKind: SRC });

const cases = [
  // ---- P-TH3-STEP-16 pins, lines 262-297 -----------------------------------
  K(0.80, 2.5, 'uni: K 0.80 -> 2.5', 264),
  K(0.85, 2.5, 'uni: K 0.85 -> 2.5', 265),
  K(1.00, 3.0, 'uni: K 1.00 -> 3.0', 266),
  K(1.20, 3.0, 'uni: K 1.20 -> 3.0', 267),
  K(1.50, 3.5, 'uni: K 1.50 -> 3.5', 268),
  K(1.80, 3.5, 'uni: K 1.80 -> 3.5', 269),
  K(2.50, 1.0, 'uni: K 2.50 -> 1.0', 270),

  UNI(100, 1.0, 36, 10, 20.0, 'uni: macro mother sqrt(12*33.3)=20', 273),
  UNI(100, 1.0, 20, 10, Math.sqrt((20.0 * 100.0) / 3.0), 'uni: knot mother geometric', 275),
  UNI(51, 3.37, 50.4, 37.4, Math.sqrt(50.4 * 51.0), 'uni: CD rides the mother rung', 278),
  UNI(100, 1.0, 0, 10, Math.sqrt((10.0 * 100.0) / 3.0), 'uni: absent mother falls back to rung', 283),
  UNI(56, 2.0, 30, 10, Math.sqrt(10.0 * 56.0), 'uni: major extension leg is the unit', 287),
  UNI(0, 0, 0, 0, 0.0, 'uni: empty inputs answer 0', 292),
  UNI(100, 1.0, 0, 0, 100.0 / 3.0, 'uni: dead rung falls back to pattern', 295),

  // ---- the seven-rung ladder, lines 306-332 --------------------------------
  LADDER(1.1000, 0.0020, 1, [0, 1, 2, 3, 4, 5, 6].map((i) => 1.1 + (i + 1) * 0.002), 'ladder: up rungs 1..7 are D + n*step', 316),
  LADDER(1.1000, 0.0020, -1, [0, 1, 2, 3, 4, 5, 6].map((i) => 1.1 - (i + 1) * 0.002), 'ladder: down rungs 1..7 are D - n*step', 322),
  UNI(100, 2.50, 100, 10, Math.sqrt((100.0 / 3.0) * 100.0), 'ladder: major extension is not shrunk by K', 331, 100.0 / 3.5),

  // ---- the closed table, lines 636-655 ------------------------------------
  CLK(0.74, 0.0, 'closed K 0.74 -> none', 637),
  CLK(0.75, 2.5, 'closed K 0.75 -> 2.5', 638),
  CLK(0.85, 2.5, 'closed K 0.85 -> 2.5', 639),
  CLK(0.86, 3.0, 'closed K 0.86 -> 3.0', 640),
  CLK(1.20, 3.0, 'closed K 1.20 -> 3.0', 641),
  CLK(1.21, 3.5, 'closed K 1.21 -> 3.5', 642),
  CLK(1.80, 3.5, 'closed K 1.80 -> 3.5', 643),
  CLK(1.81, 1.666, 'closed K 1.81 -> 1.666', 646),
  CLS(0.00780, 0.00780 / 0.01000, 0.00312, 'closed step 78/100 -> BC/2.5', '648-649'),
  CLS(0.01000, 0.01000 / 0.01000, 0.01000 / 3.0, 'closed step ratio 1.0 K=3.0', 651),
  CLS(0.00500, 0.00500 / 0.01000, 0.0, 'closed step shallow -> false', 652),

  // ---- P-TH3-INFO-05: the CLOSING leg is B/C/D, line 147-176 --------------
  RATIO(0.0062, 0.0176, 0.0176 / 0.0062, 'leg map: closing leg B/C/D answers (ratio CD/BC)', 166),
  // line 159 reads "right R = 2.84 (K=1.666, 105.6 pips)" - 1.666 is the CLOSED table's
  // macro tier (TH3ClosedK), not the unified one: TH3UnifiedK(2.84) answers 1.0.
  CLK(0.0176 / 0.0062, 1.666, 'leg map: closed K 2.84 -> 1.666', 159),
  CLS(0.0176, 0.0176 / 0.0062, 0.0176 / 1.666, 'leg map: B/C/D step is |D-C|/K', 174),
  RATIO(0.0100, 0.0062, 0.0062 / 0.0100, 'leg map: A/B/C is NOT the closing leg', 176),
  CLS(0.0062, 0.0062 / 0.0100, 0.0, 'leg map: the wrong reading goes SILENT', 176),

  // ---- the OWNER RUNG is derived, not a constant ---------------------------
  // TH3PatternStepRungTF = THAbilityPrice(tf, iTime(tf,1)) = close(tf,1) * pct / 100.
  RUNG(1.1000, 0.1666, (1.1 * 0.1666) / 100.0, 'rung: H1 table 0.1666% of close[1]', 'TH3Pivots_B.mqh:23-37 + THCalculations.mqh:122-138'),
  RUNG(1.1000, 0.6666, (1.1 * 0.6666) / 100.0, 'rung: D1 table 0.6666% of close[1]', 'ConstantsAndEnums.mqh:316-326'),
  RUNG(2000.0, 0.3333, (2000 * 0.3333) / 100.0, 'rung: H4 table on a 2000 price', 'ConstantsAndEnums.mqh:316-326'),
  RUNG(1.1000, 0.0, 0.0, 'rung: a TF the table does not name answers NOTHING', 'FractalTimeframes.mqh:40-45 (index out of range -> 0.0)'),
  RUNG(0.0, 0.1666, 0.0, 'rung: a dead close answers NOTHING', 'THCalculations.mqh:136-137 (price <= 0 -> 0.0)'),

  // ---- the SEED CHAIN, in the renderer's own order -------------------------
  SEED(50, 10, 150, 100, 28.125, 50, 'seed: the unified step answers and nothing else is read', 'TH3Renderer_B.mqh:80-90'),
  SEED(0, 10, 150, 100, 28.125, 10, 'seed: the rung stands in when there is no step', 'TH3Renderer_B.mqh:84-88'),
  SEED(0, 0, 150, 100, 28.125, (150 * 28.125) / 100.0, 'seed: last fallback is the closing leg x frequency/100', 'TH3Renderer_B.mqh:90'),
  SEED(0, 0, 0, 100, 50, 50.0, 'seed: with no closing leg the AB leg carries it', 'TH3Renderer_B.mqh:90'),
  SEED(0, 0, 150, 100, 200, (150 * 28.125) / 100.0, 'seed: an out-of-bounds frequency falls back to 28.125', 'TH3Tool_A.mqh:378-388'),

  // ---- the LOCK is a VERDICT, never an input to the step -------------------
  LOK(100, 110, 0.25, 1.0, 'lock: inside the band the verdict says LOCKED', 'TH3Renderer_B.mqh:130-137'),
  LOK(100, 125, 0.25, 1.0, 'lock: the band edge (dev == okRatio) is INSIDE', 'TH3Renderer_B.mqh:130-137'),
  LOK(100, 200, 0.25, 0.0, 'lock: outside the band the judgement is UNLOCKED', 'TH3Renderer_B.mqh:130-137'),
  LOK(100, 0, 0.25, 0.0, 'lock: no base means no LOCKED verdict', 'Biotak/TH3/TH3Pivots_B.mqh:483-486'),

  // ---- GetCurrentTH3Frequency's own bounds ---------------------------------
  FREQ(28.125, 28.125, 'freq: the documented default passes through', 'TH3Tool_A.mqh:378-388'),
  FREQ(120, 120, 'freq: the upper bound is INSIDE', 'TH3Tool_A.mqh:382'),
  FREQ(120.0001, 28.125, 'freq: past 120% it is refused, not clamped', 'TH3Tool_A.mqh:382-387'),
  FREQ(0, 28.125, 'freq: 0 is OFF and the default answers', 'TH3Tool_A.mqh:382-387'),
];

// the fields the generated probe must carry for every case
const FIELDS = ['ratio', 'priorLeg', 'lastLeg', 'legCD', 'legAB', 'mother', 'rung', 'anchor', 'ladderStep', 'dir', 'price1', 'pct', 'freqPct', 'lockBase', 'lockOk', 'uni', 'derived', 'expect'];

const normalised = cases.map((c, i) => {
  const row = { id: `${String(i + 1).padStart(2, '0')}-${c.what}` };
  for (const f of FIELDS) row[f] = c[f] ?? 0;
  row.expect = c.expect;
  return {
    ...row,
    family: c.family,
    what: c.what,
    wording: c.wording,
    oracle: c.oracle,
    oracleKind: c.oracleKind ?? 'mql4-test-label',
    ...(c.gt == null ? {} : { gt: c.gt }),
  };
});

const fixture = {
  note: 'Two oracle KINDS, and the field `oracleKind` says which one each case is. (a) mql4-test-label: the wording is a Check(...) label from tests/Biotak_TH3_Test.mq4 and the expect is that line\'s literal or its own expression. (b) source-derived: the rule was read out of the MQL4 source at the cited file:line and the expect is that rule\'s arithmetic, evaluated once and frozen. NOTHING here is derived from the Pine source.',
  oracle: ORACLE,
  tol: 1e-9,
  relTol: 1e-12,
  cases: normalised,
};

const out = path.join(ROOT, 'tests', 'fixtures', 'step-fixtures.json');
const text = JSON.stringify(fixture, null, 2) + '\n';
const check = process.argv.includes('--check');

if (check) {
  const onDisk = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : '';
  if (onDisk !== text) {
    console.error(`[FAIL] tests/fixtures/step-fixtures.json has drifted from tools/fixtures-derive.js - regenerate it deliberately with: node tools/fixtures-derive.js`);
    process.exit(1);
  }
  console.log(`[PASS] fixtures gate - ${fixture.cases.length} case(s), generator and file agree`);
  process.exit(0);
}

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, text, 'utf8');
console.log(`[fixtures] wrote tests/fixtures/step-fixtures.json - ${fixture.cases.length} case(s), oracle ${ORACLE}`);
const byWhat = {};
for (const c of normalised) byWhat[c.what] = (byWhat[c.what] ?? 0) + 1;
for (const [k, v] of Object.entries(byWhat)) console.log(`           ${String(v).padStart(2)}  ${k}`);
