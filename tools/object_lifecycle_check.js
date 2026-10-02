// object_lifecycle_check.js — a name a surface PAINTS must be a name it can DELETE.
//
// WHY. P-DRAW-84 (2026-09-29): `DrawStripGearSectionsPaint` deleted two names for a
// retired band, and only ONE of them was ever painted — so a tab switch that shrank the
// band list (Style's four bands -> Look's one) left the previous tab's captions, dots and
// pills floating on the new tab's plate. The compiler cannot see it (both names compile),
// the resource gate cannot see it (no raster involved) and the geometry gate cannot see it
// (nothing moved). It is a NAME-LEDGER defect, so it is checked against the ledger.
//
// THE RULE. For every object name a painter can create, the same family must carry a
// destroy path at run time: an `ObjectDelete`/`ObjectFind` site for that name, or an
// `ObjectsDeleteAll` prefix that covers it. The ATTACH reset is not coverage — a prefix
// that covers EVERY family (`PnlDrawS_`) proves nothing about one family's own destroy,
// so such a prefix is ignored by construction (see `resetPrefix`).
//
// COST. Line and regex reads of `Biotak/**/*.mqh`, once per build. No parse of the C
// grammar, no evaluation: local `string X = ...` assignments are unioned per file, and a
// one-line `string FooName(...) { return <expr>; }` helper is flattened so
// `DrawStripRowStateName(r)` and `DrawStripRowName(r) + "S"` land on the same family.
// Expressions the reader cannot resolve are COUNTED and printed, never guessed at.
//
// Run: node tools/object_lifecycle_check.js [root]
import { readFileSync, readdirSync } from 'node:fs';

const root = process.argv[2] ?? '.';

//--- the painters that CREATE an object, and which argument carries the name.
//    arg: 0 = the first argument · 'index' = the argument is an index/slot, so the
//    name comes from the module's own `...Name()` helper.
const WRITERS = {
  DrawStripBtnZ: 0, DrawStripBtn: 0, DrawStripFaceZ: 0, DrawStripFace: 0,
  DrawStripLblAt: 0, DrawStripLblIn: 0, DrawStripRect: 0, DrawStripSkinBmp: 0,
  DrawStripEdit: 'DrawStripEditName', DrawStripPopHex: 'DrawStripPHexEdName',
  PnlBtn: 0, PnlSetButton: 0, PnlCreate: 0, PnlLabel: 0, PnlBitmap: 0, PnlRect: 0,
};

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = `${dir}/${e.name}`;
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.mqh')) out.push(p);
  }
  return out;
}
//--- comments go, string contents stay (the literals ARE the names).
function stripComments(src) {
  let out = '', i = 0, inStr = false;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (inStr) {
      out += c;
      if (c === '\\') { out += src[i + 1] ?? ''; i += 2; continue; }
      if (c === '"') inStr = false;
      i++; continue;
    }
    if (c === '"') { inStr = true; out += c; i++; continue; }
    if (c === '/' && n === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && n === '*') { i += 2; while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; continue; }
    out += c; i++;
  }
  return out;
}
function splitTop(expr) {           // split on '+' outside quotes and parens
  const parts = []; let depth = 0, inStr = false, cur = '';
  for (let i = 0; i < expr.length; i++) {
    const c = expr[i];
    if (inStr) { cur += c; if (c === '\\') { cur += expr[++i]; continue; } if (c === '"') inStr = false; continue; }
    if (c === '"') { inStr = true; cur += c; continue; }
    if (c === '(' || c === '[') depth++;
    if (c === ')' || c === ']') depth--;
    if (c === '+' && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += c;
  }
  parts.push(cur);
  return parts;
}
const litOf = (t) => { const m = t.match(/^"([^"]*)"$/); return m ? m[1] : null; };
//--- the first argument of a call's argument text, commas inside parens/quotes ignored.
function firstArg(text) {
  let depth = 0, inStr = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inStr) { if (c === '\\') { i++; continue; } if (c === '"') inStr = false; continue; }
    if (c === '"') { inStr = true; continue; }
    if (c === '(' || c === '[') depth++;
    if (c === ')' || c === ']') { if (depth === 0) return text.slice(0, i); depth--; }
    if (c === ',' && depth === 0) return text.slice(0, i);
  }
  return text;
}

//--- THE NAME HELPERS ARE SHARED, NOT PER FILE. DrawStrip.mqh was split by owner
//--- (contract §7), so a painter in DrawStrip_GearB.mqh names its object with
//--- `DrawStripFootName(f)` — DEFINED in DrawStrip_Base.mqh — and a per-file helper
//--- table answered "unknown call" for every strip family. MEASURED before this
//--- change: `painted names: 9 (233 not resolvable, skipped)` over 125 files, i.e.
//--- the gate returned PASS over a surface it had not read. One table, built once
//--- from the whole tree, read by every file.
const FILES = walk(`${root}/Biotak`);
const HELPERS = new Map();
for (const f of FILES) {
  const src = stripComments(readFileSync(f, 'utf8'));
  for (const re of [/string\s+(\w+)\s*\(([^)]*)\)\s*\{\s*return\s+([^;]+);/g,
                    /string\s+(\w+)\s*\(([^)]*)\)\s*[\r\n]+\s*\{\s*[\r\n]+\s*return\s+([^;]+);/g]) {
    for (const m of src.matchAll(re)) HELPERS.set(m[1], { params: m[2].split(',').map((s) => s.trim().replace(/^.*\s(\w+)$/, '$1')), ret: m[3].trim() });
  }
}

//--- one file's ledger: the resolvable name expressions and where they are used.
function analyze(file) {
  const src = stripComments(readFileSync(file, 'utf8'));
  const helpers = HELPERS;
  // local assignments: every RHS ever given to the name, unioned (a variable reassigned
  // in a loop is the set of the names it can hold)
  const assigns = new Map();
  for (const m of src.matchAll(/(?:^|[\r\n;{}\s])(?:string\s+)?(\w+)\s*=(?!=)\s*([^;]+);/g)) {
    const rhs = m[2].trim();
    if (!/["(]/.test(rhs)) continue;                 // not a name expression
    if (!assigns.has(m[1])) assigns.set(m[1], []);
    assigns.get(m[1]).push(rhs);
  }

  //--- indexed arrays: `fx[2] = expr;` — a prune LIST, read as a set of destroy sites
  //--- (see the ObjectDelete reader below). A local that is assigned per element is a
  //--- name the tool can follow; the index it is read back through is not.
  const elements = new Map();
  for (const m of src.matchAll(/(?:^|[\r\n;{}\s])(\w+)\s*\[[^\]]*\]\s*=\s*([^;]+);/g)) {
    const rhs = m[2].trim();
    if (!/["(]/.test(rhs)) continue;
    if (!elements.has(m[1])) elements.set(m[1], []);
    elements.get(m[1]).push(rhs);
  }

  const resolve = (expr, params = new Set(), depth = 0) => {
    if (depth > 4) return { key: null, raw: expr };
    let head = null, suffix = '', lit = '';
    for (const raw of splitTop(expr)) {
      const t = raw.trim();
      if (!t) continue;
      const L = litOf(t);
      //--- a literal BEFORE the base builds the literal head ("PnlDrawS_GR" +
      //--- IntegerToString(r)); a literal AFTER it is the family's SUFFIX (sn + "D").
      if (L !== null) { suffix += L; if (head === null) lit += L; continue; }
      const call = t.match(/^(\w+)\s*\(([\s\S]*)\)$/);
      if (head === null) {
        if (call && helpers.has(call[1])) {
          //--- THE FAMILY IS THE OUTERMOST NAME HELPER, never the index builder inside
          //--- it: `DrawStripFootName(f)` is `"PnlDrawS_GF" + IntegerToString(f)`, and
          //--- the family is the whole call — keying it on `IntegerToString()` split one
          //--- family per caller and made the report unreadable.
          const h = helpers.get(call[1]);
          const inner = resolve(h.ret, new Set(h.params), depth + 1);
          if (inner.key === null && inner.lit === '') return { key: null, raw: expr };
          head = `${call[1]}()`;
          suffix += (inner.key && helpers.has(inner.key) ? inner.suffix : inner.suffix);
          lit = inner.lit;
          continue;
        }
        if (call && params.has(call[1])) return { key: null, raw: expr };
        if (call) {
          if (params.has(call[1])) return { key: null, raw: expr };   // a parameter: an index, no name
          const args = (call[2].match(/"[^"]*"/g) ?? []).join(',');
          head = `${call[1]}(${args})`;                 // literal args ARE part of the name
          continue;
        }
        if (assigns.has(t)) {
          const inner = resolve(assigns.get(t)[0], params, depth + 1);
          if (inner.key === null) return { key: null, raw: expr };
          head = inner.key; suffix += inner.suffix; lit = inner.lit + (inner.tail ?? '');
          continue;
        }
        if (params.has(t) || /^\w+$/.test(t) || t.includes('.')) return { key: null, raw: expr };
        head = t; continue;
      }
      if (call && !params.has(call[1])) {               // a second name part (e.g. + Suffix(i))
        const args = (call[2].match(/"[^"]*"/g) ?? []).join(',');
        suffix += `${call[1]}(${args})`;
      }
    }
    return { key: head, suffix, lit };
  };
  const site = (m) => { const line = src.slice(0, m.index).split('\n').length; return line; };
  let defs = 0;

  const painted = [], deleted = [];
  for (const [fn, arg] of Object.entries(WRITERS)) {
    for (const m of src.matchAll(new RegExp(`\\b${fn}\\s*\\(([^;]*)`, 'g'))) {
      const fa = firstArg(m[1]);
      const a = (arg === 0) ? fa : `${arg}(${fa === undefined ? '' : fa.trim()})`;
      //--- a DEFINITION, not a call: `bool DrawStripFaceZ(const string nm, …)`.
      //--- Counting it as a paint site that "cannot be resolved" is how 233 came to
      //--- read as a parser limit instead of a missing helper table; it is neither.
      if (/^\s*(const|string|int|bool|color|double)\b/.test(String(a))) { defs++; continue; }
      const r = resolve(String(a).trim());
      painted.push({ ...r, fn, line: site(m) });
    }
  }
  for (const m of src.matchAll(/ObjectCreate\s*\(\s*[^,]+,\s*([^,]+),/g)) {
    painted.push({ ...resolve(m[1].trim()), fn: 'ObjectCreate', line: site(m) });
  }
  //--- `ObjectDelete(0, DrawStripFootSkinName(fd))` — the name's own arguments carry
  //--- parens, so the name is taken by scanning to the BALANCED close, never by `[^)]+`.
  for (const m of src.matchAll(/Object(?:Delete|Find)\s*\(/g)) {
    let i = m.index + m[0].length, depth = 1, inStr = false, comma = -1;
    for (; i < src.length && depth > 0; i++) {
      const c = src[i];
      if (inStr) { if (c === '\\') i++; else if (c === '"') inStr = false; continue; }
      if (c === '"') { inStr = true; continue; }
      if (c === '(') depth++;
      if (c === ')') depth--;
      if (c === ',' && depth === 1 && comma < 0) comma = i;
    }
    if (comma < 0) continue;
    const arg = src.slice(comma + 1, i - 1).trim();
    //--- AN INDEXED PRUNE LIST IS A DESTROY SITE FOR EVERY NAME IT HOLDS.
    //--- `DrawStripPopChromePrune` writes `fx[2] = DrawStripPHeadGName(); …` and then
    //--- loops `ObjectDelete(0, fx[i])`, so the argument here is an INDEX and the
    //--- families it really takes down are the ELEMENTS. Without this the board's
    //--- whole chrome read as `unattended (no readable destroy — NOT checked)` and
    //--- eight painted names were a proof hole the gate called a pass.
    const idx = arg.match(/^(\w+)\s*\[/);
    if (idx && elements.has(idx[1])) {
      for (const e of elements.get(idx[1])) deleted.push({ ...resolve(e), line: site(m) });
      continue;
    }
    deleted.push({ ...resolve(arg), line: site(m) });
  }
  const prefixes = [];
  for (const m of src.matchAll(/ObjectsDeleteAll\s*\(\s*[^,]+,\s*"([^"]+)"/g)) prefixes.push(m[1]);
  return { file, painted, deleted, prefixes, defs };
}

//--- the attach reset: a prefix that is a prefix of EVERY family proves no family's own
//--- destroy, so it is not counted as coverage.
const ledger = FILES.map(analyze);
const allHeads = ledger.flatMap((f) => f.painted.filter((p) => p.key).map((p) => p.lit ?? ''));
const resetPrefix = (() => {
  const cands = [...new Set(ledger.flatMap((f) => f.prefixes))].filter(Boolean);
  return cands.filter((p) => allHeads.length > 0 && allHeads.every((h) => h.startsWith(p)));
})();

//--- THE VERDICT IS PER FAMILY, AND ONLY FOR A FAMILY THE TOOL CAN READ BOTH HALVES OF.
//--- A family with no resolvable destroy at all (a name held in an array, a prefix built
//--- from a settings string) is NOT a proven gap — it is unreadable, and guessing there
//--- is how a gate starts crying wolf. Such families are REPORTED as unattended, never
//--- failed; a family whose destroy IS readable must cover every suffix it paints.
let paintN = 0, delN = 0, unresolved = 0;
const missing = [];
if (process.env.LIFECYCLE_DEBUG) {
  const un = ledger.flatMap((f) => f.painted.filter((p) => !p.key || !(p.lit ?? '').length)
    .map((p) => `${f.file}:${p.line} ${p.fn} arg=${p.raw}`));
  console.log(`[debug] unresolvable paint sites: ${un.length}`);
  for (const u of un.slice(0, Number(process.env.LIFECYCLE_DEBUG) || 30)) console.log('  ' + u);
  console.log('[debug] readable paint sites:');
  for (const f of ledger)
    for (const p of f.painted)
      if (p.key && (p.lit ?? '').length)
        console.log(`  ${f.file}:${p.line} ${p.fn} ${p.key} lit=${p.lit} suf="${p.suffix}"`);
}
const fam = new Map();                       // key -> { lit, painted:[], deleted:Set }
for (const f of ledger) {
  const own = (key) => {
    if (!fam.has(key)) fam.set(key, { lit: '', painted: [], deleted: new Set(), prefixes: new Set() });
    return fam.get(key);
  };
  for (const p of f.painted) {
    if (!p.key || !(p.lit ?? '').length) { unresolved++; continue; }
    paintN++;
    const F = own(p.key);
    F.lit = F.lit || p.lit;
    F.painted.push({ ...p, file: f.file });
  }
  for (const d of f.deleted) {
    if (!d.key) continue;
    delN++;
    own(d.key).deleted.add(d.suffix ?? '');
  }
  for (const pre of f.prefixes)
    for (const F of fam.values()) F.prefixes.add(pre);
}
//--- A PREFIX IS COVERAGE ONLY WHEN IT NAMES ONE FAMILY. `PnlDrawS_G` (the panel's own
//--- purge) and `PnlDrawS_` (the attach reset) each sweep MANY families, so neither can
//--- answer "does THIS family take its own names away" — and one of them answering yes is
//--- how the P-DRAW-84 class hides. A family-specific prefix (`Pool_`, a bake's own
//--- spelling) still counts.
const bulk = new Set();
for (const pre of new Set(ledger.flatMap((f) => f.prefixes))) {
  const hit = [...fam.values()].filter((F) => F.lit && F.lit.startsWith(pre)).length;
  if (hit !== 1 || resetPrefix.includes(pre) || pre.length === 0) bulk.add(pre);
}
for (const [key, F] of fam) {
  if (F.deleted.size === 0) continue;                    // unattended: nothing to compare
  for (const p of F.painted) {
    if (F.deleted.has(p.suffix ?? '')) continue;
    if ([...F.prefixes].some((pre) => !bulk.has(pre) && F.lit.startsWith(pre))) continue;
    missing.push({ file: p.file, line: p.line, fn: p.fn, name: `${F.lit}…"${p.suffix}"`, family: key });
  }
}
const unattended = [...fam.entries()].filter(([, F]) => F.deleted.size === 0);

//--- P-DRAW-122 (2026-10-01): THE SECOND LAW — A PAINTED LAYER IS RE-ASSERTED EVERY
//--- PASS. A painter that CREATES an object and writes its layer (`OBJPROP_ZORDER`,
//--- `OBJPROP_BACK`) inside its `ObjectFind(0, nm) < 0` birth block must re-assert that
//--- layer outside it. P-DRAW-120 stated the law and healed the three painters a shot
//--- convicted (the buttons already complied; the face and the label were made to), and
//--- left five, because the heal was applied to the SITES, not to the RULE: the rect,
//--- the gear edit field, the board's hex field, the skin's underlayer and the strip's
//--- flat plate. Equal z is settled by CREATION ORDER, so an object that survives a
//--- reattach keeps the rung it was born with — the census reads it at its seat with
//--- its ink while it paints UNDER the plate, which is the report («متن‌ها ناقص است»,
//--- 2026-10-01) as a paint order and not as a missing object. A sixth site lived in
//--- the TH3 pattern renderer (an ABCD point: MOVED every pass, its rung written once).
//--- THE SET IS DERIVED, never listed: the check is per painter, in every file, so the
//--- next one is covered the day it is written — which is the difference between a law
//--- and a to-do list. COST: one regex pass over the tree per build, in the pass this
//--- gate already makes.
function functionsOf(src) {
  const out = [];
  const rx = /(?:^|[\r\n])[ \t]*(?:bool|void|int|string|double|long|color)\s+(\w+)\s*\(/g;
  let m;
  while ((m = rx.exec(src))) {
    const ob = src.indexOf('{', m.index);
    if (ob < 0) { rx.lastIndex = m.index + m[0].length; continue; }
    let depth = 0, end = -1;
    for (let i = ob; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end < 0) { rx.lastIndex = m.index + m[0].length; continue; }
    out.push({
      name: m[1],
      line: 1 + (src.slice(0, m.index).match(/\n/g) || []).length,
      body: src.slice(ob + 1, end),
    });
    rx.lastIndex = end;
  }
  return out;
}
const layerOk = [];
const layerOnlyBirth = [];
for (const file of FILES) {
  const src = stripComments(readFileSync(file, 'utf8'));
  for (const fn of functionsOf(src)) {
    if (!fn.body.includes('ObjectCreate')) continue;
    const guard = /if\s*\(\s*ObjectFind\s*\(\s*0\s*,\s*(\w+)\s*\)\s*<\s*0\s*\)/.exec(fn.body);
    if (!guard) continue;
    const nm = guard[1];
    const ob = fn.body.indexOf('{', guard.index);
    if (ob < 0) continue;
    let depth = 0, end = -1;
    for (let i = ob; i < fn.body.length; i++) {
      if (fn.body[i] === '{') depth++;
      else if (fn.body[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end < 0) continue;
    // TIGHT, so the gate cannot cry wolf: the SAME object must be created in that block
    // and ITS layer written there (a painter can own several objects and several guards).
    const birth = fn.body.slice(ob, end + 1);
    if (!new RegExp(`ObjectCreate\\s*\\(\\s*0\\s*,\\s*${nm}\\s*,`).test(birth)) continue;
    if (!new RegExp(`ObjectSetInteger\\s*\\(\\s*0\\s*,\\s*${nm}\\s*,\\s*OBJPROP_(ZORDER|BACK)`).test(birth)) continue;
    const tail = fn.body.slice(end + 1);
    const re = new RegExp(`(DrawStripSetInt|ObjectSetInteger)\\s*\\(\\s*(0\\s*,\\s*)?${nm}\\s*,\\s*OBJPROP_(ZORDER|BACK)`);
    if (re.test(tail)) layerOk.push(`${fn.name} (${file}:${fn.line})`);
    else layerOnlyBirth.push({ file, line: fn.line, fn: fn.name, name: nm });
  }
}

const show = (p) => `${p.file}:${p.line}`;
console.log('==================================================================');
console.log('OBJECT LIFECYCLE GATE  (Biotak/**/*.mqh)');
console.log('==================================================================');
const defSites = ledger.reduce((n, f) => n + (f.defs ?? 0), 0);
console.log(`  files: ${ledger.length}  name helpers: ${HELPERS.size}  painted names: ${paintN} ` +
  `(${unresolved} not resolvable, skipped; ${defSites} definition site(s) ignored)`);
console.log(`  delete sites: ${delN}  families read: ${fam.size}  unattended: ${unattended.length}`);
if (unattended.length) {
  const names = unattended.map(([k, F]) => `${k}~${F.lit || '?'}(${F.painted.length})`);
  console.log(`  unattended (no readable destroy — NOT checked): ${names.slice(0, 12).join(' ')}${names.length > 12 ? ' …' : ''}`);
}
const prefixes = [...new Set(ledger.flatMap((f) => f.prefixes))];
console.log(`  family prefixes: ${prefixes.join(' ') || '(none)'}` +
  (bulk.size ? `   (bulk, not coverage: ${[...bulk].join(' ')})` : ''));
if (resetPrefix.length) console.log(`  attach reset ignored as coverage: ${resetPrefix.join(' ')}`);
console.log(`  layers: ${layerOk.length} painter(s) re-assert OBJPROP_ZORDER/BACK every pass, ` +
  `${layerOnlyBirth.length} write the layer only at birth (P-DRAW-122)`);
if (layerOnlyBirth.length) {
  console.log('');
  for (const p of layerOnlyBirth)
    console.log(`  [FAIL] ${show(p)}  ${p.fn} writes OBJPROP_ZORDER/BACK for \`${p.name}\` only inside its birth block — a surviving object keeps its old rung and paints under the plate (P-DRAW-122)`);
  console.log('');
  console.log(`FAIL: ${layerOnlyBirth.length} painter(s) do not re-assert their layer.`);
  process.exit(1);
}
if (missing.length) {
  console.log('');
  for (const p of missing.slice(0, 40))
    console.log(`  [FAIL] ${show(p)}  ${p.fn} paints ${p.name}  (family ${p.family}) — no destroy path`);
  if (missing.length > 40) console.log(`  … ${missing.length - 40} more`);
  console.log('');
  console.log(`FAIL: ${missing.length} painted name(s) with no delete.`);
  process.exit(1);
}
console.log('');
console.log(`PASS — every painted name in ${ledger.length} file(s) has a destroy path, and ` +
  `every layered painter re-asserts its rung (${layerOk.length} of them, P-DRAW-122).`);
