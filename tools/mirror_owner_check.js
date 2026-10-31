// mirror_owner_check.js — ONE STATE, ONE OWNER: a mirror may only be moved by the
// function that owns the state.
//
// WHY. P-UI-194c/e (2026-10-31). The defect class named that day is "a derived
// property with more than one writer". mask_owner_check.js covers the property that
// is a timeframe MASK. This covers the property that is a PAIR OF VARIABLES: the
// runtime half and the value a settings card prints from it. The user's report was
// the Q reset leaving the ATR card showing the pre-reset state — `g_atrLabelsVisible`
// moved, `g_showATRLabels` did not — and the same shape turned up four more times in
// the same evening:
//
//   · Q reset, eight lines below that fix: `g_thLabelsMode` moved and
//     `g_thLabelsVisible` written by hand, but SyncTHFlagsFromMode() never called, so
//     the THREE other mirrors of that one mode (g_showTHLabels / g_showFractalTHs /
//     g_showStandardTHs) kept the pre-reset values — the TH card printed the old
//     master row, and THModeFromFlags() answered the old mode to every re-derive.
//   · RestoreDiscreteToggles (Full) and the early restore (Lite): both restored
//     `g_linesVisible` / `g_atrLabelsVisible` and left the card mirrors at the
//     Inputs-dialog value, so a chart whose LINES were off before the restart came
//     back with the lines hidden and the switch drawn ON.
//   · the P-UI-119 levels-off migration: same pair, same missing half.
//   · the corrupted-GV branch: wrote one of four mirrors.
//
// None of these is visible to the compiler: both variables are `static bool`, the
// assignment type-checks, and the only symptom is a control that disagrees with the
// chart. That is why it is a gate.
//
// THE RULE. For each declared group (one state, N variables) a function that assigns
// one member must either (a) assign EVERY member of that group, or (b) call the
// group's owner, or (c) be listed in ALLOW with a reason. An assignment of a member
// from its own `inp` alias is not an assignment at all — `#define inpShowLines
// g_showLines` makes `g_showLines = inpShowLines;` a self-assign, and the gate drops
// it before counting (there are three such lines in RuntimeSettings' seed).
//
// WHAT IT DOES NOT DO. It does not model branches or call graphs: "calls the owner"
// means the name appears in the body, wherever it sits. That is the SAFE direction —
// a conditional sync is reported, never silently accepted — and it is why the owner
// call in every current writer is unconditional.
//
// COST. Line and regex reads of Biotak/**/*.mqh, once per build. No MQL grammar.
//
// Run: node tools/mirror_owner_check.js [root]

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2] || path.join(__dirname, '..');
const SRC = path.join(ROOT, 'Biotak');

//--- ONE STATE, N VARIABLES. `owner` is the function allowed to move them; a group
//--- with no owner means every writer must move the whole group itself.
const GROUPS = [
  {
    id: 'lines',
    members: ['g_linesVisible', 'g_showLines'],
    owner: 'SetLinesVisible',
    why: 'the LINES switch: runtime half + the Zones card row 1 (P-PERF-29)',
  },
  {
    id: 'atr',
    members: ['g_atrLabelsVisible', 'g_showATRLabels'],
    owner: null,
    why: 'the ATR switch: runtime half + the ATR card row 4 (P-UI-194c)',
  },
  {
    id: 'th',
    members: ['g_thLabelsVisible', 'g_showTHLabels', 'g_showFractalTHs', 'g_showStandardTHs'],
    owner: 'SyncTHFlagsFromMode',
    why: 'the TH mode: four mirrors derived from g_thLabelsMode (P-UI-194d)',
  },
];

//--- Every entry is a REASON, not a permission.
const ALLOW = {
  'Runtime_A.mqh:RuntimeSettingsLoadOverrides':
    'the OV_ override load: seeding the MIRRORS is its whole job. InitializeUISupport ' +
    'runs it first and RestoreDiscreteToggles consumes those values immediately after ' +
    '(chart key first, mirror as the fallback), so no card can read them in between. ' +
    'The TH flags it seeds are the INPUT to that restore\'s THModeFromFlags() — which ' +
    'is why the sync that used to sit between the two was removed (P-UI-194f).',
};

const CONTROL = new Set(['if', 'for', 'while', 'switch', 'else', 'do', 'return', 'catch']);

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.mqh')) out.push(p);
  }
  return out;
}

// Strip // and /* */ so a comment that MENTIONS a variable cannot make a writer clean.
function stripComments(src) {
  let out = '';
  let i = 0, n = src.length;
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (c === '/' && d === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && d === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c; out += c; i++;
      while (i < n) { out += src[i]; if (src[i] === '\\') { out += src[i + 1]; i += 2; continue; } if (src[i] === q) { i++; break; } i++; }
      continue;
    }
    out += c; i++;
  }
  return out;
}

function lineOf(src, idx) {
  let n = 1;
  for (let i = 0; i < idx && i < src.length; i++) if (src[i] === '\n') n++;
  return n;
}

const DEF = /([A-Za-z_]\w*)\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)\s*\{/g;

function functions(src) {
  const fns = [];
  DEF.lastIndex = 0;
  let m;
  while ((m = DEF.exec(src)) !== null) {
    const name = m[1];
    if (CONTROL.has(name)) continue;
    const head = src.slice(Math.max(0, m.index - 40), m.index).trim();
    if (head.endsWith('#')) continue;
    const open = m.index + m[0].length - 1;
    let depth = 0, end = -1;
    for (let i = open; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end < 0) continue;
    fns.push({ name, start: m.index, body: src.slice(open, end + 1), line: lineOf(src, m.index) });
    DEF.lastIndex = end;
  }
  return fns;
}

//--- `#define inpShowLines g_showLines` — the alias that makes `g_showLines =
//--- inpShowLines;` a self-assign. Built once from the whole tree.
const ALIAS = new Map();   // member -> Set(alias)
for (const file of walk(SRC, [])) {
  const raw = fs.readFileSync(file, 'utf8');
  const re = /#define\s+(inp[A-Za-z0-9_]+)\s+(g_[A-Za-z0-9_]+)/g;
  let m;
  while ((m = re.exec(raw)) !== null) {
    if (!ALIAS.has(m[2])) ALIAS.set(m[2], new Set());
    ALIAS.get(m[2]).add(m[1]);
  }
}

// Count REAL assignments of `name` in `body`. A member assigned only from its own
// alias is not written (the alias IS the variable).
function assignsReal(body, name) {
  const aliases = ALIAS.get(name);
  let hits = 0;
  const re = new RegExp(`\\b${name}\\b\\s*(?:=(?!=)|\\+=|-=|\\*=|/=)`, 'g');
  let m;
  while ((m = re.exec(body)) !== null) {
    const after = body.slice(m.index + m[0].length);
    if (aliases) {
      const rhs = after.split(/[;,\n]/)[0].trim();
      if (aliases.has(rhs)) continue;          // self-assign through the input alias
    }
    hits++;
  }
  return hits > 0;
}

const files = walk(SRC, []).sort();
const violations = [];
let scanned = 0, writers = 0;

for (const file of files) {
  const rel = path.relative(SRC, file).split(path.sep).join('/');
  const src = stripComments(fs.readFileSync(file, 'utf8'));
  for (const fn of functions(src)) {
    scanned++;
    for (const g of GROUPS) {
      if (g.owner && fn.name === g.owner) continue;      // the owner moves them all
      const moved = g.members.filter((v) => assignsReal(fn.body, v));
      if (moved.length === 0) continue;
      if (moved.length === g.members.length) continue;   // the whole group, in one body
      if (g.owner && fn.body.includes(g.owner)) continue; // hands the job to the owner
      const key = `${rel}:${fn.name}`;
      if (ALLOW[key]) continue;
      writers++;
      violations.push({ rel, fn: fn.name, line: fn.line, group: g.id, moved, all: g.members, why: g.why });
    }
  }
}

console.log('==================================================================');
console.log('MIRROR OWNER GATE  (one state, one owner — every mirror moves with it)');
console.log('==================================================================');
console.log(`  files: ${files.length}  functions: ${scanned}  groups: ${GROUPS.length}`);
console.log(`  allow-listed (documented reason): ${Object.keys(ALLOW).length}`);

if (violations.length) {
  console.log('');
  for (const v of violations) {
    const missing = v.all.filter((m) => !v.moved.includes(m));
    console.log(`  [FAIL] ${v.rel}:${v.line} ${v.fn}() moves ${v.moved.join(', ')}`);
    console.log(`         but not ${missing.join(', ')} — same state (${v.group}: ${v.why}),`);
    console.log(`         so the card and the chart can now disagree. Move the whole group`);
    console.log(`         or call the owner${v.group === 'atr' ? ' (this group has none — move both halves)' : ''}.`);
  }
  console.log('');
  console.log(`FAIL: ${violations.length} partial mirror writer(s).`);
  console.log('      Move every variable of the group, call its owner, or add a sentence to');
  console.log('      ALLOW in tools/mirror_owner_check.js.');
  process.exit(1);
}

console.log('');
console.log('PASS — every mirror writer moves its whole group or hands off to the owner.');
