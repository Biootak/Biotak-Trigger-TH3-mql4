// Dev mode. `npm run dev`  (add --once for a single pass and exit)
//
// Pine's only compiler is the Pine Editor on TradingView, so "dev mode" here means:
// keep dist/*.pine fresh, and put every offline verdict on one line as you type.
// The editor extensions (see .vscode/extensions.json) run the same validator.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ROOT, SRC, BUILD } from './lib/pine-build.js';

const ONCE = process.argv.includes('--once');
const WATCH_DIRS = [SRC, path.join(ROOT, 'tests', 'fixtures'), path.join(ROOT, 'tools')];

const run = (script, args = []) =>
  spawnSync(process.execPath, [path.join(ROOT, 'tools', script), ...args], { stdio: 'inherit', cwd: ROOT });

let pass = 0;
let running = false;
let pending = false;

function cycle(why) {
  if (running) { pending = true; return; }
  running = true;
  pass++;
  const t0 = Date.now();
  process.stdout.write(`\n--- pass ${pass} (${why}) ${new Date().toISOString().slice(11, 19)} ---\n`);

  const steps = [
    ['build.js'],
    ['check-structure.js'],
    ['check-pine-limits.js'],
    ['pine-validate.js'],
  ];
  let ok = true;
  for (const [script] of steps) {
    const r = run(script);
    if (r.status !== 0) { ok = false; break; }
  }
  const ms = Date.now() - t0;
  console.log(ok ? `\n[dev] pass ${pass} GREEN in ${ms} ms - dist/ is current` : `\n[dev] pass ${pass} RED in ${ms} ms`);
  running = false;
  if (pending) { pending = false; cycle('queued change'); }
}

cycle('startup');
if (ONCE) process.exit(0);

let timer = null;
for (const dir of WATCH_DIRS) {
  if (!fs.existsSync(dir)) continue;
  fs.watch(dir, { recursive: true }, (_event, name) => {
    if (name && !/\.(pine|json)$/.test(String(name))) return;
    clearTimeout(timer);
    timer = setTimeout(() => cycle(`changed: ${name}`), 120);
  });
}
console.log(`\n[dev] watching ${WATCH_DIRS.map((d) => path.relative(ROOT, d) || '.').join(', ')} - Ctrl+C to stop`);
