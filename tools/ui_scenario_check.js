#!/usr/bin/env node
// THE UI SCENARIO GATE — every UI surface must answer every scenario, on EVERY
// platform, and the answer must be a CALL that exists in the tree that runs it.
//
// WHY. `docs/contract.md` §4 names four lifecycle scenarios in prose, and prose is
// how P-UI-222 shipped: the ring, the chip, the strip and the cards each learned to
// re-derive their place on a resize, and the two POPUPS that hang off them did not.
// The palette kept the x it opened at, the gear panel kept the y its plate had, and
// both only showed up when a chart shrank under them. Nothing was wrong in any
// single file — the SURFACE was missing a row in a list nobody kept.
//
// WHY TWO PLATFORMS. The MT4 and MT5 trees are separate sources: MT4 is split into
// ~150 modules, MT5 is the same code still in ~80 monoliths. A rule proved on one
// proves nothing about the other — MEASURED, the MT5 tree still carried BOTH
// P-UI-222 defects after the MT4 fix shipped, because no gate ever asked it.
//
// WHAT IT CHECKS (each one is a class of defect this tree has already paid for):
//   1. STALE  — an answer names a function or a call site that no longer exists.
//   2. OPEN   — a surface leaves a scenario unanswered (printed, never a silent pass).
//   3. POPUP  — a surface flagged `popup` with no resize or no escape answer.
//   4. ORPHAN — a file that creates a UI control type belongs to no surface row.
//   5. CLOSE  — a surface's teardown is never called from outside itself.
//   6. SHARED — a whitelist entry that names no file, or a file that paints nothing.
//
// THE ONE ASYMMETRY, AND WHY IT IS SAFE. A row names MT4's file for a site. On MT5
// the same code may live in a monolith, so when the named file does not exist on
// that platform the gate looks for the SAME text in the platform's whole unit and
// records it as `mapped`. When the named file DOES exist there, the check stays
// strict: the text must be in it. So a split file that loses a call is still STALE,
// and only a file that was never there gets the softer rule. An answer may also
// carry an explicit `m5` override for a place where the platforms genuinely differ
// in spelling — those are declared, never inferred.
//
// USAGE:  node tools/ui_scenario_check.js [--verbose] [--platform=mt4|mt5]
// Exit 0 = every surface is declared, every answer is wired, on every platform.

'use strict';
const fs = require('fs');
const path = require('path');
const { PLATFORMS, SCENARIOS, SURFACES, SHARED, NA } = require('./ui-scenarios.js');

const HERE = __dirname;
const REPO = path.resolve(HERE, '..');
const VERBOSE = process.argv.includes('--verbose');
const ONLY = (process.argv.find((a) => a.startsWith('--platform=')) || '').split('=')[1] || null;

// --- A COMMENT IS NOT A CALL. The first cut of this gate matched raw text, and
// --- commenting the wiring out (`// if(PalReclampOpen()) ...`) still passed — the
// --- assertion was satisfied by the very line that disabled it. Every match below
// --- therefore runs on a comment-stripped copy: `//` and `/* */` are removed with
// --- string literals respected (a path like "::Files\\Icons" survives intact).
function stripComments(src) {
  let out = '', i = 0, inStr = false, q = '';
  while (i < src.length) {
    const c = src[i];
    if (inStr) {
      out += c;
      if (c === '\\') { out += src[i + 1] || ''; i += 2; continue; }
      if (c === q) inStr = false;
      i++; continue;
    }
    if (c === '"' || c === "'") { inStr = true; q = c; out += c; i++; continue; }
    if (c === '/' && src[i + 1] === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') {
      i += 2;
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i += 2; continue;
    }
    out += c; i++;
  }
  return out;
}
function readCode(root, rel) {
  try { return stripComments(fs.readFileSync(path.join(root, rel), 'utf8')); } catch { return null; }
}
function existsFn(tree, fn) {
  const re = new RegExp(`\\b(?:void|bool|int|string|double|long|color|uint|datetime)\\s+${fn}\\s*\\(`);
  return re.test(tree);
}

// --- the files that belong to a surface ON THIS PLATFORM. MT4 is the split tree;
// --- MT5 keeps the same code in monoliths, so each row names its files separately.
function surfaceFiles(surface, key) {
  return (key === 'mt4' ? surface.files : (surface.filesM5 || surface.files)) || [];
}
const failures = [];
const notes = [];
const skipped = [];
const perPlatform = [];

const keys = Object.keys(PLATFORMS).filter((k) => !ONLY || k === ONLY);
for (const key of keys) {
  const cfg = PLATFORMS[key];
  const ROOT = path.resolve(REPO, cfg.root);
  if (!fs.existsSync(ROOT)) { skipped.push(key); continue; }

  // --- the whole unit, one string: every .mqh plus the entries. A definition is a
  // --- definition wherever it lives (the compiler resolves the unit, not the file).
  const unitFiles = [];
  const dirOf = {};
  for (const d of cfg.dirs) {
    const dir = path.join(ROOT, d);
    if (!fs.existsSync(dir)) continue;
    for (const n of fs.readdirSync(dir).filter((x) => x.endsWith('.mqh'))) {
      unitFiles.push(d + '/' + n);
      dirOf[n] = d;
    }
  }
  // --- a row may name a file bare (`BiotakMenu_C.mqh`) or with its folder
  // --- (`Biotak/DrawStrip_Paint.mqh`); both resolve, and a bare name this tree does
  // --- not hold is null — which is the "the file was never here" case below.
  const resolve = (rel) => {
    if (rel.includes('/')) return rel;
    if (dirOf[rel]) return dirOf[rel] + '/' + rel;
    if (fs.existsSync(path.join(ROOT, rel))) return rel;   // an entry file at the root
    return null;
  };
  const readAt = (rel) => { const r = resolve(rel); return r === null ? null : readCode(ROOT, r); };
  const entries = cfg.entries.filter((e) => fs.existsSync(path.join(ROOT, e)));
  const unit = unitFiles.concat(entries).map((f) => readCode(ROOT, f) || '').join('\n');
  const shared = SHARED[key] || {};

  let answered = 0, open = 0, na = 0, total = 0, mapped = 0;

  for (const surface of SURFACES) {
    const tag = `[${key}] ${surface.id}`;
    if (!surface.answers) {
      failures.push(`${tag}: no answers row — a surface with no matrix is the defect this gate names`);
      continue;
    }
    const ownFiles = surfaceFiles(surface, key);
    if (!ownFiles.length) {
      failures.push(`${tag}: no files for ${key} — the row cannot be checked`);
      continue;
    }
    const surfaceText = ownFiles.map((f) => readAt(f) || '').join('\n');
    if (!surfaceText.trim()) {
      failures.push(`${tag}: every file in its row is missing from ${cfg.root}/${cfg.dirs[0]}/`);
      continue;
    }

    for (const sc of SCENARIOS) {
      total++;
      const a = surface.answers[sc.id];
      if (a === NA) { na++; continue; }
      if (a === null || a === undefined) {
        open++;
        notes.push({ kind: 'OPEN', text: `${tag} ${sc.id} ${sc.key}: OPEN — ${sc.q}` });
        continue;
      }
      answered++;
      // (1a) the answer's function exists, in the surface or anywhere in the unit
      if (a.fn) {
        const here = existsFn(surfaceText, a.fn);
        const anywhere = existsFn(unit, a.fn);
        if (!here && !anywhere) {
          failures.push(`${tag} ${sc.id}: answer "${a.fn}" is gone — STALE (the check stopped running)`);
        } else if (!here) {
          notes.push({ kind: 'note', text: `${tag} ${sc.id}: "${a.fn}" lives outside the surface's own files (ok, but it is a shared owner)` });
        }
      }
      // (1b) the CALL that proves it is wired, in the file that runs on that event
      if (!a.site || !a.site.file || !a.site.text) {
        failures.push(`${tag} ${sc.id}: answer has no site — an unwired answer is prose`);
        continue;
      }
      const ov = key !== 'mt4' && a.m5 ? a.m5 : null;
      const file = ov ? ov.file : a.site.file;
      const text = ov ? ov.text : a.site.text;
      const siteText = readAt(file);
      if (siteText === null) {
        // the split file was never there on this platform — ask the unit, and say so
        if (unit.includes(text)) {
          mapped++;
          notes.push({ kind: 'mapped', text: `${tag} ${sc.id}: no ${file} on ${key}; "${text.slice(0, 48)}" found in the unit` });
        } else {
          failures.push(`${tag} ${sc.id}: ${file} is not in this tree and "${text}" is not anywhere in its unit — STALE`);
        }
      } else if (!siteText.includes(text)) {
        failures.push(`${tag} ${sc.id}: the call site is gone — expected "${text}" in ${file}`);
      }
    }

    // (3) a popup with no resize answer is exactly P-UI-222
    if (surface.popup) {
      const r = surface.answers.S06;
      if (r === null || r === undefined || r === NA) {
        failures.push(`${tag}: a POPUP with no S06 (resize) answer — this is the P-UI-222 class`);
      }
      // (3b) P-UI-223: and it must have an EXIT that does not need its own buttons.
      const e = surface.answers.S13;
      if (e === null || e === undefined || e === NA) {
        failures.push(`${tag}: a POPUP with no S13 (escape) answer — a popup that strands itself with no exit is P-UI-222 again`);
      }
    }

    // (5) the teardown must be called from outside the surface
    if (surface.close) {
      const outside = entries.concat(unitFiles.filter((n) => !ownFiles.includes(n)))
        .map((n) => readAt(n) || '').join('\n');
      if (!outside.includes(surface.close + '(')) {
        failures.push(`${tag}: teardown ${surface.close}() is never called from outside the surface — it cannot be taken down`);
      }
    }
  }

  // (4) every file that creates a UI control type must be claimed by a row
  const UI_TYPE = /OBJ_BUTTON|OBJ_EDIT|OBJ_BITMAP_LABEL/;
  // bare names on both sides: a row writes `BiotakMenu_C.mqh`, the walk produces
  // `Biotak/BiotakMenu_C.mqh` — comparing them raw marks every painter an orphan.
  const claimed = new Set();
  for (const s of SURFACES) for (const f of surfaceFiles(s, key)) claimed.add(path.basename(f));
  const orphans = [];
  for (const f of unitFiles) {
    const t = readAt(f);
    if (!t || !UI_TYPE.test(t)) continue;
    if (claimed.has(path.basename(f)) || shared[path.basename(f)]) continue;
    orphans.push(f);
  }
  if (orphans.length) {
    failures.push(`[${key}] ORPHAN painter(s): ${orphans.join(', ')} — a file that creates a UI control must belong to a surface row in tools/ui-scenarios.js (or to SHARED with a reason)`);
  }

  // (4b) THE WHITELIST IS CHECKED TOO (P-UI-223). `SHARED` is the only way out of the
  // orphan rule, so an unverified entry is an unverified hole. A key that names no file
  // is a free pass nobody is using (the file was renamed and the entry stayed); a key
  // for a file that creates no control type is noise that makes the list look stronger
  // than it is. Both pass silently today, which is the definition of a false green.
  for (const f of Object.keys(shared)) {
    const t = readAt(f);
    if (t === null) {
      failures.push(`[${key}] SHARED names ${f}, which is not in ${cfg.root}/${cfg.dirs[0]}/ — a dead whitelist entry is a free pass`);
    } else if (!UI_TYPE.test(t)) {
      failures.push(`[${key}] SHARED names ${f}, which creates no UI control type — it is not shared, it is just a file; delete the entry`);
    }
  }

  perPlatform.push({ key, cfg, total, answered, na, open, mapped, files: unitFiles.length, entries: entries.length });
}

// --- report
console.log('='.repeat(70));
console.log('UI SCENARIO GATE  (surface x scenario, per platform)');
console.log('='.repeat(70));
for (const p of perPlatform) {
  console.log(`  ${p.key.toUpperCase()}  ${p.cfg.root}`);
  console.log(`      surfaces: ${SURFACES.length}   scenarios: ${SCENARIOS.length}   cells: ${p.total}`);
  console.log(`      answered: ${p.answered}   not-applicable: ${p.na}   OPEN: ${p.open}   mapped-to-unit: ${p.mapped}`);
  console.log(`      unit: ${p.files} module(s), ${p.entries} entr${p.entries === 1 ? 'y' : 'ies'}`);
}
if (skipped.length) console.log(`  not present (skipped): ${skipped.join(', ')}`);

if (VERBOSE) {
  for (const p of perPlatform) {
    console.log(`\n  --- ${p.key.toUpperCase()} ---`);
    for (const s of SURFACES) {
      const row = SCENARIOS.map((sc) => {
        const a = s.answers[sc.id];
        return a === NA ? '-' : (a === null || a === undefined ? '.' : 'x');
      }).join('');
      console.log(`  ${s.id.padEnd(12)} ${row}   ${s.title}`);
    }
    console.log(`  ${''.padEnd(12)} ${SCENARIOS.map((s) => s.id[2]).join('')}`);
  }
  for (const n of notes) console.log(`  [${n.kind}] ${n.text}`);
}

if (failures.length) {
  for (const f of failures) console.log('[FAIL] ' + f);
  console.log(`\nUI SCENARIO GATE FAILED (${failures.length} problem(s))`);
  process.exit(1);
}
console.log('\nPASS — every UI painter belongs to a declared surface on every platform present, and every answered scenario is a call that exists where the row says it does.');
