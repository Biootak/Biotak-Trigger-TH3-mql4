// skin_metrics_check.js — the plate skin's two owners must agree.
//
// WHY: the 9-slice's middle band is BAKED at one width (the generator) and CROPPED at
// another (the runtime). They are two files and two numbers, and after the audit scripts
// were deleted nothing tied them together — a drift means every plate wider than the bake
// silently draws a stretched/blank band. This check is that tie.
//
// Run: node tools/skin_metrics_check.js
import { readFileSync } from 'node:fs';
import path from 'node:path';

const gen = readFileSync('tools/gen-th3-icons.js', 'utf8');
const runtimeFile = 'Biotak/DrawStrip.mqh';
// The runtime is split (DrawStrip.mqh is a wrapper of DrawStrip_*.mqh), so read
// the unit the way the compiler sees it: follow #include "..." in place.
function readUnit(p, seen = new Set()) {
  const norm = path.normalize(p);
  if (seen.has(norm)) return '';
  seen.add(norm);
  let src;
  try { src = readFileSync(norm, 'utf8'); } catch { return ''; }
  const dir = path.dirname(norm);
  return src.split('\n').map((ln) => {
    const m = ln.match(/^\s*#include\s+"([^"]+)"/);
    if (!m) return ln;
    const cand = path.normalize(path.join(dir, m[1].replace(/\\/g, path.sep)));
    try { readFileSync(cand, 'utf8'); } catch { return ln; }
    return readUnit(cand, seen);
  }).join('\n');
}
const rt = readUnit(runtimeFile);

// The generator declares `const DS_M = 14, DS_R = 14;` and derives the rest
// (`const DS_CAP = DS_M + DS_R;`), so read the whole family and evaluate the sums.
function genConsts() {
  const seen = {};
  const re = /const\s+([A-Z_][A-Z0-9_]*(?:\s*=\s*[^,;]+)?(?:\s*,\s*[A-Z_][A-Z0-9_]*(?:\s*=\s*[^,;]+)?)*)\s*;/g;
  for (const decl of gen.matchAll(re)) {
    for (const part of decl[1].split(',')) {
      const [name, expr] = part.split('=').map((s) => s && s.trim());
      if (!name || !expr) continue;
      const sum = expr.split('+').reduce((acc, t) => {
        const term = t.trim();
        return acc + (/^\d+$/.test(term) ? Number(term) : seen[term] ?? NaN);
      }, 0);
      if (Number.isFinite(sum)) seen[name] = sum;
    }
  }
  return seen;
}
function define(name) {
  const m = rt.match(new RegExp(`#define\\s+${name}\\s+(\\d+)`));
  return m ? Number(m[1]) : null;
}

const G = genConsts();
const bake = {
  MIDW: G.DS_MIDW,
  CAP: G.DS_CAP,
  MARGIN: G.DS_M,
  MAXW: null,   // the widest plate is the RUNTIME's own ceiling (its comment names 660)
};
const live = {
  MIDW: define('DSTRIP_SKIN_MIDW'),
  CAP: define('DSTRIP_SKIN_CAP'),
  MARGIN: define('DSTRIP_SKIN_M'),
  MAXW: define('DSTRIP_SKIN_MAXW'),
};

const fails = [];
const line = (k) =>
  `  ${k.padEnd(7)} generator=${String(bake[k]).padStart(4)}  runtime=${String(live[k]).padStart(4)}`;

// 1. The numbers BOTH sides own must be identical (the bake's own metrics).
for (const k of ['MIDW', 'CAP', 'MARGIN']) {
  if (bake[k] === null || bake[k] === undefined) fails.push(`${k}: the generator no longer declares it`);
  else if (bake[k] !== live[k]) fails.push(`${k} drift: generator ${bake[k]} vs runtime ${live[k]}`);
}
// 2. The runtime ceiling must be a number the check can do arithmetic with.
if (!Number.isFinite(live.MAXW)) fails.push('DSTRIP_SKIN_MAXW is not a literal number any more');
// 3. A plate at the runtime's own maximum width must still fit inside the bake:
//    the middle band it draws is `w + 2*MARGIN - 2*CAP` wide (DrawStripSkinFitsFor).
const widestMid = live.MAXW + 2 * live.MARGIN - 2 * live.CAP;
if (widestMid > live.MIDW) {
  fails.push(
    `no fit at DSTRIP_SKIN_MAXW: a ${live.MAXW}px plate draws a ${widestMid}px middle band ` +
      `against a ${live.MIDW}px bake — the widest plate would fall back to the flat rect`,
  );
}

console.log('skin metrics (generator vs runtime)');
for (const k of ['MIDW', 'CAP', 'MARGIN', 'MAXW']) console.log(line(k));
console.log(`  widest middle band = MAXW + 2*MARGIN - 2*CAP = ${widestMid} <= MIDW ${live.MIDW}`);

if (fails.length) {
  console.log('\nFAIL');
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
console.log('\nPASS — the bake and the crop agree, and the widest plate still fits');
