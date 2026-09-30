#!/usr/bin/env node
// REGRESSION REGISTER GATE — the defects that were fixed once, and the reason an
// update ANYWHERE ELSE must fail the build instead of shipping them back.
//
// WHY THIS EXISTS. The reports of 2026-09-30 were all "this used to work":
//
//   1. «لیبل های th خاموش و روشن درست کار نمیکنه» — SetTHLabelsVisibility wrote
//      OBJPROP_TIMEFRAMES to `<prefix>TH_*` while every TH object is BORN
//      `<prefix>LBL_TH_*` (the migration moved the names; this one writer kept the
//      old spelling). ~50 writes per toggle addressed names the chart did not
//      carry, MT4 answered nothing, and no compiler, no gate and no log line said
//      so (P-TH-02).
//   2. «سطوح تریگر دیر خاموش و روشن میشه» — twice. First the 20 ms burst coalescer
//      returned before the deferral, so a dropped toggle owed no frame at all and
//      waited for the next tick or the 250 ms timer (P-KEY-01). Then the fix itself:
//      the toggle's PIXELS were the render's job (a flag, a heavy frame, and an OFF
//      branch that DELETED the family the ON press had to show again). It paints in
//      its own event now, through the structure switches' technique (P-PERF-32b):
//      one owner, one bounded mask walk, one discrete repaint.
//   3. «شادو رسم میشه بعد چند ثانیه نیست» — the HTF shadow box is drawn and then
//      gone, with the body's border and every setting untouched. The first reading
//      (a LOOK that moved: box mode / wicks / body, which is why the P-HTF-PROBE
//      lines exist) was wrong. Measured 2026-09-30 pixel by pixel: the shadow's
//      12 px plate was neither repainted nor deleted — it had become the chart
//      BACKGROUND to the byte, and the hollow 45 px bodies were untouched. Cause:
//      the draw-strip's interior split, which asks "is this object ours?" through
//      `DrawIsIndicatorObject`, a test that knew only `inpObjectPrefix`
//      ("THLevels") while the overlay is born `BiotakHTF_<chartid>_*` (P-DRAW-87).
//
// Every one of them was GREEN: the compiler checks that names resolve, and a
// write to an object that does not exist is not an error in MT4. What this gate
// checks is not "does it compile" but "is the surface that owns this behaviour
// still the only writer, still spelled with the name the objects are born with,
// and still on the record". Each check below is a fixed defect; a build that
// breaks one fails HERE, at the name, before the terminal sees it.
//
// What it does NOT do: it cannot run the indicator, and it cannot see a NEW look
// that is wrong in a way nobody has fixed before. Run the probe lines (each check
// that has one names it) for the runtime number.
//
// USAGE:  node tools/check-regressions.js
// Exit 0 = clean, 1 = a fixed behaviour was edited back into a broken shape.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const BIOTAK = path.join(ROOT, 'Biotak');
const LABELS_B = path.join(BIOTAK, 'Labels_B.mqh');
const LABELS_A = path.join(BIOTAK, 'Labels_A.mqh');
const ROUTER = path.join(BIOTAK, 'EventHandlers_Router.mqh');
const CALC = path.join(BIOTAK, 'EventHandlers_Calc.mqh');
const HTF = path.join(BIOTAK, 'HTFCandles.mqh');
const VIS = path.join(BIOTAK, 'VisibilityManager.mqh');
const APPLY = path.join(BIOTAK, 'BiotakPanels_Apply.mqh');
const PAL_B = path.join(BIOTAK, 'BiotakPanels_PalB.mqh');
const OBJ = path.join(BIOTAK, 'EventHandlers_Objects.mqh');
const PIPE_A = path.join(BIOTAK, 'LevelPipe_A.mqh');
const PIPE_B = path.join(BIOTAK, 'LevelPipe_B.mqh');
const MENU_D = path.join(BIOTAK, 'BiotakMenu_D.mqh');

const failures = [];

function linesOf(abs) {
  try {
    return fs.readFileSync(abs, 'utf8').split(/\r?\n/);
  } catch {
    return null;
  }
}
function stripComment(s) {
  const i = s.indexOf('//');
  return i >= 0 ? s.slice(0, i) : s;
}
function depthDelta(s) {
  let d = 0;
  for (const ch of stripComment(s)) {
    if (ch === '{') d++;
    else if (ch === '}') d--;
  }
  return d;
}
// { from, to } line indices (inclusive) of the `{ ... }` block starting at/after `from`.
function blockAfter(lines, from) {
  let i = from;
  while (i < lines.length && !stripComment(lines[i]).includes('{')) i++;
  if (i >= lines.length) return null;
  const start = i;
  let depth = 0;
  for (; i < lines.length; i++) {
    depth += depthDelta(lines[i]);
    if (depth === 0 && i > start) return { from: start, to: i };
    if (depth === 0 && i === start && stripComment(lines[i]).includes('}')) return { from: start, to: i };
  }
  return null;
}
function indexOfLine(lines, needle, from = 0) {
  for (let i = from; i < lines.length; i++) if (lines[i].includes(needle)) return i;
  return -1;
}
// The CODE of a run of lines, comments dropped: every check below tests code, and
// this project's comments QUOTE the broken spelling they replaced (the P-PERF-38g
// note in ClearAllLabels contains the very bulk delete it is there to explain).
function codeOf(lines) {
  return lines.map(stripComment).join('\n');
}
// P-HTF-SPLIT (2026-09-30): the HTF overlay is a HUB (`HTFCandles.mqh`) plus its
// owner parts (`HTFCandles_Geom/Draw/Life.mqh`). Every check below still asks the
// UNIT its question and no check learns a part's file name: `htfFiles()` IS the
// unit's member set, and `htfFind()` reports which member a tag lives in — so a
// part may be renamed, added or split again without editing each check.
function htfFiles() {
  return fs
    .readdirSync(BIOTAK)
    .filter((n) => n === 'HTFCandles.mqh' || /^HTFCandles_[A-Za-z]+\.mqh$/.test(n))
    .sort((a, b) =>
      a === 'HTFCandles.mqh' ? -1 : b === 'HTFCandles.mqh' ? 1 : a.localeCompare(b)
    );
}
function htfFind(tag, skip = 0) {
  let seen = 0;
  for (const f of htfFiles()) {
    const lines = linesOf(path.join(BIOTAK, f));
    if (!lines) continue;
    for (let i = 0; i < lines.length; i++) {
      if (!lines[i].includes(tag)) continue;
      if (seen++ < skip) continue;
      return { file: f, at: i, line: lines[i], lines };
    }
  }
  return null;
}
function bodyOf(lines, defNeedle) {
  const at = indexOfLine(lines, defNeedle);
  if (at < 0) return null;
  const block = blockAfter(lines, at);
  if (!block) return null;
  const slice = lines.slice(block.from, block.to + 1);
  return { at, from: block.from, to: block.to, text: codeOf(slice) };
}
// The window of a `case`/`if` block: from the marker line to the next `break;`
// (or the given end marker), comments kept out of the tests.
function windowTo(lines, from, endMarker, limit = 200) {
  const out = [];
  for (let i = from; i < lines.length && i < from + limit; i++) {
    out.push(lines[i]);
    if (lines[i].includes(endMarker)) break;
  }
  return out;
}

function main() {
  const labelsB = linesOf(LABELS_B);
  const labelsA = linesOf(LABELS_A);
  const router = linesOf(ROUTER);
  const calc = linesOf(CALC);
  const htf = linesOf(HTF);
  const vis = linesOf(VIS);
  const apply = linesOf(APPLY);
  const palB = linesOf(PAL_B);
  const obj = linesOf(OBJ);
  const pipeA = linesOf(PIPE_A);
  const pipeB = linesOf(PIPE_B);
  const menuD = linesOf(MENU_D);

  for (const [name, lines] of [
    ['Labels_B.mqh', labelsB], ['Labels_A.mqh', labelsA], ['EventHandlers_Router.mqh', router],
    ['EventHandlers_Calc.mqh', calc], ['HTFCandles.mqh', htf], ['VisibilityManager.mqh', vis],
    ['BiotakPanels_Apply.mqh', apply], ['BiotakPanels_PalB.mqh', palB],
    ['EventHandlers_Objects.mqh', obj], ['LevelPipe_A.mqh', pipeA], ['LevelPipe_B.mqh', pipeB],
    ['BiotakMenu_D.mqh', menuD],
  ]) {
    if (!lines) {
      console.log('REGRESSION GATE FAILED');
      console.log(`         Biotak/${name} is missing`);
      process.exit(1);
    }
  }

  // -- 1. P-TH-02: the TH mask addresses the names the labels are BORN with -----
  // The migration moved every TH object to `<prefix>LBL_TH_*`; this writer kept
  // the pre-migration spelling, and every mask it set landed on nothing.
  const thMask = bodyOf(labelsB, 'void SetTHLabelsVisibility(');
  if (!thMask) {
    failures.push('SetTHLabelsVisibility() is gone from Biotak/Labels_B.mqh');
  } else {
    const staleName = /objectPrefix\s*\+\s*"TH_"/.test(thMask.text);
    const liveName = /uniquePrefix\s*\+\s*"TH_"/.test(thMask.text) &&
                     /objectPrefix\s*\+\s*"LBL_"/.test(thMask.text);
    if (staleName || !liveName) {
      failures.push(
        'P-TH-02: SetTHLabelsVisibility must mask `<prefix>LBL_TH_*` names ' +
        '(the names CreateTHLabel is handed) — it is writing `<prefix>TH_*`, which ' +
        'no TH object carries, so every mask write is silently ignored ' +
        '(Biotak/Labels_B.mqh)'
      );
    } else {
      console.log(`[PASS] P-TH-02 TH mask names: LBL_ infix present (Biotak/Labels_B.mqh:${thMask.from + 1}-${thMask.to + 1})`);
    }
    // The witness: the number that proves the toggle reached the chart.
    const witness = indexOfLine(labelsB, '[P-LBL] TH mask mode=');
    const witnessOk = witness >= 0 && !labelsB[witness].includes('_LOG_GATE_');
    if (!witnessOk) {
      failures.push(
        'P-TH-02: the `[P-LBL] TH mask mode= applied= of ` witness is missing or gated ' +
        '(Biotak/Labels_B.mqh) — it is the only number that says the toggle landed'
      );
    } else {
      console.log(`[PASS] P-TH-02 TH mask witness ungated (Biotak/Labels_B.mqh:${witness + 1})`);
    }
  }

  // -- 1b. P-TH-02: the two F/L walks must not blanket-unmask the TH family ------
  // They write ALL_PERIODS to every name they do not recognise, so without the
  // explicit skip an F show re-showed a TH family whose mode said OFF - the second
  // writer of the property the toggle owns.
  const visCode = codeOf(vis);
  const thSkips = (visCode.match(/StringFind\((nm|objName), "LBL_TH_"\) >= 0\) continue;/g) || []).length;
  if (thSkips < 2) {
    failures.push(
      'P-TH-02: both visibility walks in Biotak/VisibilityManager.mqh must skip the TH family ' +
      '(`if(StringFind(nm|objName, "LBL_TH_") >= 0) continue;`) — only ' + thSkips + ' found; ' +
      'without them an F show unmasks a TH family whose mode is OFF'
    );
  } else {
    console.log(`[PASS] P-TH-02 TH family skipped by both F/L walks (Biotak/VisibilityManager.mqh, ${thSkips} sites)`);
  }

  // -- 2. P-PERF-38g: the label clear is a SWEEP, not a whole-namespace wipe ----
  const clearAll = bodyOf(labelsA, 'void ClearAllLabels(');
  if (!clearAll) {
    failures.push('ClearAllLabels() is gone from Biotak/Labels_A.mqh');
  } else {
    const armed = clearAll.text.includes('LblSweepBegin(objectPrefix)');
    const bulk = clearAll.text.includes('ObjectsDeleteAll(0, objectPrefix + "LBL_")');
    if (!armed || bulk) {
      failures.push(
        'P-PERF-38g: ClearAllLabels must arm the produced-list sweep (LblSweepBegin) and must ' +
        'NOT bulk-delete the LBL_ namespace — the bulk delete is what made every label blink ' +
        '(Biotak/Labels_A.mqh)'
      );
    } else {
      console.log(`[PASS] P-PERF-38g label clear is a sweep (Biotak/Labels_A.mqh:${clearAll.from + 1}-${clearAll.to + 1})`);
    }
  }

  // -- 3. P-PERF-21 / P-PERF-32b / P-KEY-PROBE: the trigger toggle has ONE
  //       owner, it paints in its own event, and it is on the record ----------
  //
  // What this asserts is the shape of the fix, not a memory of it: the toggle's
  // pixels must not be the RENDER's job again (that is «سطوح تریگر دیر خاموش و
  // روشن میشه»), the family must answer to a MASK (a delete leaves the ON
  // direction nothing to show), the F show path must re-assert the family through
  // its own owner (its walk cannot tell a trigger band from a structure band), and
  // the three callers (T key, card SHOW row, ring light) must all go through the
  // ONE owner rather than keeping their own copy of the state.
  const tKey = indexOfLine(router, 'inpTriggerLevelsKey');
  if (tKey < 0) {
    failures.push('the T hotkey block is gone from Biotak/EventHandlers_Router.mqh');
  } else {
    const block = codeOf(windowTo(router, tKey, 'return;'));
    if (block.includes('g_forceClearOnNextDraw')) {
      failures.push(
        'P-PERF-21: the T toggle must NOT force a clear — the family answers to a mask, so the ' +
        'overlay is a re-render, never a wipe (Biotak/EventHandlers_Router.mqh)'
      );
    } else if (!block.includes('SetTriggerLevelsVisible(')) {
      failures.push(
        'P-PERF-32b: the T hotkey must go through the ONE owner `SetTriggerLevelsVisible()` ' +
        '(state + persisted key + the family mask walk + the discrete repaint) — a local copy ' +
        'of the state is how the three surfaces drift apart (Biotak/EventHandlers_Router.mqh)'
      );
    } else if (!block.includes('[P-KEY] T press')) {
      failures.push(
        'P-KEY-PROBE: the T press must stay on the record (`[P-KEY] T press`), or the latency ' +
        'report has nothing to measure against (Biotak/EventHandlers_Router.mqh)'
      );
    } else {
      console.log(`[PASS] P-PERF-32b T key: one owner + press probe (Biotak/EventHandlers_Router.mqh:${tKey + 1})`);
    }
  }
  const trigOwner = bodyOf(obj, 'void SetTriggerLevelsVisible(');
  if (!trigOwner) {
    failures.push(
      'P-PERF-32b: `SetTriggerLevelsVisible()` is gone from Biotak/EventHandlers_Objects.mqh — ' +
      'the ONE owner of the trigger overlay state + its paint'
    );
  } else {
    const missing = ['TriggerFamilyWalk(', 'RepaintForDiscreteAction()',
                     'g_redrawTHLevelsNeeded = true;', 'ScheduleHeavyFrame(',
                     '[P-KEY] T applied'].filter(
      (needle) => !trigOwner.text.includes(needle));
    // The pixels are NOT the render's: the owner must not ask for a deferred frame
    // (`RedrawAllObjects`) - `RepaintForDiscreteAction` is the paint, and the only
    // frame it may owe is the BUILD for a family the chart does not carry yet.
    const deferred = /\bRedrawAllObjects\s*\(/.test(trigOwner.text);
    if (missing.length || deferred) {
      failures.push(
        'P-PERF-32b: SetTriggerLevelsVisible must keep the press-time paint in its own body — ' +
        `missing: ${missing.join(', ') || 'none'}` +
        (deferred ? '; it must NOT call RedrawAllObjects() (a deferred frame is the lag)' : '') +
        ' (Biotak/EventHandlers_Objects.mqh)'
      );
    } else {
      console.log(`[PASS] P-PERF-32b trigger owner: walk + discrete repaint + witness (Biotak/EventHandlers_Objects.mqh:${trigOwner.from + 1})`);
    }
  }
  // The render's OFF branch: mask, never delete - and never stale.
  const trigHidden = bodyOf(pipeA, 'bool triggerHidden = (zones[i].isTrigger && !triggerEnabled);');
  const trigBranch = trigHidden || bodyOf(pipeA, 'if(zones[i].isTrigger && !triggerEnabled) {');
  if (!trigBranch) {
    failures.push(
      'P-PERF-32b: the trigger OFF branch is gone from RenderZones (Biotak/LevelPipe_A.mqh) — ' +
      'the overlay must be applied as a mask by the render'
    );
  } else if (!trigBranch.text.includes('SetPipelineZoneVisibility(') ||
             trigBranch.text.includes('DeleteManagedZoneObjects')) {
    failures.push(
      'P-PERF-32b: RenderZones must MASK a trigger band whose overlay is OFF ' +
      '(`SetPipelineZoneVisibility(name, false)`), never delete it — a deleted band leaves the ON ' +
      'press nothing to show without a full render (Biotak/LevelPipe_A.mqh)'
    );
  } else if (!trigBranch.text.includes('CacheGetObject(') || !trigBranch.text.includes('renderTop')) {
    failures.push(
      'P-PERF-32b: the hidden trigger band must be kept PRICED (`CacheGetObject` + the built ' +
      '`renderTop` compared before the mask) — the ON press paints from these objects, so a band ' +
      'left at the previous centre flashes at the old price for a frame (Biotak/LevelPipe_A.mqh)'
    );
  } else if (indexOfLine(pipeA, 'SetPipelineZoneVisibility(zones[i].name, !triggerHidden)') < 0) {
    failures.push(
      'P-PERF-32b: the render\'s create tail must mask a band the switch turned OFF ' +
      '(`SetPipelineZoneVisibility(zones[i].name, !triggerHidden)`) — the fall-through that keeps the ' +
      'hidden family priced must never make it visible (Biotak/LevelPipe_A.mqh)'
    );
  } else {
    console.log(`[PASS] P-PERF-32b render OFF branch is a priced mask (Biotak/LevelPipe_A.mqh:${trigBranch.from + 1})`);
  }
  // The family walk itself, and the F-show re-assert that keeps it honest.
  if (!bodyOf(pipeB, 'int TriggerFamilyWalk(')) {
    failures.push(
      'P-PERF-32b: `TriggerFamilyWalk()` is gone from Biotak/LevelPipe_B.mqh — the trigger family\'s ' +
      'press-time walk (the structure switches\' technique)'
    );
  } else if (indexOfLine(obj, 'TriggerFamilyWalk(g_triggerLevelsEnabled,') < 0) {
    failures.push(
      'P-PERF-32b: the F show path must re-assert the trigger family through its own walk ' +
      '(`TriggerFamilyWalk(g_triggerLevelsEnabled, …)` in ApplyHideAllState) — its own walk cannot ' +
      'tell a trigger band from a structure band, and a band outside the frame\'s culled list is ' +
      're-decided by nobody else (Biotak/EventHandlers_Objects.mqh)'
    );
  } else {
    console.log('[PASS] P-PERF-32b family walk + F-show re-assert (Biotak/LevelPipe_B.mqh, EventHandlers_Objects.mqh)');
  }
  // The card's SHOW row and the ring light: same owner, and neither keeps a state
  // write of its own.
  const trigRow = indexOfLine(apply, 'SetTriggerLevelsVisible(v>0.5)');
  if (trigRow < 0) {
    failures.push(
      'P-PERF-32b: the TRIGGER card\'s SHOW row (case 0 row 3) must go through `SetTriggerLevelsVisible()` ' +
      '(Biotak/BiotakPanels_Apply.mqh)'
    );
  } else {
    const rowBlock = codeOf(windowTo(apply, trigRow - 6, 'break;', 24));
    if (rowBlock.includes('REFRESH_BUFFERS')) {
      failures.push(
        'P-PERF-32b: the SHOW row must not return REFRESH_BUFFERS — that requests the heavy frame the ' +
        'press no longer needs (Biotak/BiotakPanels_Apply.mqh)'
      );
    } else {
      console.log(`[PASS] P-PERF-32b card SHOW row goes through the owner (Biotak/BiotakPanels_Apply.mqh:${trigRow + 1})`);
    }
  }
  const ringCall = indexOfLine(menuD, 'SetTriggerLevelsVisible(wantOn)');
  if (ringCall < 0) {
    failures.push(
      'P-PERF-32b: the ring\'s TRIGGER light must go through `SetTriggerLevelsVisible()` ' +
      '(Biotak/BiotakMenu_D.mqh)'
    );
  } else {
    const ringBlock = codeOf(windowTo(menuD, ringCall - 6, 'else if(feat == CIR_ZONES)', 24));
    if (ringBlock.includes('g_triggerLevelsEnabled =')) {
      failures.push(
        'P-PERF-32b: the ring branch must not write `g_triggerLevelsEnabled` itself — the owner owns ' +
        'the state (Biotak/BiotakMenu_D.mqh)'
      );
    } else {
      console.log(`[PASS] P-PERF-32b ring TRIGGER light goes through the owner (Biotak/BiotakMenu_D.mqh:${ringCall + 1})`);
    }
  }
  const applied = indexOfLine(obj, '[P-KEY] T applied');
  if (applied < 0 || obj[applied].includes('_LOG_GATE_')) {
    failures.push(
      'P-KEY-PROBE: `[P-KEY] T applied on= ms= bands= masks=` must stay an ungated Print in ' +
      'SetTriggerLevelsVisible() (Biotak/EventHandlers_Objects.mqh) — it is the press→painted ' +
      'number the latency report is judged by'
    );
  } else {
    console.log(`[PASS] P-KEY-PROBE T applied line ungated (Biotak/EventHandlers_Objects.mqh:${applied + 1})`);
  }
  const settled = indexOfLine(calc, '[P-KEY] T settled');
  if (settled < 0 || calc[settled].includes('_LOG_GATE_')) {
    failures.push(
      'P-KEY-PROBE: `[P-KEY] T settled on= ms= levels= labels= hidden= reached=` must stay an ungated ' +
      'Print in RedrawAllObjects() (Biotak/EventHandlers_Calc.mqh) — it is the reconciliation frame\'s ' +
      'own witness'
    );
  } else {
    console.log(`[PASS] P-KEY-PROBE T settle line ungated (Biotak/EventHandlers_Calc.mqh:${settled + 1})`);
  }

  // -- 4. P-KEY-01: a coalesced forced call still OWES its frame ----------------
  const coalesce = indexOfLine(calc, 's_lastForcedRedrawMs < 20');
  if (coalesce < 0) {
    failures.push('the 20 ms forced-redraw coalescer is gone from Biotak/EventHandlers_Calc.mqh');
  } else {
    const block = codeOf(windowTo(calc, coalesce, 'return;', 40));
    if (!block.includes('ScheduleHeavyFrame(')) {

      failures.push(
        'P-KEY-01: the coalescer must mark the frame owed before it returns ' +
        '(`if(g_redrawTHLevelsNeeded) ScheduleHeavyFrame("coalesced")`) — returning with no debt ' +
        'is what made a dropped toggle wait for the 250 ms timer (Biotak/EventHandlers_Calc.mqh)'
      );
    } else {
      console.log(`[PASS] P-KEY-01 coalesced toggle still owes a frame (Biotak/EventHandlers_Calc.mqh:${coalesce + 1})`);
    }
  }

  // -- 5. P-UI-68: the HTF family has ONE writer, and its look is on the record --
  const foreignHtf = [];
  for (const f of fs.readdirSync(BIOTAK).filter((n) => n.endsWith('.mqh'))) {
    if (htfFiles().includes(f)) continue;   // the unit's members ARE the one writer
    const lines = linesOf(path.join(BIOTAK, f));
    lines.forEach((l, i) => {
      const code = stripComment(l);
      if (code.includes('g_HTFPrefix') || code.includes('HTF_PREFIX_BASE')) {
        foreignHtf.push(`Biotak/${f}:${i + 1}`);
      }
    });
  }
  if (foreignHtf.length) {
    failures.push(
      'P-UI-68: the HTF candle names have ONE writer (Biotak/HTFCandles.mqh); found: ' +
      foreignHtf.join(', ')
    );
  } else {
    console.log('[PASS] P-UI-68 HTF names: single writer (Biotak/HTFCandles.mqh)');
  }
  for (const tag of ['[P-HTF] ', 'cull masked=']) {
    const hit = htfFind(tag);
    if (!hit || hit.line.includes('_LOG_GATE_')) {
      failures.push(
        `P-HTF-PROBE: the HTF look must stay on the record (missing or gated: \`${tag}\`) — ` +
        'box mode / wicks / body and the cull mask count are the numbers "the shadow vanished" ' +
        'is judged by (Biotak/HTFCandles.mqh and its parts)'
      );
    } else {
      console.log(`[PASS] P-HTF-PROBE Biotak/${hit.file}:${hit.at + 1} carries \`${tag}\``);
    }
  }

  // -- 6. The HTF card row -> flag map is BEHAVIOUR (a row shift is a flag shift) -
  const htfCase = indexOfLine(apply, 'case 6:   // HTF CANDLES');
  if (htfCase < 0) {
    failures.push('the HTF CANDLES case is gone from Biotak/BiotakPanels_Apply.mqh');
  } else {
    const block = codeOf(windowTo(apply, htfCase, 'break;', 60));
    const map = [
      ['row==9', 'g_HTFShowWicks'],
      ['row==10', 'g_HTFBoxMode'],
      ['row==11', 'g_HTFShadowPct'],
    ];
    const broken = map.filter(([row, flag]) => {
      const line = block.split('\n').find((l) => l.includes(row));
      return !line || !line.includes(flag);
    });
    if (broken.length) {
      failures.push(
        'the HTF card row map moved: ' +
        broken.map(([r, f]) => `${r} must write ${f}`).join('; ') +
        ' (Biotak/BiotakPanels_Apply.mqh) — a shifted row changes the flag a slider writes'
      );
    } else {
      console.log(`[PASS] HTF card row map intact (Biotak/BiotakPanels_Apply.mqh:${htfCase + 1})`);
    }
    // The captions the user reads must agree with those rows: row 9/10/11 carry
    // their own `row==` address, row 12 IS the trailing `else` of the chain.
    const itemIdx = indexOfLine(palB, 'else if(item==6)');
    const palBlock = itemIdx >= 0 ? codeOf(windowTo(palB, itemIdx, 'else if(item==7)', 60)) : '';
    const brokenCaptions = [
      [9, 'SHOW WICKS'], [10, 'BOX'], [11, 'SHADOW WIDTH'],
    ].filter(([row, text]) => {
      const line = palBlock.split('\n').find((l) => l.includes(`row==${row}`));
      return !line || !line.includes(text);
    });
    if (itemIdx < 0 || brokenCaptions.length || !palBlock.includes('SHADOW GAP')) {
      failures.push(
        'the HTF card captions moved: ' +
        brokenCaptions.map(([r, t]) => `row ${r} must read "${t}"`).join('; ') +
        (palBlock.includes('SHADOW GAP') ? '' : ' the trailing row must read "SHADOW GAP"') +
        ' (Biotak/BiotakPanels_PalB.mqh)'
      );
    } else {
      console.log(`[PASS] HTF card captions match the row map (Biotak/BiotakPanels_PalB.mqh:${itemIdx + 1})`);
    }
  }

  // -- 10. P-DRAW-87: the draw-strip's "is this ours?" test still sees the OVERLAY --
  //
  // The fixed defect (2026-09-30): the HTF family is born `BiotakHTF_<chartid>_*`,
  // which `inpObjectPrefix` does not cover, so `DrawIsIndicatorObject` answered
  // false for every HTF box and the 2 s `BoxExtrasPump` split each shadow's interior
  // into an `<name>_FL` child painted in the chart background and cleared the
  // master's FILL — «شادو رسم میشه بعد چند ثانیه نیست», with every box, every row and
  // the whole log intact. The fix is ONE test on the root the HTF module PUBLISHES
  // (P-UI-68 keeps the name itself single-writer, so the literal may not be
  // re-declared outside HTFCandles): drop any one of the three lines below and the
  // family is a user drawing again.
  {
    const ta = linesOf(path.join(BIOTAK, 'Toolbar_A.mqh'));
    const gv = linesOf(path.join(BIOTAK, 'GlobalVariables.mqh'));
    const pred = ta ? bodyOf(ta, 'bool DrawIsIndicatorObject(') : null;
    const declared = gv ? indexOfLine(gv, 'static string g_OverlayNameRoot = ""') : -1;
    const pub = htfFind('g_OverlayNameRoot = g_HTFPrefix');
    const published = pub ? pub.at : -1;
    if (!pred || !pred.text.includes('g_OverlayNameRoot')) {
      failures.push(
        'P-DRAW-87: DrawIsIndicatorObject must consult the published overlay root ' +
        '(Biotak/Toolbar_A.mqh) — without it the draw-strip reads the HTF boxes as ' +
        'USER drawings and its 2 s pump clears their FILL'
      );
    } else if (declared < 0) {
      failures.push(
        'P-DRAW-87: g_OverlayNameRoot must be declared (Biotak/GlobalVariables.mqh) — ' +
        'DrawToolbar is included BEFORE HTFCandles, so the root crosses on a shared global'
      );
    } else if (published < 0) {
      failures.push(
        'P-DRAW-87: Biotak/HTFCandles.mqh (or the part that owns the init) must publish ' +
        'g_OverlayNameRoot = g_HTFPrefix (one writer, one publish)'
      );
    } else {
      console.log(
        `[PASS] P-DRAW-87 overlay namespace published for the draw-strip ` +
        `(Biotak/Toolbar_A.mqh:${pred.at + 1})`
      );
    }
  }

  // -- 12. P-HTF-SLOT: the high rungs keep a readable pitch ---------------------
  //
  // Fixed 2026-09-30 (the report «ویکی و ماهانه ... کندل های تایم بالا واقعی»).
  // One MN1 bar on an M5 chart is 43200/5 = 8640 chart bars against a ~300-bar
  // window: body edges, shadow edges, all four outside the window, so the overlay
  // painted the horizontal strips of a 28-window-wide box and no candle. The fix
  // is a slot pitch (visBars / HTF_SLOT_MIN_CANDLES, anchored at bar 0) applied by
  // ONE function to the candle's two edges — the shape law stays HTFCandleGeometry.
  // Asserted here: the constant, the decision, the three call sites, the witness
  // line, and the draw-count assignment standing AFTER the box-mode flip (a flip
  // left `drawn=0` with the boxes on the chart, which blinded the cull and the
  // range probe until the next HTF bar).
  {
    const def = htfFind('#define HTF_SLOT_MIN_CANDLES');
    const refresh = htfFind('void HTFRefreshSlotMetrics(');
    const slots = htfFind('void HTFSlotTimes(');
    const geom = htfFind('void HTFSlotTimes(const int i');
    const drawCore = htfFind('void DrawHTFCandleCore(');
    const core = drawCore ? bodyOf(drawCore.lines, 'void DrawHTFCandleCore(') : null;
    const drawPass = htfFind('int DrawHTFCandles()');
    const passBody = drawPass ? bodyOf(drawPass.lines, 'int DrawHTFCandles()') : null;
    const forming = htfFind('bool UpdateHTFFormingCandle()');
    const formingBody = forming ? bodyOf(forming.lines, 'bool UpdateHTFFormingCandle()') : null;
    const probe = htfFind('[P-HTF] slot ');
    const broken = [];
    if (!def) broken.push('HTF_SLOT_MIN_CANDLES is gone');
    if (!refresh) broken.push('HTFRefreshSlotMetrics is gone');
    if (!slots) broken.push('HTFSlotTimes is gone');
    if (!core || !core.text.includes('HTFSlotTimes('))
      broken.push('DrawHTFCandleCore must put the candle on the slot grid (HTFSlotTimes)');
    if (!passBody || !passBody.text.includes('HTFRefreshSlotMetrics('))
      broken.push('the history pass must refresh the pitch before it draws');
    if (!formingBody || !formingBody.text.includes('HTFRefreshSlotMetrics('))
      broken.push('the forming candle must stand on the SAME pitch as the history pass');
    const range = htfFind('bool HTFRangeStale()');
    const rangeBody = range ? bodyOf(range.lines, 'bool HTFRangeStale()') : null;
    if (!rangeBody || !rangeBody.text.includes('HTFRefreshSlotMetrics('))
      broken.push('a zoom must re-pitch the strip (the throttled range probe owns it)');
    if (!probe || probe.line.includes('_LOG_GATE_'))
      broken.push('the `[P-HTF] slot` witness is missing or gated');
    if (!geom) broken.push('the geometry owner is gone');
    if (passBody) {
      const flip = indexOfLine(passBody.text.split('\n'), 's_lastBoxMode != g_HTFBoxMode');
      const counted = indexOfLine(passBody.text.split('\n'), 'g_HTFDrawnCount = count;');
      if (flip < 0 || counted < 0 || counted < flip) {
        broken.push(
          'the drawn count must be assigned AFTER the box-mode flip — above it, a BOX ' +
          'flip leaves `drawn=0` with the boxes on the chart (cull blind, range probe dead)'
        );
      }
    }
    if (broken.length) {
      failures.push('P-HTF-SLOT: ' + broken.join('; ') + ' (Biotak/HTFCandles_*.mqh)');
    } else {
      console.log(
        `[PASS] P-HTF-SLOT pitch + count order intact (Biotak/${refresh.file}:${refresh.at + 1})`
      );
    }
  }

  // -- 13. P-HTF-SPLIT: the hub still reaches every part ------------------------
  //
  // The overlay was one 1519-line file against a 1500-line ceiling (§7). It is a
  // hub + parts now; a part that no longer sits on the hub's include list is a
  // part the compiling unit silently DROPS (MQL4 answers nothing), so the hub's
  // own includes are the check.
  {
    const hub = linesOf(HTF);
    const parts = htfFiles().filter((f) => f !== 'HTFCandles.mqh');
    const orphans = parts.filter((f) => !hub || !hub.some((l) => stripComment(l).includes(`include "${f}"`)));
    if (!hub || !parts.length) {
      failures.push('P-HTF-SPLIT: the overlay hub or its parts are gone (Biotak/HTFCandles*.mqh)');
    } else if (orphans.length) {
      failures.push(
        'P-HTF-SPLIT: the hub does not include ' + orphans.join(', ') +
        ' (Biotak/HTFCandles.mqh) — a part outside the include chain is not compiled at all'
      );
    } else {
      console.log(
        `[PASS] P-HTF-SPLIT hub reaches all ${parts.length} parts (Biotak/HTFCandles.mqh)`
      );
    }
  }

  // -- 14. P-SIZE-1500: one file, one owner, <= 1500 lines (contract §7) ---------
  //
  // The ceiling was prose. Six files had drifted past it by 2026-09-30
  // (EventHandlers_Init 1650, Router 1592, Labels_A 1576, Calc 1562, LevelPipe_A
  // 1557, HTFCandles 1519); the overlay left the list the day it was split into
  // its owners. A file already over the ceiling never GROWS — that is what the
  // baseline is — and a file not on it fails the build above 1500, so the next
  // drift is caught here instead of in a review. Counting is [System.IO.File]
  // ::ReadAllLines: split on newlines, a trailing newline is not a line.
  {
    const SIZE_BASELINE = {
      'EventHandlers_Init.mqh': 1650,
      'EventHandlers_Router.mqh': 1592,
      'Labels_A.mqh': 1576,
      'EventHandlers_Calc.mqh': 1562,
      'LevelPipe_A.mqh': 1557,
    };
    const counted = [];
    const sizeOf = (label, abs) => {
      const lines = linesOf(abs);
      if (!lines) return;
      if (lines.length && lines[lines.length - 1] === '') lines.pop();
      counted.push({ label, n: lines.length });
    };
    for (const f of fs.readdirSync(BIOTAK).filter((n) => n.endsWith('.mqh')))
      sizeOf(`Biotak/${f}`, path.join(BIOTAK, f));
    for (const f of fs.readdirSync(ROOT).filter((n) => n.endsWith('.mq4')))
      sizeOf(f, path.join(ROOT, f));
    const over = counted.filter(({ label, n }) => {
      const base = SIZE_BASELINE[path.basename(label)];
      return base === undefined ? n > 1500 : n > base;
    });
    const freed = Object.keys(SIZE_BASELINE).filter(
      (k) => !counted.some(({ label }) => path.basename(label) === k)
    );
    if (over.length || freed.length) {
      failures.push(
        'P-SIZE-1500: ' +
          over.map(({ label, n }) => `${label} is ${n} lines (ceiling 1500)`).join('; ') +
          (freed.length ? `${over.length ? '; ' : ''}baseline names a file that is gone: ${freed.join(', ')}` : '') +
          ' — split it by owner (contract §7)'
      );
    } else {
      console.log(
        `[PASS] P-SIZE-1500 ${counted.length} files, ${Object.keys(SIZE_BASELINE).length} grandfathered at or under their baseline, 0 over the ceiling`
      );
    }
  }

  // -- 15. P-HTF-TOP: the top of the ladder is a rung, not a hide --------------
  //
  // Fixed 2026-09-30 (report «کندل های مثل htf candle دیده نمیشه» on an
  // EURUSD,Monthly chart): the ladder tops out at MN1, so on a monthly chart the
  // structure rung snaps to the chart's OWN MN1 — and the old `rung > Period()`
  // test answered "nothing above, hide", so the overlay painted nothing at all.
  // One rule, four sites (the resolve, the history pass, the forming candle and
  // the ensure probe) now read `>=`; a rung strictly BELOW the chart TF still
  // hides. The geometry's fence moved with it: span 0 — both edges clamped onto
  // one slot by a history that does not reach them — is the collapse, while a span
  // below one bar is the chart's own period and takes the shape law.
  {
    const joined = htfFiles()
      .map((f) => codeOf(linesOf(path.join(BIOTAK, f)) || []))
      .join('\n');
    const broken = [];
    if (!/rung >= \(int\)Period\(\)/.test(joined))
      broken.push("ResolveHTFPeriod must accept the chart's OWN rung (`rung >= (int)Period()`)");
    for (const stale of ['rung > (int)Period()', 'tf <= Period()', 'tf <= (int)Period()'])
      if (joined.includes(stale)) broken.push(`a gate still hides the chart's own rung: \`${stale}\``);
    if (!joined.includes('htf >= chartTf'))
      broken.push('HTFViewportBarTarget must cap the chart-own-rung case too (`htf >= chartTf`)');
    if (!joined.includes('span <= 0.0'))
      broken.push('HTFCandleGeometry must treat only span 0 as the collapse (`span <= 0.0`)');
    if (joined.includes('span < 2.0'))
      broken.push('`span < 2.0` sends the chart-own-period candle to the calendar fallback');
    if (broken.length) {
      failures.push('P-HTF-TOP: ' + broken.join('; ') + ' (Biotak/HTFCandles_*.mqh)');
    } else {
      console.log(
        "[PASS] P-HTF-TOP the chart's own rung draws (Biotak/HTFCandles_Geom.mqh ResolveHTFPeriod)"
      );
    }
  }

  // -- 16. P-HTF-SYN: the two rungs ABOVE the tallest terminal TF ---------------
  //
  // Added 2026-09-30 («کندل های 12 ماه رو میشه برای ساختار و شش ماه میشه پترنش» /
  // «برای ماهانه و بری ای ویگی میشه 6 ماه ساختارش»). MN1 is the tallest series MT4
  // builds, so a W1 chart's structure rung (16 weeks) and a MONTHLY chart's (16
  // months) both snapped DOWN onto MN1 — the overlay drew the chart's own candles.
  // The ladder gains 6M (259200) and 12M (518400) and NO 3M entry: that is what
  // makes the UNCHANGED nearest-snap answer 6M for W1-Structure, 12M for
  // MN-Structure and 6M for MN-Pattern. Neither rung has a terminal series, so the
  // OHLC is aggregated from MN1 (HTFSynBarOpen/HTFSynOHLC) — and every reader of a
  // series had to learn that: the history pass, the forming candle, the ready check
  // and the badge.
  {
    const joined = htfFiles()
      .map((f) => codeOf(linesOf(path.join(BIOTAK, f)) || []))
      .join('\n');
    const broken = [];
    const ladder = '{1, 5, 15, 30, 60, 240, 1440, 10080, 43200, 259200, 518400}';
    if (!joined.includes(ladder))
      broken.push(`the TF ladder must carry 6M/12M and no 3M (${ladder})`);
    for (const name of [
      '#define HTF_TF_6M  259200',
      '#define HTF_TF_12M 518400',
      'HTFTfIsSynthetic(',
      'HTFSynMonths(',
      'HTFSynBarOpen(',
      'HTFSynBarCount(',
      'HTFSynOHLC(',
    ])
      if (!joined.includes(name)) broken.push(`missing \`${name}\``);
    const pass = htfFind('int DrawHTFCandles()');
    const passBody = pass ? bodyOf(pass.lines, 'int DrawHTFCandles()') : null;
    if (!passBody || !passBody.text.includes('HTFSynOHLC(') || !passBody.text.includes('HTFSynBarCount('))
      broken.push('the history pass must build a synthetic rung from MN1');
    const form = htfFind('bool UpdateHTFFormingCandle()');
    const formBody = form ? bodyOf(form.lines, 'bool UpdateHTFFormingCandle()') : null;
    if (!formBody || !formBody.text.includes('HTFSynOHLC('))
      broken.push('the live candle of a synthetic rung must aggregate MN1 too');
    const ens = htfFind('void HTFEnsureDrawn()');
    const ensBody = ens ? bodyOf(ens.lines, 'void HTFEnsureDrawn()') : null;
    if (!ensBody || !ensBody.text.includes('HTFSynBarCount('))
      broken.push('the ready check must ask MN1 for a synthetic rung, not iBars(6M/12M)');
    const menu = codeOf(linesOf(path.join(BIOTAK, 'BiotakMenu_A.mqh')) || []);
    if (!menu.includes('periodMinutes / 43200'))
      broken.push('CircHtfBadgeLabel must name the synthetic rungs in MONTHS (6M/12M)');
    if (broken.length) {
      failures.push('P-HTF-SYN: ' + broken.join('; ') + ' (Biotak/HTFCandles_*.mqh)');
    } else {
      console.log(
        '[PASS] P-HTF-SYN ladder 6M/12M present and built from MN1 (Biotak/HTFCandles_Geom.mqh HTFSnapTf)'
      );
    }
  }

  console.log('');
  if (failures.length) {
    for (const f of failures) console.log(`[FAIL] ${f}`);
    console.log('');
    console.log('REGRESSION GATE FAILED');
    process.exit(1);
  }
  console.log('REGRESSION GATE PASSED');
  process.exit(0);
}

if (require.main === module) main();

module.exports = { ROOT };
