#!/usr/bin/env node
/*
 * bk-shot-sync.js — file every captured Base Knot sample into the dataset.
 *
 * THE CHAIN IT CLOSES
 *   press K in MT4  ->  BaseKnotCaptureSample (Biotak/BaseKnot_Shot.mqh)
 *                   ->  MQL4\Files\BK_Dataset\Samples\<box>_<stamp>\{shot.png,sample.txt}
 *                   ->  THIS TOOL: copy into the repo, assign BK-00NN, add the CSV row,
 *                       write notes.md, rebuild the site.
 *
 * WHY A FOLDER AND NOT A LOG LINE. MT4 can only write inside MQL4\Files, and its journal
 * wraps long lines at ~64 characters, so a log-driven importer has to re-join fragments and
 * guess. The capture writes a self-describing folder instead: `sample.txt` is `Key: Value`,
 * one per line, with the Dataset.csv column names. This tool is therefore a COPY, not a
 * translation — and a press that happened while the terminal was closed is still a folder.
 *
 * USAGE
 *   node tools/bk-shot-sync.js                 # file everything new, rebuild the site
 *   node tools/bk-shot-sync.js --dry           # list what would be filed, touch nothing
 *   node tools/bk-shot-sync.js --watch         # poll every 3 s, file on sight
 *   node tools/bk-shot-sync.js --watch --notify
 *   node tools/bk-shot-sync.js --list          # what is waiting, and why
 *
 * Exit: 0 = ok, 1 = a capture was refused (a folder with no sample.txt), 2 = nothing to do
 * and --strict was passed.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const DS = path.join(ROOT, 'Samples', 'BK_Dataset');
const CSV = path.join(DS, 'Dataset.csv');
const LEDGER = path.join(DS, '.filed.json');
const SAMPLE_DIR = path.join(DS, 'Samples');
const REL = 'BK_Dataset' + path.sep + 'Samples';

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const WATCH = argv.includes('--watch');
const NOTIFY = argv.includes('--notify');
const LIST = argv.includes('--list');
const STRICT = argv.includes('--strict');

//--- the capture's own key set. A missing one is a silent blank column on the site, so it is
//--- reported at filing time, not discovered three weeks later while re-scoring.
const REQUIRED = [
  'Folder', 'Capture_Date', 'Capture_Clock', 'Symbol', 'Chart_TF', 'Node_TF', 'Box_ID',
  'Story_Anchor', 'Edge_Anchor', 'Box_Pips', 'ATR_Trig', 'ATR_Pat', 'ATR_Str', 'ATR_Fourth',  'Band_FTR', 'Band_ETR', 'Band_CTR', 'Type', 'Edge_Margin_Pips', 'U', 'U_Margin',
  'Entry_Off_Pips', 'Stop_Pips', 'Stop_V1_Pips', 'TP1_Pips', 'TP2_Pips', 'TP3_Pips', 'PerPip', 'Balance',
  'Risk_Pct', 'Lot', 'Risk_USD', 'Direction', 'Formula_Version', 'Screenshot', 'Shot_Ok'
];

//--- ---------------------------------------------------------------------------
//--- where MT4 writes
//--- ---------------------------------------------------------------------------
function mt4Roots() {
  const base = path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
                         'MetaQuotes', 'Terminal');
  const out = [];
  let names = [];
  try { names = fs.readdirSync(base); } catch { return out; }
  for (const n of names) {
    const p = path.join(base, n, 'MQL4', 'Files', REL);
    if (fs.existsSync(p)) out.push(p);
  }
  return out;
}

function readSampleTxt(file) {
  const txt = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  const rec = {};
  for (const line of txt.split(/\r?\n/)) {
    //--- digits are part of a key here: TP1_Pips / TP2_Pips / TP3_Pips. Without them the
    //--- three targets parse as missing and the capture is refused (measured 2026-10-27).
    const m = line.match(/^([A-Za-z0-9_]+):\s?(.*)$/);
    if (m) rec[m[1]] = m[2].trim();
  }
  return rec;
}

function ledger() {
  try { return JSON.parse(fs.readFileSync(LEDGER, 'utf8')); } catch { return { filed: [] }; }
}
function saveLedger(l) {
  fs.writeFileSync(LEDGER, JSON.stringify(l, null, 1) + '\n', 'utf8');
}

//--- the CSV keeps its BOM: Excel and the dashboard both read it, and a rewritten file
//--- without one changes the first column's name to "\uFEFFSample_ID" for every reader.
function readCsv() {
  const raw = fs.readFileSync(CSV, 'utf8');
  const bom = raw.charCodeAt(0) === 0xFEFF;
  const text = bom ? raw.slice(1) : raw;
  const lines = text.split(/\r?\n/).filter((l) => l.length > 0);
  const header = parseLine(lines[0]);
  const rows = lines.slice(1).map((l) => {
    const cells = parseLine(l);
    const o = {};
    header.forEach((h, i) => { o[h] = cells[i] === undefined ? '' : cells[i]; });
    return o;
  });
  return { bom, header, rows };
}

function parseLine(line) {
  const out = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) {
      if (c === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; } else q = false;
      } else cur += c;
    } else if (c === '"') q = true;
    else if (c === ',') { out.push(cur); cur = ''; }
    else cur += c;
  }
  out.push(cur);
  return out;
}

function esc(v) {
  const s = v === undefined || v === null ? '' : String(v);
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function nextId(rows) {
  let max = 0;
  for (const r of rows) {
    const m = /^BK-(\d+)$/.exec(r.Sample_ID || '');
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  return 'BK-' + String(max + 1).padStart(4, '0');
}

//--- ---------------------------------------------------------------------------
//--- filing
//--- ---------------------------------------------------------------------------
function pending() {
  const done = new Set(ledger().filed);
  const out = [];
  for (const root of mt4Roots()) {
    let names = [];
    try { names = fs.readdirSync(root, { withFileTypes: true }); } catch { continue; }
    for (const d of names) {
      if (!d.isDirectory()) continue;
      if (done.has(d.name)) continue;
      const dir = path.join(root, d.name);
      const txt = path.join(dir, 'sample.txt');
      const png = path.join(dir, 'shot.png');
      out.push({
        leaf: d.name,
        dir,
        txt: fs.existsSync(txt) ? txt : null,
        png: fs.existsSync(png) ? png : null,
        rec: fs.existsSync(txt) ? readSampleTxt(txt) : null
      });
    }
  }
  //--- oldest first: the folder name ends in <yyyymmdd-hhmmss>, so a sort is chronological
  out.sort((a, b) => a.leaf.localeCompare(b.leaf));
  return out;
}

function fileOne(item, csv) {
  const rec = item.rec;
  if (!rec) return { ok: false, why: 'no sample.txt (the shot or the record failed at capture)' };
  const missing = REQUIRED.filter((k) => !(k in rec) || rec[k] === '');
  if (missing.length) return { ok: false, why: 'missing keys: ' + missing.join(', ') };

  const id = nextId(csv.rows);
  const dst = path.join(SAMPLE_DIR, id);
  if (DRY) return { ok: true, id, dry: true };

  fs.mkdirSync(dst, { recursive: true });
  if (item.png) fs.copyFileSync(item.png, path.join(dst, 'shot.png'));
  //--- the raw capture is kept verbatim beside the copy: if a later schema change drops a
  //--- field, the original is still on disk to re-derive it from
  fs.copyFileSync(item.txt, path.join(dst, 'sample.txt'));

  const row = {};
  for (const h of csv.header) row[h] = '';
  row.Sample_ID = id;
  row.Capture_Date = rec.Capture_Date;
  row.Capture_Clock = rec.Capture_Clock;
  row.Symbol = rec.Symbol;
  row.Chart_TF = rec.Chart_TF;
  row.Node_TF = rec.Node_TF;
  row.Box_ID = rec.Box_ID;
  row.Story_Anchor = rec.Story_Anchor;
  row.Edge_Anchor = rec.Edge_Anchor;
  row.Box_Pips = rec.Box_Pips;
  row.ATR_Trig = rec.ATR_Trig;
  row.ATR_Pat = rec.ATR_Pat;
  row.ATR_Str = rec.ATR_Str;
  row.ATR_Fourth = rec.ATR_Fourth;   // the rung an OTR stop reads — `u` is exact only with it
  row.Band_FTR = rec.Band_FTR;
  row.Band_ETR = rec.Band_ETR;
  row.Band_CTR = rec.Band_CTR;
  row.Type = rec.Type;
  row.Edge_Margin_Pips = rec.Edge_Margin_Pips;
  row.Entry_Off_Pips = rec.Entry_Off_Pips;
  row.Stop_Pips = rec.Stop_Pips;
  row.Stop_V1_Pips = rec.Stop_V1_Pips;   // what the NAME's hop would have charged (the 20-sample checkpoint)
  row.TP1_Pips = rec.TP1_Pips;
  row.TP2_Pips = rec.TP2_Pips;
  row.TP3_Pips = rec.TP3_Pips;
  row.PerPip = rec.PerPip;
  row.Balance = rec.Balance;
  row.Risk_Pct = rec.Risk_Pct;
  row.Lot = rec.Lot;
  row.Risk_USD = rec.Risk_USD;
  row.Direction = rec.Direction;
  row.Log_File = '';
  row.Log_Lines = '';
  row.Screenshot = 'shot.png';
  row.Formula_Version = rec.Formula_Version;
  row.Note = 'captured by K · source ' + item.leaf;

  //--- A BLANK COLUMN IS THE ONE BUG A SAMPLE CANNOT RECOVER FROM: the row files, the site
  //--- shows a gap, and nothing says which key the capture spelled differently. Measured
  //--- 2026-10-27: the sidecar wrote `Per_Pip` while the CSV column is `PerPip`, and the row
  //--- filed with an empty money-per-pip cell. So every column that must carry a number is
  //--- checked here, by NAME, before anything is written.
  const OPTIONAL = new Set(['Log_File', 'Log_Lines', 'Note']);
  const blank = csv.header.filter((h) => !OPTIONAL.has(h) && (row[h] === undefined || row[h] === ''));
  if (blank.length) return { ok: false, why: 'column(s) would be blank: ' + blank.join(', ') };

  csv.rows.push(row);
  writeCsv(csv);
  fs.writeFileSync(path.join(dst, 'notes.md'), notesMd(id, rec), 'utf8');

  const l = ledger();
  l.filed.push(item.leaf);
  saveLedger(l);
  return { ok: true, id };
}

function writeCsv(csv) {
  const lines = [csv.header.map(esc).join(',')];
  for (const r of csv.rows) lines.push(csv.header.map((h) => esc(r[h])).join(','));
  fs.writeFileSync(CSV, (csv.bom ? '\uFEFF' : '') + lines.join('\r\n') + '\r\n', 'utf8');
}

//--- the scaffold the discussion happens on: every number the capture measured, then two
//--- empty headings. The site renders this file, so a sample's story lives with the sample.
function notesMd(id, r) {
  const u = r.U === '' ? '' : Number(r.U).toFixed(3);
  const um = r.U_Margin === '' ? '' : Number(r.U_Margin).toFixed(3);
  return [
    '# ' + id + ' · ' + r.Type + ' · ' + r.Box_Pips + 'p',
    '',
    '| | |',
    '|---|---|',
    '| نماد / چارت | ' + r.Symbol + ' · ' + r.Chart_TF + ' |',
    '| گره | ' + r.Node_TF + ' |',
    '| لنگر داستان | ' + r.Story_Anchor + ' |',
    '| لنگر لبه | ' + r.Edge_Anchor + ' |',
    '| ارتفاع | ' + r.Box_Pips + 'p |',
    '| ATR | ' + r.ATR_Trig + ' / ' + r.ATR_Pat + ' / ' + r.ATR_Str + ' (+3: ' + r.ATR_Fourth + ') |',
    '| مرزها | FTR<' + r.Band_FTR + ' · ETR<' + r.Band_ETR + ' · CTR<' + r.Band_CTR + ' |',
    '| نوع | ' + r.Type + ' · فاصله از مرز ' + r.Edge_Margin_Pips + 'p |',
    '| u | ' + u + ' · حاشیه ' + um + ' رنگ |',
    '| ورود / استاپ | ' + r.Entry_Off_Pips + 'p / ' + r.Stop_Pips + 'p (v1: ' + r.Stop_V1_Pips + 'p) |',
    '| TP | ' + r.TP1_Pips + ' / ' + r.TP2_Pips + ' / ' + r.TP3_Pips + ' |',
    '| لات / ریسک | ' + r.Lot + ' · $' + r.Risk_USD + ' |',
    '| جهت | ' + r.Direction + ' |',
    '| نسخه | ' + r.Formula_Version + ' |',
    '',
    '## روایت',
    '',
    '_(چه دیدی — چرا این بکس ارزش ثبت داشت)_',
    '',
    '## تصمیم',
    '',
    '_(چه چیزی باید عوض شود، یا چرا هیچ‌چیز)_',
    ''
  ].join('\n');
}

function rebuild() {
  if (DRY) return;
  const r = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'bk-dataset-dashboard.js')],
                      { cwd: ROOT, encoding: 'utf8' });
  if (r.status !== 0) {
    console.log('  [site] rebuild failed:');
    console.log((r.stdout || '') + (r.stderr || ''));
  }
}

function syncOnce() {
  const items = pending();
  if (items.length === 0) return 0;
  const csv = readCsv();
  let filed = 0;
  let bad = 0;
  for (const it of items) {
    const res = fileOne(it, csv);
    if (res.ok) {
      filed++;
      console.log('  ' + (res.dry ? '[dry] ' : 'filed ') + res.id + '  <-  ' + it.leaf);
      if (NOTIFY) process.stdout.write('\u0007');
    } else {
      bad++;
      console.log('  [skip] ' + it.leaf + ' — ' + res.why);
    }
  }
  if (filed > 0) rebuild();
  console.log('  ' + filed + ' filed, ' + bad + ' skipped');
  if (bad > 0 && STRICT) return 1;
  return 0;
}

function main() {
  if (LIST) {
    const items = pending();
    if (!items.length) { console.log('  nothing waiting'); return 0; }
    for (const it of items) {
      console.log('  ' + it.leaf + '  png=' + (it.png ? 'y' : 'n') + ' txt=' + (it.txt ? 'y' : 'n'));
    }
    return 0;
  }
  const roots = mt4Roots();
  if (roots.length === 0) {
    console.log('  no MT4 capture folder yet (' + REL + ') — press K in the indicator first');
    return WATCH ? 0 : 2;
  }
  console.log('  watching: ' + roots.join(' | '));
  if (!WATCH) return syncOnce();

  let last = 0;
  const tick = () => {
    const n = syncOnce();
    if (n !== 0) process.exitCode = n;
  };
  tick();
  setInterval(tick, 3000);
  return 0;
}

process.exitCode = main();
