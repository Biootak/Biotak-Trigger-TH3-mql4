#!/usr/bin/env node
// th3-dataset-sync.js — P-TH3-REC-06: move the recorder's samples out of the
// terminal's data folder and into the repo, where they are reviewable,
// diffable, and survive a reinstall.
//
// P-TH3-DB (2026-10-05) — ONE FOLDER PER SAMPLE, AND THE INDEX IS BUILT HERE.
// The recorder already writes each sample into its own folder
// (TH3_Dataset/Samples/<date>-<clock>_<SYM>_<TF>_S<NNN>_<pattern>/ holding the
// TXT, the PNG and a one-row sample.csv), so this tool's job is now threefold:
//
//   1. copy each sample FOLDER across (per file, newest wins, one failure does
//      not stop the run);
//   2. MIGRATE the flat layout the first twenty samples were recorded in
//      (Screenshots/ + Logs/ + Master_Dataset.csv) into that same folder shape,
//      reading the numbers back out of the TXT so nothing is lost — the old TXT
//      carried every field the new row has except the capture stamp, which comes
//      from the file's own mtime;
//   3. REBUILD the repo's global index Samples/TH3_Dataset/Dataset.csv from the
//      per-sample sample.csv rows, so the database and the folders cannot
//      disagree: the folders are the truth, the index is a view of them.
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
// It COPIES, it never deletes inside the terminal: MT4's own files are the
// running system's record and are left exactly as the terminal wrote them.
// Inside the REPO the legacy flat files are moved into their folders, because
// two layouts for one dataset is one dataset nobody can count.
//
//   node tools/th3-dataset-sync.js            # copy, migrate, rebuild the index
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

// P-TH3-DB: the global index, and the shape every sample folder obeys. Both
// names are the recorder's (Biotak/TH3/TH3DatasetPaths.mqh) — the header below
// is the SAME list TH3DatasetHeader() writes, and `checkHeader` says so out
// loud instead of quietly producing a database with shifted columns.
const COLS = ['Sample_ID', 'Capture_Date', 'Capture_Clock', 'Capture_Stamp', 'Symbol',
  'TF', 'Owner_TF', 'Pattern', 'Direction', 'D_Time', 'D_Price', 'Digits', 'Pip_Size',
  'Mother_Pips', 'Leg_AB', 'Leg_BC', 'Leg_CD', 'Ratio_BC_AB', 'Ratio_CD_BC', 'K',
  'Step_Mother', 'Step_Pattern', 'Step_Pips', 'Target_1', 'Target_3', 'Target_5',
  'Target_7', 'Actual_Turn', 'Error_Pips', 'Rungs_Hit', 'Folder', 'Log_File',
  'Screenshot', 'Rung_Pips'];

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
    // stdio captured, never inherited: Pillow prints a traceback for anything it
    // cannot open, and that traceback on the console reads as a failed sync even
    // though the catch below ships the original file untouched.
    out = require('child_process').execFileSync(
      py, ['-c', COMPRESS_SCRIPT, target, tmp],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
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
  // when two terminals hold the same sample file, the newer file wins
  if (!fs.existsSync(a)) return b;
  if (!fs.existsSync(b)) return a;
  return fs.statSync(a).mtimeMs >= fs.statSync(b).mtimeMs ? a : b;
}

function safeName(raw, max) {
  let s = String(raw == null ? '' : raw).replace(/[^\w-]/g, '_');
  return max > 0 ? s.slice(0, max) : s;
}

function stampFrom(ms) {
  const d = new Date(ms);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-` +
         `${p(d.getHours())}${p(d.getMinutes())}`;
}

function dateFrom(ms) {
  const d = new Date(ms);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())}`;
}

function clockFrom(ms) {
  const d = new Date(ms);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** Split a recorder CSV line. Safe because the recorder refuses commas in a
 *  field (TH3CsvField), so a quoted-field parser would be a second dialect. */
function splitCsv(line) {
  return line.replace(/\r$/, '').split(',');
}

/** Every number the legacy TXT carries, as a flat lookup. */
function parseTxt(txt) {
  const out = {};
  for (const line of txt.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.+?)\s*$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

/** `Point_C: {Price: 1.15876, Time: ...}` -> the number after the label. */
function afterColon(text, label) {
  const i = text.indexOf(label);
  if (i < 0) return '';
  const rest = text.slice(i + label.length);
  const m = rest.match(/-?\d+(\.\d+)?/);
  return m ? m[0] : '';
}

/** The legacy flat TXT -> the 33-column row the new recorder writes. */
function legacyRow(txt, id, folder, logName, shotName, ms) {
  const k = parseTxt(txt);
  const dPrice = afterColon(k.Point_D || '', 'Price:');
  const cPrice = afterColon(k.Point_C || '', 'Price:');
  const digits = (dPrice.split('.')[1] || '').length;
  // MQL4's own rule (GetCachedPipSize): odd digits -> 10^-(d-1), even -> 10^-d
  const pip = digits ? Math.pow(10, -(digits % 2 ? digits - 1 : digits)) : 0;
  const low = k.Actual_Reversal_Low && k.Actual_Reversal_Low !== 'none'
    ? k.Actual_Reversal_Low : '';
  const high = k.Actual_Reversal_High && k.Actual_Reversal_High !== 'none'
    ? k.Actual_Reversal_High : '';
  const row = {};
  row.Sample_ID = k.SAMPLE_ID || id;
  row.Capture_Date = dateFrom(ms);
  row.Capture_Clock = clockFrom(ms);
  row.Capture_Stamp = stampFrom(ms);
  row.Symbol = k.SYMBOL || '';
  row.TF = k.TIMEFRAME || '';
  row.Owner_TF = k.OWNER_TF || '';
  row.Pattern = k.PATTERN || '';
  row.Direction = (cPrice && dPrice && parseFloat(dPrice) > parseFloat(cPrice)) ? 'down' : 'up';
  row.D_Time = k.DATETIME_D || '';
  row.D_Price = dPrice;
  row.Digits = String(digits);
  row.Pip_Size = pip ? String(pip) : '';
  row.Mother_Pips = k.Size_Pips || '';
  row.Leg_AB = k.Leg_AB_Pips || '';
  row.Leg_BC = k.Leg_BC_Pips || '';
  row.Leg_CD = k.Leg_CD_Pips || '';
  row.Ratio_BC_AB = k.Ratio_BC_AB || '';
  row.Ratio_CD_BC = k.Ratio_CD_BC || '';
  row.K = k.K_Factor || '';
  row.Step_Mother = k.Step_Mother || '';
  row.Step_Pattern = k.Step_Pattern || '';
  row.Step_Pips = k.Final_Step_BaseUnit || '';
  row.Target_1 = k.Step_1 || '';
  row.Target_3 = k.Step_3_Target || '';
  row.Target_5 = k.Step_5_Target || '';
  row.Target_7 = k.Step_7_Target || '';
  row.Actual_Turn = low || high;
  row.Error_Pips = (row.Actual_Turn ? k.Error_Margin_Pips : '') || '';
  row.Rungs_Hit = '';                 // the legacy recorder never stored it
  row.Rung_Pips = '';                 // ditto — a tuner falls back and says so
  row.Folder = folder;
  row.Log_File = logName;
  row.Screenshot = shotName;
  return row;
}

function rowToCsv(row) {
  return COLS.map((c) => {
    const v = row[c] == null ? '' : String(row[c]);
    return /[",\n]/.test(v) ? v.replace(/"/g, "'").replace(/,/g, ' ') : v;
  }).join(',');
}

/** The recorder's own header must match COLS, or every column is shifted. */
function checkHeader(dir, where) {
  const csv = path.join(dir, 'Dataset.csv');
  if (!fs.existsSync(csv)) return true;
  const header = fs.readFileSync(csv, 'utf8').split(/\r?\n/)[0];
  const got = splitCsv(header);
  const same = got.length === COLS.length && got.every((c, i) => c === COLS[i]);
  if (!same) {
    console.error(`  WARNING ${where}: Dataset.csv header does not match the ` +
      `tool's column list (${got.length} vs ${COLS.length} columns) — the MQL4 ` +
      `header and this tool have drifted apart.`);
  }
  return same;
}

/**
 * Copy one file, newest wins, and never let one file kill the run.
 * Returns 'copied' | 'skipped', or throws for the caller to record.
 */
function copyOne(s, target) {
  if (fs.existsSync(target) &&
      fs.statSync(target).mtimeMs >= fs.statSync(s).mtimeMs) return 'skipped';
  fs.mkdirSync(path.dirname(target), { recursive: true });   // the DESTINATION's
  const chosen = newest(target, s);
  fs.copyFileSync(chosen, target);
  if (chosen === target) fs.utimesSync(target, fs.statSync(s).atime, fs.statSync(s).mtime);
  return 'copied';
}

/** The recorder's own layout: TH3_Dataset/Samples/<folder>/{txt,png,csv}. */
function syncFolders(src, dest, state, listOnly) {
  const srcSamples = path.join(src, 'Samples');
  if (!fs.existsSync(srcSamples)) return;
  for (const folder of fs.readdirSync(srcSamples)) {
    const dir = path.join(srcSamples, folder);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const name of fs.readdirSync(dir)) {
      const s = path.join(dir, name);
      if (!fs.statSync(s).isFile()) continue;
      const target = path.join(dest, 'Samples', folder, name);
      if (listOnly) {
        state.listed.push(target + (fs.existsSync(target) ? '  [have]' : '  [new]'));
        continue;
      }
      try {
        if (copyOne(s, target) === 'copied') {
          state.copied++;
          if (name.toLowerCase().endsWith('.png')) {
            const before = fs.statSync(target).size;
            const after = compressLossless(target);
            if (after < before) state.saved += before - after;
            state.bytes += after;
          } else {
            state.bytes += fs.statSync(target).size;
          }
        } else {
          state.skipped++;
        }
      } catch (err) {
        state.failed.push(`${folder}/${name}: ${err.code || err.message}`);
      }
    }
  }
}

/** Retire the flat copies once the folder holds them: two layouts for one
 *  dataset is one dataset nobody can count (and here it was stored TWICE —
 *  0.71 MB of flat PNGs left beside the 0.71 MB of folders). */
function dropFlat(txtPath, shotPath, dirs) {
  if (fs.existsSync(txtPath)) fs.unlinkSync(txtPath);
  if (shotPath && fs.existsSync(shotPath)) fs.unlinkSync(shotPath);
  for (const dir of dirs) {
    if (fs.existsSync(dir) && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
  }
}

/**
 * The FIRST layout: Logs/Sample_NNN.txt + Screenshots/Sample_NNN_*.png. Every
 * sample already recorded this way is rebuilt into its own folder, with the row
 * read back out of the TXT, and the flat copies are left where they are when
 * `move` is false (the terminal) or removed from the repo when it is true.
 */
function migrateLegacy(root, dest, state, listOnly, move) {
  const logDir = path.join(root, 'Logs');
  const shotDir = path.join(root, 'Screenshots');
  if (!fs.existsSync(logDir)) return;
  for (const name of fs.readdirSync(logDir)) {
    if (!name.toLowerCase().endsWith('.txt')) continue;
    const id = name.replace(/\.txt$/i, '');
    const txtPath = path.join(logDir, name);
    const txt = fs.readFileSync(txtPath, 'utf8');
    const k = parseTxt(txt);
    const ms = fs.statSync(txtPath).mtimeMs;
    const folder = `${stampFrom(ms)}_${safeName(k.SYMBOL, 12)}_` +
      `${safeName(k.TIMEFRAME, 6)}_${id.replace('Sample_', 'S')}_${safeName(k.PATTERN, 20)}`;
    const shotName = fs.existsSync(shotDir)
      ? (fs.readdirSync(shotDir).find((f) => f.startsWith(id + '_') && f.endsWith('.png')) || '')
      : '';
    const targetDir = path.join(dest, 'Samples', folder);
    if (listOnly) {
      state.listed.push(targetDir + (fs.existsSync(targetDir) ? '  [have]' : '  [new]'));
      continue;
    }
    if (fs.existsSync(path.join(targetDir, name)) && fs.existsSync(path.join(targetDir, 'sample.csv'))) {
      // already migrated by an earlier run (or by the terminal pass a moment
      // ago): count it, and inside the repo still retire the flat original.
      if (move) {
        dropFlat(txtPath, shotName ? path.join(shotDir, shotName) : '', [logDir, shotDir]);
        state.migrated++;
      } else {
        state.skipped++;
      }
      continue;
    }
    try {
      fs.mkdirSync(targetDir, { recursive: true });
      fs.copyFileSync(txtPath, path.join(targetDir, name));
      if (shotName) {
        const shot = path.join(targetDir, shotName);
        fs.copyFileSync(path.join(shotDir, shotName), shot);
        const before = fs.statSync(shot).size;
        const after = compressLossless(shot);
        if (after < before) state.saved += before - after;
      }
      const row = legacyRow(txt, id, folder, name, shotName, ms);
      fs.writeFileSync(path.join(targetDir, 'sample.csv'),
        COLS.join(',') + '\n' + rowToCsv(row) + '\n');
      state.migrated++;
      state.bytes += fs.statSync(path.join(targetDir, name)).size;
      if (move) dropFlat(txtPath, shotName ? path.join(shotDir, shotName) : '', [logDir, shotDir]);
    } catch (err) {
      state.failed.push(`${id}: ${err.code || err.message}`);
    }
  }
}

/** The index is a VIEW of the folders, rebuilt from their own sample.csv. */
function rebuildIndex(dest, state) {
  const samplesDir = path.join(dest, 'Samples');
  if (!fs.existsSync(samplesDir)) return 0;
  const rows = [];
  const dupes = new Map();
  for (const folder of fs.readdirSync(samplesDir).sort()) {
    const csv = path.join(samplesDir, folder, 'sample.csv');
    if (!fs.existsSync(csv)) {
      state.failed.push(`${folder}: no sample.csv — the index would lose it`);
      continue;
    }
    const cells = splitCsv(fs.readFileSync(csv, 'utf8').split(/\r?\n/)[1] || '');
    if (cells.length !== COLS.length) {
      state.failed.push(`${folder}: sample.csv has ${cells.length} columns, expected ${COLS.length}`);
      continue;
    }
    const row = {};
    COLS.forEach((c, i) => { row[c] = cells[i]; });
    row.Folder = row.Folder || folder;            // an older row without it
    const prev = dupes.get(row.Sample_ID);
    if (prev && prev.folder !== folder) {
      // the same sample captured twice: the newer capture stamp is the truth
      if ((row.Capture_Stamp || '') < (prev.row.Capture_Stamp || '')) continue;
      rows.splice(rows.indexOf(prev.row), 1);
      state.dupes++;
    }
    dupes.set(row.Sample_ID, { folder, row });
    rows.push(row);
  }
  rows.sort((a, b) => (a.Capture_Stamp + a.Sample_ID).localeCompare(b.Capture_Stamp + b.Sample_ID));
  const out = path.join(dest, 'Dataset.csv');
  const body = [COLS.join(',')].concat(rows.map(rowToCsv)).join('\n') + '\n';
  const old = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : '';
  if (old !== body) fs.writeFileSync(out, body);
  else state.indexUnchanged = true;
  return rows.length;
}

// P-TH3-DB: the budget counts the DATASET, not the page built from it.
// dashboard.html and dashboard.inline.html live in this folder, the inline one
// embeds every PNG (1.0 MB for 20 samples, ~6 MB at the 100-sample cap) — and
// both are generated and gitignored. Counting them made the number jump 0.73 ->
// 1.78 MB with no sample recorded, which is exactly how a budget line stops
// being evidence. They are named, not pattern-matched, so a new generated file
// has to be listed here deliberately.
const GENERATED = new Set(['dashboard.html', 'dashboard.inline.html']);

function dirBytes(dir, top) {
  let total = 0;
  for (const f of fs.readdirSync(dir, { withFileTypes: true })) {
    if (top && GENERATED.has(f.name)) continue;
    const p = path.join(dir, f.name);
    total += f.isDirectory() ? dirBytes(p, false) : fs.statSync(p).size;
  }
  return total;
}

//+------------------------------------------------------------------+
//| P-TH3-DB — CLEAR. Deleting a sample has to delete it in BOTH places:  |
//| the repo copy alone comes straight back on the next sync, because the  |
//| terminal is where the recorder wrote it. That trap is why «از داشبورد |
//| پاک کردم ولی برگشت» happens, so clear() walks the terminal folders AND |
//| the repo folders, and the folder name is the key for both.            |
//|                                                                    |
//| WITHOUT --yes it only PRINTS. A destructive command whose dry run is  |
//| the default is the difference between «the samples I wanted to drop   |
//| are gone» and «so is the whole set».                                 |
//+------------------------------------------------------------------+
function parseFilter(args, startAt) {
  const f = { all: false, ids: [], symbols: [], tfs: [], verdicts: [], yes: false };
  for (let i = startAt; i < args.length; i++) {
    const a = args[i];
    const next = () => args[++i];
    if (a === '--all') f.all = true;
    else if (a === '--yes' || a === '-y') f.yes = true;
    else if (a === '--id') f.ids.push(next());
    else if (a === '--symbol') f.symbols.push(next().toUpperCase());
    else if (a === '--tf') f.tfs.push(next().toUpperCase());
    else if (a === '--verdict') f.verdicts.push(next().toLowerCase());
  }
  return f;
}

function loadReviews() {
  const f = path.join(DEST, 'Reviews.csv');
  if (!fs.existsSync(f)) return [];
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/).filter(Boolean);
  if (lines.length < 2) return [];
  const head = splitCsv(lines[0]);
  return lines.slice(1).map((l) => {
    const c = splitCsv(l), row = {};
    head.forEach((h, i) => { row[h] = c[i] == null ? '' : c[i]; });
    return row;
  });
}

/** Does a sample folder name (or a legacy log file name) match the filter? */
function matches(name, f, verdict) {
  if (f.all) return true;
  if (verdict && f.verdicts.length && !f.verdicts.includes(String(verdict).toLowerCase())) return false;
  const parts = String(name).split('_');
  const sym = parts[1] || '';
  const tf = parts[2] || '';
  const id = (parts[3] || '').replace(/^S/, '');
  const sampleId = 'Sample_' + id;
  if (f.ids.length && !f.ids.includes(sampleId) && !f.ids.includes(id)) return false;
  if (f.symbols.length && !f.symbols.includes(sym)) return false;
  if (f.tfs.length && !f.tfs.includes(tf)) return false;
  return f.ids.length || f.symbols.length || f.tfs.length || f.verdicts.length;
}

function clear(args) {
  const f = parseFilter(args, 1);
  if (!f.all && !f.ids.length && !f.symbols.length && !f.tfs.length && !f.verdicts.length) {
    console.error('clear: nothing to do — give --all, --id Sample_015, --symbol EURUSD, --tf M5 or --verdict real');
    return 1;
  }
  const reviews = new Map(loadReviews().map((r) => [r.Sample_ID, r.Verdict]));
  const hits = [];
  // --- the repo folders
  const repoSamples = path.join(DEST, 'Samples');
  if (fs.existsSync(repoSamples)) {
    for (const folder of fs.readdirSync(repoSamples)) {
      const csv = path.join(repoSamples, folder, 'sample.csv');
      let id = '';
      if (fs.existsSync(csv)) {
        const c = splitCsv(fs.readFileSync(csv, 'utf8').split(/\r?\n/)[1] || '');
        id = c[0] || '';
      }
      if (matches(folder, f, reviews.get(id))) {
        hits.push({ where: 'repo', path: path.join(repoSamples, folder), id, folder });
      }
    }
  }
  // --- the terminals: the same rule, so a deleted sample cannot come back
  for (const src of listTerminals()) {
    const dir = path.join(src, 'Samples');
    if (!fs.existsSync(dir)) continue;
    for (const folder of fs.readdirSync(dir)) {
      if (fs.statSync(path.join(dir, folder)).isDirectory() &&
          matches(folder, f, null)) {
        hits.push({ where: 'terminal', path: path.join(dir, folder), id: '', folder });
      }
    }
    // legacy flat samples too, or they would re-import on the next sync
    for (const [sub, ext] of [['Logs', '.txt'], ['Screenshots', '.png']]) {
      const d = path.join(src, sub);
      if (!fs.existsSync(d)) continue;
      for (const file of fs.readdirSync(d)) {
        if (!file.toLowerCase().endsWith(ext)) continue;
        const id = file.split('.')[0];
        if (matches(id.replace('Sample_', 'S'), f, null)) {
          hits.push({ where: 'terminal', path: path.join(d, file), id, folder: file });
        }
      }
    }
  }
  if (!hits.length) {
    console.log('clear: nothing matched — nothing was touched.');
    return 0;
  }
  console.log(`clear: ${hits.length} item(s) match ${f.all ? 'EVERYTHING' :
    [...f.ids, ...f.symbols.map((x) => 'sym:' + x), ...f.tfs.map((x) => 'tf:' + x),
     ...f.verdicts.map((x) => 'verdict:' + x)].join(', ')}`);
  for (const h of hits) console.log(`  ${h.where.padEnd(9)} ${path.relative(ROOT, h.path)}`);
  if (!f.yes) {
    console.log('  dry run — add --yes to delete for real.');
    return 0;
  }
  let removed = 0;
  for (const h of hits) {
    try { fs.rmSync(h.path, { recursive: true, force: true }); removed++; }
    catch (err) { console.error(`  FAILED ${h.path}: ${err.code || err.message}`); }
  }
  const left = loadReviews().filter((r) => !hits.some((h) => h.id === r.Sample_ID));
  fs.writeFileSync(path.join(DEST, 'Reviews.csv'),
    ['Sample_ID,Verdict,Note,Reviewer,Reviewed_At'].concat(left.map((r) =>
      ['Sample_ID', 'Verdict', 'Note', 'Reviewer', 'Reviewed_At'].map((c) =>
        String(r[c] == null ? '' : r[c]).replace(/,/g, ' ')).join(','))).join('\n') + '\n');
  appendJournal(`clear — removed ${removed} item(s)${f.all ? ' (ALL)' : ''}`);
  rebuildIndex(DEST, { failed: [], dupes: 0, indexUnchanged: false });
  console.log(`  removed ${removed}; Dataset.csv and Reviews.csv rebuilt.`);
  console.log(`  NOTE: the sample counter is a chart-scoped GlobalVariable, so the`);
  console.log(`        next capture is Sample_001 on a FRESH chart (a chart that`);
  console.log(`        already recorded keeps counting from where it stopped).`);
  return 0;
}

function appendJournal(text) {
  const j = path.join(DEST, 'journal.md');
  const head = fs.existsSync(j) && fs.statSync(j).size
    ? fs.readFileSync(j, 'utf8').replace(/\s*$/, '\n') : '# TH3 dataset journal\n\n';
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  fs.writeFileSync(j, head + `- ${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
    `${p(d.getHours())}:${p(d.getMinutes())} | ${text}\n`);
}

//+------------------------------------------------------------------+
//| P-TH3-DB — ONE COMMAND AFTER EVERY M PRESS. `capture` is one pass; |
//| `--watch` polls and runs a pass whenever the terminal's dataset     |
//| changes, then rebuilds the page and, with --notify, says so on the   |
//| desktop. The recorder cannot do any of this itself (WebRequest 4060, |
//| FileOpen sandboxed), so the loop lives on the user's side.          |
//+------------------------------------------------------------------+
function datasetSignature() {
  let sig = '';
  for (const src of listTerminals()) {
    const walk = (dir) => {
      let s = dir;
      for (const f of fs.readdirSync(dir)) {
        const p = path.join(dir, f);
        const st = fs.statSync(p);
        s += '|' + f + ':' + (st.isDirectory() ? 'd' : st.size) + ':' + Math.round(st.mtimeMs);
        if (st.isDirectory()) s += walk(p);
      }
      return s;
    };
    if (fs.existsSync(src)) sig += walk(src);
  }
  return sig;
}

function notify(text) {
  if (!process.argv.includes('--notify')) { console.log('  ' + text); return; }
  const { spawnSync } = require('child_process');
  const esc = text.replace(/"/g, '');
  // msg.exe is the zero-dependency Windows notifier; a toast module is not
  // installed here and failing to notify must never fail the sync.
  const r = spawnSync('msg', ['*', esc], { encoding: 'utf8' });
  if (r.status !== 0) console.log('  (notify: msg.exe unavailable — see the console)');
  else console.log('  notified: ' + esc);
}

function refreshDashboard() {
  const { spawnSync } = require('child_process');
  const tool = path.join(__dirname, 'th3-dataset-dashboard.js');
  const r = spawnSync(process.execPath, [tool], { encoding: 'utf8' });
  const out = (r.stdout || '').trim().split(/\r?\n/).pop() || '';
  if (r.status !== 0) console.error('  dashboard: ' + ((r.stderr || '').trim() || 'failed'));
  return out;
}

function capturePass(args) {
  const rc = main(['--internal']);
  const line = refreshDashboard();
  const rows = fs.existsSync(path.join(DEST, 'Dataset.csv'))
    ? fs.readFileSync(path.join(DEST, 'Dataset.csv'), 'utf8').split(/\r?\n/).filter(Boolean).length - 1
    : 0;
  console.log('  ' + line);
  notify(`TH3 dataset: ${rows} sample(s) in the repo — ${line || 'sync done'}`);
  return rc;
}

function main(argv) {
  const args = argv || process.argv.slice(2);
  const listOnly = args.includes('--list');
  const destArg = args.indexOf('--dest');
  const dest = destArg >= 0 && args[destArg + 1]
    ? path.resolve(args[destArg + 1])
    : DEST;

  const sources = listTerminals();
  if (sources.length === 0) {
    // P-TH3-DB: an empty dataset is the state of a clean set, and it is what the
    // terminal looks like right after a reset — so this must NOT be an error,
    // because the automation that runs this after every M press would report a
    // failure for doing nothing. Only a MISSING terminals tree is a problem.
    if (!fs.existsSync(TERMINALS)) {
      console.error('no MetaQuotes terminal tree under ' + TERMINALS);
      return 1;
    }
    console.log('th3-dataset-sync: no samples recorded yet — draw a pattern and ' +
                'press M, then run this again.');
    return 0;
  }

  const state = { copied: 0, skipped: 0, bytes: 0, saved: 0, migrated: 0,
    dupes: 0, failed: [], listed: [], indexUnchanged: false };

  for (const src of sources) {
    checkHeader(src, path.basename(path.dirname(path.dirname(path.dirname(src)))));
    syncFolders(src, dest, state, listOnly);
    // the terminal keeps its own files: copy-and-migrate, never move there
    migrateLegacy(src, dest, state, listOnly, false);
  }
  // the repo's own legacy flat files ARE moved, so one dataset has one layout
  migrateLegacy(dest, dest, state, listOnly, true);
  if (listOnly) {
    for (const l of state.listed) console.log('  ' + path.relative(ROOT, l));
    return 0;
  }

  const legacyCsv = path.join(dest, 'Master_Dataset.csv');
  let legacyFolded = 0;
  if (fs.existsSync(legacyCsv)) {
    const lines = fs.readFileSync(legacyCsv, 'utf8').split(/\r?\n/).filter(Boolean);
    legacyFolded = Math.max(0, lines.length - 1);
    fs.unlinkSync(legacyCsv);         // its rows live on in the TXT -> sample.csv
  }

  const indexed = rebuildIndex(dest, state);
  const total = dirBytes(dest, true);
  const pct = (total / (1024 * 1024 * 1024)) * 100;
  const folders = fs.existsSync(path.join(dest, 'Samples'))
    ? fs.readdirSync(path.join(dest, 'Samples')).length : 0;

  console.log(`th3-dataset-sync: copied ${state.copied}, skipped ${state.skipped} (up to date), ` +
    `migrated ${state.migrated} legacy sample(s)`);
  console.log(`  ${path.relative(ROOT, dest)}  ${folders} sample folder(s), ` +
    `${indexed} row(s) in Dataset.csv, ${(state.bytes / 1024).toFixed(0)} KB written`);
  if (legacyFolded) console.log(`  Master_Dataset.csv folded into the folders (${legacyFolded} row(s)) and removed`);
  if (state.dupes) console.log(`  ${state.dupes} duplicate Sample_ID(s): the newer capture won`);
  if (state.saved > 0) {
    console.log(`  lossless palette compression saved ${(state.saved / 1024).toFixed(0)} KB` +
      ` (verified pixel-identical; a lossy re-encode is refused)`);
  }
  if (state.indexUnchanged) console.log('  Dataset.csv already matched the folders — not rewritten');
  console.log(`  dataset total ${(total / 1024 / 1024).toFixed(2)} MB = ` +
    `${pct.toFixed(2)}% of GitHub's 1 GB recommended ceiling (cap is 100 samples)`);
  if (pct > 5) {
    console.warn(`  WARNING: dataset is over 5% of the ceiling — archive the ` +
      `oldest samples before adding more.`);
  }
  if (state.failed.length) {
    for (const f of state.failed) console.error(`  FAILED ${f}`);
    console.error(`th3-dataset-sync: ${state.failed.length} file(s) could not be ` +
      `copied; the rest are in place.`);
    return 1;
  }
  return 0;
}

function run(argv) {
  const args = argv.slice();
  if (args[0] === 'clear') return clear(args);
  if (args[0] === 'capture') return capturePass(args);
  if (args.includes('--watch')) {
    const i = args.indexOf('--watch');
    const every = Number(args[i + 1] && /^\d+$/.test(args[i + 1]) ? args[i + 1] : 2500);
    let sig = datasetSignature();
    console.log(`th3-dataset-sync --watch: every ${every} ms. Press M on a chart;`);
    console.log('  each capture is pulled in, the dashboard is rebuilt, and');
    console.log('  --notify pops a desktop message. Ctrl+C to stop.');
    setInterval(() => {
      const now = datasetSignature();
      if (now === sig) return;            // nothing new: the common case, one walk
      sig = now;
      console.log(`[${new Date().toLocaleTimeString()}] dataset changed —`);
      capturePass(args);
    }, every);
    return null;                          // the interval owns the process now
  }
  return main(args);
}

const rc = run(process.argv.slice(2));
// null means «a watcher is now holding the process open» — calling exit here
// killed the interval one line after starting it, which is why --watch returned
// instantly with a success code and silently never watched anything.
if (rc !== null) process.exit(rc);