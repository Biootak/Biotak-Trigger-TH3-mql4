// Structure gate. Runs in every build; a rule below is not advice.
//
//   node tools/check-structure.js
//
// Every finding names file:line. A rule with no number is not a finding.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { ROOT, SRC, DIST, listEntries, listModules, parseModule, resolveEntry, render } from './lib/pine-build.js';

const MODULE_MAX_LINES = 400;
const MODULE_MAX_LINES_WHY = 'contract 7: a file over the ceiling never grows - touch it, split it by owner';

// Literals owned by src/10_const.pine. A second spelling anywhere in src/ is the
// defect: the K bands are what the port is checked against, so two copies of one
// band is two answers to one question.
const OWNED_LITERALS = [
  '0.85', '1.20', '1.80', '0.75', '1.666', '2.5', '3.5', '3.0', '500', '3000',
  // the professor's rung table, the frequency default and the pip multiplier
  '0.0208', '0.0417', '0.0833', '0.1666', '0.3333', '0.6666', '2.6664', '5.3328', '28.125', '0.25',
  // the six conditions' own numbers (TH3Pivots_A.mqh:12-22); tools/check-mql4-consts.js
  // compares the NAMES against that header, this list stops a second spelling in src/.
  '0.60', '2.40', '0.80', '1.00',
];
const OWNER_FILE = '10_const.pine';

// THE REGRESSION REGISTER - a defect that shipped once and must not come back.
// Each entry is asserted against the source in every build, so the next edit that
// puts it back fails HERE, at the name, before the terminal sees it.
const REGRESSIONS = [
  {
    file: '30_math.pine',
    mustNotMatch: /0\.5 \* \(\s*base/,
    why: 'the lock AVERAGED base and derived and so APPLIED the verdict. P-TH3-STEP-16 (TH3Renderer_B.mqh:130-137) discards it: it is a caption. Ship the average and the step is a different number.',
  },
  {
    file: '30_math.pine',
    mustNotMatch: /th3LockStep\b/,
    why: 'the applying lock is retired; th3LockVerdict returns the words and never a step.',
  },
  {
    file: '40_levels.pine',
    mustNotMatch: /th3LockStep\b/,
    why: 'a caller resurrecting the applying lock undoes the same fix from the other end.',
  },
  {
    file: '20_settings.pine',
    mustMatch: /TH3_SET_RUNG_PIPS = input\.float\(0\.0,/,
    why: 'the owner rung must DEFAULT to derived (0). TH3PatternStepRungTF is close[1] * pct / 100, never a constant: a fixed default makes the macro-span gate a different rule on every timeframe.',
  },
  {
    file: '35_pivot.pine',
    mustMatch: /var int pvExtShift = 0/,
    why: 'the candidate\'s age must be a COUNTER. Recording an absolute bar_index and subtracting it is off by the one bar between an index and a shift, and that single bar moved every read (the run, the cover, the key line) one candle into the past - measured: the detector declared 0 pivots on a zigzag built to satisfy it.',
  },
  {
    file: '40_levels.pine',
    mustMatch: /th3SrcName = /,
    why: 'the ladder falls back to the fractal ring because the six-condition ring is empty; the fallback must NAME itself on the readout, or a chart with no detector behind it looks exactly like a chart whose detector worked.',
  },
  {
    file: '30_math.pine',
    mustMatch: /TH3_PIP_POINT_MULT/,
    why: 'GetCachedPipSize gives ten points to a 2-digit METAL and one point to any other 2-digit symbol (PerformanceOptimizations.mqh:176-186); dropping the multiplier is a silent 10x pip error on gold and silver.',
  },
];

const problems = [];
const notes = [];        // printed on every run: the evidence a normal report cites
const readerNotes = [];  // printed only with --readers: one line per constant
const add = (file, line, msg) => problems.push(`${file}${line ? `:${line}` : ''} ${msg}`);

const stripComments = (lines) => lines.map((l) => l.replace(/\/\/.*$/, ''));

const entries = listEntries();
const modules = listModules();
const parsed = new Map();
for (const rel of [...modules, ...entries]) parsed.set(rel, parseModule(rel));

// ---- 1. every module is reachable from an entry (no orphan file) -------------
const reachable = new Set();
for (const rel of entries) {
  const { modules: chain, cycles, missing } = resolveEntry(rel);
  for (const m of chain) reachable.add(m.file);
  for (const c of cycles) add(`src/${rel}`, 0, `include cycle: ${c}`);
  for (const m of missing) add('src/' + m.split(' -> ')[0], 0, `//@includes a file that does not exist: ${m.split(' -> ')[1]}`);
}
for (const rel of modules) {
  if (!reachable.has(rel)) add(`src/${rel}`, 0, 'orphan module: no entry reaches it - dead code, or a missing //@includes');
}

// ---- 2. headers -------------------------------------------------------------
for (const [rel, mod] of parsed) {
  if (!mod.id) add(`src/${rel}`, 1, 'missing //@module <id>');
  if (!mod.owner) add(`src/${rel}`, 1, 'missing //@owner <one line of ownership>');
  if (mod.unknown.length) add(`src/${rel}`, 1, `unknown directive(s): ${mod.unknown.map((k) => `//@${k}`).join(', ')}`);
  if (mod.includes.some((i) => path.isAbsolute(i) || i.includes('..'))) add(`src/${rel}`, 1, '//@includes must be a path inside src/');
}

const entryNames = new Set();
for (const rel of entries) {
  const mod = parsed.get(rel);
  if (!mod.entry) add(`src/${rel}`, 1, 'missing //@entry <name>');
  else if (entryNames.has(mod.entry)) add(`src/${rel}`, 1, `//@entry ${mod.entry} is used by more than one entry`);
  else entryNames.add(mod.entry);
  if (!mod.output) add(`src/${rel}`, 1, 'missing //@output <file.pine>');
  else if (!mod.output.endsWith('.pine')) add(`src/${rel}`, 1, '//@output must end in .pine');
  const logic = mod.body.filter((l) => l.trim() !== '');
  if (logic.length) add(`src/${rel}`, 0, `entry carries ${logic.length} line(s) of logic - entries stay thin`);
}

// ---- 3. ceilings ------------------------------------------------------------
for (const [rel, mod] of parsed) {
  if (mod.lines.length > MODULE_MAX_LINES) {
    add(`src/${rel}`, MODULE_MAX_LINES + 1, `${mod.lines.length} lines, ceiling is ${MODULE_MAX_LINES} (${MODULE_MAX_LINES_WHY})`);
  }
}

// ---- 4. one owner per constant ---------------------------------------------
for (const [rel, mod] of parsed) {
  if (rel === OWNER_FILE) continue;
  const code = stripComments(mod.body);
  code.forEach((line, i) => {
    for (const lit of OWNED_LITERALS) {
      const re = new RegExp(`(?<![\\d.])${lit.replace('.', '\\.')}(?![\\d])`);
      if (re.test(line)) {
        add(`src/${rel}`, mod.header.length + i + 1, `literal ${lit} is owned by src/${OWNER_FILE} - read the name, never respell the number`);
      }
    }
  });
}

// ---- 5. one flat namespace: no name declared twice --------------------------
const FN_DEF = /^([A-Za-z_]\w*)\s*\([^)]*\)\s*=>/;
const ASSIGN = /^([A-Za-z_]\w*)\s*=[^=]/;
for (const rel of entries) {
  const { entry, modules: chain } = resolveEntry(rel);
  const seen = new Map();
  const consider = (file, lines) => {
    lines.forEach((line, i) => {
      const m = FN_DEF.exec(line) ?? ASSIGN.exec(line);
      if (!m) return;
      const name = m[1];
      if (['if', 'for', 'while', 'switch', 'var', 'varip'].includes(name)) return;
      const where = `${file}:${i + 1}`;
      if (seen.has(name)) add(file, i + 1, `name ${name} is already declared at ${seen.get(name)} - Pine has ONE flat namespace`);
      else seen.set(name, where);
    });
  };
  for (const m of chain) consider(`src/${m.file}`, m.body);
  consider(`src/${entry.file}`, entry.declare);
}

// ---- 6. no owner without a caller ------------------------------------------
const allBodies = [...parsed.entries()].filter(([rel]) => rel !== '' ).map(([rel, m]) => ({ rel, body: m.body }));
for (const [rel, mod] of parsed) {
  mod.body.forEach((line, i) => {
    const decl = /^(TH3_SET_[A-Z0-9_]+)\s*=/.exec(line);
    if (!decl) return;
    const name = decl[1];
    const re = new RegExp(`\\b${name}\\b`);
    let reads = 0;
    for (const { rel: other, body } of allBodies) {
      body.forEach((l, j) => {
        if (other === rel && j === i) return;
        if (re.test(l)) reads++;
      });
    }
    if (reads === 0) add(`src/${rel}`, mod.header.length + i + 1, `${name} is declared and never read - an owner without a caller is dead weight, delete it`);
  });
}
for (const [rel, mod] of parsed) {
  mod.body.forEach((line, i) => {
    const decl = /^(TH3_GRP_[A-Z0-9_]+)\s*=/.exec(line);
    if (!decl) return;
    const name = decl[1];
    const re = new RegExp(`\\b${name}\\b`);
    let reads = 0;
    for (const { body } of allBodies) body.forEach((l) => { if (re.test(l)) reads++; });
    if (reads <= 1) add(`src/${rel}`, mod.header.length + i + 1, `${name} labels a group no input uses`);
  });
}

// ---- 6c. NO owner without a caller, measured on EVERY constant -------------
// The rule was only asserted for TH3_SET_* before this run, which left the rest of
// 10_const.pine free to carry numbers nothing reads - a dead literal that a future
// reader would take for a rule in force. A constant is read if its NAME appears in
// any module's code, or in any entry's declaration (the {TH3_MAX_LINES} placeholders).
for (const [rel, mod] of parsed) {
  mod.body.forEach((line, i) => {
    const decl = /^(TH3_[A-Z0-9_]+)\s*=/.exec(line);
    if (!decl) return;
    const name = decl[1];
    const re = new RegExp(`\\b${name}\\b`);
    let reads = 0;
    const where = [];
    for (const [other, otherMod] of parsed) {
      stripComments(otherMod.body).forEach((l, j) => {
        if (other === rel && j === i) return;
        if (re.test(l)) { reads++; where.push(`src/${other}:${j + 1}`); }
      });
      otherMod.declare.forEach((l, j) => {
        if (re.test(l)) { reads++; where.push(`src/${other} decl:${j + 1}`); }
      });
    }
    if (reads === 0) {
      add(`src/${rel}`, mod.header.length + i + 1, `${name} is declared and NEVER READ by any module or any entry's declaration - delete it, or make it read; a literal nothing reads is not a rule`);
    } else readerNotes.push(`${name} <- ${where.slice(0, 3).join(', ')}${where.length > 3 ? ` +${where.length - 3}` : ''}`);
  });
}

// ---- 6b. the regression register -------------------------------------------
for (const r of REGRESSIONS) {
  const mod = parsed.get(r.file);
  if (!mod) { add(`src/${r.file}`, 0, `the regression register names a file that does not exist (${r.why})`); continue; }
  const code = stripComments(mod.body).join('\n');
  if (r.mustNotMatch && r.mustNotMatch.test(code)) {
    add(`src/${r.file}`, 0, `REGRESSED: ${r.mustNotMatch} is back. ${r.why}`);
  }
  if (r.mustMatch && !r.mustMatch.test(code)) {
    add(`src/${r.file}`, 0, `REGRESSED: ${r.mustMatch} is gone. ${r.why}`);
  }
}

// ---- 7. dist is GENERATED, and it is CURRENT --------------------------------
for (const rel of entries) {
  const mod = parsed.get(rel);
  if (!mod.output) continue;
  const abs = path.join(DIST, mod.output);
  if (!fs.existsSync(abs)) { add(`dist/${mod.output}`, 0, 'missing - run npm run build'); continue; }
  const onDisk = fs.readFileSync(abs, 'utf8').replace(/\r\n?/g, '\n');
  let fresh;
  try {
    fresh = render({ entry: mod, modules: resolveEntry(rel).modules });
  } catch (err) {
    add(`src/${rel}`, 0, err.message);
    continue;
  }
  const same = crypto.createHash('sha256').update(onDisk).digest('hex') === crypto.createHash('sha256').update(fresh.text).digest('hex');
  if (same) notes.push(`dist/${mod.output} is CURRENT (sha256 matches a fresh assemble of src/)`);
  else add(`dist/${mod.output}`, 0, 'is NOT CURRENT - it does not match an assemble of src/. Never hand-edit a generated file; run npm run build');
}

// ---- report -----------------------------------------------------------------
for (const n of notes) console.log(`[note] ${n}`);
if (process.argv.includes('--readers')) for (const n of readerNotes) console.log(`[note] ${n}`);
if (problems.length) {
  for (const p of problems) console.error(`[FAIL] ${p}`);
  console.error(`\nSTRUCTURE FAILED - ${problems.length} finding(s)`);
  process.exit(1);
}
console.log(`\n[PASS] structure gate - ${modules.length} module(s), ${entries.length} entr${entries.length === 1 ? 'y' : 'ies'}, all reachable, one owner per constant`);
