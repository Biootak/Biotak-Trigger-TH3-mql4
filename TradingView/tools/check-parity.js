// PARITY - the same numbers, in every state, and the levels drawn the same way.
//
//   node tools/check-parity.js                 # fixtures + dataset + the drawn ladder
//   node tools/check-parity.js --tol 1e-6      # widen the numeric tolerance
//   node tools/check-parity.js --selftest      # prove this checker can FAIL
//   node tools/check-parity.js --dump-draw     # print the drawing objects it found
//
// Two oracles, and neither of them is the Pine source:
//   1. tests/fixtures/step-fixtures.json - the MQL4 build's own test labels and
//      expected values (tools/fixtures-derive.js freezes them).
//   2. Samples/TH3_Dataset/Dataset.csv - what the MQL4 RECORDER wrote on a real
//      chart: legs, the mother, the rung, and the seven rungs it drew as prices.
//      A row is the strongest evidence this project can have, because nothing in
//      the port took part in producing it.
//
// Everything is executed, never re-derived: the probe is assembled from
// src/30_math.pine and run on PineTS with a deterministic local data provider.

import fs from 'node:fs';
import path from 'node:path';
import { PineTS } from 'pinets';
import { ROOT, SRC, parseModule, resolveEntry, listModules, render } from './lib/pine-build.js';
import { buildProbe } from './lib/parity-probe.js';
import { runPine, plotValues, syntheticBars, close, LocalProvider } from './lib/parity-engine.js';

const argv = process.argv.slice(2);
const SELFTEST = argv.includes('--selftest');
const DUMP_DRAW = argv.includes('--dump-draw');
const tolFlag = argv.indexOf('--tol');
const ROWS_PER_BAR = 1;

let failures = 0;
let checks = 0;
const failLines = [];
const noteLines = [];
const fail = (msg) => { failures++; failLines.push(msg); };
const note = (msg) => noteLines.push(msg);

// ---------------------------------------------------------------- fixtures ---
const FIXTURE_FILE = path.join(ROOT, 'tests', 'fixtures', 'step-fixtures.json');
if (!fs.existsSync(FIXTURE_FILE)) {
  console.error(`[FAIL] no fixtures at tests/fixtures/step-fixtures.json - generate them: node tools/fixtures-derive.js`);
  process.exit(1);
}
const fixture = JSON.parse(fs.readFileSync(FIXTURE_FILE, 'utf8'));
const TOL = tolFlag >= 0 ? Number(argv[tolFlag + 1]) : (fixture.tol ?? 1e-9);
const REL = fixture.relTol ?? 1e-12;

const inTol = (a, b) => close(a, b, TOL) || close(a, b, REL * Math.abs(b));

function compareRow(caseRow, values) {
  const label = `${caseRow.id} ${caseRow.wording}`;
  switch (caseRow.what) {
    case 'k': {
      checks++;
      if (!inTol(values.K, caseRow.expect)) fail(`k        ${label}: Pine ${values.K} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'closedK': {
      checks++;
      if (!inTol(values.KClosed, caseRow.expect)) fail(`closedK  ${label}: Pine ${values.KClosed} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'ratio': {
      checks++;
      if (!inTol(values.Ratio, caseRow.expect)) fail(`ratio    ${label}: Pine ${values.Ratio} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'step': {
      checks++;
      if (!inTol(values.Step, caseRow.expect)) fail(`step     ${label}: Pine ${values.Step} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      if (caseRow.gt != null) {
        checks++;
        if (!(values.Step > caseRow.gt)) fail(`step>    ${label}: Pine ${values.Step} is not greater than ${caseRow.gt} (${caseRow.oracle})`);
      }
      break;
    }
    case 'closedStep': {
      checks++;
      if (!inTol(values.StepClosed, caseRow.expect)) fail(`clStep   ${label}: Pine ${values.StepClosed} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'ladder': {
      for (let n = 1; n <= 7; n++) {
        checks++;
        const got = values[`R${n}`];
        const want = caseRow.expect[n - 1];
        if (!inTol(got, want)) fail(`ladder${n}  ${label}: Pine ${got} vs oracle ${want} (${caseRow.oracle})`);
      }
      break;
    }
    case 'rungFromClose': {
      checks++;
      if (!inTol(values.RungFromClose, caseRow.expect)) fail(`rung     ${label}: Pine ${values.RungFromClose} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'seed': {
      checks++;
      if (!inTol(values.SeedStep, caseRow.expect)) fail(`seed     ${label}: Pine ${values.SeedStep} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'locked': {
      checks++;
      if (!inTol(values.Locked, caseRow.expect)) fail(`lock     ${label}: Pine ${values.Locked} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    case 'freq': {
      checks++;
      if (!inTol(values.FreqPct, caseRow.expect)) fail(`freq     ${label}: Pine ${values.FreqPct} vs oracle ${caseRow.expect} (${caseRow.oracle})`);
      break;
    }
    default:
      fail(`unknown case kind "${caseRow.what}" for ${label}`);
  }
}

async function runFixtures() {
  const rows = fixture.cases.map((c) => ({
    ratio: c.ratio, priorLeg: c.priorLeg, lastLeg: c.lastLeg, legCD: c.legCD, legAB: c.legAB,
    mother: c.mother, rung: c.rung, anchor: c.anchor, ladderStep: c.ladderStep, dir: c.dir,
    price1: c.price1, pct: c.pct, freqPct: c.freqPct, lockBase: c.lockBase, lockOk: c.lockOk,
    uni: c.uni, derived: c.derived,
  }));
  const probe = buildProbe(rows);
  const bars = syntheticBars(Math.max(rows.length, 1));
  const { ctx } = await runPine({ code: probe.text, bars });

  const series = {};
  for (const title of ['Ratio', 'K', 'KClosed', 'StepMother', 'StepPattern', 'Step', 'StepClosed', 'R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'RungPct', 'RungFromClose', 'SeedStep', 'Locked', 'FreqPct']) {
    series[title] = plotValues(ctx, title);
  }

  // the chart-TF rung lookup is per RUN, not per row: the probe ran on 60 (H1).
  checks++;
  if (!inTol(series.RungPct[0], 0.1666)) {
    fail(`rungpct  chart TF "60" resolved to ${series.RungPct[0]}, not the H1 rung 0.1666 (FractalTimeframes.mqh:5-16)`);
  }
  fixture.cases.forEach((c, i) => {
    const values = {};
    for (const [k, arr] of Object.entries(series)) values[k] = arr[i];
    compareRow(c, values);
  });

  const byKind = {};
  for (const c of fixture.cases) byKind[c.oracleKind] = (byKind[c.oracleKind] ?? 0) + 1;
  console.log(`[parity] fixtures: ${fixture.cases.length} case(s)   tol ${TOL}   oracle kinds: ${Object.entries(byKind).map(([k, v]) => `${k}=${v}`).join(', ')}`);
  console.log(`         probe assembled from src/30_math.pine (${probe.modules.join(', ')}) and executed on PineTS`);
}

// ------------------------------------------------------------- pip size ------
// GetCachedPipSize's own table, and the ONE place a port quietly goes 10x wrong:
// MT4 gives a 2-digit METAL ten points and a 2-digit non-metal one point.
const PIP_CASES = [
  { mintick: 0.00001, ticker: 'EURUSD', expect: 0.0001, why: '5 digits -> 10 points' },
  { mintick: 0.001, ticker: 'USDJPY', expect: 0.01, why: '3 digits -> 10 points' },
  { mintick: 0.0001, ticker: 'EURUSD', expect: 0.0001, why: '4 digits -> 1 point' },
  { mintick: 0.1, ticker: 'SOMETHING', expect: 1.0, why: '1 digit -> 10 points' },
  { mintick: 0.01, ticker: 'XAUUSD', expect: 0.1, why: '2 digits + XAU -> 10 points' },
  { mintick: 0.01, ticker: 'GOLD', expect: 0.1, why: '2 digits + GOLD -> 10 points' },
  { mintick: 0.01, ticker: 'XAGUSD', expect: 0.1, why: '2 digits + XAG -> 10 points' },
  { mintick: 0.01, ticker: 'SILVER', expect: 0.1, why: '2 digits + SILVER -> 10 points' },
  { mintick: 0.01, ticker: 'NATGAS', expect: 0.01, why: '2 digits, not a metal -> 1 point' },
  { mintick: 0.01, ticker: 'US500', expect: 0.01, why: '2 digits, an index -> 1 point' },
  { mintick: 1, ticker: 'ABC', expect: 1.0, why: 'unknown digits -> the fallback, 1 point' },
];

async function runPipCheck() {
  const probe = buildProbe([{ ratio: 1, priorLeg: 0, lastLeg: 0, legCD: 0, mother: 0, rung: 0, anchor: 0, ladderStep: 0, dir: 0 }]);
  let bad = 0;
  for (const c of PIP_CASES) {
    const { ctx } = await runPine({ code: probe.text, bars: syntheticBars(1), symbolInfo: { mintick: c.mintick, ticker: c.ticker, tickerid: c.ticker } });
    const got = plotValues(ctx, 'PipSize')[0];
    checks++;
    if (!inTol(got, c.expect)) {
      bad++;
      fail(`pip      ${c.ticker} mintick=${c.mintick} (${c.why}): Pine ${got} vs GetCachedPipSize ${c.expect} (PerformanceOptimizations.mqh:168-215)`);
    }
  }
  console.log(`[parity] pip size: ${PIP_CASES.length - bad}/${PIP_CASES.length} symbol shapes match GetCachedPipSize`);
}

// ---------------------------------------------------------------- dataset ----
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (ch !== '\r') field += ch;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows.filter((r) => r.some((v) => v !== ''));
}

const DATASET = path.resolve(ROOT, '..', 'Samples', 'TH3_Dataset', 'Dataset.csv');

function datasetRowsFromCsv(text) {
  const table = parseCsv(text);
  if (table.length === 0) return { header: [], rows: [] };
  const header = table[0].map((h) => h.trim());
  const rows = table.slice(1).filter((r) => r.length && r[0] !== '').map((r) => {
    const o = {};
    header.forEach((h, i) => { o[h] = (r[i] ?? '').trim(); });
    return o;
  });
  return { header, rows };
}

// The CSV's own rounding is the only tolerance the dataset may be read with:
// Ratio 3dp, K 3dp, the legs and the steps 1dp, the targets at the symbol's Digits.
function toleranceFor(name, row) {
  const pip = Number(row.Pip_Size) || 0;
  if (name === 'K') return 0.0006;
  if (name === 'Ratio') return 0.0006;
  if (name === 'Step') return 0.05 + 0.0006 * Math.abs(Number(row.Leg_CD) || 0);
  if (name === 'StepMother') return 0.05;
  if (name === 'StepPattern') return 0.06 + 0.001 * Math.abs(Number(row.Leg_CD) || 0);
  if (name === 'Target') return 0.06 * pip;
  if (name === 'StepPrice') return 0.06 * pip;
  return 0.06;
}

async function runDataset(rows, { mutate = null } = {}) {
  if (rows.length === 0) return { evaluated: 0, passed: 0, failed: 0 };

  const probeRows = rows.map((r) => ({
    ratio: Number(r.Ratio_CD_BC),
    priorLeg: Number(r.Leg_BC),
    lastLeg: Number(r.Leg_CD),
    legCD: Number(r.Leg_CD),
    mother: Number(r.Mother_Pips),
    rung: Number(r.Rung_Pips),
    anchor: 0,
    ladderStep: 0,
    dir: 0,
  }));

  const probe = buildProbe(probeRows);
  const bars = syntheticBars(Math.max(probeRows.length, 1));
  const { ctx } = await runPine({ code: probe.text, bars });

  const series = {};
  for (const title of ['Ratio', 'K', 'StepMother', 'StepPattern', 'Step']) series[title] = plotValues(ctx, title);

  let evaluated = 0;
  let passed = 0;
  const perRow = [];

  rows.forEach((row, i) => {
    const pip = Number(row.Pip_Size) || 0;
    const dPrice = Number(row.D_Price) || 0;
    const t1 = Number(row.Target_1) || 0;
    const t3 = Number(row.Target_3) || 0;
    const t5 = Number(row.Target_5) || 0;
    const t7 = Number(row.Target_7) || 0;
    const stepPips = Number(row.Step_Pips) || 0;
    const dirDown = String(row.Direction).toLowerCase() === 'down';
    const checksForRow = [];

    const pushCheck = (name, got, want, tol) => {
      evaluated++;
      const ok = Math.abs(got - want) <= tol;
      if (ok) passed++;
      checksForRow.push({ name, got, want, tol, ok });
    };

    pushCheck('Ratio', series.Ratio?.[i], Number(row.Ratio_CD_BC), toleranceFor('Ratio', row));
    pushCheck('K', series.K?.[i], Number(row.K), toleranceFor('K', row));
    pushCheck('StepMother', series.StepMother?.[i], Number(row.Step_Mother), toleranceFor('StepMother', row));
    pushCheck('StepPattern', series.StepPattern?.[i], Number(row.Step_Pattern), toleranceFor('StepPattern', row));
    pushCheck('Step', series.Step?.[i], stepPips, toleranceFor('Step', row));

    // THE LADDER, read from the least-rounded columns the row carries. The recorded
    // targets are PRICES, so the step the recorder actually used is |Target_1 - D|,
    // and every other rung must be that same step times its own odd multiplier.
    if (pip > 0 && dPrice > 0 && t1 > 0) {
      const stepPrice = Math.abs(t1 - dPrice);
      pushCheck('StepPrice', stepPrice, stepPips * pip, toleranceFor('StepPrice', row));
      const sign = dirDown ? -1 : 1;
      const rungs = [1, 3, 5, 7];
      const targets = [t1, t3, t5, t7];
      rungs.forEach((rung, k) => {
        if (targets[k] > 0) pushCheck(`Target_${rung}`, targets[k], dPrice + sign * rung * stepPrice, toleranceFor('Target', row));
      });
    }

    const rowOk = checksForRow.every((c) => c.ok);
    if (mutate) mutate(row, checksForRow, i);
    if (!rowOk) {
      const bad = checksForRow.filter((c) => !c.ok).map((c) => `${c.name} got=${c.got} want=${c.want} tol=${c.tol}`).join('; ');
      fail(`dataset ${row.Sample_ID || `row ${i + 1}`}: ${bad}`);
    }
    perRow.push({ id: row.Sample_ID || `row ${i + 1}`, ok: rowOk, checksForRow });
  });

  return { evaluated, passed, failed: evaluated - passed, perRow };
}

// ------------------------------------------------------- both entries RAN ---
// The MQL4 project's rule is "both entries are built, always" - a report that says
// main and Lite compile without a second line did not build Lite. Here the stronger
// form is available: both artifacts are EXECUTED, and the readout must be present in
// one and absent in the other, because that difference IS what Lite means.
// THE MARK, FED TO A GENERATED ARTIFACT. The ladder's anchor is a set of inputs -
// that IS the MQL4 gesture (see src/40_levels.pine), and an input cannot be clicked in
// an offline run. So this rewrites the four default values in the BUILT text with four
// real corners off the series. It changes no rule: it is the same edit a reader makes
// by clicking, and every assertion below still has to hold afterwards.
function withMarks(code, bars) {
  const at = (back) => bars[bars.length - back];
  const corners = { A: at(220), B: at(160), C: at(100), D: at(40) };
  const value = { A: corners.A.low, B: corners.B.high, C: corners.C.low, D: corners.D.high };
  let out = code;
  for (const k of ['A', 'B', 'C', 'D']) {
    out = out.replace(`input.time(0, "${k} time"`, `input.time(${corners[k].openTime}, "${k} time"`);
    out = out.replace(`input.price(0.0, "${k} price"`, `input.price(${value[k]}, "${k} price"`);
  }
  if (!out.includes(`input.price(${value.D}`)) throw new Error('the mark injection found no input.price to rewrite - the inputs moved and this harness is blind');
  return out;
}

async function runEntrySmoke() {
  const entries = [
    { file: 'dist/BiotakTriggerTH3.pine', wantTable: true },
    { file: 'dist/BiotakTriggerTH3_Lite.pine', wantTable: false },
  ];
  for (const e of entries) {
    const abs = path.join(ROOT, e.file);
    checks++;
    if (!fs.existsSync(abs)) { fail(`${e.file} is missing - run npm run build`); continue; }
    let ctx;
    try {
      const bars = syntheticBars(400);
      ({ ctx } = await runPine({ code: withMarks(fs.readFileSync(abs, 'utf8'), bars), bars }));
    } catch (err) {
      fail(`${e.file} did not RUN: ${err.message} - the validator checks syntax, this is the execution`);
      continue;
    }
    const countOf = (kind) => ((ctx?.plots?.[`__${kind}__`]?.data) ?? []).flatMap((d) => (Array.isArray(d?.value) ? d.value : [])).length;
    const lines = countOf('lines');
    const labels = countOf('labels');
    const tables = countOf('tables');
    note(`${e.file} ran: ${lines} line(s), ${labels} label(s), ${tables} table(s)`);
    checks++;
    if (lines === 0) fail(`${e.file} ran but drew nothing - an entry that produces no surface is not a build, it is a paste that looks fine`);
    checks++;
    if (e.wantTable && tables === 0) fail(`${e.file} carries the readout module but created no table - the surface is in the set and not in the output`);
    checks++;
    if (!e.wantTable && tables !== 0) fail(`${e.file} created ${tables} table(s) - Lite must not carry the readout surface at all`);
  }
}

// ----------------------------------------------------------- drawn ladder ----
async function runDrawCheck() {
  const dist = path.join(ROOT, 'dist', 'BiotakTriggerTH3.pine');
  if (!fs.existsSync(dist)) { fail('dist/BiotakTriggerTH3.pine is missing - run npm run build'); return; }
  const bars = syntheticBars(400);
  const code = withMarks(fs.readFileSync(dist, 'utf8'), bars);
  const { ctx } = await runPine({ code, bars });

  const linesEntry = ctx?.plots?.__lines__;
  const labelsEntry = ctx?.plots?.__labels__;
  const linesData = (Array.isArray(linesEntry) ? linesEntry : linesEntry?.data) ?? [];
  const labelsData = (Array.isArray(labelsEntry) ? labelsEntry : labelsEntry?.data) ?? [];

  if (DUMP_DRAW) {
    console.log('[dump] __lines__ shape:', JSON.stringify(linesData).slice(0, 1200));
    console.log('[dump] __labels__ shape:', JSON.stringify(labelsData).slice(0, 600));
  }

  const allLines = linesData.flatMap((d) => (Array.isArray(d?.value) ? d.value : []));
  const allLabels = labelsData.flatMap((d) => (Array.isArray(d?.value) ? d.value : []));

  if (allLines.length === 0) {
    fail('the built indicator drew NO ladder line on 400 bars - the surface never reached a decision, or the draw path is dead');
    return;
  }
  note(`drawn ladder: ${allLines.length} line object(s), ${allLabels.length} label object(s) on a 400-bar run`);

  // Read the LAST generation: the rungs are rebuilt as one family, so the last bar
  // that carries seats IS the current model. Reading the literal final bar instead
  // would read a bar the surface deliberately left alone (a still frame is zero
  // writes), which is the mistake this line exists to not make.
  const withSeats = linesData.filter((d) => Array.isArray(d?.value) && d.value.length > 0);
  const lastBar = withSeats[withSeats.length - 1];
  const seatOf = (o) => Number(o?.y1 ?? o?.y ?? o?.price ?? o?.value);
  const seatObjs = (Array.isArray(lastBar?.value) ? lastBar.value : []);
  const seats = seatObjs.map(seatOf).filter(Number.isFinite);
  if (seats.length < 2) {
    note('the last generation carried fewer than two rung seats, so uniform spacing is not decidable from it - the object count above is the whole reading');
    return;
  }

  // A control that is PAINTED is not a control that WORKS: every rung carries a
  // caption, and the caption has to state the seat's own number or the surface is
  // lying about the level it drew.
  const lastLabels = (labelsData.filter((d) => Array.isArray(d?.value) && d.value.length > 0).pop()?.value) ?? [];
  checks++;
  if (lastLabels.length !== seats.length) {
    fail(`${seats.length} rung line(s) against ${lastLabels.length} caption(s) - a rung without its caption is a level nobody can read`);
  } else {
    const pairs = lastLabels.map((lb, i) => {
      const m = /^L(\d+)\s+([-\d.]+)/.exec(String(lb?.text ?? ''));
      return { text: String(lb?.text ?? ''), rung: m ? Number(m[1]) : null, stated: m ? Number(m[2]) : null, actual: seatOf(seatObjs[i]) };
    });
    const lies = pairs.filter((p) => p.stated === null || !close(p.stated, p.actual, Math.max(1e-9, Math.abs(p.actual) * 1e-5)));
    checks++;
    if (lies.length) {
      fail(`caption(s) disagree with the seat they label: ${lies.map((p) => `"${p.text}" over y=${p.actual}`).join('; ')}`);
    }
    const rungNums = pairs.map((p) => p.rung).filter((r) => r !== null).sort((a, b) => a - b);
    checks++;
    if (rungNums.join(',') !== rungNums.map((_, i) => i + 1).join(',')) {
      fail(`the drawn rungs are not 1..N: got ${rungNums.join(',')} - the ladder skipped a rung or drew its own numbering wrong`);
    }
    // the split is 1-based: rungs 1/3/5/7 are the impulse targets, 2/4/6 the shelves.
    // Written against the RUNG NUMBER, not against a fixed index - the earlier form
    // hard-coded 4 seats and would have gone quiet the moment the count changed.
    const inks = seatObjs.map((o, i) => ({ rung: i + 1, style: String(o?.style ?? '') }));
    checks++;
    if (inks.length >= 2) {
      const odd = new Set(inks.filter((r) => r.rung % 2 === 1).map((r) => r.style));
      const even = new Set(inks.filter((r) => r.rung % 2 === 0).map((r) => r.style));
      if (odd.size !== 1 || even.size !== 1 || [...odd][0] === [...even][0]) {
        fail(`the odd/even rung ink is not split as the ladder law says (targets solid, shelves dotted): ${inks.map((r) => `L${r.rung}=${r.style}`).join(', ')}`);
      }
    }
  }

  // the OFF switch must own a sweep: a family that was rebuilt 4x400 times without
  // ever being deleted reads as a leak, so the count must stay near one generation.
  const perBarCounts = linesData.map((d) => (Array.isArray(d?.value) ? d.value.length : 0));
  const maxPerBar = perBarCounts.length ? Math.max(...perBarCounts) : 0;
  checks++;
  if (seats.length > 0 && maxPerBar > 2 * seats.length) {
    fail(`the ladder family reached ${maxPerBar} live lines against ${seats.length} rung(s) - the purge is not taking the old generation down`);
  }

  const sorted = [...new Set(seats)].sort((a, b) => a - b);
  if (sorted.length >= 2) {
    const gaps = sorted.slice(1).map((v, i) => v - sorted[i]);
    const first = gaps[0];
    const worst = gaps.reduce((w, g) => Math.max(w, Math.abs(g - first)), 0);
    checks++;
    if (worst > 1e-9) {
      fail(`ladder rungs are not evenly spaced: gaps ${gaps.map((g) => g.toPrecision(8)).join(', ')} - the rung multipliers are not 1,2,3,4 from one step`);
    } else {
      note(`rungs evenly spaced at step=${first.toPrecision(10)} over ${sorted.length} seat(s)`);
    }
  }
}

// ------------------------------------- owner TF / retrace / k-pick / lock shift ---
const MQL4_TEST_FILE = path.resolve(ROOT, '..', 'tests', 'Biotak_TH3_Test.mq4');
const MQL4_PERCENT_FILE = path.resolve(ROOT, '..', 'Biotak', 'ConstantsAndEnums.mqh');
const PIP = 0.0001;

function readMql4Labels() {
  const text = fs.existsSync(MQL4_TEST_FILE) ? fs.readFileSync(MQL4_TEST_FILE, 'utf8').replace(/\r\n?/g, '\n') : '';
  const owner = [...text.matchAll(/Check\("(owner: [^"]+)",\s*TH3ClosedOwnerTFEx\((\d+),\s*(\d+)\)\s*==\s*(\d+)\)/g)]
    .map((m) => ({ wording: m[1], tfMin: Number(m[2]), cdBars: Number(m[3]), expect: Number(m[4]), kind: 'mql4-test-label' }));
  const retrace = [...text.matchAll(/Check\("(ret8: [^"]+)",\s*(!?)TH3RetraceBestStep\(([\d.]+)(?: \* pip)?, ([\d.]+)(?: \* pip)?, ([\d.]+)(?: \* pip)?, bS, bQ, bI\)(?:\s*&&\s*MathAbs\(bS - ([\d.]+) \* pip\) < 1e-9 && bI == (\d+))?\)/g)]
    .map((m) => ({
      wording: m[1], refuse: m[2] === '!', R: Number(m[3]) * PIP, ref: Number(m[4]) * PIP, th: Number(m[5]) * PIP,
      expectStep: m[6] === undefined ? 0 : Number(m[6]) * PIP, expectIdx: m[7] === undefined ? -1 : Number(m[7]), kind: 'mql4-test-label',
    }));
  const kpick = [...text.matchAll(/Check\("(kpick: [^"]+)",\s*(!?)TH3HitKPick\(([\d.]+), ([\d.]+), pk, ps\)(?:\s*&&\s*pk == (\d))?\)/g)]
    .map((m) => ({ wording: m[1], refuse: m[2] === '!', dist: Number(m[3]), ref: Number(m[4]), expectK: m[5] === undefined ? 0 : Number(m[5]), kind: 'mql4-test-label' }));
  return { found: text !== '', owner, retrace, kpick };
}

function readMql4Percents() {
  const text = fs.existsSync(MQL4_PERCENT_FILE) ? fs.readFileSync(MQL4_PERCENT_FILE, 'utf8') : '';
  const m = /MODIFIED_FRACTAL_PERCENTAGES\[\]\s*=\s*\{([\s\S]*?)\};/.exec(text);
  if (!m) return null;
  return m[1].split('\n').map((l) => /^\s*([\d.]+)\s*,?/.exec(l)).filter(Boolean).map((x) => Number(x[1]));
}

const RUNG_TABLE_INDEX = { 1: 0, 5: 1, 15: 2, 30: 2, 60: 3, 240: 4, 1440: 5, 10080: 7, 43200: 8 };

const OWNER_DERIVED = [
  { wording: 'owner: M5/8 -> M15', tfMin: 5, cdBars: 8, expect: 15, why: 'up(M5)=M15, 8*5/15 = 2.67 -> 3 <= 7' },
  { wording: 'owner: M1/200 -> H1', tfMin: 1, cdBars: 200, expect: 60, why: 'M5 40 -> M15 13.3 -> 13 -> H1 3.25 -> 3' },
  { wording: 'owner: off-chain M30/8 -> H1', tfMin: 30, cdBars: 8, expect: 60, why: 'first chain member above 30 is 60, 8*30/60 = 4' },
  { wording: 'owner: off-chain M30/20 -> H4', tfMin: 30, cdBars: 20, expect: 240, why: 'H1 10 > 7, 10*60/240 = 2.5 -> 3' },
  { wording: 'owner: unmeasurable span keeps the chart', tfMin: 60, cdBars: -1, expect: 60, why: 'cdBars <= 7 gate, -1 is the unmeasurable answer' },
  { wording: 'owner: zero span keeps the chart', tfMin: 60, cdBars: 0, expect: 60, why: 'cdBars <= 7 gate' },
  { wording: 'owner: H4/8 -> D1', tfMin: 240, cdBars: 8, expect: 1440, why: '8*240/1440 = 1.33 -> 1' },
  { wording: 'owner: MN/8 stays', tfMin: 43200, cdBars: 8, expect: 43200, why: 'up(MN) == MN, chain top' },
  { wording: 'owner: W1/50 -> MN', tfMin: 10080, cdBars: 50, expect: 43200, why: '50*10080/43200 = 11.67 -> 12 > 7, next up is the chain top' },
  { wording: 'owner: six climbs at most', tfMin: 1, cdBars: 1000000, expect: 10080, why: 'M5, M15, H1, H4, D1, W1 - the loop ends after 6 and never reaches MN' },
  { wording: 'owner: 2D chart/20 -> W1', tfMin: 2880, cdBars: 20, expect: 10080, why: 'first chain member above 2880 is 10080, 20*2880/10080 = 5.7 -> 6' },
  { wording: 'owner: seconds chart has no chain', tfMin: 0, cdBars: 100, expect: 0, why: 'tfMin <= 0 is returned as it came' },
];

const RET_DERIVED = [
  { wording: 'ret8 weights: R=60 ref=20 th=30 -> S=20 (q=3)', R: 60 * PIP, ref: 20 * PIP, th: 30 * PIP, expectStep: 20 * PIP, expectIdx: 6, why: 'candidates 180,90,60,45,36,30,20,12 pips: 20 scores 0.6*0 + 0.4*(1/3) = 0.1333, 30 scores 0.6*0.5 = 0.30; with the weights swapped 30 wins' },
  { wording: 'ret8 weights: R=90 ref=20 th=30 -> S=18 (q=5)', R: 90 * PIP, ref: 20 * PIP, th: 30 * PIP, expectStep: 18 * PIP, expectIdx: 7, why: '18 scores 0.6*0.1 + 0.4*0.4 = 0.22, 30 scores 0.6*0.5 = 0.30; with the weights swapped 30 wins' },
  { wording: 'ret8 tie: R=60 ref=75 -> nearer q=1 wins', R: 60 * PIP, ref: 75 * PIP, th: 0, expectStep: 60 * PIP, expectIdx: 2, why: '90 (q=2/3) and 60 (q=1) are both 15 from 75, score 0.2; the tie goes to the candidate nearer q = 1' },
];

const SHIFT_CASES = [
  { wording: 'lock shift: climbed owner, no hand base', derived: 0.001, base: 0, ownerUp: 1, chartRung: 0.002, pip: PIP, applied: 1, locked: 0, why: 'TH3Pivots_B.mqh:505-512' },
  { wording: 'lock shift: a hand base is exempt', derived: 0.001, base: 0.0012, ownerUp: 1, chartRung: 0.002, pip: PIP, applied: 0, locked: 1, why: 'TH3Pivots_B.mqh:505 pbStep <= 0' },
  { wording: 'lock shift: owner is the chart', derived: 0.001, base: 0, ownerUp: 0, chartRung: 0.002, pip: PIP, applied: 0, locked: 1, why: 'TH3Pivots_B.mqh:505 ownerTF != chartTF' },
  { wording: 'lock shift: no closed step', derived: 0, base: 0, ownerUp: 1, chartRung: 0.002, pip: PIP, applied: 0, locked: 1, why: 'the shift lives inside the closedStep > 0 branch' },
  { wording: 'lock shift: no chart rung', derived: 0.001, base: 0, ownerUp: 1, chartRung: 0, pip: PIP, applied: 0, locked: 1, why: 'TH3Pivots_B.mqh:507 lsLower > 0' },
];

async function runOwnerRetrace({ transform = null } = {}) {
  const labels = readMql4Labels();
  const percents = readMql4Percents();
  checks++;
  if (!labels.found) { fail(`owner/retrace/kpick oracle: ${MQL4_TEST_FILE} not found - an absent oracle is a failed check`); return; }
  checks++;
  if (labels.owner.length < 6 || labels.retrace.length < 11 || labels.kpick.length < 7) {
    fail(`owner/retrace/kpick oracle moved: parsed ${labels.owner.length}/6 owner, ${labels.retrace.length}/11 ret8, ${labels.kpick.length}/7 kpick label(s) from tests/Biotak_TH3_Test.mq4`);
    return;
  }
  checks++;
  if (!percents || percents.length !== 9) { fail(`MODIFIED_FRACTAL_PERCENTAGES not readable from ${MQL4_PERCENT_FILE}`); return; }

  const tasks = [];
  for (const c of [...labels.owner, ...OWNER_DERIVED]) {
    tasks.push({ row: { tfMin: c.tfMin, cdBars: c.cdBars }, verify: (v) => (v.OwnerTF !== c.expect ? `${c.wording}: Pine owner ${v.OwnerTF} vs ${c.expect} (${c.kind ?? 'source-derived'}${c.why ? `: ${c.why}` : ''})` : null) });
  }
  const tfs = [1, 2, 3, 5, 15, 30, 45, 60, 120, 240, 1440, 2880, 10080, 43200, 0];
  for (const tf of tfs) {
    const want = tf in RUNG_TABLE_INDEX ? percents[RUNG_TABLE_INDEX[tf]] : 0;
    tasks.push({ row: { tfMin: tf }, verify: (v) => (!inTol(v.RungPctTF, want) ? `rung pct by minutes: ${tf} -> Pine ${v.RungPctTF} vs MODIFIED_FRACTAL_PERCENTAGES ${want}` : null) });
  }
  for (const c of [...labels.retrace, ...RET_DERIVED]) {
    tasks.push({
      row: { retR: c.R, retRef: c.ref, retTh: c.th },
      verify: (v) => {
        if (c.refuse) return v.RetStep !== 0 || v.RetIdx !== -1 ? `${c.wording}: a refusal answered step ${v.RetStep} idx ${v.RetIdx}` : null;
        if (!close(v.RetStep, c.expectStep, 1e-9) || v.RetIdx !== c.expectIdx) return `${c.wording}: Pine step ${v.RetStep} idx ${v.RetIdx} vs ${c.expectStep} idx ${c.expectIdx} (${c.kind ?? 'source-derived'}${c.why ? `: ${c.why}` : ''})`;
        return null;
      },
    });
  }
  for (const c of labels.kpick) {
    tasks.push({
      row: { kDist: c.dist, kRef: c.ref },
      verify: (v) => {
        if (c.refuse) return v.KpOk !== 0 ? `${c.wording}: Pine accepted a vote MQL4 refuses` : null;
        return v.KpOk !== 1 || v.KpK !== c.expectK ? `${c.wording}: Pine ok=${v.KpOk} k=${v.KpK} vs k=${c.expectK} (mql4-test-label)` : null;
      },
    });
  }
  for (const c of SHIFT_CASES) {
    tasks.push({
      row: { derived: c.derived, lockBase: c.base, ownerUp: c.ownerUp, chartRung: c.chartRung, pip: c.pip },
      verify: (v) => (v.ShiftApplied !== c.applied || v.ShiftLocked !== c.locked ? `${c.wording}: Pine applied=${v.ShiftApplied} locked=${v.ShiftLocked} vs applied=${c.applied} locked=${c.locked} (${c.why})` : null),
    });
  }

  const probe = buildProbe(tasks.map((t) => t.row), { transform });
  const { ctx } = await runPine({ code: probe.text, bars: syntheticBars(Math.max(tasks.length, 1)) });
  const series = {};
  for (const title of ['OwnerTF', 'RungPctTF', 'RetStep', 'RetIdx', 'KpOk', 'KpK', 'ShiftApplied', 'ShiftLocked']) series[title] = plotValues(ctx, title);
  let bad = 0;
  tasks.forEach((t, i) => {
    const values = {};
    for (const [k, arr] of Object.entries(series)) values[k] = arr[i];
    checks++;
    const msg = t.verify(values);
    if (msg) { bad++; fail(msg); }
  });
  if (!transform) {
    console.log(`[parity] owner/retrace/kpick: ${tasks.length - bad}/${tasks.length} case(s) match (labels read from the MQL4 test: ${labels.owner.length} owner, ${labels.retrace.length} ret8, ${labels.kpick.length} kpick; rung table read from ConstantsAndEnums.mqh:316-326)`);
  }
}

async function runChartTfMapping({ transform = null } = {}) {
  const percents = readMql4Percents();
  if (!percents) { checks++; fail('MODIFIED_FRACTAL_PERCENTAGES not readable - the chart timeframe mapping has no oracle'); return; }
  const cases = [['1', 1], ['5', 5], ['15', 15], ['30', 30], ['60', 60], ['240', 240], ['D', 1440], ['1D', 1440], ['W', 10080], ['1W', 10080], ['M', 43200], ['1M', 43200], ['2D', 2880], ['120', 120], ['3', 3]];
  const probe = buildProbe([{ ratio: 1, priorLeg: 0, lastLeg: 0, legCD: 0, mother: 0, rung: 0, anchor: 0, ladderStep: 0, dir: 0 }], { transform });
  let bad = 0;
  for (const [tf, want] of cases) {
    let got = null;
    let pct = null;
    try {
      const { ctx } = await runPine({ code: probe.text, bars: syntheticBars(2), timeframe: tf });
      got = plotValues(ctx, 'ChartTf')[1];
      pct = plotValues(ctx, 'RungPct')[1];
    } catch (err) {
      checks++; bad++; fail(`chart timeframe ${tf}: the probe did not run (${err.message.slice(0, 100)})`);
      continue;
    }
    const wantPct = want in RUNG_TABLE_INDEX ? percents[RUNG_TABLE_INDEX[want]] : 0;
    checks++;
    if (got !== want) { bad++; fail(`chart timeframe ${tf}: Pine reads ${got} minutes vs ${want}`); }
    checks++;
    if (!inTol(pct, wantPct)) { bad++; fail(`chart timeframe ${tf}: rung pct ${pct} vs MODIFIED_FRACTAL_PERCENTAGES ${wantPct} - Pine v6 reports daily/weekly/monthly as 1D/1W/1M, so a string compare on timeframe.period answers 0 there`); }
  }
  if (!transform) console.log(`[parity] chart timeframe -> rung: ${cases.length * 2 - bad}/${cases.length * 2} check(s) (1, 5, 15, 30, 60, 240, D/1D, W/1W, M/1M, and three off-table charts)`);
}

// ------------------------------------------------ source contracts (static) ---
function runSourceContracts() {
  const strip = (t) => t.split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');
  const bodies = {};
  for (const rel of listModules()) bodies[rel] = strip(fs.readFileSync(path.join(SRC, rel), 'utf8').replace(/\r\n?/g, '\n'));
  const levels = bodies['40_levels.pine'] ?? '';
  let noted = 0;

  let requests = 0;
  for (const [rel, text] of Object.entries(bodies)) {
    for (const m of text.matchAll(/request\.security\(([^\n]*)\)/g)) {
      requests++;
      checks++;
      if (!/lookahead\s*=/.test(m[1])) fail(`src/${rel}: a request.security without an explicit lookahead - say which one: ${m[0].slice(0, 90)}`);
      checks++;
      if (/lookahead_on/.test(m[1]) && !/\[\s*[1-9]\d*\s*\]/.test(m[1])) fail(`src/${rel}: request.security with lookahead_on and no [1] offset reads the FUTURE of every historical bar: ${m[0].slice(0, 90)}`);
    }
    checks++;
    if (/timeframe\.period\s*[!=]=/.test(text)) fail(`src/${rel}: compares timeframe.period to a string - Pine v6 spells the daily chart "1D" and the string never matches (read timeframe.isdaily / multiplier)`);
  }
  noted += requests;
  checks++;
  if (requests === 0) fail('no request.security in src/ - the owner timeframe is read from the chart alone');

  for (const k of ['A', 'B', 'C', 'D']) {
    const time = new RegExp(`TH3_SET_${k}_TIME\\s*=\\s*input\\.time\\(([^\\n]*)\\)`).exec(levels);
    const price = new RegExp(`TH3_SET_${k}_PRICE\\s*=\\s*input\\.price\\(([^\\n]*)\\)`).exec(levels);
    checks++;
    if (!time || !price) { fail(`src/40_levels.pine: corner ${k} lacks its input.time / input.price pair`); continue; }
    const inl = (s) => (/inline\s*=\s*"([^"]*)"/.exec(s) ?? [])[1];
    checks++;
    if (!inl(time[1]) || inl(time[1]) !== inl(price[1])) fail(`src/40_levels.pine: corner ${k} time/price do not share one inline key (${inl(time[1])} vs ${inl(price[1])}) - TradingView will not ask for them with one click`);
    checks++;
    if (!/confirm\s*=\s*true/.test(time[1]) || !/confirm\s*=\s*true/.test(price[1])) fail(`src/40_levels.pine: corner ${k} is not confirm=true on both halves - it is not an interactive input`);
    noted++;
  }

  const calls = [...levels.matchAll(/th3ReactionRungs\(([^)]*)\)/g)].filter((m) => !/float|bool|int/.test(m[1]));
  checks++;
  if (calls.length === 0) fail('src/40_levels.pine: the reaction walk is never called');
  for (const m of calls) {
    checks++;
    if (!/,\s*th3StepFinal\s*$/.test(m[1])) fail(`src/40_levels.pine: the reaction walk is measured in "${m[1].split(',').pop().trim()}" - MQL4 passes baseUnit, the step the ladder draws (TH3Renderer_B.mqh:146)`);
  }
  checks++;
  if (!/TH3_MAX_BARS_BACK/.test(levels)) fail('src/40_levels.pine: the reaction bound does not read TH3_MAX_BARS_BACK');
  checks++;
  if (!/th3MarkGap\([^)]*\)\s*=>\s*\n?\s*p > 0 and t > 0/.test(levels)) fail('src/40_levels.pine: a corner is no longer a (time, price) pair - a missing time must withdraw the model');
  console.log(`[parity] source contracts: ${noted} reading(s) - every request.security names its lookahead and offsets the future, four inline-paired confirm inputs, the reaction walk reads the drawn step`);
}

// -------------------------------------------- the model, run from src/ itself ---
const H1 = 3600000;
const DAY = 86400000;
const T0 = Date.UTC(2024, 0, 1);

const bucketOf = (tf, t) => {
  if (tf === '240') return Math.floor(t / (4 * H1));
  if (tf === 'D') return Math.floor(t / DAY);
  if (tf === 'W') return Math.floor((t + 3 * DAY) / (7 * DAY));
  const d = new Date(t);
  return d.getUTCFullYear() * 12 + d.getUTCMonth();
};
const bucketStart = (tf, b) => {
  if (tf === '240') return b * 4 * H1;
  if (tf === 'D') return b * DAY;
  if (tf === 'W') return b * 7 * DAY - 3 * DAY;
  return Date.UTC(Math.floor(b / 12), b % 12, 1);
};
const bucketEnd = (tf, b) => (tf === 'M' ? bucketStart(tf, b + 1) : bucketStart(tf, b) + (tf === 'W' ? 7 * DAY : tf === 'D' ? DAY : 4 * H1));

function aggregate(bars, tf, zero) {
  const groups = new Map();
  for (const b of bars) {
    const g = bucketOf(tf, b.openTime);
    if (!groups.has(g)) groups.set(g, []);
    groups.get(g).push(b);
  }
  return [...groups.keys()].sort((a, b) => a - b).map((g) => {
    const s = groups.get(g);
    const v = (x) => (zero ? 0 : x);
    return {
      openTime: bucketStart(tf, g), open: v(s[0].open), high: v(Math.max(...s.map((x) => x.high))), low: v(Math.min(...s.map((x) => x.low))),
      close: v(s[s.length - 1].close), volume: 1, closeTime: bucketEnd(tf, g) - 1,
    };
  });
}

function completedClose(bars, tf) {
  const last = bucketOf(tf, bars[bars.length - 1].openTime);
  let found = null;
  for (const b of bars) if (bucketOf(tf, b.openTime) === last - 1) found = b.close;
  return found;
}

class AggProvider extends LocalProvider {
  constructor(bars, { zero = [] } = {}) {
    super(bars);
    this.zero = zero;
  }

  async _getMarketDataNative(_id, timeframe, limit) {
    const tf = String(timeframe);
    if (tf === '240' || tf === 'D' || tf === 'W' || tf === 'M') {
      if (this.bars.length > 1 && this.bars[1].openTime - this.bars[0].openTime >= { 240: 4 * H1, D: DAY, W: 7 * DAY, M: 28 * DAY }[tf]) return this.bars.slice();
      return aggregate(this.bars, tf, this.zero.includes(tf));
    }
    return typeof limit === 'number' && limit > 0 ? this.bars.slice(-limit) : this.bars.slice();
  }
}

const flatBars = (n, { start = T0, stepMs = H1, price = 1.1, half = 0.0004 } = {}) => Array.from({ length: n }, (_, i) => ({
  openTime: start + i * stepMs, open: price, high: price + half, low: price - half, close: price, volume: 100, closeTime: start + (i + 1) * stepMs - 1,
}));

function shapeV(bars, { dIdx, valleyIdx, valleyClose, valleyLow, recoverIdx, recoverClose, dHigh, half = 0.0004 }) {
  const r = (v) => Math.round(v * 1e5) / 1e5;
  const dClose = r(dHigh - half);
  let prev = dClose;
  for (let i = dIdx; i < bars.length; i++) {
    let c = dClose;
    if (i > dIdx && i <= valleyIdx) c = dClose + (valleyClose - dClose) * (i - dIdx) / (valleyIdx - dIdx);
    else if (i > valleyIdx && i <= recoverIdx) c = valleyClose + (recoverClose - valleyClose) * (i - valleyIdx) / (recoverIdx - valleyIdx);
    else if (i > recoverIdx) c = recoverClose;
    c = r(c);
    const o = i === dIdx ? dClose : prev;
    const b = bars[i];
    b.open = o;
    b.close = c;
    b.high = r(Math.max(o, c) + half);
    b.low = r(Math.min(o, c) - half);
    if (i === dIdx) b.high = dHigh;
    if (i === valleyIdx) b.low = valleyLow;
    prev = c;
  }
}

function reactionOracle(bars, dIdx, dPrice, wantHigh, step) {
  const last = bars.length - 1;
  let deepest = 0;
  let hit = 0;
  for (let i = dIdx + 3; i <= last - 3; i++) {
    const h0 = bars[i].high;
    const l0 = bars[i].low;
    if (!(h0 > 0 && l0 > 0)) continue;
    let tip = true;
    for (let k = i - 2; k <= i + 2 && tip; k++) {
      if (k === i) continue;
      const v = wantHigh ? bars[k].high : bars[k].low;
      if (v <= 0 || (wantHigh ? v >= h0 : v <= l0)) tip = false;
    }
    if (!tip) continue;
    const d = Math.abs(dPrice - (wantHigh ? h0 : l0));
    if (d > deepest) deepest = d;
    if (d >= 2.4 * step) { hit = d; break; }
  }
  return { rungs: deepest / step, hit };
}

function assembleSrc(entryRel, mutate) {
  const { text } = render({ entry: parseModule(entryRel), modules: resolveEntry(entryRel).modules });
  return mutate ? mutate(text) : text;
}

function injectMarks(code, marks) {
  let out = code;
  for (const k of ['A', 'B', 'C', 'D']) {
    const m = marks?.[k];
    if (!m) continue;
    if (m.t) {
      const before = out;
      out = out.replace(`input.time(0, "${k} time"`, `input.time(${m.t}, "${k} time"`);
      if (out === before) throw new Error(`the mark injection found no "${k} time" input to rewrite - the inputs moved and this harness is blind`);
    }
    if (m.p) {
      const before = out;
      out = out.replace(`input.price(0.0, "${k} price"`, `input.price(${m.p}, "${k} price"`);
      if (out === before) throw new Error(`the mark injection found no "${k} price" input to rewrite - the inputs moved and this harness is blind`);
    }
  }
  return out;
}

const DEBUG_TAIL = [
  'plot(th3VoteState, "dbg_state")', 'plot(th3DAge, "dbg_age")', 'plot(th3DeepestRungs, "dbg_deep")', 'plot(th3VoteDist, "dbg_dist")',
  'plot(th3VoteOK ? 1.0 : 0.0, "dbg_ok")', 'plot(th3Marked ? 1.0 : 0.0, "dbg_marked")', 'plot(th3Rung, "dbg_rung")', 'plot(th3OwnerMin, "dbg_owner")',
  'plot(th3CdBars, "dbg_cd")', 'plot(th3StepFinal, "dbg_step")', 'plot(na(th3AnchorPrice) ? 1.0 : 0.0, "dbg_anchor_na")',
  'plot(str.contains(th3VoteHow, "below floor") ? 1.0 : 0.0, "dbg_below")', 'plot(str.contains(th3VoteHow, "unknown") ? 1.0 : 0.0, "dbg_unknown")',
  'plot(str.contains(th3VoteHow, "waiting") ? 1.0 : 0.0, "dbg_waiting")', 'plot(str.contains(th3VoteHow, "VOTES k=3") ? 1.0 : 0.0, "dbg_votes3")',
  'plot(str.contains(th3RungHow, "(chart)") ? 1.0 : 0.0, "dbg_chartfb")',
].join('\n');

async function execSrc({ entry = 'entry/main.pine', mutate = null, bars, tf = '60', marks = null, rungPips = 0, srcName = '', provider = null }) {
  let code = injectMarks(assembleSrc(entry, mutate), marks);
  if (rungPips) {
    const before = code;
    code = code.replace('input.float(0.0, "Owner rung override', `input.float(${rungPips}, "Owner rung override`);
    if (code === before) throw new Error('the rung override input moved - this harness is blind');
  }
  code += `\n${DEBUG_TAIL}\nplot(th3SrcName == "${srcName}" ? 1.0 : 0.0, "dbg_src")\n`;
  const engine = new PineTS(provider ?? new AggProvider(bars), 'PARITY', tf, bars.length);
  await engine.ready();
  return engine.run(code);
}

const lastOf = (ctx, title) => {
  const a = plotValues(ctx, title);
  return a[a.length - 1];
};
const objectCount = (ctx, kind) => ((ctx?.plots?.[`__${kind}__`]?.data) ?? []).flatMap((d) => (Array.isArray(d?.value) ? d.value : [])).length;

const GEO = { pA: 1.09, pB: 1.11, pC: 1.10, pD: 1.12 };
const cornersAt = (bars, idx) => ({
  A: { t: bars[idx.A].openTime, p: GEO.pA }, B: { t: bars[idx.B].openTime, p: GEO.pB },
  C: { t: bars[idx.C].openTime, p: GEO.pC }, D: { t: bars[idx.D].openTime, p: GEO.pD },
});
const STEP_EXPECT = Math.sqrt(0.004 * 0.02);

const SCENARIOS = {
  'owner-D1': async (o) => {
    const bars = syntheticBars(400, { start: T0, stepMs: H1 });
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 180, B: 240, C: 300, D: 360 }), srcName: 'marked' });
    const want = completedClose(bars, 'D') * percentOf(1440) / 100;
    checks++;
    if (lastOf(ctx, 'dbg_cd') !== 60 || lastOf(ctx, 'dbg_owner') !== 1440) fail(`owner-D1: H1 chart, C->D 60 bars: Pine owner ${lastOf(ctx, 'dbg_owner')} over ${lastOf(ctx, 'dbg_cd')} bars, wanted D1 over 60`);
    checks++;
    if (!close(lastOf(ctx, 'dbg_rung'), want, 1e-9)) fail(`owner-D1: rung ${lastOf(ctx, 'dbg_rung')} vs the LAST COMPLETED daily close x 0.6666% = ${want} - the owner close leaks the developing day or the chart rung was used`);
  },
  'owner-W1': async (o) => {
    const bars = syntheticBars(400, { start: T0, stepMs: 4 * H1 });
    const ctx = await execSrc({ ...o, bars, tf: '240', marks: cornersAt(bars, { A: 20, B: 50, C: 80, D: 380 }), srcName: 'marked' });
    const want = completedClose(bars, 'W') * percentOf(10080) / 100;
    checks++;
    if (lastOf(ctx, 'dbg_owner') !== 10080) fail(`owner-W1: H4 chart, 300 bars: owner ${lastOf(ctx, 'dbg_owner')}, wanted W1 (240 -> 1440 at 50 bars -> 10080 at 7)`);
    checks++;
    if (!close(lastOf(ctx, 'dbg_rung'), want, 1e-9)) fail(`owner-W1: rung ${lastOf(ctx, 'dbg_rung')} vs last completed weekly close x 2.6664% = ${want}`);
  },
  'owner-MN': async (o) => {
    const bars = syntheticBars(400, { start: T0, stepMs: DAY });
    const ctx = await execSrc({ ...o, bars, tf: 'D', marks: cornersAt(bars, { A: 10, B: 30, C: 50, D: 350 }), srcName: 'marked' });
    const want = completedClose(bars, 'M') * percentOf(43200) / 100;
    checks++;
    if (lastOf(ctx, 'dbg_owner') !== 43200) fail(`owner-MN: D1 chart, 300 bars: owner ${lastOf(ctx, 'dbg_owner')}, wanted MN (the chain top)`);
    checks++;
    if (!close(lastOf(ctx, 'dbg_rung'), want, 1e-9)) fail(`owner-MN: rung ${lastOf(ctx, 'dbg_rung')} vs last completed monthly close x 5.3328% = ${want}`);
  },
  'owner-chart': async (o) => {
    const bars = syntheticBars(400, { start: T0, stepMs: H1 });
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 180, B: 240, C: 300, D: 305 }), srcName: 'marked' });
    const want = bars[bars.length - 2].close * percentOf(60) / 100;
    checks++;
    if (lastOf(ctx, 'dbg_owner') !== 60) fail(`owner-chart: a 5-bar leg climbed to ${lastOf(ctx, 'dbg_owner')}`);
    checks++;
    if (!close(lastOf(ctx, 'dbg_rung'), want, 1e-9)) fail(`owner-chart: rung ${lastOf(ctx, 'dbg_rung')} vs close[1] x 0.1666% = ${want}`);
  },
  'owner-fallback': async (o) => {
    const bars = syntheticBars(400, { start: T0, stepMs: H1 });
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 180, B: 240, C: 300, D: 360 }), srcName: 'marked', provider: new AggProvider(bars, { zero: ['D'] }) });
    const want = bars[bars.length - 2].close * percentOf(60) / 100;
    checks++;
    if (!close(lastOf(ctx, 'dbg_rung'), want, 1e-9) || lastOf(ctx, 'dbg_chartfb') !== 1) fail(`owner-fallback: an owner rung that answers nothing must fall back to the chart rung and say so (rung ${lastOf(ctx, 'dbg_rung')} vs ${want}, "(chart)" flag ${lastOf(ctx, 'dbg_chartfb')})`);
  },
  'vote-step': async (o) => {
    const bars = flatBars(400);
    shapeV(bars, { dIdx: 250, valleyIdx: 290, valleyClose: 1.105, valleyLow: 1.103, recoverIdx: 330, recoverClose: 1.115, dHigh: 1.12 });
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 100, B: 150, C: 200, D: 250 }), rungPips: 40, srcName: 'marked' });
    const step = lastOf(ctx, 'dbg_step');
    const byStep = reactionOracle(bars, 250, GEO.pD, false, step);
    const byRung = reactionOracle(bars, 250, GEO.pD, false, 0.004);
    checks++;
    if (!close(step, STEP_EXPECT, 1e-9)) fail(`vote-step: the ladder step moved to ${step}, the closed form is ${STEP_EXPECT} - the vote must never overwrite it`);
    checks++;
    if (lastOf(ctx, 'dbg_state') !== 0 || lastOf(ctx, 'dbg_age') !== 149) fail(`vote-step: D is 149 bars back and inside the bound, Pine says state ${lastOf(ctx, 'dbg_state')} age ${lastOf(ctx, 'dbg_age')}`);
    checks++;
    if (!close(lastOf(ctx, 'dbg_deep'), byStep.rungs, 1e-9)) fail(`vote-step: reaction ${lastOf(ctx, 'dbg_deep')} steps vs the MQL4 walk measured in the drawn step = ${byStep.rungs} (measured in the raw rung it would read ${byRung.rungs})`);
    checks++;
    if (close(byStep.rungs, byRung.rungs, 1e-6)) fail('vote-step: the scenario no longer separates the step from the rung - the check is blind');
    checks++;
    if (lastOf(ctx, 'dbg_below') !== 1 || lastOf(ctx, 'dbg_ok') !== 0) fail(`vote-step: ${byStep.rungs.toFixed(2)} of 2.40 steps must read "below floor" and not vote`);
  },
  'vote-far': async (o) => {
    const bars = flatBars(400);
    shapeV(bars, { dIdx: 100, valleyIdx: 290, valleyClose: 1.1, valleyLow: 1.088, recoverIdx: 330, recoverClose: 1.115, dHigh: 1.12 });
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 20, B: 50, C: 80, D: 100 }), rungPips: 40, srcName: 'marked' });
    const step = lastOf(ctx, 'dbg_step');
    const want = reactionOracle(bars, 100, GEO.pD, false, step);
    checks++;
    if (!(want.hit > 0)) fail('vote-far: the scenario reaches no floor - the check is blind');
    checks++;
    if (!close(lastOf(ctx, 'dbg_deep'), want.rungs, 1e-9) || !close(lastOf(ctx, 'dbg_dist'), want.hit, 1e-12)) fail(`vote-far: D 299 bars back, tip 190 bars after D: Pine reaction ${lastOf(ctx, 'dbg_deep')} / dist ${lastOf(ctx, 'dbg_dist')} vs MQL4 walk ${want.rungs} / ${want.hit} - the walk is capped or D was not found`);
    checks++;
    if (lastOf(ctx, 'dbg_votes3') !== 1 || lastOf(ctx, 'dbg_ok') !== 1) fail('vote-far: dist/3 sits inside the 25% gate of the closed step (0.02/1.666) and must read "VOTES k=3"');
    checks++;
    if (!close(step, STEP_EXPECT, 1e-9)) fail(`vote-far: a voting reaction changed the ladder step to ${step} (closed form ${STEP_EXPECT}) - P-TH3-STEP-16 says NO overwrite`);
  },
  'vote-boundary': async (o) => {
    for (const [dIdx, state] of [[198, 0], [197, 3]]) {
      const bars = flatBars(3200);
      const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 10, B: 40, C: 70, D: dIdx }), rungPips: 40, srcName: 'marked' });
      const age = 3199 - dIdx;
      checks++;
      if (lastOf(ctx, 'dbg_age') !== age || lastOf(ctx, 'dbg_state') !== state) fail(`vote-boundary: D ${age} bars back must be state ${state} (reach ${age - 1} against max_bars_back 3000), Pine says state ${lastOf(ctx, 'dbg_state')} age ${lastOf(ctx, 'dbg_age')}`);
      checks++;
      if (state === 3 && (lastOf(ctx, 'dbg_unknown') !== 1 || lastOf(ctx, 'dbg_below') !== 0)) fail('vote-boundary: a D beyond the readable history must say "unknown", never "below floor"');
      checks++;
      if (state === 0 && lastOf(ctx, 'dbg_unknown') !== 0) fail('vote-boundary: a D inside the bound was refused');
    }
  },
  'vote-no-d': async (o) => {
    const bars = flatBars(400);
    const marks = cornersAt(bars, { A: 100, B: 150, C: 200, D: 250 });
    marks.D.t = bars[0].openTime - DAY;
    const ctx = await execSrc({ ...o, bars, tf: '60', marks, rungPips: 40, srcName: 'marked' });
    checks++;
    if (lastOf(ctx, 'dbg_state') !== 2 || lastOf(ctx, 'dbg_unknown') !== 1 || lastOf(ctx, 'dbg_below') !== 0 || lastOf(ctx, 'dbg_cd') !== -1) fail(`vote-no-d: a D before the first loaded bar must be "unknown (D not on chart)" with an unmeasurable span, Pine says state ${lastOf(ctx, 'dbg_state')} unknown ${lastOf(ctx, 'dbg_unknown')} below ${lastOf(ctx, 'dbg_below')} cd ${lastOf(ctx, 'dbg_cd')}`);
  },
  'vote-young': async (o) => {
    const bars = flatBars(400);
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: cornersAt(bars, { A: 300, B: 330, C: 360, D: 396 }), rungPips: 40, srcName: 'marked' });
    checks++;
    if (lastOf(ctx, 'dbg_state') !== 4 || lastOf(ctx, 'dbg_waiting') !== 1 || lastOf(ctx, 'dbg_below') !== 0) fail(`vote-young: a D 3 bars old has no reaction to measure yet: state ${lastOf(ctx, 'dbg_state')}, waiting ${lastOf(ctx, 'dbg_waiting')}, below ${lastOf(ctx, 'dbg_below')}`);
  },
  absence: async (o) => {
    const bars = flatBars(400);
    const ctx = await execSrc({ ...o, bars, tf: '60', marks: null, srcName: 'no marks' });
    checks++;
    if (lastOf(ctx, 'dbg_marked') !== 0 || lastOf(ctx, 'dbg_anchor_na') !== 1 || lastOf(ctx, 'dbg_src') !== 1 || lastOf(ctx, 'dbg_state') !== 1 || objectCount(ctx, 'lines') !== 0) fail(`absence: no marks must be no model and no lines (marked ${lastOf(ctx, 'dbg_marked')}, anchor-na ${lastOf(ctx, 'dbg_anchor_na')}, src "no marks" ${lastOf(ctx, 'dbg_src')}, vote state ${lastOf(ctx, 'dbg_state')}, ${objectCount(ctx, 'lines')} line(s))`);
  },
  'missing-time': async (o) => {
    const bars = flatBars(400);
    const marks = cornersAt(bars, { A: 100, B: 150, C: 200, D: 250 });
    marks.D.t = 0;
    const ctx = await execSrc({ ...o, bars, tf: '60', marks, rungPips: 40, srcName: 'incomplete: D time' });
    checks++;
    if (lastOf(ctx, 'dbg_marked') !== 0 || lastOf(ctx, 'dbg_anchor_na') !== 1 || lastOf(ctx, 'dbg_src') !== 1 || objectCount(ctx, 'lines') !== 0) fail(`missing-time: D with a price and no time must withdraw the model and say "incomplete: D time" (marked ${lastOf(ctx, 'dbg_marked')}, anchor-na ${lastOf(ctx, 'dbg_anchor_na')}, src ${lastOf(ctx, 'dbg_src')}, ${objectCount(ctx, 'lines')} line(s))`);
  },
  'missing-gaps': async (o) => {
    const bars = flatBars(400);
    const marks = cornersAt(bars, { A: 100, B: 150, C: 200, D: 250 });
    marks.A.t = 0;
    marks.C.p = 0;
    const ctx = await execSrc({ ...o, bars, tf: '60', marks, rungPips: 40, srcName: 'incomplete: A time, C price' });
    checks++;
    if (lastOf(ctx, 'dbg_marked') !== 0 || lastOf(ctx, 'dbg_src') !== 1) fail(`missing-gaps: the readout must name every missing half in corner order ("incomplete: A time, C price"), marked ${lastOf(ctx, 'dbg_marked')}, src match ${lastOf(ctx, 'dbg_src')}`);
  },
  lite: async (o) => {
    const bars = syntheticBars(400, { start: T0, stepMs: H1 });
    const ctx = await execSrc({ ...o, entry: 'entry/lite.pine', bars, tf: '60', marks: cornersAt(bars, { A: 180, B: 240, C: 300, D: 360 }), srcName: 'marked' });
    checks++;
    if (objectCount(ctx, 'lines') === 0 || objectCount(ctx, 'tables') !== 0) fail(`lite (from src): ${objectCount(ctx, 'lines')} line(s), ${objectCount(ctx, 'tables')} table(s) - Lite must draw the ladder and carry no readout`);
  },
};

let PERCENTS_CACHE = null;
function percentOf(tfMin) {
  PERCENTS_CACHE ??= readMql4Percents();
  if (!PERCENTS_CACHE) throw new Error('MODIFIED_FRACTAL_PERCENTAGES not readable - the owner rung has no oracle');
  return PERCENTS_CACHE[RUNG_TABLE_INDEX[tfMin]];
}

async function runModelScenarios({ mutate = null, only = null } = {}) {
  const ids = only ?? Object.keys(SCENARIOS);
  for (const id of ids) {
    const before = failLines.length;
    try {
      await SCENARIOS[id]({ mutate });
    } catch (err) {
      checks++;
      fail(`${id}: the scenario did not RUN: ${err.message.slice(0, 160)}`);
    }
    if (!mutate && failLines.length === before) note(`scenario ${id}: held`);
  }
  if (!mutate) console.log(`[parity] model from src/: ${ids.length} scenario(s) executed on PineTS (owner D1/W1/MN/chart/fallback, reaction by step, D beyond 120 and 3000 bars, absence, missing halves, Lite)`);
}

// --------------------------------------------------------------- self test ---
async function selfTest() {
  console.log('\n[selftest] a rule is only gated if its INVERSE fails the gate.');
  // The mutations below FAIL on purpose. Their findings are the evidence, not the
  // verdict, so the counters are snapshotted and the run's own tallies restored -
  // otherwise a passing selftest would exit non-zero and read as a broken build.
  const savedFailures = failures;
  const savedFailLines = failLines.length;
  const savedChecks = checks;
  const restore = () => { failures = savedFailures; failLines.length = savedFailLines; checks = savedChecks; };
  const good = {
    Sample_ID: 'SELFTEST-GOOD', Direction: 'down', D_Price: '1.10000', Pip_Size: '0.0001',
    Leg_BC: '100.0', Leg_CD: '150.0', Ratio_CD_BC: '1.500', K: '3.500',
    Mother_Pips: '50.0', Rung_Pips: '40.0',
    Step_Mother: '50.0', Step_Pattern: '42.9', Step_Pips: '46.3',
    Target_1: '1.09537', Target_3: '1.08611', Target_5: '1.07685', Target_7: '1.06759',
  };
  // Step = sqrt(50 * 150/3.5) = sqrt(2142.857) = 46.29057... pips -> 46.3 âœ“
  // stepPrice = 46.29057 * 0.0001 = 0.004629057; D - 1*step = 1.10000 - 0.0046291 = 1.0953709 -> 1.09537
  // D - 3*step = 1.10000 - 0.0138872 = 1.0861128 -> 1.08611
  // D - 5*step = 1.10000 - 0.0231453 = 1.0768547 -> 1.07685
  // D - 7*step = 1.10000 - 0.0324034 = 1.0675966 -> 1.06759
  const goodResult = await runDataset([good]);
  if (goodResult.failed > 0) {
    console.error(`[selftest] FAIL - a row the formula itself produced was rejected (${goodResult.failed} check(s))`);
    console.error(`           ${failLines.slice(savedFailLines).join('\n           ')}`);
    process.exit(1);
  }
  console.log(`[selftest] PASS  the consistent row was accepted (${goodResult.passed}/${goodResult.evaluated} checks)`);
  restore();

  const badRows = [
    { ...good, Sample_ID: 'SELFTEST-BAD-STEP', Step_Pips: '99.9' },
    { ...good, Sample_ID: 'SELFTEST-BAD-K', K: '2.500' },
    { ...good, Sample_ID: 'SELFTEST-BAD-RATIO', Ratio_CD_BC: '0.500' },
    { ...good, Sample_ID: 'SELFTEST-BAD-LADDER', Target_5: '1.09000' },
    { ...good, Sample_ID: 'SELFTEST-BAD-MOTHER', Step_Mother: '10.0' },
  ];
  let killed = 0;
  for (const bad of badRows) {
    const r = await runDataset([bad]);
    const died = r.failed > 0;
    if (died) killed++;
    console.log(`[selftest] ${died ? 'KILLED' : 'SURVIVED'}  ${bad.Sample_ID}`);
  }
  restore();
  if (killed !== badRows.length) {
    console.error(`\n[selftest] FAIL - ${badRows.length - killed} mutated row(s) SURVIVED: the checker cannot see that defect`);
    process.exit(1);
  }
  console.log(`[selftest] PASS  all ${badRows.length} mutated rows were KILLED`);

  const sourceMutants = [
    { id: 'LEAK-FUTURE', why: 'owner close read without the [1] offset', only: ['owner-D1'], mutate: (t) => t.split('close[1], lookahead=barmerge.lookahead_on').join('close, lookahead=barmerge.lookahead_on') },
    { id: 'LOOKAHEAD-OFF', why: 'owner close read with lookahead off (stale mid-day)', only: ['owner-D1'], mutate: (t) => t.split(', lookahead=barmerge.lookahead_on').join('') },
    { id: 'VOTE-IN-RUNG', why: 'reaction measured in the raw rung, not the drawn step', only: ['vote-step'], mutate: (t) => t.replace('th3ReactionRungs(th3D, th3DBar, th3VoteWantHigh, th3StepFinal)', 'th3ReactionRungs(th3D, th3DBar, th3VoteWantHigh, th3Rung)') },
    { id: 'D-OLDER-120', why: 'a D older than 120 bars is refused', only: ['vote-step'], mutate: (t) => t.replace('th3VoteReach > TH3_MAX_BARS_BACK ? 3', 'th3VoteReach > 120 ? 3') },
    { id: 'FALSE-BELOW-FLOOR', why: 'a D beyond the bound is not named unknown', only: ['vote-boundary'], mutate: (t) => t.replace('th3VoteReach > TH3_MAX_BARS_BACK ? 3 :', '') },
    { id: 'TIME-NOT-REQUIRED', why: 'a corner without its time still counts', only: ['missing-time'], mutate: (t) => t.replace('p > 0 and t > 0 ? ""', 'p > 0 ? ""') },
  ];
  const probeMutants = [
    { id: 'OWNER-GATE-8', why: 'the span gate is 8, not 7', transform: (t) => t.replace('TH3_OWNER_GATE_BARS = 7', 'TH3_OWNER_GATE_BARS = 8'), run: (tr) => runOwnerRetrace({ transform: tr }) },
    { id: 'OWNER-WALK-5', why: 'the climb is bounded at 5 steps', transform: (t) => t.replace('TH3_OWNER_WALK_MAX = 6', 'TH3_OWNER_WALK_MAX = 5'), run: (tr) => runOwnerRetrace({ transform: tr }) },
    { id: 'RET-WEIGHTS', why: 'the 60/40 weights are swapped', transform: (t) => t.replace('TH3_RET_W_REF = 0.6', 'TH3_RET_W_REF = 0.4').replace('TH3_RET_W_RUNG = 0.4', 'TH3_RET_W_RUNG = 0.6'), run: (tr) => runOwnerRetrace({ transform: tr }) },
    { id: 'RET-TIEBREAK', why: 'a tie goes to the farther q', transform: (t) => t.replace('central < bestCentral', 'central > bestCentral'), run: (tr) => runOwnerRetrace({ transform: tr }) },
    { id: 'KPICK-FAR-4', why: 'the far k is 4', transform: (t) => t.replace('TH3_HIT_K_FAR = 5', 'TH3_HIT_K_FAR = 4'), run: (tr) => runOwnerRetrace({ transform: tr }) },
    { id: 'SHIFT-NO-EXEMPT', why: 'a hand base is no longer exempt from the walk-up shift', transform: (t) => t.replace('base <= 0 and ownerUp', 'ownerUp'), run: (tr) => runOwnerRetrace({ transform: tr }) },
    { id: 'TF-STRING-D', why: 'the daily chart is matched on the string "D"', transform: (t) => t.replace('timeframe.isdaily ? TH3_TF_D1 * timeframe.multiplier :', 'timeframe.period == "D" ? TH3_TF_D1 :'), run: (tr) => runChartTfMapping({ transform: tr }) },
  ];
  let survivors = 0;
  const attempt = async (id, why, runner) => {
    const before = failLines.length;
    const savedF = failures;
    const savedC = checks;
    try { await runner(); } catch (err) { fail(`${id}: ${err.message}`); }
    const died = failLines.length > before;
    failLines.length = before;
    failures = savedF;
    checks = savedC;
    if (!died) survivors++;
    console.log(`[selftest] ${died ? 'KILLED' : 'SURVIVED'}  ${id} (${why})`);
  };
  const sampleSrc = assembleSrc('entry/main.pine', null);
  const sampleProbe = buildProbe([{ ratio: 1 }]).text;
  const stale = (id, text, mutate) => {
    if (mutate(text) !== text) return false;
    survivors++;
    console.log(`[selftest] STALE     ${id} - the anchor text moved, the mutation changes nothing`);
    return true;
  };
  for (const m of sourceMutants) {
    if (stale(m.id, sampleSrc, m.mutate)) continue;
    await attempt(m.id, m.why, () => runModelScenarios({ mutate: m.mutate, only: m.only }));
  }
  for (const m of probeMutants) {
    if (stale(m.id, sampleProbe, m.transform)) continue;
    await attempt(m.id, m.why, () => m.run(m.transform));
  }
  if (survivors) {
    console.error(`\n[selftest] FAIL - ${survivors} source mutation(s) SURVIVED: the checker cannot see that defect`);
    process.exit(1);
  }
  console.log(`[selftest] PASS  all ${sourceMutants.length + probeMutants.length} source mutations were KILLED`);
}

// -------------------------------------------------------------------- main ---
console.log(`[parity] Biotak Trigger TH3 / TradingView - the same numbers, in every state`);
const scenarioFlag = argv.indexOf('--scenario');
if (scenarioFlag >= 0) {
  const only = argv[scenarioFlag + 1].split(',');
  const unknown = only.filter((id) => !(id in SCENARIOS));
  if (unknown.length) { console.error(`[FAIL] unknown scenario(s): ${unknown.join(', ')} - known: ${Object.keys(SCENARIOS).join(', ')}`); process.exit(1); }
  const t0 = Date.now();
  for (const id of only) {
    const before = failLines.length;
    const s0 = Date.now();
    await runModelScenarios({ only: [id] });
    console.log(`[scenario] ${id}: ${failLines.length === before ? 'held' : 'FAILED'} in ${Date.now() - s0} ms`);
  }
  for (const f of failLines) console.error(`[FAIL] ${f}`);
  process.exit(failures ? 1 : 0);
}
await runFixtures();
await runPipCheck();
await runOwnerRetrace();
await runChartTfMapping();
runSourceContracts();
await runModelScenarios();
await runEntrySmoke();
await runDrawCheck();

if (fs.existsSync(DATASET)) {
  const { rows } = datasetRowsFromCsv(fs.readFileSync(DATASET, 'utf8'));
  if (rows.length === 0) {
    console.log(`[parity] dataset: 0 row(s) in Samples/TH3_Dataset/Dataset.csv (header only)`);
    console.log('         nothing to compare - a row is written by the MQL4 recorder (key M) on a keyed chart.');
    console.log('         run tools/check-parity.js --selftest to prove this half of the checker can still FAIL.');
  } else {
    const r = await runDataset(rows);
    console.log(`[parity] dataset: ${rows.length} row(s), ${r.passed}/${r.evaluated} check(s) within the CSV's own rounding`);
  }
} else {
  console.log('[parity] dataset: Samples/TH3_Dataset/Dataset.csv not found - the fixture oracle is the only one on this machine');
}

if (SELFTEST) await selfTest();

for (const n of noteLines) console.log(`[note] ${n}`);
if (failures) {
  for (const f of failLines) console.error(`[FAIL] ${f}`);
  console.error(`\nPARITY FAILED - ${failures} finding(s) across ${checks} fixture check(s)`);
  process.exit(1);
}
console.log(`\n[PASS] parity gate - ${checks} fixture check(s), 0 divergence`);
