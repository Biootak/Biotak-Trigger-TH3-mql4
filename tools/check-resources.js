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

// ── P-DRAW-106 — THE SIZE TABLE, AGAINST THE FILES ────────────────────────────
// `DrawStripFaceZ` centres a raster in its cell with `x + (w - DrawStripResW(res))/2`
// (Biotak/DrawStrip_GearB.mqh:236), so a raster the table does not carry — or
// carries at the wrong canvas — is painted OFF ITS CELL, silently: the size is a
// number inside a chain of string tests, so a green compile names nothing.
// MEASURED 2026-10-01: `pnl_btn_ghost.bmp` (88x44) had no entry and shipped 44px
// right and 22px below its own foot button (below the plate, off its label, all
// three buttons), `bk_w`/`bk_style`/`bk_ray` answered 16 for 24x24 canvases, and
// `gl_pin*`/`gl_textsize*`/`gl_layers*` answered 15 for 26x26 ones. This walks the
// table OUT OF THE MQL (no second copy of the numbers) and every raster the
// DrawStrip files name, and refuses any name whose file size the table does not
// answer.
const BIOTAK_DIR = path.join(ROOT, 'Biotak');
const DRAWSTRIP_TABLE = path.join(BIOTAK_DIR, 'DrawStrip_Base.mqh');
// rasters PAINTED WITH THEIR OWN RECT: `DrawStripSkinBmp` writes XDISTANCE,
// YDISTANCE, XSIZE and YSIZE itself (the strip's `ds_*` nine-slice and the panel's
// `pnl_card*` bakes), so the table never sizes them and owes them no entry.
const RECT_PAINTED = ['ds_', 'pnl_card'];

// STATEMENTS, not lines: a rule may wrap (`if(StringFind(res, "gl_pin") >= 0 ||`
// on one line, `... return 26;` on the next). That is legal MQL, so the reader
// splits on `;` and keeps a buffer open across lines — a line-based reader would
// attribute the FIRST return to both prefixes and then trust a wrong number.
// P-DRAW-108 (2026-10-01): AND A COMMENT IS NOT CODE. The reader used to keep the
// `//` tail of every line, so a statement written AFTER a comment on the same line
// was read as LIVE while the MQL compiler read it as text — the `pnl_cntchip` W rule
// sat behind `pnl_secdot`'s own `// P-DRAW-71: ...`, so the table answered
// `DrawStripIconPx`'s 0 for a 28x20 canvas (its count pill painted 14px right and
// 10px down of its own rect) and this gate answered 28 and passed it. So the
// comment is dropped before the statement is read.
function sizeRules(src) {
  const out = { W: [], H: [], I: [] };
  let cur = null;
  let buf = '';
  for (const raw of src.split(/\r?\n/)) {
    const cm = raw.indexOf('//');
    const line = cm >= 0 ? raw.slice(0, cm) : raw;
    // the DEFINITION, never the call: `int DrawStripResW(...)` starts a row, and
    // the `{` of this project's style is on the line below it.
    if (/^\s*int\s+DrawStripResW\s*\(/.test(line)) { cur = 'W'; buf = ''; continue; }
    if (/^\s*int\s+DrawStripResH\s*\(/.test(line)) { cur = 'H'; buf = ''; continue; }
    if (/^\s*int\s+DrawStripIconPx\s*\(/.test(line)) { cur = 'I'; buf = ''; continue; }
    if (!cur) continue;
    buf += ' ' + line;
    while (buf.includes(';')) {
      const stmt = buf.slice(0, buf.indexOf(';'));
      buf = buf.slice(buf.indexOf(';') + 1);
      const pfx = [...stmt.matchAll(/StringFind\(res,\s*"([^"]+)"/g)].map((m) => m[1]);
      const v = Number((stmt.match(/\breturn\s+(\d+)/) || [])[1]);
      if (pfx.length && !Number.isNaN(v)) out[cur].push({ pfx, v });
    }
  }
  return out;
}

// the table's answer for one name: the FIRST rule whose prefix it carries; the
// `DrawStripIconPx` chain is the fallback, exactly as the MQL reads it.
function tableSize(rules, name, dim) {
  for (const r of dim === 'W' ? rules.W : rules.H) {
    if (r.pfx.some((p) => name.includes(p))) return r.v;
  }
  for (const r of rules.I) {
    if (r.pfx.some((p) => name.includes(p))) return r.v;
  }
  return 0;
}

// BITMAPINFOHEADER: width u32 at 18, height i32 at 22 (negative = top-down).
function bmpCanvas(file) {
  const b = fs.readFileSync(file);
  return { w: b.readUInt32LE(18), h: Math.abs(b.readInt32LE(22)) };
}

function stripSizeDrift() {
  const rules = sizeRules(fs.readFileSync(DRAWSTRIP_TABLE, 'utf8'));
  const names = new Set();
  for (const f of fs.readdirSync(BIOTAK_DIR)) {
    if (!/^DrawStrip.*\.mqh$/.test(f)) continue;
    const s = fs.readFileSync(path.join(BIOTAK_DIR, f), 'utf8');
    for (const m of s.matchAll(/Files\\+Icons\\+([A-Za-z0-9_.+-]+\.bmp)/g)) names.add(m[1]);
  }
  const bad = [];
  for (const n of names) {
    if (RECT_PAINTED.some((p) => n.startsWith(p))) continue;
    const file = path.join(ICONS, n);
    if (!fs.existsSync(file)) continue;   // the declared/on-disk check owns this
    const { w, h } = bmpCanvas(file);
    const tw = tableSize(rules, n, 'W');
    const th = tableSize(rules, n, 'H');
    if (tw !== w || th !== h) bad.push({ n, w, h, tw, th });
  }
  return { checked: names.size, bad };
}

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

  const drift = stripSizeDrift();
  if (drift.bad.length === 0) {
    console.log(
      `[PASS] raster size table - ${drift.checked} raster(s) the DrawStrip names, ` +
        `each answered at its file's own canvas`
    );
  } else {
    failed = true;
    console.log(`[FAIL] raster size table - DrawStripFaceZ would place these off their cell:`);
    for (const b of drift.bad) {
      console.log(`         ${b.n}  file ${b.w}x${b.h}  table ${b.tw}x${b.th}`);
    }
  }

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
