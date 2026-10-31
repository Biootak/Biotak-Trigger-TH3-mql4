// mask_owner_check.js — ONE PROPERTY, ONE OWNER: every unmask must know the mute.
//
// WHY. P-HTF-AUDIT-4 / P-UI-194b (2026-10-31). The user's report was
// «کندل‌های تایم بالا ... میاد در صورتی که خاموش بودشه»: the HTF overlay came back
// with its switch OFF. The switch was not broken and no flag was stale — the
// F-SHOW walk (`VisibilityShowAllCached`) wrote `OBJ_ALL_PERIODS` over every rect
// in the object cache, and the overlay's own rects are in that cache. The overlay
// has a MASK COMPOSER (`HTFBoxMask`) that folds the switch AND the mute; a generic
// walk that knows neither overruled it. Same week, same shape, second find: the L
// hotkey's walk (`SetAllLineObjectsVisibility`) was the only family writer that did
// not fold `IsIndicatorHidden()` either, so L on a muted chart flashed the whole
// level family across a chart the user had muted.
//
// The class is not "HTF". It is: A DERIVED PROPERTY WITH MORE THAN ONE WRITER, one
// of which does not know all of the property's inputs. In this tree the property is
// `OBJPROP_TIMEFRAMES` — 135 raw writes across 22 files — and its inputs are the
// family switch, the F mute, the line switch, the panel cull and the chart's own
// per-TF rule. A writer that reads one input and writes the property is a candidate
// second owner, and the compiler cannot see it: the name resolves, the write lands,
// and only the PICTURE is wrong.
//
// THE RULE. A function that writes `OBJPROP_TIMEFRAMES = OBJ_ALL_PERIODS` must
// either consult the mute (directly, or through a composer/guard that does) or be
// listed in ALLOW with the reason it is safe. The second rule covers the memo that
// caches such a write: a `static bool s_last…` early-return must key on the same
// terms the mask is built from — a key narrower than the value is how P-UI-194b's
// own fix re-introduced the defect one line below itself.
//
// WHAT IT DOES NOT DO. It does not model branches, and it does not know that a
// function is only ever called from the show path — that is exactly what ALLOW is
// for, and it is the reason each entry carries a sentence instead of a filename.
//
// COST. Line and regex reads of Biotak/**/*.mqh, once per build. No MQL grammar.
//
// Run: node tools/mask_owner_check.js [root]

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2] || path.join(__dirname, '..');
const SRC = path.join(ROOT, 'Biotak');

//--- A writer is MUTE-AWARE when its body names one of these. Each is a door that
//--- already folds `IsIndicatorHidden()` (or is the guarded writer that remembers
//--- what it wrote): the family composers, the zone mask, the HTF composer, the
//--- two F walks, and the countdown's own predicate.
const AWARE = [
  'IsIndicatorHidden',            // the mute itself
  'ApplyTfMaskGuarded',          // the P-PERF-02 guard (its callers fold the mute)
  'VisibilityZoneMask',          // the zone composer
  'HTFBoxMask',                  // the HTF composer
  'VisibilityIsHTFName',         // the F-show walk's skip (the HTF composer decides)
  'VisibilityShowAllCached',     // the show walk (decides per family)
  'SetPipelineObjectTimeframesIfExists', // the guarded zone/trigger writer
  'PnlMuteGatedValue',           // the panel's displayed fold
  'LiveCountdownEnabled',        // the countdown's own switch (folds the mute)
];

//--- Every entry is a REASON, not a permission. A new blind writer must either fold
//--- the mute or add a sentence here saying why the picture cannot be wrong.
const ALLOW = {
  'EventHandlers_CustomPrice.mqh:ShowAllDrawingFamilies':
    'the SHOW half of the F cycle — ApplyHideAllState calls it only after SetIndicatorHiddenState(false)',
  'HRayTool.mqh:HRayShowAll': 'reached only from ShowAllDrawingFamilies (the show branch)',
  'PathTool.mqh:PathShowAll': 'reached only from ShowAllDrawingFamilies (the show branch)',
  'TH3Tool_Mute.mqh:TH3PatternsShowAll': 'reached only from ShowAllDrawingFamilies (the show branch)',
  'TH3Tool_Mute.mqh:LegMeasureShowAll': 'reached only from ShowAllDrawingFamilies (the show branch)',
  'BoxPreview.mqh:BoxPreviewEnd': 'a drag PREVIEW: the object exists only for the gesture that owns it',
  'FibPen.mqh:FibPenPreviewEnd': 'a drag PREVIEW: the object exists only for the gesture that owns it',
  'PenStack.mqh:PenStackPreviewEnd': 'a drag PREVIEW: the object exists only for the gesture that owns it',
  'TH3Tool_A.mqh:SetActiveABCDPattern': 'the ABCD editor is cancelled by the hide pass (TH3SessionCancel), so it cannot be live while muted',
  //--- The TH3 caption family learned THIS lesson on 2026-10-16 (P-UI-160b) and
  //--- guards its ENTRIES, not its leaves: every path into these four returns at
  //--- the top when IsIndicatorHidden(). The invariant is real; it just lives one
  //--- call up, which this gate cannot see. If a new caller appears, it must carry
  //--- the same guard — the reason string names the three that have it.
  'TH3/TH3Renderer_A.mqh:TH3InfoFamilySetVisible':
    'callers are SetActiveABCDPattern (guarded TH3Tool_A:205) and TH3PatternsHideAll (the hide half)',
  'TH3/TH3Renderer_A.mqh:TH3InfoFamilyPlateGrow':
    'reached only from TH3InfoFamilySetVisible/Draw, both under those guarded entries',
  'TH3/TH3Renderer_A.mqh:TH3InfoFamilyVerify':
    'callers are RepositionABCDInfoLabels (guarded TH3Tool_A:205) and the 250 ms heal (guarded TH3Renderer_A:1015)',
  'TH3/TH3Renderer_A.mqh:TH3InfoFamilyDraw':
    'its only caller is DrawABCDPattern, which returns at TH3Renderer_B:12 when muted',
  'ExtDraw_B.mqh:DrawFactorLevelsAligned':
    'dead code — no callers (its own NOTE at ExtDraw_B:755); revive it must fold the mute first',
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

// Strip // and /* */ so a comment that MENTIONS a term cannot make a writer "aware".
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
    if (c === '"' || c === "'") {           // keep string literals opaque
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

// name(args) { … } — a definition, not a call (a call is followed by `;` or `,`).
const DEF = /([A-Za-z_]\w*)\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)\s*\{/g;

function functions(src) {
  const fns = [];
  DEF.lastIndex = 0;
  let m;
  while ((m = DEF.exec(src)) !== null) {
    const name = m[1];
    if (CONTROL.has(name)) continue;
    const head = src.slice(Math.max(0, m.index - 40), m.index).trim();
    if (head.endsWith('#')) continue;                       // a #define body
    const open = m.index + m[0].length - 1;
    let depth = 0, end = -1;
    for (let i = open; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end < 0) continue;
    fns.push({ name, start: m.index, body: src.slice(open, end + 1), line: lineOf(src, m.index) });
    DEF.lastIndex = end;                                    // do not re-scan a body
  }
  return fns;
}

const files = walk(SRC, []).sort();
const violations = [];
const memoViolations = [];
let scanned = 0, unmaskers = 0;

for (const file of files) {
  const rel = path.relative(SRC, file).split(path.sep).join('/');   // "TH3/TH3Renderer_A.mqh"
  const src = stripComments(fs.readFileSync(file, 'utf8'));
  for (const fn of functions(src)) {
    scanned++;
    //--- A WRITER, not a reader: `TH3InfoRowsLit` compares against OBJ_ALL_PERIODS
    //--- to answer "are the rows lit?" and must not be asked to justify itself.
    const writesMask = fn.body.includes('OBJPROP_TIMEFRAMES') && fn.body.includes('ObjectSetInteger');
    if (!writesMask) continue;

    //--- "Can this function put an ALL_PERIODS mask on something?" — the literal
    //--- may sit in a local (`long tf = visible ? OBJ_ALL_PERIODS : …`) rather than
    //--- in the write itself, which is exactly how the L-key writer is spelled. A
    //--- function that only COMPARES against it lands here too: that is the safe
    //--- direction (it is asked to justify itself), and no such case exists today.
    const unmask = fn.body.includes('OBJ_ALL_PERIODS');
    const aware = AWARE.some((t) => fn.body.includes(t));

    if (unmask) {
      unmaskers++;
      const key = `${rel}:${fn.name}`;
      if (!aware && !ALLOW[key]) {
        violations.push({ rel, fn: fn.name, line: fn.line });
      }
    }

    //--- The memo rule: a mask write cached behind `static … s_last…` must key on
    //--- the mute as well, because the value it caches is built from it.
    if (unmask && /static\s+bool\s+s_last/i.test(fn.body) && aware &&
        fn.body.includes('IsIndicatorHidden') &&
        !/s_last[A-Za-z_]*[Hh]idden/.test(fn.body)) {
      memoViolations.push({ rel, fn: fn.name, line: fn.line });
    }
  }
}

console.log('==================================================================');
console.log('MASK OWNER GATE  (every unmask knows the mute — one property, one owner)');
console.log('==================================================================');
console.log(`  files: ${files.length}  functions: ${scanned}  unmask writers: ${unmaskers}`);
console.log(`  allow-listed (documented reason): ${Object.keys(ALLOW).length}`);

if (memoViolations.length) {
  console.log('');
  for (const v of memoViolations)
    console.log(`  [FAIL] ${v.rel}:${v.line} ${v.fn}() — the mask folds IsIndicatorHidden() but its\n` +
      `         memo keys on something narrower; a moved mute would be cached away`);
}

if (violations.length) {
  console.log('');
  for (const v of violations)
    console.log(`  [FAIL] ${v.rel}:${v.line} ${v.fn}() writes OBJ_ALL_PERIODS without asking\n` +
      `         IsIndicatorHidden() (or a composer that does) — a second owner of the mask`);
  console.log('');
  console.log(`FAIL: ${violations.length + memoViolations.length} blind mask writer(s).`);
  console.log('      Fold the mute, or add a sentence to ALLOW in tools/mask_owner_check.js.');
  process.exit(1);
}

console.log('');
console.log('PASS — every unmask writer either folds the mute or is a documented exception.');
