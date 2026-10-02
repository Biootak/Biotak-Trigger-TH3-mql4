#!/usr/bin/env node
// ICON DEPLOY GATE — the raster the SOURCE tree holds is the raster the CHART
// must paint.
//
// WHY THIS EXISTS. P-UI-131 (2026-10-02). `#resource "\Files\Icons\x.bmp"` is
// resolved by MetaEditor against the COMPILING UNIT's own tree, so a green
// compile proves the repo's art is embedded — and `tools/check-resources.js`
// walks that same repo tree, so its size table is right too. But every painter
// writes `OBJPROP_BMPFILE = "::Files\Icons\x.bmp"`, and `::Files\` is the
// TERMINAL's `MQL4\Files`, loaded at PAINT time, per chart, from whatever is
// there. Two trees, two readers, one of them the pixels.
// `compile-th3.ps1` had this exactly wrong and said so: P-DRAFT-01 retired
// `Sync-IconsToTerminal` after measuring it "INERT" — which was true, for the
// compile, and false for the screen. Nothing delivered the tree, and nothing
// compared the two, so the whole P-UI-132 / P-DRAW-106 re-bake (the three gl_*
// glyph families at 26, and bk_w / bk_style / bk_ray at 24) was correct in the
// repo and INVISIBLE on the chart.
// MEASURED 2026-10-02, this repo against the live AMarkets terminal: 22 of 280
// canvases disagreed — gl_pin/gl_layers/gl_textsize shipping 15x15 where the
// source holds 26x26 (the pin and the layers glyph drew a third smaller than
// every neighbour), and bk_w*/bk_style*/bk_ray* shipping 16x16 where the source
// holds 24x24. Both sizes are right in the code's own tables; the screen was the
// only thing reading the wrong number.
//
// WHAT IT CHECKS. For every name in `tools/icon-manifest.txt` (the generator's
// exact runtime-reachable set — not a glob, not the whole directory), the canvas
// AND the bytes must match between the repo tree and every terminal tree that
// hosts this project. A missing terminal file counts as a mismatch: the terminal
// keeps serving whatever it cached until it is overwritten.
//
// USAGE:  node tools/check-icon-deploy.js
// Exit 0 = every hosting terminal serves the source tree's bytes, 1 = drift.

'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'Files', 'Icons');
const MANIFEST = path.join(__dirname, 'icon-manifest.txt');

// BMP: bfOffBits at 10, biWidth/biHeight (signed) at 18.
function canvas(p) {
  const fd = fs.openSync(p, 'r');
  try {
    const h = Buffer.alloc(40);
    fs.readSync(fd, h, 0, 40, 0);
    if (h.toString('ascii', 0, 2) !== 'BM') return null;
    return { w: h.readInt32LE(18), h: h.readInt32LE(22) };
  } finally {
    fs.closeSync(fd);
  }
}
function sha(p) {
  return crypto.createHash('sha1').update(fs.readFileSync(p)).digest('hex');
}

// Every terminal data folder that already serves at least one of our rasters is
// a host: that is the same rule compile-th3.ps1's Get-TerminalMql4DirsForProject
// uses (a terminal that hosts nothing of ours is none of our business).
function hostTrees(names) {
  const base = path.join(os.homedir(), 'AppData', 'Roaming', 'MetaQuotes', 'Terminal');
  const out = [];
  if (!fs.existsSync(base)) return out;
  for (const d of fs.readdirSync(base)) {
    const icons = path.join(base, d, 'MQL4', 'Files', 'Icons');
    if (!fs.existsSync(icons)) continue;
    let served = 0;
    for (const n of names) if (fs.existsSync(path.join(icons, n))) served++;
    if (served > 0) out.push({ data: d, icons, served });
  }
  return out;
}

function main() {
  if (!fs.existsSync(MANIFEST)) {
    console.error('[FAIL] tools/icon-manifest.txt is missing — run `node tools/gen-th3-icons.js`');
    return 1;
  }
  const names = fs.readFileSync(MANIFEST, 'utf8').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);

  const missingSrc = names.filter((n) => !fs.existsSync(path.join(SRC, n)));
  if (missingSrc.length) {
    console.error(`[FAIL] ${missingSrc.length} manifest raster(s) absent from the source tree — ${SRC}`);
    for (const n of missingSrc.slice(0, 10)) console.error('    ' + n);
    return 1;
  }

  const hosts = hostTrees(names);
  if (!hosts.length) {
    console.log('[SKIP] icon deploy - no hosting terminal found under ' + path.dirname(SRC, 2));
    return 0;
  }

  let bad = 0;
  for (const h of hosts) {
    const drift = [];
    for (const n of names) {
      const src = path.join(SRC, n);
      const dst = path.join(h.icons, n);
      if (!fs.existsSync(dst)) { drift.push({ n, why: 'not delivered' }); continue; }
      const a = canvas(src), b = canvas(dst);
      if (!a || !b) { drift.push({ n, why: 'not a BMP' }); continue; }
      if (a.w !== b.w || a.h !== b.h) {
        drift.push({ n, why: `canvas ${b.w}x${b.h} in terminal, ${a.w}x${a.h} in source` });
      } else if (sha(src) !== sha(dst)) {
        drift.push({ n, why: `same ${a.w}x${a.h} canvas, different bytes` });
      }
    }
    console.log(`  terminal ${h.data}: ${names.length} manifest raster(s), ${drift.length} drifted`);
    if (drift.length) {
      bad += drift.length;
      for (const d of drift) console.log(`    [DRIFT] ${d.n}: ${d.why}`);
    }
  }

  if (bad > 0) {
    console.error('[FAIL] icon deploy gate — the chart reads the terminal tree, the compile and every other gate read this one.');
    console.error('       Re-deliver with: powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all -Gates full');
    return 1;
  }
  console.log(`[PASS] icon deploy - ${hosts.length} hosting terminal(s) serve the source tree's ${names.length} raster(s)`);
  return 0;
}

process.exit(main());