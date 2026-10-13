// skin_metrics_check.js — the plate skin's two owners must agree.
//
// WHY: the 9-slice's middle band is BAKED at one width (the generator) and CROPPED at
// another (the runtime). They are two files and two numbers, and after the audit scripts
// were deleted nothing tied them together — a drift means every plate wider than the bake
// silently draws a stretched/blank band. This check is that tie.
//
// Run: node tools/skin_metrics_check.js
import { readFileSync, readdirSync } from 'node:fs';
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

// The generator declares `const DS_M = 14;` / `let DS_R = 14;` and derives the rest
// (`let DS_CAP = DS_M + DS_R;`), so read the whole family and evaluate the sums.
//
// P-UI-149 (2026-10-13): `let` IS PART OF THE FAMILY. The reader matched `const`
// only, so when the generator moved `DS_CAP` to a `let` (gen-th3-icons.js:1791 —
// the board bakes a rounder plate and resets `DS_R` right after) the check stopped
// seeing the corner cap at all and reported "the generator no longer declares it".
// A rule whose reader cannot see its own constant is not a rule: the CAP half of
// "the bake and the crop agree" was silently ungated, and the failure read as a
// product defect rather than as a blind reader.
function genConsts() {
  const seen = {};
  const re = /(?:const|let)\s+([A-Z_][A-Z0-9_]*(?:\s*=\s*[^,;]+)?(?:\s*,\s*[A-Z_][A-Z0-9_]*(?:\s*=\s*[^,;]+)?)*)\s*;/g;
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

// Every `#define NAME value` in a source string, with the trailing comment cut.
//
// P-UI-149 (2026-10-13) — NO `$` ANCHOR, AND THAT IS THE WHOLE POINT. Every file in
// this tree is CRLF, and in JavaScript `.` matches neither `\n` NOR `\r` while `$`
// (without `m`) refuses to match in front of a trailing `\r`. So `/...(.+)$/` on a
// CRLF line matches NOTHING at all — the reader comes back empty, the gate reports
// "the generator no longer declares it", and the failure reads as a product defect
// when it is a blind regex. Capturing `[^\r\n]+` reaches the end of the line on both
// line endings. (The pre-existing `(\d+)` reads below never had `$`, which is why
// they were immune.)
function rawDefines(src) {
  const map = {};
  for (const line of src.split('\n')) {
    const m = line.match(/^[ \t]*#define[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+([^\r\n]+)/);
    if (!m) continue;
    const val = m[2].split('//')[0].trim();
    if (val) map[m[1]] = val;
  }
  return map;
}

const RT_DEFS = rawDefines(rt);

// P-UI-149 (2026-10-13): THE RUNTIME'S METRICS ARE ALIASES, AND THE ALIAS'S OWNER
// IS NOT IN THE STRIP'S UNIT. `DrawStrip_Head.mqh:500` reads
//   `#define DSTRIP_SKIN_M  PNL_MARGIN  // P-DRAW-116: the card bake's own fringe`
// and `PNL_MARGIN` lives in `CardMetrics.mqh`, which reaches the strip only through
// `BiotakPanels_State.mqh` — i.e. NOT through `DrawStrip.mqh`, whose includes are
// the `DrawStrip_*.mqh` family alone. The old reader wanted a bare literal, got
// nothing, and reported "MARGIN drift: generator 14 vs runtime null" — a mismatch
// that does not exist (PNL_MARGIN IS 14, CardMetrics.mqh:28). Resolving the chain
// is the honest answer; the two sides really are one number, and the strip aliasing
// the cards' bake is exactly what P-DRAW-116 intended.
let FALLBACK_DEFS = null;
function fallbackDefines() {
  if (FALLBACK_DEFS) return FALLBACK_DEFS;
  const all = {};
  const walk = (dir) => {
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.mqh$/i.test(e.name)) {
        try { Object.assign(all, rawDefines(readFileSync(p, 'utf8'))); } catch { /* unreadable: skipped */ }
      }
    }
  };
  walk('Biotak');
  FALLBACK_DEFS = all;
  return FALLBACK_DEFS;
}

// Resolve `NAME` to a number: a literal, or the alias chain it stands on.
function define(name, seen = new Set()) {
  if (seen.has(name)) return null;
  seen.add(name);
  const raw = RT_DEFS[name] ?? fallbackDefines()[name];
  if (raw === undefined) return null;
  if (/^\d+$/.test(raw)) return Number(raw);
  if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(raw)) return define(raw, seen);   // the alias chain
  // a small sum of literals and/or aliases, e.g. `(A + B)` or `A + B`
  const parts = raw.replace(/[()]/g, '').split('+').map((t) => t.trim());
  let total = 0;
  for (const p of parts) {
    if (/^\d+$/.test(p)) { total += Number(p); continue; }
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(p)) {
      const v = define(p, seen);
      if (v === null) return null;
      total += v;
      continue;
    }
    return null;
  }
  return total;
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
