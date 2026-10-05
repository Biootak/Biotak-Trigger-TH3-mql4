#!/usr/bin/env node
// th3-tune-k.js — P-TH3-DB: WHICH K, BY SEARCH, ON THE SAMPLES YOU JUDGED REAL.
//
// WHAT IT IS. The recorder draws a ladder with K = TH3UnifiedK(ratio), a four-step
// table (2.5 / 3.0 / 3.5 / 1.0). That table was chosen by reading charts, not by
// measuring them, and the dataset is exactly the instrument that can replace the
// reading with a number: every sample already carries the market's turn, so a
// candidate K can be scored instead of argued about.
//
// THE MODEL IS THE MQL4's, PORTED (Biotak/TH3/TH3Pivots_B.mqh:405-430), because a
// tuner that scores a DIFFERENT formula than the one on the chart would be a
// number about nothing:
//
//   step_mother = (mother >= 2.5*rung) ? mother/3 : mother      // macro-span rule
//   step_pattern = legCD / K
//   step = sqrt(step_mother * step_pattern)                     // the resonance
//
// Only K moves in the search, which is the point: step_mother does not depend on
// K, so holding it fixed isolates the one thing being tuned. Where the row has
// no Rung_Pips (the samples recorded before the column existed) step_mother is
// RECOVERED from the recorded step and the recorded K — the same identity the
// formula states — and the tool says so in its output rather than guessing
// silently.
//
// THE SCORE is the same quantity the recorder measures: the distance from the
// actual turn to the THIRD rung, in pips (MARKET_REACTION/Error_Margin_Pips).
// The median leads, because one sample with no reaction should not move a
// coefficient; mean, p90 and the share within 5 pips follow.
//
//   node tools/th3-tune-k.js                 # the real samples only
//   node tools/th3-tune-k.js --all           # include unreviewed and invented
//   node tools/th3-tune-k.js --csv other.csv # score any CSV with this schema
//   node tools/th3-tune-k.js --from 0.5 --to 5 --step 0.05
//
// Exit 0 on a run, 1 when there is nothing scoreable — an empty dataset is not a
// result, and saying «K is fine» from zero samples is how a bad table survives.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DS = path.join(ROOT, 'Samples', 'TH3_Dataset');
const NL = String.fromCharCode(10);

function splitCsv(line) { return line.replace(/\r$/, '').split(','); }

function readCsv(file) {
  if (!fs.existsSync(file)) return null;
  const lines = fs.readFileSync(file, 'utf8').split(NL).map((l) => l.trim()).filter(Boolean);
  if (lines.length < 2) return [];
  const head = splitCsv(lines[0]);
  return lines.slice(1).map((l) => {
    const cells = splitCsv(l), row = {};
    head.forEach((h, i) => { row[h] = cells[i] == null ? '' : cells[i]; });
    return row;
  });
}

const DEC = 8;   // price decimals in the shape key; 8 keeps forex and gold apart

function num(v) {
  const f = parseFloat(v);
  return Number.isFinite(f) ? f : null;
}

//--- the formula, ported line for line from the MQL4
function unifiedK(ratio) {
  if (ratio <= 0.85) return 2.5;
  if (ratio <= 1.20) return 3.0;
  if (ratio <= 1.80) return 3.5;
  return 1.0;                     // major extension: the leg itself is the unit
}

function stepMotherOf(motherPrice, rung) {
  if (!(motherPrice > 0)) return null;
  if (rung && rung > 0 && motherPrice >= 2.5 * rung) return motherPrice / 3.0;
  return motherPrice;
}

/** Turn one CSV row into a scoreable sample, or a reason it cannot be scored. */
function prepare(row, reviews) {
  const why = [];
  const pip = num(row.Pip_Size);
  const dPrice = num(row.D_Price);
  const turn = num(row.Actual_Turn);
  const legCdPips = num(row.Leg_CD);
  const motherPips = num(row.Mother_Pips);
  const rungPips = num(row.Rung_Pips);
  const stepPips = num(row.Step_Pips);
  const recK = num(row.K);
  const ratio = num(row.Ratio_CD_BC);
  const verdict = (reviews.get(row.Sample_ID) || {}).Verdict || 'unreviewed';

  if (!(pip > 0) || dPrice === null || turn === null) why.push('no turn/pip/price');
  if (!(legCdPips > 0) || !(motherPips > 0)) why.push('no legs');
  if (ratio === null) why.push('no ratio');

  let smPips = null;
  let recovered = false;
  if (motherPips > 0 && rungPips !== null && rungPips > 0) {
    smPips = stepMotherOf(motherPips * pip, rungPips * pip) / pip;
  } else if (stepPips && recK && legCdPips > 0) {
    // step = sqrt(sm * legCD/K)  =>  sm = step^2 * K / legCD
    smPips = (stepPips * stepPips * recK) / legCdPips;
    recovered = true;
  } else {
    why.push('cannot recover step_mother');
  }

  return {
    id: row.Sample_ID, symbol: row.Symbol, tf: row.TF, verdict,
    ratio, legCdPips, motherPips, rungPips, smPips, recovered, recK,
    direction: row.Direction === 'down' ? -1 : 1,
    dPrice, turn, pip,
    scoredError: num(row.Error_Pips),
    why: why.join(', '),
  };
}

/** |turn - (D - dir*3*step)| in pips — the recorder's own error measure. */
function errorFor(s, k) {
  const step = Math.sqrt(s.smPips * (s.legCdPips / k)) * s.pip;
  const rung3 = s.dPrice + s.direction * 3 * step;
  return Math.abs(s.turn - rung3) / s.pip;
}

function stats(errs) {
  if (!errs.length) return null;
  const sorted = errs.slice().sort((a, b) => a - b);
  const med = sorted[Math.floor(sorted.length / 2)];
  const mean = errs.reduce((a, b) => a + b, 0) / errs.length;
  const p90 = sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.9))];
  const within = errs.filter((e) => e <= 5).length / errs.length;
  return { n: errs.length, med, mean, p90, worst: sorted[sorted.length - 1], within };
}

function fmt(v, n = 2) { return v === null || v === undefined ? '—' : v.toFixed(n); }

function main() {
  const args = process.argv.slice(2);
  const csvArg = args.indexOf('--csv');
  const csv = csvArg >= 0 && args[csvArg + 1] ? path.resolve(args[csvArg + 1])
    : path.join(DS, 'Dataset.csv');
  const from = Number(args[args.indexOf('--from') + 1]) || 0.5;
  const to = Number(args[args.indexOf('--to') + 1]) || 5.0;
  const stepSize = Number(args[args.indexOf('--step') + 1]) || 0.05;
  const all = args.includes('--all');

  const rows = readCsv(csv);
  if (rows === null) {
    console.error('no dataset at ' + path.relative(ROOT, csv));
    console.error('record a sample with M, then: node tools/th3-dataset-sync.js');
    return 1;
  }
  const reviews = new Map(readCsv(path.join(DS, 'Reviews.csv')).map((r) => [r.Sample_ID, r.Verdict]));
  const allRows = rows.map((r) => prepare(r, reviews));
  const usable = allRows.filter((s) => !s.why && (all || s.verdict === 'real'));

  console.log(`th3-tune-k: ${path.relative(ROOT, csv)} — ${rows.length} row(s), ` +
    `${usable.length} scoreable (${all ? 'all verdicts' : 'verdict=real only'})`);
  if (!usable.length) {
    if (!allRows.length) {
      console.log('  the dataset is empty. Nothing can be tuned from nothing:');
      console.log('    draw a pattern, press B for the mother, press M, then');
      console.log('    node tools/th3-dataset-sync.js && node tools/th3-tune-k.js');
      return 1;
    }
    const reasons = {};
    allRows.forEach((s) => { if (s.why) reasons[s.why] = (reasons[s.why] || 0) + 1; });
    for (const [r, n] of Object.entries(reasons)) console.log(`  unusable: ${n} x ${r}`);
    const v = {};
    allRows.forEach((s) => { v[s.verdict] = (v[s.verdict] || 0) + 1; });
    console.log(`  verdicts present: ${Object.entries(v).map(([k, n]) => k + '=' + n).join(', ')}`);
    console.log('  mark samples real first: node tools/th3-dataset-dashboard.js ' +
      'review Sample_001 real "..."');
    return 1;
  }
  // P-TH3-DB: the failure mode this dataset already committed once — twenty
  // captures of ONE structure. A K fitted to that describes one pattern, and the
  // number would be quoted as a law. Distinctness is counted on the structure
  // itself (D, legs, ratio), not on Sample_ID.
  const shapes = new Set(usable.map((s) =>
    [s.dPrice.toFixed(DEC), s.legCdPips.toFixed(2), s.ratio.toFixed(3), s.motherPips.toFixed(2)].join('|')));
  if (usable.length > 2 && shapes.size <= Math.max(1, Math.floor(usable.length / 4))) {
    console.log(`  WARNING: ${usable.length} sample(s) but only ${shapes.size} distinct` +
      ` structure(s) (same D, legs and ratio). A K fitted to this describes ONE` +
      ` pattern, not the formula — record diverse symbols and timeframes first.`);
  }
  const recovered = usable.filter((s) => s.recovered).length;
  if (recovered) {
    console.log(`  ${recovered}/${usable.length} row(s) have no Rung_Pips: ` +
      'step_mother was recovered from the recorded step (step^2*K/legCD)');
  }

  //--- the table as it stands, scored the same way
  const current = usable.map((s) => errorFor(s, s.recK || unifiedK(s.ratio)));
  const curStats = stats(current);
  const byTier = {};
  usable.forEach((s) => {
    const k = s.recK || unifiedK(s.ratio);
    (byTier[k] = byTier[k] || []).push(errorFor(s, k));
  });
  console.log('\ncurrent tiers (K from TH3UnifiedK), scored on the same samples:');
  for (const k of Object.keys(byTier).sort((a, b) => a - b)) {
    const st = stats(byTier[k]);
    console.log(`  K=${(+k).toFixed(2).padEnd(5)} n=${String(st.n).padEnd(4)} ` +
      `median ${fmt(st.med)}  mean ${fmt(st.mean)}  p90 ${fmt(st.p90)}  ` +
      `worst ${fmt(st.worst)}  within5 ${(st.within * 100).toFixed(0)}%`);
  }
  console.log(`  ALL        n=${String(curStats.n).padEnd(4)} median ${fmt(curStats.med)}` +
    `  mean ${fmt(curStats.mean)}  p90 ${fmt(curStats.p90)}  worst ${fmt(curStats.worst)}` +
    `  within5 ${(curStats.within * 100).toFixed(0)}%`);

  //--- the search
  const results = [];
  for (let k = from; k <= to + 1e-9; k += stepSize) {
    const st = stats(usable.map((s) => errorFor(s, k)));
    if (st) results.push({ k: +k.toFixed(4), st });
  }
  results.sort((a, b) => (a.st.med - b.st.med) || (a.st.mean - b.st.mean));
  // a winner pinned to an edge means the answer is outside the searched range;
  // printing it as «best» would be reporting a boundary as a finding
  const atEdge = results.length && (results[0].k <= from + 1e-9 || results[0].k >= to - 1e-9);
  if (atEdge) {
    console.log(`  WARNING: the best candidate is ON the search boundary (K=` +
      `${results[0].k.toFixed(2)} of ${from}..${to}). The real optimum is outside` +
      ` that range — widen it: --from ${(from / 2).toFixed(2)} --to ${(to * 2).toFixed(2)}`);
  }
  console.log(`\nsearched K ${from} .. ${to} step ${stepSize} (${results.length} candidates), ` +
    'ranked by median rung-3 error:');
  console.log('  K      n    median   mean    p90     worst   within5');
  for (const r of results.slice(0, 8)) {
    console.log(`  ${r.k.toFixed(2).padEnd(6)}${String(r.st.n).padEnd(5)}` +
      `${fmt(r.st.med).padEnd(9)}${fmt(r.st.mean).padEnd(8)}${fmt(r.st.p90).padEnd(8)}` +
      `${fmt(r.st.worst).padEnd(8)}${(r.st.within * 100).toFixed(0)}%`);
  }

  //--- what each ratio band would want, which is what TH3UnifiedK actually is
  const bands = [[0, 0.85, 'ratio <= 0.85'], [0.85, 1.20, '0.85 < ratio <= 1.20'],
    [1.20, 1.80, '1.20 < ratio <= 1.80'], [1.80, Infinity, 'ratio > 1.80 (major)']];
  console.log('\nbest K per ratio band (the shape TH3UnifiedK should have):');
  for (const [lo, hi, label] of bands) {
    const inBand = usable.filter((s) => s.ratio > lo && s.ratio <= hi);
    if (!inBand.length) {
      console.log(`  ${label.padEnd(24)} no samples`);
      continue;
    }
    let best = null;
    for (let k = from; k <= to + 1e-9; k += stepSize) {
      const st = stats(inBand.map((s) => errorFor(s, k)));
      if (st && (!best || st.med < best.st.med)) best = { k: +k.toFixed(2), st };
    }
    const now = stats(inBand.map((s) => errorFor(s, s.recK || unifiedK(s.ratio))));
    console.log(`  ${label.padEnd(24)} n=${String(inBand.length).padEnd(4)} ` +
      `now ${fmt(now.med).padEnd(7)} (K=${(s0K(inBand)).toFixed(2)})  ->  ` +
      `best ${fmt(best.st.med).padEnd(7)} (K=${best.k.toFixed(2)})`);
  }

  console.log('\nHOW TO READ THIS');
  console.log('  - n is the evidence. Under ~20 real samples a K difference of a few');
  console.log('    tenths is noise; the tool says the number, not a verdict.');
  console.log('  - the median leads because one sample with no reaction should not');
  console.log('    move a coefficient that is used on every chart.');
  console.log('  - a "major extension" row (ratio > 1.8) is scored against K too, but');
  console.log('    MQL4 returns 1.0 there: the leg itself IS the unit. Keep that.');
  return 0;
}

function s0K(inBand) {
  const s = inBand[0];
  return s.recK || unifiedK(s.ratio);
}

process.exit(main());