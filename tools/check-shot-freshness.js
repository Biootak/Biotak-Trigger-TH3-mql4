#!/usr/bin/env node
// REAL PIXELS GATE — the only pixels a report may call "what is on the screen".
//
// WHY THIS EXISTS. `tools/sim-gear-panel.py` and `tools/sim-strip-panels.py` are
// MIRRORS: they rebuild the panel from the same literals the indicator compiles.
// A mirror is honest about the arithmetic and blind about the one thing only the
// terminal knows — what the blit really does — and it has already been wrong on
// exactly that (P-DRAW-109: the mirror drew a column the MQL never painted). So a
// mirror may SHOW a layout; it may never be the EVIDENCE that a change is on the
// screen. The evidence is `tests/Biotak_StripShot_Test.mq4`'s own PNGs, written by
// the real paint path inside MT4 (`compile-th3.ps1 -Shot -RestartTerminal`).
//
// MEASURED 2026-10-01, the day this gate was written: the tree held 24 states the
// harness shoots and ZERO of their PNGs — the third column of before-after.html had
// never been filled, and both "verified" renders in the reports of that week were
// mirrors. A green compile says the names resolve; a fresh PNG says a user can see
// it. This gate is the difference, per state:
//
//   fresh   the PNG is at least as new as the newest source it is supposed to show
//   stale   the PNG exists but the code moved after it was taken (the pixels are a
//           previous build's — the exact way a mirror gets mistaken for reality)
//   missing no PNG at all
//
// WANTED = the tags the HARNESS asks for, parsed out of it — so a new state (`panel_
// fold`, P-DRAW-117) cannot be silently unshot, and a retired one cannot keep its
// column.
//
// USAGE:  node tools/check-shot-freshness.js            -> report
//           exit 0 = CURRENT · exit 2 = NOT CURRENT (no/stale pixels)
//         node tools/check-shot-freshness.js --strict   -> exit 1 unless all fresh
//         (the build runs it plainly in every gate run — and the build must be able
//          to say "PASS" only when the pixels are current, so NOT CURRENT is its own
//          exit code and the build prints [WARN], never [PASS]. --strict runs after a
//          -Shot: a capture that left a stale or partial set is a FAILED build, not
//          a column that looks full.)
//
// The sources of PNGs are the two places the terminal writes them: the build's own
// sweep (`build-logs/shot/`) and the instance's `<MQL4>\Files` folder.

'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const BIOTAK = path.join(ROOT, 'Biotak');
const HARNESS = path.join(ROOT, 'tests', 'Biotak_StripShot_Test.mq4');
const SHOTS = path.join(ROOT, 'build-logs', 'shot');
const strict = process.argv.includes('--strict');

//--- what the harness shoots: the tags it passes to SSState()/SSKind().
function wanted() {
  let text = '';
  try {
    text = fs.readFileSync(HARNESS, 'utf8');
  } catch {
    return { tags: [], err: 'tests/Biotak_StripShot_Test.mq4 is missing' };
  }
  const out = [];
  for (const m of text.matchAll(/SS(?:State|Kind)\s*\(\s*"([A-Za-z0-9_]+)"/g)) {
    if (!out.includes(m[1])) out.push(m[1]);
  }
  return { tags: out, err: out.length ? null : 'the harness names no state at all' };
}

//--- every PNG the terminal left behind, by tag. The OLDEST copy wins: a swept copy
//--- that carries its own copy-time must not make a previous build's shot look fresh.
function found() {
  const byTag = new Map();
  const dirs = [SHOTS];
  const term = path.join(os.homedir(), 'AppData', 'Roaming', 'MetaQuotes', 'Terminal');
  const roots = fs.existsSync(term) ? fs.readdirSync(term).map((d) => path.join(term, d, 'MQL4', 'Files')) : [];
  for (const d of [...dirs, ...roots]) {
    if (!fs.existsSync(d)) continue;
    for (const f of fs.readdirSync(d)) {
      if (!/^StripShot_.+\.png$/i.test(f)) continue;
      const tag = f.slice('StripShot_'.length, -'.png'.length);
      const full = path.join(d, f);
      let mt = 0;
      try {
        mt = fs.statSync(full).mtimeMs;
      } catch {
        continue;
      }
      const prev = byTag.get(tag);
      byTag.set(tag, { file: path.relative(ROOT, full).split(path.sep).join('/'), mtime: prev ? Math.min(prev.mtime, mt) : mt });
    }
  }
  return byTag;
}

//--- the code the pixels are supposed to show. Every module the harness compiles
//--- (Biotak/**/*.mqh), both entries, and the harness itself.
function newestSource() {
  let best = { file: '(none)', mtime: 0 };
  const take = (full) => {
    let st;
    try {
      st = fs.statSync(full);
    } catch {
      return;
    }
    if (st.mtimeMs > best.mtime) best = { file: path.relative(ROOT, full).split(path.sep).join('/'), mtime: st.mtimeMs };
  };
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.name.endsWith('.mqh')) take(full);
    }
  };
  if (fs.existsSync(BIOTAK)) walk(BIOTAK);
  for (const f of ['Biotak Trigger TH3.mq4', 'Biotak Trigger TH3 Lite.mq4',
                   'tests/Biotak_StripShot_Test.mq4']) take(path.join(ROOT, f));
  return best;
}

function main() {
  const { tags, err } = wanted();
  const pngs = found();
  const src = newestSource();
  // local time, so it can be read beside the build log's own clock
  const stamp = (ms) =>
    ms ? new Date(ms).toLocaleString('sv-SE').replace('T', ' ').slice(0, 19) : '(never)';

  console.log('==================================================================');
  console.log('REAL PIXELS GATE  (the terminal\'s own PNGs vs the code on disk)');
  console.log('==================================================================');
  if (err) {
    console.log(`  [FAIL] ${err}`);
    console.log('');
    console.log('VERDICT: NOT CURRENT — no state list, so nothing can be called seen.');
    process.exit(1);
  }
  const fresh = [], stale = [], missing = [];
  for (const t of tags) {
    const p = pngs.get(t);
    if (!p) missing.push(t);
    else if (p.mtime + 999 < src.mtime) stale.push({ t, ...p });   // 1s of filesystem slack
    else fresh.push({ t, ...p });
  }
  console.log(`  harness asks for ${tags.length} state(s) (tests/Biotak_StripShot_Test.mq4)`);
  console.log(`  fresh ${fresh.length} · stale ${stale.length} · missing ${missing.length}`);
  console.log(`  newest source: ${src.file}  ${stamp(src.mtime)}`);
  for (const s of stale)
    console.log(`  [STALE]   ${s.t} — ${s.file} is ${stamp(s.mtime)}, older than the code it shows`);
  if (missing.length)
    console.log(`  [MISSING] ${missing.join(' ')}`);
  if (fresh.length && !stale.length && !missing.length)
    console.log(`  fresh PNGs: ${fresh.map((f) => f.file).join(' ')}`);
  console.log('');
  if (fresh.length && !stale.length && !missing.length)
    console.log(`VERDICT: CURRENT — all ${tags.length} state(s) are the terminal's own pixels of this code.`);
  else
    console.log('VERDICT: NOT CURRENT — a mirror may show this panel; only these PNGs are evidence.\n' +
                '         capture them with: compile-th3.ps1 -Shot -RestartTerminal -Project all');
  if (stale.length || missing.length) process.exit(strict ? 1 : 2);
  process.exit(0);
}

main();
