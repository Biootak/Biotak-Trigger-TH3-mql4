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

  let copied = 0, skipped = 0, bytes = 0;
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
        const chosen = newest(target, s);
        fs.mkdirSync(path.dirname(chosen), { recursive: true });
        fs.copyFileSync(chosen, target);
        copied++;
        bytes += fs.statSync(target).size;
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
  console.log(`  dataset total ${(total / 1024 / 1024).toFixed(2)} MB = ` +
              `${pct.toFixed(2)}% of GitHub's 1 GB recommended ceiling ` +
              `(cap is 100 samples)`);
  if (pct > 5) {
    console.warn(`  WARNING: dataset is over 5% of the ceiling — archive the ` +
                `oldest samples before adding more.`);
  }
  return 0;
}

process.exit(main());
