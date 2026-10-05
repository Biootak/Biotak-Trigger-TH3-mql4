#!/usr/bin/env node
// th3-dataset-sync.js — P-TH3-REC-06: move the recorder's samples out of the
// terminal's data folder and into the repo, where they are reviewable,
// diffable, and survive a reinstall.
//
// WHY THIS IS A SCRIPT AND NOT INDICATOR CODE (P-TH3-REC-06, and the reason
// is in the MQL4 docs, docs.mql4.com/common/webrequest): an MQL4 program
// cannot write outside its own data folder. `FileOpen` is sandboxed to
// `<terminal data>\MQL4\Files`, so `Samples/` in the repo is simply not
// writable from inside MT4. The recorder therefore writes once, in the one
// place it can, and this moves the result. (The same doc is why a direct
// cloud upload from the indicator is impossible: `WebRequest` returns error
// 4060 "Function is not allowed for call" from an indicator, because
// indicators share one thread across every chart of a symbol.)
//
// It COPIES, it never moves and never deletes: MT4's copy is the running
// system's own record and is left exactly as the terminal wrote it.
//
//   node tools/th3-dataset-sync.js            # copy anything new, report
//   node tools/th3-dataset-sync.js --list     # what is there, no writes
//   node tools/th3-dataset-sync.js --dest D   # write somewhere else
//
// The images ARE tracked (P-TH3-REC-06: a rung price is a claim until it is
// read off the picture), so this reports the running total against GitHub's
// 1 GB recommended ceiling and says so plainly rather than filling the history
// in silence: 56 KB a shot against a 100-sample cap is 5.5 MB, and this repo
// is 22 MB today. Above the budget the tool still copies — the trader decides —
// but it says the number out loud.
//
// P-TH3-REC-07: the shots are COMPRESSED, and the way that works is measured,
// not assumed. Three candidates were tried on a real capture
// (Sample_020, 1816x828, 56.9 KB):
//
//   re-deflate the PNG (levels 9/6/3)  -> 68.9 / 70.1 / 73.5 KB  = BIGGER
//   WebP q95/90/85/80                  -> 123/103/89/79 KB      = BIGGER, and
//                                        max per-pixel deviation 159-169, i.e.
//                                        lossy AND larger
//   indexed PNG, adaptive 256-colour  -> 34.4 KB, max deviation 0
//
// The reason is in the picture: the capture holds EXACTLY 256 distinct colours
// (a flat-shaded chart), which is what deflate already squeezes well — so
// lossy codecs pay for their own transforms on top and lose. The one lever
// that wins is an indexed palette, and at 256 colours it is LOSSLESS: the
// round-trip measured a maximum per-pixel deviation of ZERO, so a rung price
// read off the compressed image is the same rung price. Anything that DID
// change pixels is refused below, because these images are the evidence the
// formula is read against.
//
// Exit 0 on a clean run, 1 on any failure, so a build can gate on it.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DEST = path.join(ROOT, 'Samples', 'TH3_Dataset');
const PROFILE = process.env.USERPROFILE || process.env.HOME || '';
const TERMINALS = path.join(
  PROFILE, 'AppData', 'Roaming', 'MetaQuotes', 'Terminal');

const ARTIFACTS = [
  { from: 'Screenshots', ext: ['.png'] },
  { from: 'Logs', ext: ['.txt'] },
  { from: '.', ext: ['.csv'] },          // Master_Dataset.csv at the root
];

//+------------------------------------------------------------------+
//| P-TH3-REC-07 — PALETTE COMPRESSION, PROVEN LOSSLESS OR REFUSED.    |
//|                                                                     |
//| The encoder is optional on purpose: without Pillow the shots are       |
//| copied as-is and the run still succeeds, because a missing optimiser  |
//| must never cost us a sample. WITH it, a shot is re-encoded as an       |
//| indexed PNG and then VERIFIED: the tool compares the re-encoded pixels |
//| against the original and throws the compressed file away if a single  |
//| pixel moved. So "compressed without loss" is a checked claim, not a    |
//| hope — which matters, because these images are the evidence the step   |
//| formula is read against and a shifted pixel is a shifted answer.      |
//+------------------------------------------------------------------+
const COMPRESS_SCRIPT = `
import sys
from PIL import Image
import numpy as np, os
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
a0 = np.array(im).astype(int)
im.convert('P', palette=Image.ADAPTIVE, colors=256).save(dst, 'PNG', optimize=True)
a1 = np.array(Image.open(dst).convert('RGB')).astype(int)
d = int(np.abs(a1 - a0).max())
print(('OK' if d == 0 else 'LOSSY') + ' ' + str(os.path.getsize(dst)))
`;

/**
 * Re-encode `target` to an indexed PNG in place, but only if the round trip is
 * bit-identical. Returns the new byte size, or the original size when the
 * re-encode was refused (any pixel moved, no win, or no encoder available).
 */
function compressLossless(target) {
  const original = fs.statSync(target).size;
  const tmp = target + '.c.png';
  const py = process.env.PYTHON || 'python';
  let out;
  try {
    out = require('child_process').execFileSync(
      py, ['-c', COMPRESS_SCRIPT, target, tmp], { encoding: 'utf8' }).trim();
  } catch (_) {
    try { fs.unlinkSync(tmp); } catch (_) { /* nothing to clean */ }
    return original;                 // no Pillow: ship the original
  }
  const [verdict, size] = out.split(' ');
  if (verdict !== 'OK' || original <= Number(size)) {
    try { fs.unlinkSync(tmp); } catch (_) { /* nothing to clean */ }
    return original;                 // lossy, or no win: keep the original
  }
  fs.renameSync(tmp, target);
  return Number(size);
}

function listTerminals() {
  if (!fs.existsSync(TERMINALS)) return [];
  return fs.readdirSync(TERMINALS)
    .map((d) => path.join(TERMINALS, d, 'MQL4', 'Files', 'TH3_Dataset'))
    .filter((p) => fs.existsSync(p));
}

function newest(a, b) {
  // when two terminals hold the same sample name, the newer file wins
  if (!fs.existsSync(a)) return b;
  if (!fs.existsSync(b)) return a;
  return fs.statSync(a).mtimeMs >= fs.statSync(b).mtimeMs ? a : b;
}

function main() {
  const args = process.argv.slice(2);
  const listOnly = args.includes('--list');
  const destArg = args.indexOf('--dest');
  const dest = destArg >= 0 && args[destArg + 1]
    ? path.resolve(args[destArg + 1])
    : DEST;

  const sources = listTerminals();
  if (sources.length === 0) {
    console.error('no TH3_Dataset found under ' + TERMINALS);
    console.error('press M on a chart with an active pattern first.');
    return 1;
  }

  let copied = 0, skipped = 0, bytes = 0, saved = 0;
  const failed = [];
  for (const src of sources) {
    for (const { from, ext } of ARTIFACTS) {
      const dir = from === '.' ? src : path.join(src, from);
      if (!fs.existsSync(dir)) continue;
      for (const name of fs.readdirSync(dir)) {
        if (!ext.some((e) => name.toLowerCase().endsWith(e))) continue;
        const s = path.join(dir, name);
        if (!fs.statSync(s).isFile()) continue;

        const target = path.join(dest, from === '.' ? '' : from, name);
        if (listOnly) {
          console.log('  ' + path.relative(ROOT, s) +
                      (fs.existsSync(target) ? '  [have]' : '  [new]'));
          continue;
        }
        // --- never clobber a newer project copy
        if (fs.existsSync(target) &&
            fs.statSync(target).mtimeMs >= fs.statSync(s).mtimeMs) {
          skipped++;
          continue;
        }
        // P-TH3-REC-08: the DESTINATION's directory, always. The obvious
        // `mkdirSync(path.dirname(chosen))` was the wrong one: when the
        // project copy does not exist yet, `chosen` is the SOURCE (the
        // terminal's file), so it created the terminal's directory — which
        // exists — and then copyFileSync died with ENOENT on the destination.
        // A first run into a clean tree therefore crashed instead of
        // creating the tree, which is the one run that must always work.
        fs.mkdirSync(path.dirname(target), { recursive: true });
        // P-TH3-REC-08: ONE FILE'S FAILURE IS NOT THE RUN'S FAILURE. A single
        // unreadable or locked file used to throw out of the whole loop and
        // leave the rest of the dataset uncopied, so one bad sample cost all
        // of them. It is now counted, named, and the run continues — a
        // partial sync that says what it missed beats a crash that says
        // nothing.
        try {
          const chosen = newest(target, s);
          fs.copyFileSync(chosen, target);
        } catch (err) {
          failed.push(`${name}: ${err.code || err.message}`);
          continue;
        }
        copied++;
        //--- P-TH3-REC-07: shrink the shot, but only ever LOSSLESSLY. The
        //--- compression runs on the PROJECT copy, never on MT4's own file.
        let after = fs.statSync(target).size;
        if (name.toLowerCase().endsWith('.png')) {
          const before = after;
          after = compressLossless(target);
          if (after < before) saved += before - after;
        }
        bytes += after;
      }
    }
  }

  if (listOnly) return 0;
  const shotDir = path.join(dest, 'Screenshots');
  const logDir = path.join(dest, 'Logs');
  const shots = fs.existsSync(shotDir) ? fs.readdirSync(shotDir).length : 0;
  const logs = fs.existsSync(logDir) ? fs.readdirSync(logDir).length : 0;

  //--- the budget line (P-TH3-REC-06). The recorder caps at 100 samples, so
  //--- this is the size the dataset is DESIGNED to reach, not a guess.
  let total = 0;
  for (const dir of [shotDir, logDir, dest]) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      const p = path.join(dir, f);
      if (fs.statSync(p).isFile()) total += fs.statSync(p).size;
    }
  }
  const pct = (total / (1024 * 1024 * 1024)) * 100;
  console.log(`th3-dataset-sync: copied ${copied}, skipped ${skipped} (up to date)`);
  console.log(`  ${path.relative(ROOT, dest)}  ${shots} shots, ${logs} logs, ` +
              `${(bytes / 1024).toFixed(0)} KB written`);
  if (saved > 0) {
    console.log(`  lossless palette compression saved ${(saved / 1024).toFixed(0)} KB` +
                ` (verified pixel-identical; a lossy re-encode is refused)`);
  }
  console.log(`  dataset total ${(total / 1024 / 1024).toFixed(2)} MB = ` +
              `${pct.toFixed(2)}% of GitHub's 1 GB recommended ceiling ` +
              `(cap is 100 samples)`);
  if (pct > 5) {
    console.warn(`  WARNING: dataset is over 5% of the ceiling — archive the ` +
                `oldest samples before adding more.`);
  }
  if (failed.length) {
    for (const f of failed) console.error(`  FAILED ${f}`);
    console.error(`th3-dataset-sync: ${failed.length} file(s) could not be ` +
                  `copied; the rest are in place.`);
    return 1;
  }
  return 0;
}

process.exit(main());
