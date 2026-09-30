#!/usr/bin/env node
// BUILD HASH — ONE source identity for every stamp the panel and the log print.
//
// WHY THIS EXISTS. The stamps that answer "which build is on this chart?" were
// hand-typed strings: `TH3_BUILD_TAG "T2"` (ProjectConstants) and
// `INDICATOR_BUILD_TAG "D4m-native 2026-09-20"` (BuildConfig). Neither changes
// when the code changes, so every build of 2026-09-29 printed the SAME line —
// measured: a chart running an ex4 whose strip painted the retired chart-background
// tone (0xFEFDBF21) and a freshly built one printed identical `[BUILD] TH3 T2`
// lines and identical `Build Tag:` banners. Eight days were spent comparing two
// numbers that were never about the code.
//
// The fix is to print a fact the SOURCE owns: a content hash over the bytes of
// every file the compiling unit actually contains — the two entries, every
// `#include` they reach transitively, and every raster those units `#resource`
// (the BMPs are baked into the ex4, so an icon change is a build change too).
//
//   same tree    -> same hash -> same stamp (a re-compile is not a new build)
//   one edit     -> new hash  -> a different stamp (any edit is a new build)
//
// The hash is written to Biotak/BuildHash.mqh, which BuildConfig/ProjectConstants
// include; the panel chip, the `[BUILD]` line and the init banner all read it.
// The build also drops the same hash into each terminal's MQL4\Files\th3-src.txt,
// so the running instance can compare the file against the value baked inside it
// and say `match=yes|NO` — a stale ex4 now names itself instead of looking fresh.
//
// USAGE:  node tools/gen-build-hash.js           -> rewrite Biotak/BuildHash.mqh
//         node tools/gen-build-hash.js --check   -> exit 1 if it is out of date
// Stdout (first line): hash=<16hex> short=<8hex> files=<n>
//
// The file walker is NOT re-implemented here: tools/check-resources.js owns
// "what files one unit is", and this reads it, so the hash can never cover a
// different file set than the gate checks.

'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const { unitOf, ROOT, DEFAULT_ENTRIES } = require(path.join(__dirname, 'check-resources.js'));

const OUT = path.join(ROOT, 'Biotak', 'BuildHash.mqh');
const SELF = OUT; // the generated file is not part of its own input

// Same declaration the resource gate reads: `#resource "\Files\Icons\a.bmp"`.
const RE_RESOURCE = /^\s*#resource\s+"\\+Files\\+Icons\\+([^"]+)"/gim;

function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function relOf(abs) {
  return path.relative(ROOT, abs).split(path.sep).join('/');
}

// The hashed set: the union of the entries' own units + the rasters they embed.
function sourceSet() {
  const files = new Set();
  for (const entry of DEFAULT_ENTRIES) {
    const entryAbs = path.join(ROOT, entry);
    if (!fs.existsSync(entryAbs)) {
      console.error(`[FAIL] entry not found: ${entry}`);
      process.exit(1);
    }
    const seen = new Set([entryAbs]);
    const unit = unitOf(entryAbs, seen);
    for (const f of unit.files) {
      const abs = path.resolve(f);
      if (abs === path.resolve(SELF)) continue; // not part of its own input
      files.add(abs);
      const src = fs.readFileSync(abs, 'utf8');
      RE_RESOURCE.lastIndex = 0;
      let m;
      while ((m = RE_RESOURCE.exec(src)) !== null) {
        const bmp = path.join(ROOT, 'Files', 'Icons', m[1]);
        if (fs.existsSync(bmp)) files.add(path.resolve(bmp));
      }
    }
  }
  return [...files].sort((a, b) => relOf(a) < relOf(b) ? -1 : 1);
}

function compute() {
  const files = sourceSet();
  const h = crypto.createHash('sha256');
  for (const f of files) {
    h.update(relOf(f) + '\n' + sha256(fs.readFileSync(f)) + '\n');
  }
  const hash = h.digest('hex').slice(0, 16);
  return { hash, short: hash.slice(0, 8), count: files.length };
}

function render({ hash, short, count }) {
  const EOL = '\r\n';
  return [
    '//+------------------------------------------------------------------+',
    '//| BuildHash.mqh — GENERATED FILE. DO NOT EDIT.                      |',
    '//|                                                                   |',
    '//| Owner: tools/gen-build-hash.js, run by compile-th3.ps1.           |',
    '//|                                                                   |',
    '//| TH3_SRC_HASH is a SHA-256 (16 hex chars) over the bytes of every  |',
    '//| file these entries compile: the two .mq4 entries, every .mqh they |',
    '//| #include transitively, and every raster they #resource. It is the |',
    '//| ONLY build identity the panel and the log print — a hand-typed tag |',
    '//| cannot change when the code changes, and that is how a stale ex4   |',
    '//| printed the same line as a fresh one for eight days.              |',
    '//|                                                                   |',
    '//| same tree -> same hash ; any edit -> a different hash              |',
    '//|                                                                   |',
    `//| files=${count} hash=${hash}`,
    '//+------------------------------------------------------------------+',
    '#ifndef TH3_BUILD_HASH_MQH',
    '#define TH3_BUILD_HASH_MQH',
    '',
    `#define TH3_SRC_HASH   "${hash}"   // full identity, printed in the log`,
    `#define TH3_SRC_SHORT  "${short}"           // the 8-char stamp the panel chip shows`,
    `#define TH3_SRC_FILES  ${count}                // files covered by the hash`,
    '',
    '#endif // TH3_BUILD_HASH_MQH',
    '',
  ].join(EOL);
}

const { hash, short, count } = compute();
const want = render({ hash, short, count });
const check = process.argv.includes('--check');

if (check) {
  const have = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
  if (have !== want) {
    console.error('[FAIL] Biotak/BuildHash.mqh is not the hash of this tree.');
    console.error(`       on disk: ${(have.match(/hash=([0-9a-f]{16})/) || [])[1] || 'none'}`);
    console.error(`       tree:    ${hash}`);
    console.error('       Run: node tools/gen-build-hash.js');
    process.exit(1);
  }
} else {
  fs.writeFileSync(OUT, want);
}

console.log(`hash=${hash} short=${short} files=${count}`);
