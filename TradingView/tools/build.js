// Biotak Trigger TH3 - TradingView build. ONE way to build, and it prints the proof.
//
//   npm run build
//
// Blocks on the first structural fault rather than writing a half-assembled file:
// a dist/*.pine that a reader cannot trust is worse than no dist at all.

import path from 'node:path';
import { ROOT, listEntries, resolveEntry, render, writeDist } from './lib/pine-build.js';

const t0 = Date.now();
let failures = 0;
const fail = (msg) => { failures++; console.error(`[FAIL] ${msg}`); };

console.log(`[build] Biotak Trigger TH3 / TradingView   node ${process.version}`);

const entries = listEntries();
if (entries.length === 0) fail('src/entry/ holds no entry - nothing to build');

for (const rel of entries) {
  const { entry, modules, cycles, missing } = resolveEntry(rel);
  const tag = entry.entry ?? '(no //@entry)';

  for (const c of cycles) fail(`src/${rel}: include cycle: ${c}`);
  for (const m of missing) fail(`src/${rel}: //@includes a file that does not exist: ${m}`);
  if (!entry.entry) fail(`src/${rel}: missing //@entry`);
  if (!entry.output) fail(`src/${rel}: missing //@output`);
  if (!entry.owner) fail(`src/${rel}: missing //@owner`);
  if (entry.body.some((l) => l.trim() !== '')) {
    fail(`src/${rel}: the entry carries ${entry.body.filter((l) => l.trim() !== '').length} line(s) of logic - entries stay thin, logic lives in src/*.pine`);
  }
  if (cycles.length || missing.length || !entry.output) continue;

  let built;
  try {
    built = render({ entry, modules });
  } catch (err) {
    fail(err.message);
    continue;
  }

  const written = writeDist(entry.output, built.text);
  const laneCount = entry.declare.find((l) => l.trim().startsWith('indicator(')) ? 'indicator' : '?';
  const delta = written.before ? written.after.size - written.before.bytes : null;

  console.log(`[build] src/${rel}  ->  ${written.rel}`);
  console.log(`        ${laneCount}   modules ${modules.length}   lines ${built.text.split('\n').length}   sha256 ${built.hash}`);
  console.log(`        was ${written.before ? `${written.before.bytes} bytes` : '(absent)'}   now ${written.after.size} bytes${delta === null ? '' : `   d=${delta > 0 ? '+' : ''}${delta}`}${written.rewritten ? '   rewritten' : '   UNCHANGED (same bytes)'}`);
  console.log(`        chain: ${modules.map((m) => m.id).join(' -> ')}`);
  if (written.before && !written.rewritten) {
    console.log('        NOTE: same bytes as the previous build - a green build that rewrote nothing changed nothing.');
  }
}

if (failures) {
  console.error(`\nBUILD FAILED - ${failures} fault(s)`);
  process.exit(1);
}
console.log(`\nBUILD OK - ${entries.length} entr${entries.length === 1 ? 'y' : 'ies'} in ${Date.now() - t0} ms`);
console.log('NEXT: paste dist/*.pine into the TradingView Pine Editor (Pine has no offline compiler).');
