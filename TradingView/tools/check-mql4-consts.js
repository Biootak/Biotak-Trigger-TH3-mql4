// The MT4 agreement gate - the one check that answers "is this the same detector".
//
//   node tools/check-mql4-consts.js
//
// The MQL4 build owns the course's numbers; this port does not get to remember them.
// So this gate READS Biotak/TH3/TH3Pivots_A.mqh, parses its #defines, and compares
// them with src/10_const.pine by value. A number that drifted, or a condition that
// was added on the MT4 side and never ported, fails HERE - not on a chart.
//
// A finding names both sides: the MQL4 line and the Pine name.

import fs from 'node:fs';
import path from 'node:path';
import { ROOT, readSource } from './lib/pine-build.js';

const MQL4_ROOT = path.resolve(ROOT, '..');
const HEADERS = [
  'Biotak/TH3/TH3Pivots_A.mqh',     // the six conditions and the lock's band
  'Biotak/TH3/TH3Pivots_B.mqh',     // the unified step's own numbers
];
const PINE_FILE = '10_const.pine';
const TOL = 1e-12;

// Arithmetic only. Anything else in a #define is refused rather than evaluated, so
// a gate that reads arbitrary MQL4 cannot become a gate that RUNS it.
const SAFE = /^[\d\s.+\-*/()]+$/;

function evaluate(expr, where) {
  const body = expr.replace(/\/\/.*$/, '').trim().replace(/[fF]$/, '');
  if (!SAFE.test(body)) throw new Error(`${where}: refusing to evaluate ${JSON.stringify(body)} - not arithmetic`);
  const value = Function(`"use strict"; return (${body});`)();
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${where}: ${body} is not a finite number`);
  return value;
}

// ---- what MQL4 says ----------------------------------------------------------
const mql4 = new Map();   // NAME -> { value, file, line, raw }
const mql4Bad = [];
for (const rel of HEADERS) {
  const abs = path.join(MQL4_ROOT, rel);
  if (!fs.existsSync(abs)) { mql4Bad.push(`${rel}: not found under ${MQL4_ROOT} - the oracle is missing, and an absent oracle is a FAILED check`); continue; }
  const lines = fs.readFileSync(abs, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const m = /^#define\s+((?:TH3_P6_[A-Z0-9_]+)|TH3_HIT_MAX_STEP_ERR|TH3_STEP_MIN_LEG_RUNGS|TH3_MOTHER[A-Z0-9_]*)\s+(\S.*)$/.exec(line.trim());
    if (!m) return;
    try {
      const value = evaluate(m[2], `${rel}:${i + 1} ${m[1]}`);
      if (!mql4.has(m[1])) mql4.set(m[1], { value, file: rel, line: i + 1, raw: m[2].trim() });
    } catch (err) {
      mql4Bad.push(err.message);
    }
  });
}

// ---- what the port says ------------------------------------------------------
const pine = new Map();
readSource(PINE_FILE).split(/\r?\n/).forEach((line, i) => {
  const m = /^(TH3_[A-Z0-9_]+)\s*=\s*(.+)$/.exec(line);
  if (!m) return;
  try {
    pine.set(m[1], { value: evaluate(m[2], `src/${PINE_FILE}:${i + 1} ${m[1]}`), line: i + 1 });
  } catch {
    // a non-arithmetic constant (a color, a string) is not this gate's business
  }
});

// ---- the comparison ----------------------------------------------------------
const problems = [...mql4Bad];
const checked = [];
for (const [name, m] of mql4) {
  const p = pine.get(name);
  if (!p) {
    problems.push(`MISSING: ${m.file}:${m.line} defines ${name} = ${m.raw} and src/${PINE_FILE} has no such constant - a condition MT4 applies and this port does not`);
    continue;
  }
  if (Math.abs(p.value - m.value) > TOL * Math.max(1, Math.abs(m.value))) {
    problems.push(`DRIFT: ${name} is ${m.raw} in ${m.file}:${m.line} but ${p.value} in src/${PINE_FILE}:${p.line}`);
    continue;
  }
  checked.push(`${name} = ${m.value} (${m.file}:${m.line})`);
}

// The reverse direction too: a TH3_P6_* name the port invented would be a rule with
// no course behind it - the port may not add conditions to the detector.
for (const name of pine.keys()) {
  if (name.startsWith('TH3_P6_') && !mql4.has(name)) {
    problems.push(`INVENTED: src/${PINE_FILE} declares ${name}, and no MQL4 header defines it - the port may not add a condition to the detector`);
  }
}

console.log(`[note] oracles read: ${HEADERS.join(', ')}`);
if (process.argv.includes('--list')) for (const c of checked) console.log(`[note] ${c}`);
if (problems.length) {
  for (const p of problems) console.error(`[FAIL] ${p}`);
  console.error(`\nMT4 AGREEMENT FAILED - ${problems.length} finding(s)`);
  process.exit(1);
}
console.log(`\n[PASS] mt4 agreement gate - ${checked.length} constant(s) equal to the MQL4 header, no invented condition`);
