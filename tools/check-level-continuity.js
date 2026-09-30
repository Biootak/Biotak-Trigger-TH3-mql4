#!/usr/bin/env node
// LEVEL CONTINUITY GATE — a timeframe switch is a HANDOFF, and no other surface
// may turn it back into a wipe-and-rebuild.
//
// WHY THIS EXISTS. This defect has now been reported three times, in three
// different costumes, and every costume was a change made SOMEWHERE ELSE:
//
//   1. the level prefix named the timeframe  -> a switch RENAMED the whole family
//      (~900 deletes + ~900 creates for a switch that only changes the prices);
//   2. the teardown deleted the family and the fresh instance's first comparison
//      was trivially "topology changed"    -> a wipe on every switch;
//   3. the adoption verdict was a GlobalVariable that could be MISSING, and the
//      missing case returned with `adopt = false` and printed NOTHING -> a wipe
//      with no line in the log naming its author (P-VIEW-05, 2026-09-30).
//
// Each one was green: the compiler only checks that names resolve. The invariant
// the user finally asked for in words — «هر تغییری که میدی نباید این رفتار سطوح
// را عوض کند، خواسته یا ناخواسته» — cannot be a habit, because the change that
// breaks it is never made in this file. So it is checked here, in every build,
// against the SOURCES: the six things below are the whole mechanism, and each one
// is a named site. A gate that catches the next costume is worth more than a note
// asking the next reader to be careful.
//
// What it does NOT do: it cannot see a NEW delete path that deletes the family
// under a different name, and it cannot run the indicator. The number that proves
// the behaviour is the runtime pair (`probe=handoff preexist=` -> `probe=adopt
// preexist= adopted=1`) plus `stage=0` in the census on a switch; this gate keeps
// the sites that print them alive and un-gated.
//
// USAGE:  node tools/check-level-continuity.js
// Exit 0 = clean, 1 = a reinit path can delete the level family again.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const BIOTAK = path.join(ROOT, 'Biotak');
const INIT_FILE = path.join(BIOTAK, 'EventHandlers_Init.mqh');
const CALC_FILE = path.join(BIOTAK, 'EventHandlers_Calc.mqh');
const TAIL_FILE = path.join(BIOTAK, 'EventHandlers_Tail.mqh');

const failures = [];

function linesOf(abs) {
  try {
    return fs.readFileSync(abs, 'utf8').split(/\r?\n/);
  } catch {
    return null;
  }
}

// --- the body of a block, by BRACE DEPTH, comments stripped --------------------
// Enough for this tree: `// text {` must not count, and no brace lives inside a
// string literal on the lines this gate reads.
function stripComment(s) {
  const i = s.indexOf('//');
  return i >= 0 ? s.slice(0, i) : s;
}
function depthDelta(s) {
  let d = 0;
  for (const ch of stripComment(s)) {
    if (ch === '{') d++;
    else if (ch === '}') d--;
  }
  return d;
}
// Returns { from, to } line indices (inclusive) of the `{ ... }` block that
// starts at or after `from`, or null.
function blockAfter(lines, from) {
  let i = from;
  while (i < lines.length && !stripComment(lines[i]).includes('{')) i++;
  if (i >= lines.length) return null;
  const start = i;
  let depth = 0;
  for (; i < lines.length; i++) {
    depth += depthDelta(lines[i]);
    if (depth === 0 && i > start) return { from: start, to: i };
    if (depth === 0 && i === start && stripComment(lines[i]).includes('{') &&
        stripComment(lines[i]).includes('}')) return { from: start, to: i };
  }
  return null;
}
function indexOfLine(lines, needle, from = 0) {
  for (let i = from; i < lines.length; i++) if (lines[i].includes(needle)) return i;
  return -1;
}

function main() {
  const init = linesOf(INIT_FILE);
  const calc = linesOf(CALC_FILE);
  const tail = linesOf(TAIL_FILE);
  if (!init || !calc || !tail) {
    console.log('LEVEL CONTINUITY GATE FAILED');
    console.log('         one of the event-handler files is missing');
    process.exit(1);
  }

  // -- 1. the CHART is a witness, not just the stamp ---------------------------
  // `LevelFamilyObjectsOnChart()` is the probe; `preexist` must reach the verdict.
  const probeDef = indexOfLine(init, 'int LevelFamilyObjectsOnChart()');
  const resolveDef = indexOfLine(init, 'void ResolveTopologyAdoption()');
  const resolveBlock = resolveDef >= 0 ? blockAfter(init, resolveDef) : null;
  const resolveBody = resolveBlock ? init.slice(resolveBlock.from, resolveBlock.to + 1).join('\n') : '';
  const witnessOk =
    probeDef >= 0 && resolveBody.includes('LevelFamilyObjectsOnChart()') &&
    resolveBody.includes('preexist > 0') && resolveBody.includes('g_adoptPreviousTopology =');
  if (!witnessOk) {
    failures.push(
      'chart witness missing: ResolveTopologyAdoption must read LevelFamilyObjectsOnChart() ' +
        'and let `preexist > 0` reach the verdict (Biotak/EventHandlers_Init.mqh)'
    );
  } else {
    console.log(
      `[PASS] chart witness: preexist probe wired into the verdict ` +
        `(Biotak/EventHandlers_Init.mqh:${probeDef + 1}, :${resolveDef + 1})`
    );
  }

  // -- 2. the two probe lines exist and are UNGATED ----------------------------
  // A gated proof is a proof that disappears exactly when it is needed (the third
  // costume printed nothing at all).
  for (const [file, abs, lines, tag] of [
    ['Biotak/EventHandlers_Init.mqh', INIT_FILE, init, 'probe=adopt'],
    ['Biotak/EventHandlers_Calc.mqh', CALC_FILE, calc, 'probe=handoff'],
  ]) {
    const i = indexOfLine(lines, tag);
    const line = i >= 0 ? lines[i] : '';
    const ok = i >= 0 && line.includes('Print(') && !line.includes('_LOG_GATE_');
    if (!ok) {
      failures.push(
        `${tag} proof line missing or gated (${file}): it must be a plain Print whose ` +
          'line carries both the tag and the call'
      );
    } else {
      console.log(`[PASS] ${tag} proof ungated (${file}:${i + 1})`);
    }
  }

  // -- 3. the switch branch KEEPS the family ----------------------------------
  // The reason CHAIN's own branch: the earlier `reason == REASON_CHARTCHANGE ||
  // REASON_PARAMETERS` block belongs to the TF-switch STAMP, not to the teardown
  // branch this check is about (`else if`, so the two cannot be confused).
  const chartChange = indexOfLine(calc, 'else if(reason == REASON_CHARTCHANGE)');
  const branch = chartChange >= 0 ? blockAfter(calc, chartChange) : null;
  const branchText = branch ? calc.slice(branch.from, branch.to + 1).join('\n') : '';
  const sworeNoDelete = ['DeleteAllIndicatorObjects(', 'ClearAllLevels(', 'ClearTopologyAdoptionStamp('];
  const foundForbidden = sworeNoDelete.filter((n) => branchText.includes(n));
  const handoffOk =
    branch !== null &&
    branchText.includes('SaveTopologyAdoptionStamp()') &&
    branchText.includes('probe=handoff') &&
    foundForbidden.length === 0;
  if (!handoffOk) {
    failures.push(
      'the REASON_CHARTCHANGE branch in Biotak/EventHandlers_Calc.mqh must SAVE the adoption ' +
        'stamp, print probe=handoff, and delete nothing' +
        (foundForbidden.length ? ` (found: ${foundForbidden.join(', ')})` : '')
    );
  } else {
    console.log(
      `[PASS] switch branch keeps the family: stamp saved, handoff printed, ` +
        `no delete (Biotak/EventHandlers_Calc.mqh:${branch.from + 1}-${branch.to + 1})`
    );
  }

  // -- 4. the family has exactly two declared delete paths ---------------------
  const calls = [];
  for (const f of fs.readdirSync(BIOTAK).filter((n) => n.endsWith('.mqh'))) {
    const lines = linesOf(path.join(BIOTAK, f));
    lines.forEach((l, i) => {
      if (/^\s*ClearAllLevels\s*\(/.test(stripComment(l))) {
        const window = lines.slice(Math.max(0, i - 60), i).join('\n');
        const guard = window.includes('if(shouldClearLevels)') || window.includes('!inpShowTHLevels');
        calls.push({ file: `Biotak/${f}`, line: i + 1, guard });
      }
    });
  }
  const unguarded = calls.filter((c) => !c.guard);
  if (calls.length === 0 || unguarded.length > 0) {
    failures.push(
      `ClearAllLevels must be called only on the two declared paths (the shouldClearLevels wipe ` +
        `and the levels-off branch); ${calls.length} call site(s), ${unguarded.length} unguarded` +
        (unguarded.length ? `: ${unguarded.map((c) => `${c.file}:${c.line}`).join(', ')}` : '')
    );
  } else {
    console.log(
      `[PASS] ClearAllLevels: ${calls.length} call site(s), each on a declared path ` +
        `(${calls.map((c) => `${c.file.split('/').pop()}:${c.line}`).join(', ')})`
    );
  }

  // -- 5. ONE writer of the adoption flag -------------------------------------
  const writers = [];
  for (const f of fs.readdirSync(BIOTAK).filter((n) => n.endsWith('.mqh'))) {
    const lines = linesOf(path.join(BIOTAK, f));
    lines.forEach((l, i) => {
      const code = stripComment(l);
      // A DECLARATION is not a verdict: `bool g_adoptPreviousTopology = false;`
      // states the type, and only assignments may state the answer.
      if (/\bg_adoptPreviousTopology\s*=/.test(code) &&
          !/^\s*(static\s+)?(bool|int|double|string)\s+g_adoptPreviousTopology\s*=/.test(code)) {
        writers.push({ file: `Biotak/${f}`, line: i + 1 });
      }
    });
  }
  const foreign = resolveBlock
    ? writers.filter(
        (w) => w.file !== 'Biotak/EventHandlers_Init.mqh' || w.line < resolveBlock.from + 1 || w.line > resolveBlock.to + 1
      )
    : writers;
  if (writers.length === 0 || foreign.length > 0) {
    failures.push(
      'g_adoptPreviousTopology must be written ONLY inside ResolveTopologyAdoption() ' +
        '(a second writer is a second verdict); offenders: ' +
        foreign.map((w) => `${w.file}:${w.line}`).join(', ')
    );
  } else {
    console.log(
      `[PASS] adoption flag: ${writers.length} writer(s), all inside ResolveTopologyAdoption()`
    );
  }

  // -- 6. the reinit wipe is still FENCED --------------------------------------
  // The one assignment that turned "we lost the handoff" into "delete ~900
  // objects" lives in EventHandlers_Tail and must stay behind the adoption test.
  const tailWipe = indexOfLine(tail, 'g_forceClearOnNextDraw = true');
  const tailWindow = tailWipe >= 0 ? tail.slice(Math.max(0, tailWipe - 3), tailWipe + 1).join('\n') : '';
  const fenceOk = tailWipe >= 0 && tailWindow.includes('!g_adoptPreviousTopology');
  if (!fenceOk) {
    failures.push(
      'the timeframe-invalidation wipe must stay fenced: ' +
        '`if(!g_adoptPreviousTopology) g_forceClearOnNextDraw = true;` (Biotak/EventHandlers_Tail.mqh)'
    );
  } else {
    console.log(
      `[PASS] reinit wipe fenced behind the adoption verdict ` +
        `(Biotak/EventHandlers_Tail.mqh:${tailWipe + 1})`
    );
  }

  console.log('');
  if (failures.length) {
    for (const f of failures) console.log(`[FAIL] ${f}`);
    console.log('');
    console.log('LEVEL CONTINUITY GATE FAILED');
    process.exit(1);
  }
  console.log('LEVEL CONTINUITY GATE PASSED');
  process.exit(0);
}

if (require.main === module) main();

module.exports = { ROOT };
