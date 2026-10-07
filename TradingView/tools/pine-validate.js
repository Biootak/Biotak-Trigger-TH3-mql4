// The compile gate. Pine has no offline compiler, so this runs the closest thing
// that exists: `pinescript-v6-validator`, the same engine behind the Pine Script v6
// IDE Tools extension, so the editor and this gate can never disagree about a file.
//
//   node tools/pine-validate.js [file.pine ...]

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { ROOT, DIST } from './lib/pine-build.js';

const require = createRequire(import.meta.url);
let validatePineScript;
try {
  ({ validatePineScript } = require('pinescript-v6-validator'));
} catch {
  console.error('[SKIP] validator gate - pinescript-v6-validator is not installed. Run: npm install');
  process.exit(2);
}
if (typeof validatePineScript !== 'function') {
  console.error('[SKIP] validator gate - the installed pinescript-v6-validator exposes no validatePineScript()');
  process.exit(2);
}

const targets = process.argv.slice(2).length
  ? process.argv.slice(2)
  : fs.existsSync(DIST)
    ? fs.readdirSync(DIST).filter((f) => f.endsWith('.pine')).sort().map((f) => path.join(DIST, f))
    : [];

if (targets.length === 0) {
  console.error('[FAIL] validator gate - no .pine file to check. Run: npm run build');
  process.exit(1);
}

let errors = 0;
let warnings = 0;

for (const file of targets) {
  const src = fs.readFileSync(file, 'utf8').replace(/\r\n?/g, '\n');
  const diags = validatePineScript(src) ?? [];
  const rel = path.relative(ROOT, file) || file;
  const errs = diags.filter((d) => d.severity === 0);
  const warns = diags.filter((d) => d.severity !== 0);
  errors += errs.length;
  warnings += warns.length;

  if (diags.length === 0) {
    console.log(`[PASS] ${rel} - ${src.split('\n').length} lines, no diagnostic`);
    continue;
  }
  for (const d of errs) {
    console.error(`[FAIL] ${rel}:${d.line}:${d.column} ${d.message}`);
  }
  for (const d of warns) {
    console.warn(`[WARN] ${rel}:${d.line}:${d.column} ${d.message}`);
  }
}

if (errors) {
  console.error(`\nVALIDATE FAILED - ${errors} error(s), ${warnings} warning(s)`);
  process.exit(1);
}
console.log(`\n[PASS] validate gate - ${targets.length} file(s), 0 errors, ${warnings} warning(s)`);
