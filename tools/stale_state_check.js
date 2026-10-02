// stale_state_check.js — a per-pass value must be WRITTEN before it is READ.
//
// WHY. P-DRAW-91 (2026-09-30). `s_dsGearW` — the settings panel's column width —
// is derived fresh on every layout pass, because it is 312 on one tab and 624 on
// another. Its only reset stood inside `DrawStripGearPlace`, which the layout pass
// calls AFTER the content pass. So the content measured its hex fields against the
// PREVIOUS tab's width: a 592-wide field inside a 312 plate, two dark bars 312px
// past the card, and a term full of "why does it fall apart when I switch tabs".
// The bug is an ORDER, not a number — which is why it survived every gate: the
// compiler resolves the name, the geometry gate reads the arithmetic, and both are
// right. Only the RUN ORDER of one pass can see it.
//
// THE RULE. For every `static` in the strip's own files, and for each layout pass
// that derives state, find the first write and the first read IN RUN ORDER (the
// pass body, with calls to functions of the same family expanded in place). If a
// read comes first and a write exists later in the same pass, the reader used the
// previous pass's value. That is the defect, and this gate fails on it by file and
// line.
//
// WHAT IT DOES NOT DO. It does not model branches: a write inside an `if` counts as
// a write wherever it sits. That is the SAFE direction — a pass whose write is real
// only on some branch is reported, never silently accepted — and it is why the gate
// reads a pass as one straight line.
//
// AND IT DOES NOT REPORT THE SELF-MANAGED IDIOM (2026-09-30, its second reader). A
// name a pass both READS and WRITES inside the SAME function is that function's own
// state machine: an idempotent guard (`if(s_dsVisInit) return; s_dsVisInit = true;`),
// a compare-and-store (`if(cell == s_dsPalCell) return; … s_dsPalCell = cell;`) or a
// save-then-clear (`int old = s_dsColorHoverCell; s_dsColorHoverCell = -1;`). Those
// four names were the gate's first run's false positives — a guard is not a reader of
// the previous pass — and they are PRINTED as `self-managed`, never dropped: the
// defect class this gate exists for is a CROSS-function read (a reader that never
// writes the name and runs before the pass derived it, e.g. P-DRAW-93's board
// placement reading `s_dsW`/`s_dsGearW0` from the pass before it).
//
// COST. Line and regex reads of `Biotak/DrawStrip_*.mqh`, once per build. No C
// grammar, no evaluation. Calls it cannot place (a function outside the family) end
// the walk of that line and are counted, never guessed at.
//
// Run: node tools/stale_state_check.js [root]
import { readFileSync, readdirSync } from 'node:fs';

const root = process.argv[2] ?? '.';

function files(dir) {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) continue;
    if (/^DrawStrip.*\.mqh$/.test(e.name)) out.push(`${dir}/${e.name}`);
  }
  return out.sort();
}

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

//--- every function of the family, as its body's lines with unit line numbers.
const SRC = new Map();
const FNS = new Map();           // name -> { file, line, body: [{line, text}] }
for (const f of files(`${root}/Biotak`)) {
  const text = stripComments(readFileSync(f, 'utf8'));
  SRC.set(f, text.split('\n'));
  const lines = SRC.get(f);
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*(?:void|int|bool|string|double|color|long|uint)\s+(\w+)\s*\(/);
    if (!m) continue;
    //--- THE BODY IS THE BRACES, NOT "until the next line that starts with }".
    //--- A one-line definition (`string DrawStripFootName(const int f) { return …; }`)
    //--- has its `}` on the SAME line, so the naive walk swallowed every function
    //--- after it and the pass expansion grew to 1954 statements — most of them the
    //--- paint, the hit tests and the teardowns, read as if the layout called them.
    //--- Measured: that false model reported 10 problems, 9 of them cross-function
    //--- reads of state the layout never touches.
    const body = [];
    let depth = 0, opened = false;
    for (let j = i; j < lines.length; j++) {
      const text = lines[j];
      if (j > i) body.push({ line: j + 1, text });
      for (const ch of text) {
        if (ch === '{') { depth++; opened = true; }
        else if (ch === '}') depth--;
      }
      if (opened && depth <= 0) break;
    }
    FNS.set(m[1], { file: f, line: i + 1, body });
  }
}

//--- the passes that DERIVE state. Each is read as one straight line, with calls
//--- to the family's own functions expanded in place (depth-bounded, no recursion).
const PASSES = ['DrawStripLayout', 'DrawStripGearLayout'];
const isWrite = (text, name) =>
  new RegExp(`\\b${name}\\s*(?:\\[[^\\]]*\\])?\\s*=(?!=)`).test(text);
const isRead = (text, name) =>
  new RegExp(`\\b${name}\\b`).test(text) && !isWrite(text, name);

//--- A READ THAT IS ONLY A GUARD CONDITION IS NOT A DERIVED NUMBER. `if(s_dsGear != 0)`
//--- asks the open/dismiss state the TAP owns — the pass's own later write (a tab
//--- validation inside DrawStripGearTabs) is not what that branch read. The gate reads
//--- NUMBERS: a name consumed into an assignment/argument is geometry, and that is the
//--- class P-DRAW-93's board placement belonged to. A guard-only use is counted and
//--- printed, never silently dropped.
function isGuardOnlyRead(text, name) {
  const m = text.match(/^\s*(?:else\s+)?(if|while)\s*\(/);
  if (!m) return false;
  let i = text.indexOf('(', m.index), depth = 0, end = -1;
  for (; i < text.length; i++) {
    if (text[i] === '(') depth++;
    else if (text[i] === ')') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (end < 0) return false;
  const re = new RegExp(`\\b${name}\\b`);
  return re.test(text.slice(0, end + 1)) && !re.test(text.slice(end + 1));
}

function flatten(fnName, depth = 0, seen = new Set()) {
  const fn = FNS.get(fnName);
  if (!fn || depth > 3 || seen.has(fnName)) return [];
  seen.add(fnName);
  const out = [];
  for (const { line, text } of fn.body) {
    out.push({ fn: fnName, file: fn.file, line, text });
    //--- EVERY call on the line is expanded, not just the first: `if(Kind(slot))
    //--- DrawStripBoardPlace();` is TWO calls, and expanding only the first hid the
    //--- second one's reads entirely (measured 2026-09-30: the move of the board's
    //--- placement to the layout's tail lost 77 statements from the walk — the gate
    //--- would have passed for the one reason it exists to catch).
    for (const c of text.matchAll(/\b(\w+)\s*\(/g)) {
      if (FNS.has(c[1]) && c[1] !== fnName) {
        out.push(...flatten(c[1], depth + 1, new Set(seen)));
      }
    }
  }
  return out;
}

//--- every mutable static the family owns. `static int s_dsX = 0;` and arrays.
const STATICS = [];
for (const [f, lines] of SRC) {
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*static\s+[\w]+\s+(s_\w+)\s*(?:\[[^\]]*\])?\s*(?:=[^;]*)?;/);
    if (m) STATICS.push({ file: f, line: i + 1, name: m[1] });
  }
}

//--- P-DRAW-118 (2026-10-01) — THE HOVER'S OWN RESTORE IS NOT A STALE DERIVATION.
//--- `DrawStripColorHoverFace` / `DrawStripColorHoverValue` put BACK the rim of the
//--- cell the pointer just left, or preview the colour under it: the value they need
//--- is the seat the LAST pass painted — the pixel the user is looking at — and the
//--- hover runs BETWEEN passes, so no pass has derived anything for that frame yet.
//--- That is the opposite of the defect this gate hunts (a layout reader that could
//--- not see the number this pass derives). Exempted for the SEAT arrays only, and
//--- printed in its own bucket: any other name read there still fails.
const HOVER_OWNERS = new Set(['DrawStripColorHoverFace', 'DrawStripColorHoverValue']);
const isHoverSeat = (name) =>
  /^s_dsGG(W|H|X|Y|Kind|Slot|Arg)$/.test(name) || name === 's_dsGGC' ||
  /^s_ds(PN|Recent|PalCell|ColorHoverCell)$/.test(name);

const problems = [];
const selfManaged = [];
const guardReads = [];
const hoverReads = [];
const walks = [];
for (const pass of PASSES) {
  const order = flatten(pass);
  if (!order.length) continue;
  walks.push(`${pass} (${order.length} statements)`);
  for (const st of STATICS) {
    let firstWrite = -1, firstRead = -1;
    for (let i = 0; i < order.length; i++) {
      const { text } = order[i];
      if (firstWrite < 0 && isWrite(text, st.name)) firstWrite = i;
      if (firstRead < 0 && isRead(text, st.name)) firstRead = i;
      if (firstWrite >= 0 && firstRead >= 0) break;
    }
    //--- a static the pass never writes is state that OUTLIVES the pass by design
    //--- (the strip's served object, the open tab). Not this gate's business.
    if (firstWrite < 0 || firstRead < 0) continue;
    if (firstRead < firstWrite) {
      const read = order[firstRead], write = order[firstWrite];
      //--- THE SELF-MANAGED IDIOM IS NOT THIS GATE'S QUESTION. A name a pass both
      //--- READS and WRITES inside the SAME function is that function's own state
      //--- machine — an idempotent guard (`if(s_dsVisInit) return; s_dsVisInit = true;`),
      //--- a compare-and-store (`if(cell == s_dsPalCell) return; … s_dsPalCell = cell;`)
      //--- or a save-then-clear (`int old = s_dsColorHoverCell; s_dsColorHoverCell = -1;`).
      //--- The read is the POINT of the write, so "it used the previous pass's value"
      //--- is not a defect there — it is the last frame of a fact this function owns.
      //--- The line the gate exists for is a CROSS-function read: a reader that never
      //--- writes the name and runs before the pass derived it. Reported here as a
      //--- count, never hidden — a name may not leave this list silently.
      if (read.fn === write.fn) {
        selfManaged.push({ pass, name: st.name, at: read, fn: read.fn });
        continue;
      }
      if (isGuardOnlyRead(read.text, st.name)) {
        guardReads.push({ pass, name: st.name, at: read, write });
        continue;
      }
      if (HOVER_OWNERS.has(read.fn) && isHoverSeat(st.name)) {
        hoverReads.push({ pass, name: st.name, at: read, write });
        continue;
      }
      problems.push({
        pass, name: st.name,
        read, write,
        decl: st,
      });
    }
  }
}

console.log('==================================================================');
console.log('STALE STATE GATE  (a per-pass value must be written before it is read)');
console.log('==================================================================');
console.log(`  files: ${SRC.size}  functions: ${FNS.size}  statics: ${STATICS.length}`);
console.log(`  passes walked: ${walks.join(' · ')}`);
if (selfManaged.length) {
  console.log(`  self-managed (read and written in ONE function — that function's own\n` +
              `  guard/compare-and-store, not a reader of the previous pass):`);
  for (const s of selfManaged)
    console.log(`    · ${s.name} — ${s.fn}() at ${s.at.file}:${s.at.line}`);
}if (guardReads.length) {
  console.log(`  guard-only reads (a branch condition asking state OUTSIDE this pass —\n` +
              `  reported for the record, not a stale derivation):`);
  for (const g of guardReads)
    console.log(`    · ${g.name} — ${g.at.file}:${g.at.line} (later written at ${g.write.file}:${g.write.line})`);
}
if (hoverReads.length) {
  console.log(`  hover restores (the pointer's own frame: the seat the LAST pass\n` +
              `  painted is the pixel on screen — the hover runs between passes):`);
  for (const h of hoverReads)
    console.log(`    · ${h.name} — ${h.at.fn}() at ${h.at.file}:${h.at.line} (this pass writes it at ${h.write.file}:${h.write.line})`);
}
if (problems.length) {
  console.log('');
  for (const p of problems) {
    console.log(`  [FAIL] ${p.name} is READ at ${p.read.file}:${p.read.line}` +
      ` but its first WRITE in ${p.pass} is at ${p.write.file}:${p.write.line}` +
      ` — the reader used the PREVIOUS pass's value`);
  }
  console.log('');
  console.log(`FAIL: ${problems.length} per-pass value(s) read before they are written.`);
  process.exit(1);
}
console.log('');
console.log('PASS — every per-pass value these passes derive is written before it is read.');
