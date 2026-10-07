// Biotak Trigger TH3 - TradingView build core.
//
// Pine has no #include, so the build IS the include system: it reads the module
// headers, resolves the graph from an entry, drops the directives, and emits one
// file with exactly one //@version and one declaration.
//
// The three rules this file exists to enforce, all carried from the MQL4 build:
//   1. entries stay thin;
//   2. include ORDER is ownership - Pine resolves top-down, so a module is
//      emitted before anything that reads it;
//   3. a constant has ONE owner, and the declaration reads it through a build-time
//      placeholder ({TH3_MAX_LINES}) because Pine's indicator() call is the first
//      statement and cannot see a name a later module defines.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const ROOT = path.resolve(import.meta.dirname, '..', '..');
export const SRC = path.join(ROOT, 'src');
export const DIST = path.join(ROOT, 'dist');
export const BUILD = path.join(ROOT, 'build');

const DIRECTIVE = /^\/\/@([a-zA-Z]+)\s*(.*?)\s*$/;
const DECLEND = /^\/\/@declend\s*$/;
const CONST = /^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.+?)\s*$/;

export const ENTRY_DIR = path.join(SRC, 'entry');

export function readSource(rel) {
  const abs = path.join(SRC, rel);
  if (!fs.existsSync(abs)) return null;
  return fs.readFileSync(abs, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
}

export function listEntries() {
  return fs.readdirSync(ENTRY_DIR).filter((f) => f.endsWith('.pine')).sort().map((f) => `entry/${f}`);
}

export function listModules() {
  const out = [];
  const walk = (dir, prefix) => {
    for (const name of fs.readdirSync(dir).sort()) {
      const abs = path.join(dir, name);
      const rel = prefix ? `${prefix}/${name}` : name;
      if (fs.statSync(abs).isDirectory()) {
        if (name === 'entry') continue;
        walk(abs, rel);
      } else if (name.endsWith('.pine')) {
        out.push(rel);
      }
    }
  };
  walk(SRC, '');
  return out;
}

export function parseModule(rel) {
  const text = readSource(rel);
  if (text === null) throw new Error(`module not found: src/${rel}`);
  const lines = text.split('\n');
  const mod = {
    file: rel,
    id: null,
    owner: null,
    includes: [],
    entry: null,
    output: null,
    declare: [],
    body: [],
    header: [],
    unknown: [],
    lines,
  };
  let i = 0;
  while (i < lines.length) {
    if (lines[i].trim() === '' && mod.header.length === 0) { i++; continue; }
    const m = DIRECTIVE.exec(lines[i]);
    if (!m) break;
    const key = m[1].toLowerCase();
    const val = m[2];
    mod.header.push(lines[i]);
    i++;
    if (key === 'declare') {
      while (i < lines.length && !DECLEND.test(lines[i])) { mod.declare.push(lines[i]); i++; }
      if (i < lines.length) { mod.header.push(lines[i]); i++; }
      continue;
    }
    if (key === 'module') mod.id = val;
    else if (key === 'owner') mod.owner = val;
    else if (key === 'includes') mod.includes = val.split(',').map((s) => s.trim()).filter(Boolean);
    else if (key === 'entry') mod.entry = val;
    else if (key === 'output') mod.output = val;
    else mod.unknown.push(key);
  }
  mod.body = lines.slice(i);
  while (mod.body.length && mod.body[mod.body.length - 1].trim() === '') mod.body.pop();
  return mod;
}

// Resolve any file (entry OR plain module) into its dependency chain, dependencies
// first and each file once. `order` INCLUDES the file that was asked for, which is
// what a harness wants when it is assembling a probe out of a module.
export function resolveChain(rootRel) {
  const order = [];
  const seen = new Set();
  const stack = [];
  const cycles = [];
  const missing = [];

  const walk = (rel) => {
    if (stack.includes(rel)) {
      cycles.push([...stack.slice(stack.indexOf(rel)), rel].join(' -> '));
      return;
    }
    if (seen.has(rel)) return;
    const mod = parseModule(rel);
    for (const inc of mod.includes) {
      if (!fs.existsSync(path.join(SRC, inc))) missing.push(`${rel} -> ${inc}`);
    }
    seen.add(rel);
    stack.push(rel);
    for (const inc of mod.includes) walk(inc);
    stack.pop();
    order.push(mod);
  };

  walk(rootRel);
  return { root: parseModule(rootRel), order, cycles, missing };
}

// Resolve an entry: same chain, minus the entry's own body (it carries no logic).
export function resolveEntry(entryRel) {
  const { root, order, cycles, missing } = resolveChain(entryRel);
  return {
    entry: root,
    modules: order.filter((m) => m.file !== entryRel),
    all: order,
    cycles,
    missing,
  };
}

// Every ALL_CAPS_NAME = value in the emitted modules. One owner per name.
export function collectConstants(modules) {
  const owners = new Map();
  for (const m of modules) {
    for (const line of m.body) {
      const mm = CONST.exec(line);
      if (!mm) continue;
      const name = mm[1];
      if (!owners.has(name)) owners.set(name, { value: mm[2], file: m.file, line });
    }
  }
  return owners;
}

export function render({ entry, modules, extraBody = [], provenance = true }) {
  const consts = collectConstants(modules);
  const declared = entry.declare.join('\n').replace(/\{([A-Z][A-Z0-9_]*)\}/g, (whole, name) => {
    const hit = consts.get(name);
    if (!hit) throw new Error(`src/${entry.file}: placeholder ${whole} has no owner among the emitted modules`);
    return hit.value;
  });

  const declLines = declared.split('\n').filter((l) => l.trim() !== '');
  const versionLine = declLines.find((l) => l.startsWith('//@version')) ?? '//@version=6';
  const declRest = declLines.filter((l) => !l.startsWith('//@version'));

  const hash = crypto
    .createHash('sha256')
    .update(modules.map((m) => `== ${m.file}\n${m.body.join('\n')}`).join('\n'))
    .digest('hex')
    .slice(0, 12);

  const out = [versionLine.trim()];
  if (provenance) {
    out.push('// ' + '='.repeat(76));
    out.push('// Biotak Trigger TH3 for TradingView - GENERATED by tools/build.js. DO NOT EDIT.');
    out.push(`// entry src/${entry.file}   modules ${modules.length}   body sha256 ${hash}`);
    out.push('// edit src/*.pine and run:  npm run build');
    out.push('// ' + '='.repeat(76));
  }
  out.push(...declRest, '');
  for (const m of modules) {
    out.push('// ' + '-'.repeat(74));
    out.push(`// module ${m.id}   src/${m.file}`);
    out.push(`// owner  ${m.owner}`);
    out.push('// ' + '-'.repeat(74));
    out.push(...m.body, '');
  }
  if (extraBody.length) out.push(...extraBody, '');

  let text = out.join('\n');
  if (!text.endsWith('\n')) text += '\n';
  return { text, hash, consts };
}

export function writeDist(name, text) {
  fs.mkdirSync(DIST, { recursive: true });
  const abs = path.join(DIST, name);
  const before = fs.existsSync(abs) ? { bytes: fs.statSync(abs).size, mtime: fs.statSync(abs).mtime } : null;
  const same = before && fs.readFileSync(abs, 'utf8') === text;
  if (!same) fs.writeFileSync(abs, text, 'utf8');
  const after = fs.statSync(abs);
  return { path: abs, rel: path.relative(ROOT, abs), before, after, rewritten: !same };
}
