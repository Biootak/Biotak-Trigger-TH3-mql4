#!/usr/bin/env node
// RESOURCE GATE — every raster a unit PAINTS is declared in that unit, and every
// declared raster exists on disk.
//
// WHY THIS EXISTS. On MT4 `#resource` binds per COMPILING UNIT, and a
// `OBJPROP_BMPFILE` path of `::Files\Icons\x.bmp` resolves ONLY for a raster the
// unit declared. A missing declaration is a SILENT no-op: the object is created,
// the property is written, and MT4 paints NOTHING — while the compile stays
// green, because the name is a string, not a symbol. That exact class of defect
// shipped a settings panel whose plate, foot skin and two glyphs never drew
// (2026-09-29), and the compiler could not name it.
//
// It is also the check that must run per UNIT, not per file: DrawStrip.mqh and
// BiotakPanels.mqh are the same unit when both are included by one entry, so a
// declaration in either satisfies a paint in the other. That is a fact about the
// compiler, not a licence to ignore it — a move of one include line between the
// entries is exactly how the defect returns.
//
// USAGE:  node tools/check-resources.js [entry.mq4 ...]
//         (no argument = both product entries)
// Exit 0 = clean, 1 = a painted raster is undeclared or a declared one is gone.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ICONS = path.join(ROOT, 'Files', 'Icons');
const DEFAULT_ENTRIES = [
  'Biotak Trigger TH3.mq4',
  'Biotak Trigger TH3 Lite.mq4',
];

// --- the unit: an entry plus every file it #include's, transitively ------------
function unitOf(entryAbs, seen) {
  const dir = path.dirname(entryAbs);
  let src;
  try {
    src = fs.readFileSync(entryAbs, 'utf8');
  } catch {
    return { src: '', files: [] };
  }
  const files = [entryAbs];
  const re = /^\s*#include\s+"([^"]+)"/gm;
  let m;
  while ((m = re.exec(src)) !== null) {
    let rel = m[1].replace(/\\/g, path.sep);
    let abs = path.resolve(dir, rel);
    if (!fs.existsSync(abs)) abs = path.resolve(ROOT, rel);
    if (!fs.existsSync(abs) || seen.has(abs)) continue;
    seen.add(abs);
    const sub = unitOf(abs, seen);
    files.push(abs, ...sub.files);
  }
  return { src, files };
}

// `#resource "\Files\Icons\a.bmp"`  — backslashes doubled in the source text.
const RE_RESOURCE = /^\s*#resource\s+"\\+Files\\+Icons\\+([^"]+)"/gim;
// the strings a painter actually writes into OBJPROP_BMPFILE.
const RE_PAINT = /Files\\+Icons\\+([A-Za-z0-9_.+-]+\.bmp)/g;

function audit(entryRel) {
  const entryAbs = path.join(ROOT, entryRel);
  if (!fs.existsSync(entryAbs)) {
    return { entry: entryRel, error: 'entry not found' };
  }
  const seen = new Set([entryAbs]);
  const unit = unitOf(entryAbs, seen);

  const declared = new Set();
  for (const f of unit.files) {
    const s = fs.readFileSync(f, 'utf8');
    RE_RESOURCE.lastIndex = 0;
    let m;
    while ((m = RE_RESOURCE.exec(s)) !== null) declared.add(m[1]);
  }

  const painted = new Map(); // name -> first file that names it
  for (const f of unit.files) {
    const s = fs.readFileSync(f, 'utf8');
    // A #resource line is a DECLARATION, not a paint — do not count it as one.
    const s2 = s.replace(/^\s*#resource[^\n]*$/gim, '');
    RE_PAINT.lastIndex = 0;
    let m;
    while ((m = RE_PAINT.exec(s2)) !== null) {
      if (!painted.has(m[1])) painted.set(m[1], path.relative(ROOT, f));
    }
  }

  const undeclared = [...painted.entries()].filter(([n]) => !declared.has(n));
  const missingOnDisk = [...declared].filter((n) => !fs.existsSync(path.join(ICONS, n)));

  return {
    entry: entryRel,
    unitFiles: unit.files.length,
    declared: declared.size,
    painted: painted.size,
    undeclared,
    missingOnDisk,
  };
}

function main() {
  const entries = process.argv.length > 2 ? process.argv.slice(2) : DEFAULT_ENTRIES;
  let failed = false;

  for (const e of entries) {
    const r = audit(e);
    if (r.error) {
      console.log(`[FAIL] ${e} - ${r.error}`);
      failed = true;
      continue;
    }
    const ok = r.undeclared.length === 0 && r.missingOnDisk.length === 0;
    console.log(
      `[${ok ? 'PASS' : 'FAIL'}] ${e} - unit ${r.unitFiles} file(s), ` +
        `${r.declared} declared, ${r.painted} painted`
    );
    for (const [n, f] of r.undeclared) {
      console.log(`         painted but NOT #resource'd: ${n}   (${f})`);
    }
    for (const n of r.missingOnDisk) {
      console.log(`         #resource'd but NOT on disk:  ${n}`);
    }
    if (!ok) failed = true;
  }

  console.log('');
  console.log(failed ? 'RESOURCE GATE FAILED' : 'RESOURCE GATE PASSED');
  process.exit(failed ? 1 : 0);
}

if (require.main === module) main();

// One owner of "what files one compiling unit is". tools/gen-build-hash.js reads
// the SAME walker, so the hash cannot cover a different set of files than the
// gate does — a second walker would be a second unit definition.
module.exports = { unitOf, audit, ROOT, ICONS, DEFAULT_ENTRIES };
