import io

p = 'tools/th3-dataset-sync.js'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


# --- 1. no samples yet is a STATE, not a failure
rep('''  const sources = listTerminals();
  if (sources.length === 0) {
    console.error('no TH3_Dataset found under ' + TERMINALS);
    console.error('press M on a chart with an active pattern first.');
    return 1;
  }''',
    '''  const sources = listTerminals();
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
  }''')

# --- 2. clear + watch + capture, all on the same tool
rep('''function main() {
  const args = process.argv.slice(2);
  const listOnly = args.includes('--list');
  const destArg = args.indexOf('--dest');
  const dest = destArg >= 0 && args[destArg + 1]
    ? path.resolve(args[destArg + 1])
    : DEST;
''',
    '''//+------------------------------------------------------------------+
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
  const f = path.join(DS, 'Reviews.csv');
  if (!fs.existsSync(f)) return [];
  const lines = fs.readFileSync(f, 'utf8').split(/\\r?\\n/).filter(Boolean);
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
  const repoSamples = path.join(DS, 'Samples');
  if (fs.existsSync(repoSamples)) {
    for (const folder of fs.readdirSync(repoSamples)) {
      const csv = path.join(repoSamples, folder, 'sample.csv');
      let id = '';
      if (fs.existsSync(csv)) {
        const c = splitCsv(fs.readFileSync(csv, 'utf8').split(/\\r?\\n/)[1] || '');
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
  fs.writeFileSync(path.join(DS, 'Reviews.csv'),
    ['Sample_ID,Verdict,Note,Reviewer,Reviewed_At'].concat(left.map((r) =>
      ['Sample_ID', 'Verdict', 'Note', 'Reviewer', 'Reviewed_At'].map((c) =>
        String(r[c] == null ? '' : r[c]).replace(/,/g, ' ')).join(','))).join('\\n') + '\\n');
  appendJournal(`clear — removed ${removed} item(s)${f.all ? ' (ALL)' : ''}`);
  rebuildIndex(DS, { failed: [], dupes: 0, indexUnchanged: false });
  console.log(`  removed ${removed}; Dataset.csv and Reviews.csv rebuilt.`);
  console.log(`  NOTE: the sample counter is a chart-scoped GlobalVariable, so the`);
  console.log(`        next capture is Sample_001 on a FRESH chart (a chart that`);
  console.log(`        already recorded keeps counting from where it stopped).`);
  return 0;
}

function appendJournal(text) {
  const j = path.join(DS, 'journal.md');
  const head = fs.existsSync(j) && fs.statSync(j).size
    ? fs.readFileSync(j, 'utf8').replace(/\\s*$/, '\\n') : '# TH3 dataset journal\\n\\n';
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  fs.writeFileSync(j, head + `- ${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
    `${p(d.getHours())}:${p(d.getMinutes())} | ${text}\\n`);
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
  const out = (r.stdout || '').trim().split(/\\r?\\n/).pop() || '';
  if (r.status !== 0) console.error('  dashboard: ' + ((r.stderr || '').trim() || 'failed'));
  return out;
}

function capturePass(args) {
  const rc = main(['--internal']);
  const line = refreshDashboard();
  const rows = fs.existsSync(path.join(DS, 'Dataset.csv'))
    ? fs.readFileSync(path.join(DS, 'Dataset.csv'), 'utf8').split(/\\r?\\n/).filter(Boolean).length - 1
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
''')

# --- the dispatcher, and the watcher that drives it
rep('''process.exit(main());''',
    '''function run(argv) {
  const args = argv.slice();
  if (args[0] === 'clear') return clear(args);
  if (args[0] === 'capture') return capturePass(args);
  if (args.includes('--watch')) {
    const i = args.indexOf('--watch');
    const every = Number(args[i + 1] && /^\\d+$/.test(args[i + 1]) ? args[i + 1] : 2500);
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

const rc = run();
process.exit(rc === null ? 0 : rc);''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('sync: clear + watch + capture added')