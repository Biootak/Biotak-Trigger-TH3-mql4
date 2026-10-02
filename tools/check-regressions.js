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
// P-DRAW-93/94/95/96 (2026-09-30): the strip panel's own four. The layout ORDER
// (`DrawStrip_GearA`), the gear hit test's seat (`DrawStrip_Base`), the recent tap's
// one writer and the foot Reset's owed mid re-ink (`DrawStrip_Tap`).
const GEAR_A = path.join(BIOTAK, 'DrawStrip_GearA.mqh');
const GEAR_B = path.join(BIOTAK, 'DrawStrip_GearB.mqh');
const STRIP_BASE = path.join(BIOTAK, 'DrawStrip_Base.mqh');
const STRIP_HEAD = path.join(BIOTAK, 'DrawStrip_Head.mqh');
const STRIP_SKIN = path.join(BIOTAK, 'DrawStrip_Skin.mqh');
const GEAR_GATE = path.join(__dirname, 'check-gear-panel.py');
// P-DRAW-118: the card surface's own number table — the panel's quick row reads
// PNL_QSW_N and PNL_WEL from it, so the register resolves those names where the
// compiler does (the entry includes it ABOVE the strip, P-DRAW-116).
const CARD_METRICS = path.join(BIOTAK, 'CardMetrics.mqh');
const STRIP_TAP = path.join(BIOTAK, 'DrawStrip_Tap.mqh');
const STRIP_ROUTER = path.join(BIOTAK, 'DrawStrip_Router.mqh');
const RES_GATE = path.join(__dirname, 'check-resources.js');
const STRIP_PAINT = path.join(BIOTAK, 'DrawStrip_Paint.mqh');
const STRIP_PICK = path.join(BIOTAK, 'DrawStrip_Pick.mqh');
const BUILD_PS1 = path.join(ROOT, 'compile-th3.ps1');

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
  const gearA = linesOf(GEAR_A);
  const gearB = linesOf(GEAR_B);
  const stripBase = linesOf(STRIP_BASE);
  const stripHead = linesOf(STRIP_HEAD);
  const stripSkin = linesOf(STRIP_SKIN);
  const stripTap = linesOf(STRIP_TAP);
  // P-DRAW-97..105 (2026-09-30): the strip panel UI/UX audit. The event router's two
  // release channels, the colour board's page seats and the one painter.
  const stripRouter = linesOf(STRIP_ROUTER);
  const stripPaint = linesOf(STRIP_PAINT);
  const stripPick = linesOf(STRIP_PICK);

  for (const [name, lines] of [
    ['Labels_B.mqh', labelsB], ['Labels_A.mqh', labelsA], ['EventHandlers_Router.mqh', router],
    ['EventHandlers_Calc.mqh', calc], ['HTFCandles.mqh', htf], ['VisibilityManager.mqh', vis],
    ['BiotakPanels_Apply.mqh', apply], ['BiotakPanels_PalB.mqh', palB],
    ['EventHandlers_Objects.mqh', obj], ['LevelPipe_A.mqh', pipeA], ['LevelPipe_B.mqh', pipeB],
    ['DrawStrip_Router.mqh', stripRouter], ['DrawStrip_Paint.mqh', stripPaint],
    ['DrawStrip_Pick.mqh', stripPick],
    ['BiotakMenu_D.mqh', menuD],
    ['DrawStrip_GearA.mqh', gearA], ['DrawStrip_GearB.mqh', gearB],
    ['DrawStrip_Base.mqh', stripBase], ['DrawStrip_Tap.mqh', stripTap],
    ['DrawStrip_Head.mqh', stripHead], ['DrawStrip_Skin.mqh', stripSkin],
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

  // -- 17. P-DRAW-93: the colour board is placed AFTER the pass derived the rects --
  //
  // «زبان پنل استریپ» / the colour board's dock. `DrawStripBoardPlace` scores its four
  // candidates against the strip's own rect (`s_dsW`/`s_dsH`) and the panel's
  // (`s_dsGearW0`/`s_dsGearH`). It stood inside the picker branch, ABOVE the writes that
  // produce them, so it scored against the PREVIOUS pass's plate: open the width list,
  // tap the colour seat, and the fresh board docked 200px under a strip that is 48 tall
  // — or clamped to the window's edge on a small chart. Measured by
  // `node tools/stale_state_check.js` (9 findings, 5 of them this one order).
  {
    const broken = [];
    const body = bodyOf(gearA, 'void DrawStripLayout()');
    if (!body) {
      broken.push('DrawStripLayout() is gone from Biotak/DrawStrip_GearA.mqh');
    } else {
      const call = indexOfLine(gearA, 'DrawStripBoardPlace();', body.from);
      const wStrip = indexOfLine(gearA, 's_dsW = maxW;', body.from);
      const wPanel = indexOfLine(gearA, 's_dsGearW0 = s_dsGearW;', body.from);
      if (call < 0 || call > body.to)
        broken.push('the pass must still place the colour board (`DrawStripBoardPlace();`)');
      if (wStrip < 0) broken.push('the pass must still derive `s_dsW = maxW;`');
      if (wPanel < 0) broken.push('the pass must still derive `s_dsGearW0 = s_dsGearW;`');
      if (call >= 0 && wStrip >= 0 && call < wStrip)
        broken.push('the board is placed before the STRIP\u2019s own rect is derived (it reads s_dsW/s_dsH)');
      if (call >= 0 && wPanel >= 0 && call < wPanel)
        broken.push('the board is placed before the PANEL\u2019s own rect (it reads s_dsGearW0/s_dsGearH)');
    }
    // and the gate that reads the ORDER must run in every build, or this class is
    // unguarded the moment two edits meet again.
    const ps1 = linesOf(BUILD_PS1);
    if (!ps1) broken.push('compile-th3.ps1 is missing (the build is the only entry point)');
    else if (indexOfLine(ps1, 'stale_state_check.js') < 0)
      broken.push('the ORDER gate is not run by the build — re-add `node tools/stale_state_check.js` to compile-th3.ps1 (or delete this entry and say so in the report)');
    if (broken.length) {
      failures.push('P-DRAW-93: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearA.mqh DrawStripLayout)');
    } else {
      console.log('[PASS] P-DRAW-93 colour board placed after the pass derived its rects (Biotak/DrawStrip_GearA.mqh:761-775)');
    }
  }

  // -- 18. P-DRAW-94: the gear hit test's edit probe reads the PAINT's own seat -----
  //
  // `DrawStripGearPaint` puts a field at `px + s_dsGearEditCol[e] * DSTRIP_GEAR_COL +
  // s_dsGearEditX[e]` (the WIDE pass writes that column); `DrawStripGearHit` probed
  // `px + s_dsGearEditX[e]`. On a wide tab (a fibo's Levels) the "add a level" field was
  // DRAWN in the right column and probed in the left: unfocusable by clicking it, and a
  // click on the empty left column at that row focused a field 312px away.
  {
    const broken = [];
    const term = 's_dsGearEditCol[e] * DSTRIP_GEAR_COL';
    const hit = bodyOf(stripBase, 'bool DrawStripGearHit(');
    const paint = bodyOf(gearB, 'bool DrawStripGearPaint()');
    if (!hit) broken.push('DrawStripGearHit() is gone from Biotak/DrawStrip_Base.mqh');
    else if (!hit.text.includes(term))
      broken.push('the hit test must add the field\u2019s own column (`' + term + '`)');
    if (!paint) broken.push('DrawStripGearPaint() is gone from Biotak/DrawStrip_GearB.mqh');
    else if (!paint.text.includes(term))
      broken.push('the paint must still place a field on its column (`' + term + '`)');
    if (hit && /=\s*px \+ s_dsGearEditX\[e\]\s*;/.test(hit.text))
      broken.push('the old column-free probe (`px + s_dsGearEditX[e]`) is back');
    if (broken.length) {
      failures.push('P-DRAW-94: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh DrawStripGearHit)');
    } else {
      console.log('[PASS] P-DRAW-94 gear field probe carries the paint\u2019s own column (Biotak/DrawStrip_Base.mqh DrawStripGearHit)');
    }
  }

  // -- 19. P-DRAW-95: one FILL-show writer in the recent tap -------------------------
  //
  // The pair `if(DrawStripIsColorSlot(...) && s_dsPicker == DRAW_SLOT_FILLCLR)
  // DrawStripFillShowGroup();` was pasted twice in the same function: two writers of one
  // act, and every recent tap walked the group once per copy.
  {
    const body = bodyOf(stripTap, 'bool DrawStripPickTapRecent(');
    if (!body) {
      failures.push('P-DRAW-95: DrawStripPickTapRecent() is gone from Biotak/DrawStrip_Tap.mqh');
    } else {
      const n = (body.text.match(/DrawStripFillShowGroup\(\);/g) || []).length;
      if (n !== 1) {
        failures.push('P-DRAW-95: the recent tap must SHOW the interior through ONE `DrawStripFillShowGroup()` call, found ' + n + ' (Biotak/DrawStrip_Tap.mqh)');
      } else {
        console.log('[PASS] P-DRAW-95 recent tap shows the interior once (Biotak/DrawStrip_Tap.mqh DrawStripPickTapRecent)');
      }
    }
  }

  // -- 20. P-DRAW-96: the foot's Reset re-inks the box it just changed ---------------
  //
  // `DrawPresetApply` writes DRAW_SLOT_COLOR, so every colour path owes the box's own
  // `mid` line the new ink (P-DRAW-64a). The foot's Reset was the one that did not: the
  // 50 % line kept the pre-Reset border colour until the pump's next 2 s pass.
  {
    const body = bodyOf(stripTap, 'bool DrawStripFootTap(');
    if (!body) {
      failures.push('P-DRAW-96: DrawStripFootTap() is gone from Biotak/DrawStrip_Tap.mqh');
    } else {
      // the SEAT's own window, not the whole function: the Reset branch is `f == 0`,
      // and a call in the Copy branch would not be the fix.
      const seat = body.text.slice(body.text.indexOf('f == 0'),
                                   body.text.indexOf('f == 1'));
      if (!/BoxMidSync(Served|Group)\(\);/.test(seat)) {
        failures.push('P-DRAW-96: the foot\u2019s Reset writes the border colour (`DrawPresetApply(s_dsObj, 0)`) and must re-ink the box\u2019s mid through `BoxMidSyncServed()` in the same branch (Biotak/DrawStrip_Tap.mqh DrawStripFootTap)');
      } else {
        console.log('[PASS] P-DRAW-96 foot Reset re-inks the served box\u2019s mid (Biotak/DrawStrip_Tap.mqh DrawStripFootTap)');
      }
    }
  }

  // -- 21. P-DRAW-97: the colour scrub's release resolves on the channel that carries it
  //
  // A press on a swatch starts the preview on the press EDGE (DrawStripGripMove) and a
  // MOTIONLESS release emits no MOUSE_MOVE (P-LM-13) — the terminal's own note, and the
  // reason the CHARTEVENT_CLICK branch exists at all. That branch called only
  // DrawStripGripRelease(), which clears `s_dsPalGrab` and nothing else, so
  // `DrawSlotPreviewColor`'s OBJPROP_COLOR write (the pixels, NOT the pure tag its own
  // property is read from) was left standing: the shape wore a colour its tags did not
  // name, the swatch stayed rimmed, the panel and the HEX field kept the old value and
  // no undo step existed.
  {
    const broken = [];
    const router = bodyOf(stripRouter, 'bool DrawStripOnEvent(');
    if (!router) broken.push('DrawStripOnEvent() is gone from Biotak/DrawStrip_Router.mqh');
    else {
      // the CLICK branch's own window: from its `if(id == CHARTEVENT_CLICK)` line to the
      // dismissal test, so a call in the move path (which was always there) cannot pass.
      const at = router.text.indexOf('if(id == CHARTEVENT_CLICK)');
      const seat = at >= 0 ? router.text.slice(at, router.text.indexOf('DrawStripPointInside', at)) : '';
      if (at < 0) broken.push('the CHARTEVENT_CLICK branch is gone');
      else if (!/DrawStripPalRelease\(/.test(seat))
        broken.push('the release on this branch must call `DrawStripPalRelease(rcx, rcy)` BEFORE `DrawStripGripRelease()`');
      else if (!/if\(s_dsPalGrab\)\s*DrawStripPalRelease\(/.test(seat))
        broken.push('the scrub must be resolved under its own `s_dsPalGrab` guard, not unconditionally');
      else if (seat.indexOf('DrawStripPalRelease(') > seat.indexOf('DrawStripGripRelease();'))
        broken.push('the scrub must APPLY first and the one ender second (the move path\u2019s order)');
    }
    if (broken.length) {
      failures.push('P-DRAW-97: ' + broken.join('; ') + ' (Biotak/DrawStrip_Router.mqh DrawStripOnEvent)');
    } else {
      console.log('[PASS] P-DRAW-97 the scrub\u2019s motionless release commits on the CLICK channel (Biotak/DrawStrip_Router.mqh DrawStripOnEvent)');
    }
  }

  // -- 22. P-DRAW-98: a painted gear field is a reachable gear field -----------------
  //
  // `DrawStripGearPaint` gives a field `int ew = (s_dsGearEditW[e] > 0) ?
  // s_dsGearEditW[e] : cw` — the WHOLE cell when the slot has no measured width. Only
  // the two Paint-tab hex fields ever set one, so `add a level` (e1), `Caption` (e2) and
  // `Template name` (e3) were drawn as full-width OBJ_EDITs while `DrawStripGearHit`
  // skipped them on `s_dsGearEditW[e] <= 0`. Every painter in the family is born
  // `OBJPROP_SELECTABLE=false`, so the terminal could not reach them either: on the two
  // tabs the gear-panel gate measures narrow (Look 312, Text 312) that is every field
  // but the two hex ones.
  {
    const broken = [];
    const hit = bodyOf(stripBase, 'bool DrawStripGearHit(');
    if (!hit) broken.push('DrawStripGearHit() is gone from Biotak/DrawStrip_Base.mqh');
    else {
      if (/if\(s_dsGearEditW\[e\]\s*<=\s*0\)\s*continue;/.test(hit.text))
        broken.push('the `s_dsGearEditW[e] <= 0` skip is back \u2014 the paint does NOT skip that field, it falls back to the cell width');
      if (!/if\(s_dsGearEditY\[e\]\s*<\s*0\)\s*continue;/.test(hit.text))
        broken.push('the probe must guard on the paint\u2019s own `s_dsGearEditY[e] >= 0` (which is exactly the paint\u2019s `want`)');
      if (!/int ew = \(s_dsGearEditW\[e\] > 0\) \? s_dsGearEditW\[e\] : DrawStripGearCellW\(\);/.test(hit.text))
        broken.push('the probe must carry the paint\u2019s own width expression, fallback included (`DrawStripGearCellW()`)');
      if (!/mx < ex \+ ew/.test(hit.text))
        broken.push('the probe\u2019s x test must use that `ew`, not the raw seat width');
    }
    if (broken.length) {
      failures.push('P-DRAW-98: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh DrawStripGearHit)');
    } else {
      console.log('[PASS] P-DRAW-98 every painted gear field is reachable (Biotak/DrawStrip_Base.mqh DrawStripGearHit)');
    }
  }

  // -- 23. P-DRAW-99: one COLUMN\u2019s cell is 280 on every tab, and it is one owner ----
  //
  // `DrawStripGearColW()` is the tab\u2019s whole content box: 280 on a 312 tab, 592 on a
  // 624 one. A 624 tab is TWO columns at a `DSTRIP_GEAR_COL` (312) pitch, so each column
  // is 280 with a 32px gutter and 312 + 280 = 592 closes the box. Two readers asked the
  // BOX instead of the column and got two different wrong answers:
  //   * DrawStripGearResizeEdits re-measured a field the wide pass had moved into
  //     column 1 against 592 \u2014 the Levels tab\u2019s `add a level` ended at
  //     `s_dsGEX+920` on a card that ends at `s_dsGEX+624`: 296px of live text field.
  //   * DrawStripGearHit probed a list row 592 wide while the paint gave it 280, so
  //     312px of bare plate to the right of every Style/Row row acted as that row.
  // P-DRAW-90 had already moved the FOOT off `colW` and named this hazard; the rows and
  // the field were the readers it did not reach.
  {
    const broken = [];
    const gearA = linesOf(GEAR_A) || [];
    const def = indexOfLine(gearA, 'int DrawStripGearCellW()');
    if (def < 0) broken.push('the owner `DrawStripGearCellW()` is gone from Biotak/DrawStrip_GearA.mqh');
    else if (!/return DSTRIP_GEAR_W - 2 \* DSTRIP_GEAR_PAD;/.test(gearA[def]))
      broken.push('`DrawStripGearCellW()` must stay `DSTRIP_GEAR_W - 2 * DSTRIP_GEAR_PAD` (280 on every tab)');
    // the four readers, and the shape of each
    const resize = bodyOf(linesOf(GEAR_A) || [], 'void DrawStripGearResizeEdits()');
    if (!resize) broken.push('DrawStripGearResizeEdits() is gone from Biotak/DrawStrip_GearA.mqh');
    else if (/int colW = DrawStripGearColW\(\);/.test(resize.text))
      broken.push('the wide pass must re-measure a moved field against the COLUMN (`DrawStripGearCellW()`), not the 592 content box');
    const hit = bodyOf(stripBase, 'bool DrawStripGearHit(');
    if (!hit) broken.push('DrawStripGearHit() is gone from Biotak/DrawStrip_Base.mqh');
    else if (/mx >= rx \|\| mx >= rx \+ colW/.test(hit.text))
      broken.push('the list row is still probed against the content box `colW`; it must use the painted cell width');
    else if (!/int rowW = DrawStripGearCellW\(\);/.test(hit.text))
      broken.push('the list row must read the painted cell width from `DrawStripGearCellW()`');
    for (const [tag, ret, file] of [
      ['DrawStripGearPaint', 'bool ', gearB],
      ['DrawStripGearContent', 'void ', linesOf(GEAR_A) || []],
      ['DrawStripGearGridChips', 'bool ', linesOf(GEAR_A) || []],
    ]) {
      const b = bodyOf(file, ret + tag + '(');
      if (!b) { broken.push(tag + '() is gone from its file'); continue; }
      if (/int cw = DSTRIP_GEAR_W - 2 \* DSTRIP_GEAR_PAD;/.test(b.text))
        broken.push(tag + '() writes the cell width as a second literal; it must read `DrawStripGearCellW()`');
    }
    if (broken.length) {
      failures.push('P-DRAW-99: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearA.mqh DrawStripGearCellW + its four readers)');
    } else {
      console.log('[PASS] P-DRAW-99 one column\u2019s cell is one owner, read by the field, the row, the chips and the hit test (Biotak/DrawStrip_GearA.mqh)');
    }
  }

  // -- 24. P-DRAW-100: the HEX field follows the drawing, and the commit lets go
  //
  // `DrawStripEdit` wrote `OBJPROP_TEXT` once, inside the create, so the Paint tab's
  // `COLOR`/`FILL` boxes stated the colour the drawing wore the first time the tab was
  // opened and nothing ever changed them \u2014 press `Reset` in the foot and the drawing
  // changed while the field kept the old hex. The board\u2019s own hex field had solved
  // this and its law is the one copied here: a guarded write that follows the value, and
  // an EMPTY seed never writes so the field being typed in keeps the hand\u2019s word. The
  // guard is `s_dsHexFocus`.
  //
  // P-DRAW-118 (2026-10-01) MOVED THIS SITE: the panel\u2019s two hex boxes are retired
  // (a colour is a swatch now), so the ONE hex field left in the product is the
  // BOARD\u2019s, behind the colour row\u2019s `+`. The check therefore asks the board\u2019s
  // own pair \u2014 the guarded seed and the release AFTER the parse guard \u2014 and asks
  // that the panel\u2019s colour seats are really gone (a retired field\u2019s name that is
  // still created is an orphan, Touch rule 2; a colour write outside the owner is a
  // second writer, Touch rule 6).
  {
    const broken = [];
    const edit = bodyOf(gearB, 'bool DrawStripEdit(');
    // the SIGNATURE, as lines (never a joined string cut with line indices).
    const iEdit = indexOfLine(gearB, 'bool DrawStripEdit(');
    const iHex = indexOfLine(gearB, 'bool DrawStripPopHex(');
    const sig = (iEdit >= 0 && iHex > iEdit) ? gearB.slice(iEdit, iHex).join('\n') : '';
    if (!edit) broken.push('DrawStripEdit() is gone from Biotak/DrawStrip_GearB.mqh');
    else if (!/const bool reseed/.test(sig))
      broken.push('DrawStripEdit() must take the caller\u2019s `reseed` word');
    // the board\u2019s hex field: seeded from the colour it states, withheld while typed in
    // (the SEED is the board paint\u2019s, and the board is the one hex field left).
    if (!/s_dsHexFocus\s*\?\s*""\s*:\s*DrawStripColorHex\(/.test(codeOf(stripPaint)))
      broken.push('the hex field must withhold its seed while `s_dsHexFocus` (an empty seed is the field\u2019s own word)');
    const hexEnd = bodyOf(stripTap, 'bool DrawStripPopHexEnd(');
    if (!hexEnd)
      broken.push('DrawStripPopHexEnd() is gone from Biotak/DrawStrip_Tap.mqh: the hex commit has no owner');
    else {
      const guard = hexEnd.text.indexOf('if(!DrawStripHexToColor(ObjectGetString(0, nm, OBJPROP_TEXT), c)) return true;');
      const rel = hexEnd.text.indexOf('s_dsHexFocus = false;');
      if (guard < 0)
        broken.push('the hex commit lost its parse guard');
      else if (rel < 0 || rel < guard)
        broken.push('the hex commit must release `s_dsHexFocus` AFTER the guard, so an unparsable word keeps the field');
    }
    // the PANEL\u2019s two colour fields are retired, and the colour they wrote has ONE
    // owner (`DrawStripColorCommit`), which the palette cell, the quick swatch and the
    // board\u2019s hex all call.
    const end = bodyOf(stripTap, 'bool DrawStripEditEnd(');
    if (!end) broken.push('DrawStripEditEnd() is gone from Biotak/DrawStrip_Tap.mqh');
    else if (/DrawStripWriteValue\(DRAW_SLOT_COLOR|DrawStripWriteValue\(DRAW_SLOT_FILLCLR|DrawStripColorCommit\(/.test(end.text))
      broken.push('DrawStripEditEnd() still writes a COLOUR: the panel\u2019s hex boxes are retired, so a colour edit here is a second writer');
    if (!codeOf(stripTap).includes('bool DrawStripColorCommit('))
      broken.push('DrawStripColorCommit() is gone: the colour has no single owner');
    const pickApply = bodyOf(stripTap, 'bool DrawStripPickApply(');
    if (!pickApply || !/return DrawStripColorCommit\(slot, DrawStripPickColor\(slot, row\)\);/.test(pickApply.text))
      broken.push('the palette cell must apply through the colour\u2019s owner (DrawStripColorCommit), not its own copy of the writes');
    if (broken.length) {
      failures.push('P-DRAW-100: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh DrawStripPopHex + Biotak/DrawStrip_Tap.mqh DrawStripPopHexEnd/DrawStripColorCommit)');
    } else {
      console.log('[PASS] P-DRAW-100 the hex field follows the drawing and its commit releases the focus (Biotak/DrawStrip_GearB.mqh DrawStripPopHex)');
    }
  }

  // -- 25. P-DRAW-101: a plate that will not build is not a reason to build nothing ---
  //
  // `if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;` \u2014 and the `return`
  // is the WHOLE painter. One refused object name took the grip, the badge, the quick
  // cells, the actions, the colour board, its RECENT band, the HEX field, the opacity
  // bar, the popover AND the three calls that place, plate and paint the gear panel,
  // with `dirty` never reaching ChartRedraw. Three surfaces to nothing over one rect.
  {
    const broken = [];
    const paint = bodyOf(stripPaint, 'void DrawStripPaint()');
    if (!paint) broken.push('DrawStripPaint() is gone from Biotak/DrawStrip_Paint.mqh');
    else {
      if (/if\(!ObjectCreate\(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0\)\)\s*return;/.test(paint.text))
        broken.push('the failed-create `return` is back \u2014 it must degrade to the previous look, never to nothing');
      if (!/if\(ObjectCreate\(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0\)\)/.test(paint.text))
        broken.push('the create must be the branch\u2019s CONDITION, so the rest of the strip still paints');
    }
    if (broken.length) {
      failures.push('P-DRAW-101: ' + broken.join('; ') + ' (Biotak/DrawStrip_Paint.mqh DrawStripPaint)');
    } else {
      console.log('[PASS] P-DRAW-101 a refused plate degrades, it does not take the three surfaces with it (Biotak/DrawStrip_Paint.mqh DrawStripPaint)');
    }
  }

  // -- 26. P-DRAW-102: `s_dsGearPressSpent` is ONE gesture\u2019s flag --------------------
  //
  // Armed by the panel\u2019s coordinate channel on the press edge, spent by the release that
  // follows, and cleared only by the panel\u2019s close and the strip\u2019s. A press whose
  // release the terminal never reported as a click (the hand let go outside the chart
  // window) left it armed, and the NEXT click on the chart was spent as a twin release:
  // the click the user made to dismiss the strip did nothing and the one after it
  // worked.
  {
    const broken = [];
    const edge = bodyOf(stripRouter, 'bool DrawStripOnEvent(');
    if (!edge) broken.push('DrawStripOnEvent() is gone from Biotak/DrawStrip_Router.mqh');
    else {
      // the ASSIGNMENTS, not the prose: a comment names the flag too.
      const clear = edge.text.indexOf('s_dsGearPressSpent = false;');
      const arm = edge.text.indexOf('s_dsGearPressSpent = true;');
      if (clear < 0) broken.push('the press edge must clear `s_dsGearPressSpent` before the channel below may re-arm it');
      else if (arm < 0) broken.push('the panel\u2019s coordinate channel no longer arms `s_dsGearPressSpent`');
      else if (clear > arm) broken.push('the clear must come BEFORE `s_dsGearPressSpent = true;` (it is this press\u2019s flag)');
    }
    if (broken.length) {
      failures.push('P-DRAW-102: ' + broken.join('; ') + ' (Biotak/DrawStrip_Router.mqh DrawStripOnEvent)');
    } else {
      console.log('[PASS] P-DRAW-102 a new press edge re-arms the panel\u2019s spent flag (Biotak/DrawStrip_Router.mqh DrawStripOnEvent)');
    }
  }

  // -- 27. P-DRAW-103: the X\u2019s hit box IS the X\u2019s painted rect ----------------------
  //
  // The painted control is a 26x26 square (the cards\u2019 own XBTN) and the probe was a
  // CIRCLE of radius `26/2 + 3` = 16. On the diagonal the circle ends 11.3px from the
  // centre and the corner sits 18.4px out, so a 3.7px dead triangle sat at each corner
  // of the one control that closes the panel. The 3px thumb pad on every side is kept,
  // so the 13px seam with the carry (P-DRAW-36 stops the grip 16px short of the corner)
  // is unchanged.
  {
    const broken = [];
    const hit = bodyOf(stripBase, 'bool DrawStripGearHit(');
    if (!hit) broken.push('DrawStripGearHit() is gone from Biotak/DrawStrip_Base.mqh');
    else {
      if (/mxp \* mxp \+ myp \* myp <= half \* half/.test(hit.text))
        broken.push('the circular X probe is back; the hit box must be the painted 26x26 rect plus its pad');
      if (!/mx >= cx0 - xpad && mx < cx0 \+ xbtn \+ xpad/.test(hit.text))
        broken.push('the X probe must test the square it paints, padded on all four sides');
    }
    if (broken.length) {
      failures.push('P-DRAW-103: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh DrawStripGearHit)');
    } else {
      console.log('[PASS] P-DRAW-103 the panel X\u2019s hit box is the rect it paints (Biotak/DrawStrip_Base.mqh DrawStripGearHit)');
    }
  }

  // -- 28. P-DRAW-104: the two level-management rows are not part of the list budget ---
  //
  // The Levels tab looped the list to `nl` (capped at `DSTRIP_GLIST_MAX` = 16, because
  // `DrawStripGearLevelCount` caps the LIST at the row array\u2019s own ceiling) and then
  // asked for `All levels on` / `No levels` \u2014 which the same ceiling refused. At 9
  // common + 7 custom levels the only way to clear the level set in one gesture was not
  // built, and the only trace was a one-shot log line.
  {
    const broken = [];
    const content = bodyOf(linesOf(GEAR_A) || [], 'void DrawStripGearContent(');
    if (!content) broken.push('DrawStripGearContent() is gone from Biotak/DrawStrip_GearA.mqh');
    else {
      const at = content.text.indexOf('int nl = DrawStripGearLevelCount();');
      const seat = at >= 0 ? content.text.slice(at, content.text.indexOf('levelEdit = true;', at)) : '';
      if (at < 0) broken.push('the Levels branch is gone');
      else if (!/DSTRIP_GLIST_MAX - 2/.test(seat))
        broken.push('the list loop must reserve the two management rows\u2019 seats (`DSTRIP_GLIST_MAX - 2`)');
      else if (!/i < nl && i < room/.test(seat))
        broken.push('the list loop must stop at `room`, not at `nl`');
      else if ((seat.match(/DrawStripGearRow\(5, /g) || []).length !== 2)
        broken.push('both management rows must still be asked for');
    }
    if (broken.length) {
      failures.push('P-DRAW-104: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearA.mqh DrawStripGearContent)');
    } else {
      console.log('[PASS] P-DRAW-104 the Levels tab reserves both management rows (Biotak/DrawStrip_GearA.mqh DrawStripGearContent)');
    }
  }

  // -- 29. P-DRAW-105: a page seat is half-open, like the rect it paints ---------------
  //
  // `DrawStripPageAt` was `mx >= xa && mx <= xa+20` against a painter whose rect is
  // `[pgx+k*20, pgx+k*20+20)`, so the single column `pgx+20` belonged to seat 0 AND seat 1
  // at once \u2014 a 1px seam where the right arrow\u2019s own left edge turned the page
  // backwards.
  {
    const broken = [];
    const at = bodyOf(stripPick, 'int DrawStripPageAt(');
    if (!at) broken.push('DrawStripPageAt() is gone from Biotak/DrawStrip_Pick.mqh');
    else {
      if (/mx >= xa && mx <= xa\s*\+\s*20/.test(at.text))
        broken.push('the page seat is closed again; it must be half-open like the rect it paints');
      if (!/mx >= xa && mx < xa\s*\+\s*20/.test(at.text))
        broken.push('the page seat must test `mx < xa + 20`');
    }
    if (broken.length) {
      failures.push('P-DRAW-105: ' + broken.join('; ') + ' (Biotak/DrawStrip_Pick.mqh DrawStripPageAt)');
    } else {
      console.log('[PASS] P-DRAW-105 the board page seats are half-open, like their painted rects (Biotak/DrawStrip_Pick.mqh DrawStripPageAt)');
    }
  }

  // -- 30. P-DRAW-106: the size table IS the art, so it carries the art's canvas -----
  //
  // `DrawStripFaceZ` centres a raster in its cell as `x + (w - pw) / 2`, with
  // `pw = DrawStripResW(res)` — so a raster the table does not carry falls through to
  // `DrawStripIconPx`'s 0 and is placed HALF A CELL right and down. MEASURED on the
  // shipped files 2026-10-01: `pnl_btn_ghost.bmp` is 88x44 and had no entry, and the
  // gear panel's foot asks for it as `(fx - 8, fy - 8, bw + 16, 44)` — the 72x28
  // button plus its 8px pad — so all three foot plates shipped 44px right and 22px
  // below their buttons: under the plate's bottom edge, off their own labels, the
  // last one past the card's right edge. The same audit measured `bk_w`/`bk_style`/
  // `bk_ray` at 16 against 24x24 canvases and `gl_pin*`/`gl_textsize*`/`gl_layers*`
  // at 15 against 26x26 ones — a green compile never names any of it, because a size
  // in a chain of string tests is not a symbol.
  {
    const broken = [];
    const w = bodyOf(stripBase, 'int DrawStripResW(');
    const h = bodyOf(stripBase, 'int DrawStripResH(');
    const icon = bodyOf(stripBase, 'int DrawStripIconPx(');
    if (!w || !h || !icon) {
      broken.push('DrawStripResW/RH/IconPx are gone from Biotak/DrawStrip_Base.mqh');
    } else {
      // a rule's own statement: `if(StringFind(res, "x") >= 0 || StringFind(res, "y")
      // >= 0) return N;` is ONE statement with two prefixes, so the question is
      // "which N does the statement carrying this prefix return", asked per `;`.
      const rulesOf = (text) =>
        text.split(';').map((stmt) => ({
          pfx: [...stmt.matchAll(/StringFind\(res,\s*"([^"]+)"/g)].map((m) => m[1]),
          n: Number((stmt.match(/\breturn\s+(\d+)/) || [])[1]),
        }));
      const rule = (text, pfx, n) =>
        rulesOf(text).some((r) => r.pfx.some((p) => p === pfx || pfx.includes(p)) && r.n === n);
      if (!rule(w.text, 'pnl_btn_ghost', 88) || !rule(h.text, 'pnl_btn_ghost', 44))
        broken.push('`pnl_btn_ghost` must be answered 88x44 (its own canvas) — without it the foot ghost is placed half a cell off its button');
      for (const p of ['gl_pin', 'gl_textsize', 'gl_layers']) {
        if (!rule(w.text, p, 26) || !rule(h.text, p, 26))
          broken.push(`\`${p}*\` is a 26x26 canvas and must be answered 26`);
      }
      if (/StringFind\(res, "bk_w"\)|StringFind\(res, "bk_style"\)|StringFind\(res, "bk_ray"\)/.test(icon.text))
        broken.push('the retired `bk_w`/`bk_style`/`bk_ray` = 16 exception is back; every `bk_*` the strip paints is 24x24');
      if (!rule(icon.text, 'bk_', 24))
        broken.push('`bk_*` must be answered 24 (the shipped canvas), not 16');
      const foot = indexOfLine(gearB, 'pnl_btn_ghost.bmp');
      const footCall = foot < 0 ? '' : gearB.slice(Math.max(0, foot - 3), foot + 1).join('\n');
      if (foot < 0 || !/fx - 8/.test(footCall) || !/bw \+ 16/.test(footCall))
        broken.push('the foot must still ask for the ghost at `fx - 8, fy - 8, bw + 16, 44` (Biotak/DrawStrip_GearB.mqh) — the seat the table now centres correctly');
    }
    const gate = linesOf(RES_GATE);
    if (!gate || !gate.some((l) => l.includes('stripSizeDrift')) ||
        !gate.some((l) => l.includes('raster size table')))
      broken.push('tools/check-resources.js must assert the size table against the files (the class this defect belongs to)');
    if (broken.length) {
      failures.push('P-DRAW-106: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh + tools/check-resources.js)');
    } else {
      console.log('[PASS] P-DRAW-106 every raster the strip paints is answered at its own canvas (Biotak/DrawStrip_Base.mqh + tools/check-resources.js)');
    }
  }

  // -- 31. P-DRAW-107: the foot's ink is CENTRED on its button ----------------------
  //
  // P-DRAW-80 copied the cards' left-aligned pair (`glyph at bx+12`, `label at
  // bx+32`, BiotakPanels 6486-6507) onto this foot. A card's footer button is ~100px
  // wide; this foot's plate is `DSTRIP_GEAR_FOOT_BW` 72. MEASURED with the panel's own
  // metrics (`mt4.text_w`): `All` is 14px and began at `fx+16` inside a plate whose own
  // fill runs `fx+2 .. fx+70` — 14px of plate to its left and 40px to its right — so
  // the word hugged the left edge of the plate it names and the ring read as a mark
  // apart from its word (`Copy` 14/27, `Reset` 12/18 before its ring's own 15px).
  // Both seats now come from ONE centred group, `x0 = fx + (bw - adv - tw)/2`, with the
  // ring one `DSTRIP_GEAR_FOOT_GLYPH_ADV` inside it. It compiles green in either
  // shape, which is why this is a gate and not a note.
  {
    const broken = [];
    const lb = bodyOf(gearB, 'int DrawStripFootLabelX(');
    const gl = bodyOf(gearB, 'int DrawStripFootGlyphX(');
    const footAt = indexOfLine(gearB, 'pnl_btn_ghost.bmp');
    if (!lb || !gl) {
      broken.push('DrawStripFootLabelX/DrawStripFootGlyphX are gone from Biotak/DrawStrip_GearB.mqh');
    } else {
      if (!/DrawStripFootBw/.test(lb.text) || !/PnlTextW/.test(lb.text) ||
          !/DSTRIP_GEAR_FOOT_GLYPH_ADV/.test(lb.text))
        broken.push("DrawStripFootLabelX must centre the group: the button's own width, the glyph advance and the word's own width");
      if (/fx\s*\+\s*(16|32)\b/.test(lb.text) || /\?\s*16\s*:\s*32/.test(lb.text))
        broken.push("the cards' left-aligned seat (`fx + 16` / `fx + 32`) is back: the word hugs the plate's left edge");
      if (!/DrawStripFootLabelX\(f,\s*fx\)\s*-\s*DSTRIP_GEAR_FOOT_GLYPH_ADV/.test(gl.text))
        broken.push('DrawStripFootGlyphX must be ONE advance left of its word (only `Reset` wears a ring)');
      const win = footAt < 0 ? [] : gearB.slice(footAt, footAt + 24);
      if (!win.some((l) => /DrawStripFootGlyphName\(f\),\s*fgx,/.test(l)))
        broken.push("the foot paint must place the ring at `fgx` (DrawStripFootGlyphX), not the cards' own `fx + 12`");
      const adv = (stripHead || []).find((l) => /#define\s+DSTRIP_GEAR_FOOT_GLYPH_ADV/.test(l));
      if (!adv || !/#define\s+DSTRIP_GEAR_FOOT_GLYPH_ADV\s+20\b/.test(adv))
        broken.push("DSTRIP_GEAR_FOOT_GLYPH_ADV must stay 20 (the cards' own 32 - 12 relation): both seats read it");
    }
    if (broken.length) {
      failures.push('P-DRAW-107: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh DrawStripFootLabelX)');
    } else {
      console.log("[PASS] P-DRAW-107 the foot's ink is the centred group on its own button (Biotak/DrawStrip_GearB.mqh)");
    }
  }

  // -- 32. P-DRAW-108: a size rule never stands after a `//` ------------------------
  //
  // The `pnl_cntchip` W rule was written at the END of the `pnl_secdot` line, behind
  // that line's own `//` comment: the compiler read the whole `if` as text, so
  // DrawStripResW answered DrawStripIconPx's 0 for a 28x20 canvas and the section's
  // count pill — painted by DrawStripFaceZ in a `DSTRIP_SEC_CNT_W + 4` rect,
  // DrawStrip_GearB.mqh:842 — shipped 14px right and 10px down of its own rect, with
  // MT4 cropping the art to what was left of it. The rule owns its line now, and no
  // new one may share a line with a comment.
  {
    const broken = [];
    for (const l of stripBase) {
      const cm = l.indexOf('//');
      if (cm < 0) continue;
      if (/StringFind\(res,\s*"[^"]+"\)/.test(l.slice(cm)))
        broken.push('a size rule stands after a `//` on the same line: ' + l.trim().slice(0, 56));
    }
    if (!stripBase.some((l) => /^\s*if\(StringFind\(res, "pnl_cntchip"\) >= 0\) return 28;/.test(l)))
      broken.push('the `pnl_cntchip` W rule (28, its own canvas) is gone — the section count pill is placed half a cell off');
    if (broken.length) {
      failures.push('P-DRAW-108: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh DrawStripResW)');
    } else {
      console.log('[PASS] P-DRAW-108 no size rule shares its line with a comment (Biotak/DrawStrip_Base.mqh DrawStripResW)');
    }
  }

  // -- 33. P-DRAW-110: the composed W body starts at the HEAD's own edge ------------
  //
  // The three wide bakes are drawn from ONE origin, `gy - 14` (the plate's own 14px
  // margin), and the top cap is `14 + 56`: its pad is spent ABOVE the head, so the
  // head band ends at `gy + DSTRIP_GEAR_HEAD_H` (56) and the body must continue
  // THERE. The strip's copy started it at the cap's HEIGHT (`gy + 70`), so on the two
  // WIDE tabs — Style and Row, the only two that compose instead of baking — the body
  // sat 14px low: a 14px transparent band under the header (`gy+56 .. gy+70`) and the
  // foot cap ending at `gy + gh + 28` where the plate ends at `gy + gh + 14`.
  // MEASURED on the files: `pnl_cardWtop.bmp` 652x70 with opaque rows at y10..69,
  // `pnl_cardWmid.bmp` 652x42 with y0..41 — and `56 + 42*pairN + 62` = `gh + 14`.
  // The owner is the cards' own composition (BiotakPanels_Build.mqh:727-737, mids at
  // `py + PNL_HEAD_H + li*PNL_ROW_H`), so this is one law on two origins.
  {
    const broken = [];
    // the CODE, never the comment: this file now explains the retired `gy + 70`.
    const code = stripSkin
      .map((l) => { const i = l.indexOf('//'); return i >= 0 ? l.slice(0, i) : l; })
      .join('\n');
    if (!/DSTRIP_GEAR_HEAD_H \+ li \* 42/.test(code))
      broken.push("the W mid bands must start at DSTRIP_GEAR_HEAD_H (the head's own edge), not at the top cap's height");
    if (!/DSTRIP_GEAR_HEAD_H \+ pairN \* 42/.test(code))
      broken.push("the W foot cap must start at DSTRIP_GEAR_HEAD_H + pairN*42, like the cards' own composition");
    if (/gy \+ 70/.test(code))
      broken.push('`gy + 70` is back: the composed body is 14px low on Style and Row again');
    const gg = linesOf(GEAR_GATE);
    if (!gg || !gg.some((l) => l.includes('painted off the plate')))
      broken.push('tools/check-gear-panel.py must assert that nothing is painted beside the plate (the class this defect belongs to)');
    if (broken.length) {
      failures.push('P-DRAW-110: ' + broken.join('; ') + ' (Biotak/DrawStrip_Skin.mqh DrawStripGearPlate)');
    } else {
      console.log('[PASS] P-DRAW-110 the composed W plate closes on its own rect (Biotak/DrawStrip_Skin.mqh)');
    }
  }

  // -- 34. P-DRAW-117: the panel's nav is an ACCORDION, and a group is a ROW ------
  //
  // The user's order (2026-10-01): «پنل تنظیمات استریپ رو بکوب از نو بساز … پنل
  // تنظیمات ابجکت ها شو پاک کن و از نو با طرح جدید بساز … همون طرح قبلی رو دوباره
  // تحویل ندی ها». The horizontal TAB ROW is deleted: the groups are 42px rows of
  // the card's own grid — icon, name, and the value the group currently holds — and
  // the open group's settings HANG DIRECTLY UNDER THEIR OWN HEADER. None of the
  // ways back is visible to the compiler, so they are asserted here:
  //
  //   * the registry (order, conditions, count) has ONE owner, and the open group
  //     must be a member of it — an id the registry does not carry paints a panel
  //     whose every branch declines: a plate with no settings and no message;
  //   * the walk BRACKETS the open group (headers above, body, headers below), and
  //     a FOLDED group is asked for the id no group can have instead of an early
  //     return — a `return` there draws NOTHING where the old code drew the list
  //     (Touch rule 4);
  //   * the level list reserves the headers' OWN seats (`room = GLIST_MAX - 2 -
  //     s_dsGRN`): P-DRAW-104's defect — a mandatory row refused by a ceiling
  //     nobody re-derived — reopened in the new shape, which is why the reserve is
  //     a NAME in this register and not a number;
  //   * the retired band's NAMES are behaviour (Touch rule 2): `GT0..GT4`, `GTrack`
  //     and `GU` are swept by the panel's own purge AND by its paint, or a chart
  //     painted by the tab build wears both navs at once, and no compile can see it.
  {
    const broken = [];
    const biotakFiles = fs.readdirSync(BIOTAK).filter((n) => n.endsWith('.mqh'));
    const codeOfFile = (abs) => {
      const l = linesOf(abs);
      return l ? codeOf(l) : '';
    };
    const registry = bodyOf(gearA, 'int DrawStripGearGroups()');
    const walk = bodyOf(gearA, 'void DrawStripGearContent(');
    const gearACode = codeOf(gearA);
    const gearBCode = codeOf(gearB);
    const headCode = codeOf(stripHead);
    const tapCode = codeOf(stripTap);
    const baseCode = codeOf(stripBase);

    // (a) the registry: order, conditions, count, and the open group as a member.
    const wanted = [
      'DSTRIP_GEAR_PAINT', 'DSTRIP_GEAR_STYLE', 'DSTRIP_GEAR_LEVELS',
      'DSTRIP_GEAR_MARK', 'DSTRIP_GEAR_TPL', 'DSTRIP_GEAR_STRIP',
    ];
    if (!registry) {
      broken.push('DrawStripGearGroups() is gone: the group list has no owner (Biotak/DrawStrip_GearA.mqh)');
    } else {
      const ids = [...registry.text.matchAll(/s_dsGearGrp\[n \+ 1\] = (DSTRIP_GEAR_\w+)/g)].map((m) => m[1]);
      if (ids.join(',') !== wanted.join(','))
        broken.push(`the registry must read ${wanted.join(' · ')} in that order, it reads ${ids.join(' · ') || '(none)'}`);
      if (!/s_dsGearGrp\[0\] = n;/.test(registry.text))
        broken.push('the registry must record its count in `s_dsGearGrp[0]` — the only answer the row loop has');
      if (!/if\(DrawKindHasLevels\(s_dsKind\)\)/.test(registry.text) ||
          !/else if\(s_dsKind == DK_TEXT \|\| s_dsKind == DK_ARROW\)/.test(registry.text))
        broken.push('the Levels/Mark conditions are the registry\u2019s: a levels-kind gets Levels, TEXT/ARROW get Mark');
      if (!/if\(!ok\) s_dsGear = s_dsGearGrp\[1\];/.test(registry.text))
        broken.push('the open group must be re-seated into the registry, or the panel opens on an id no branch answers');
      // the six WRITE SITES are five groups: LEVELS and MARK sit on the same if/else
      // (a kind has one or the other), so the bound is `writes - 1` and a seventh
      // group added without raising the array fails HERE, at the number.
      const grpMax = Number((headCode.match(/#define DSTRIP_GEAR_GRP_MAX\s+(\d+)/) || [])[1]);
      if (grpMax !== ids.length - 1)
        broken.push(`DSTRIP_GEAR_GRP_MAX is ${grpMax || 'missing'}: ${ids.length} write site(s), one exclusive pair, so the array must hold ${ids.length - 1}`);
    }

    // (b) the accordion walk: headers above, the open body, headers below — and a
    // folded group is the LIST, never nothing.
    if (!walk) {
      broken.push('DrawStripGearContent() is gone: the accordion has no walk (Biotak/DrawStrip_GearA.mqh)');
    } else {
      const w = walk.text;
      if (!/int ng = DrawStripGearGroups\(\);/.test(w))
        broken.push('the walk must read the registry (`int ng = DrawStripGearGroups();`), not a second list');
      if (!/for\(int gb = 0; gb <= navAt; gb\+\+\)/.test(w) || !/for\(int ga = navAt \+ 1; ga < ng; ga\+\+\)/.test(w))
        broken.push('the headers must BRACKET the open group (gb <= navAt, then ga = navAt + 1) — the open group\u2019s rows hang under their own header');
      if (!/int gOpen = s_dsGearCollapsed \? -1 : s_dsGear;/.test(w))
        broken.push('a FOLDED group must ask for the id no group can have (`s_dsGearCollapsed ? -1 : s_dsGear`); a return here draws nothing (Touch rule 4)');
      if (/if\(\s*s_dsGearCollapsed\s*\)[^;]*return/.test(w))
        broken.push('a folded group returns early: the list it must keep painting is what disappears');
      const grpRows = (w.match(/DrawStripGearRow\(DSTRIP_GRK_GROUP, s_dsGearGrp\[/g) || []).length;
      if (grpRows < 2)
        broken.push('both header loops must paint a group row (`DrawStripGearRow(DSTRIP_GRK_GROUP, s_dsGearGrp[..., y)`)');
      if (!/int room = DSTRIP_GLIST_MAX - 2 - s_dsGRN;/.test(w))
        broken.push('the level list must reserve the headers\u2019 own seats (`room = DSTRIP_GLIST_MAX - 2 - s_dsGRN`) — P-DRAW-104 in the new shape');
      if (!/i % DSTRIP_GEAR_LVLBLK/.test(w))
        broken.push('a long level list must open a block every DSTRIP_GEAR_LVLBLK rows, or the wide pass cannot split inside it');
    }

    // (c) the retired tab band: the spelling in CODE, and the SWEEP of the names a
    // tab-era build already painted on a chart.
    const retired = [
      's_dsGearTabX', 's_dsGearTabW', 's_dsGearTabsY', 'DSTRIP_TAB_H', 'DSTRIP_TAB_GAP',
      'DSTRIP_TAB_PAD', 'DSTRIP_TAB_UL', 'DrawStripGearTabName', 'DrawStripGearTabLineName',
      'DrawStripGearTrackName', 'DrawStripGearTabTap', 'DSTRIP_GEAR_TAB_MAX',
    ];
    const back = [];
    for (const f of biotakFiles) {
      const c = codeOfFile(path.join(BIOTAK, f));
      for (const t of retired) if (c.includes(t)) back.push(`${f}: ${t}`);
    }
    if (back.length)
      broken.push('the retired tab row is back in CODE: ' + back.join('; '));
    for (const [nm, c] of [['DrawStrip_GearA.mqh', gearACode], ['DrawStrip_GearB.mqh', gearBCode]]) {
      for (const lit of ['"PnlDrawS_GT" + IntegerToString', '"PnlDrawS_GTrack"', '"PnlDrawS_GU"'])
        if (!c.includes(lit))
          broken.push(`${nm}: the sweep of the tab era\u2019s own names lost ${lit} — a chart painted by that build keeps them (Touch rule 2)`);
    }

    // (d) the group row's other half: the digest, and the kind every face knows.
    if (!baseCode.includes('DrawStripRowDigestName'))
      broken.push('DrawStripRowDigestName is gone (Biotak/DrawStrip_Base.mqh): the digest has no name to paint or to retire');
    if (!gearBCode.includes('string DrawStripGearGroupDigest(') || !gearBCode.includes('DSTRIP_GEAR_DG_PAD'))
      broken.push('the group row\u2019s value digest (DrawStripGearGroupDigest + DSTRIP_GEAR_DG_PAD) is gone from Biotak/DrawStrip_GearB.mqh');
    const kind9 = (gearBCode.match(/DSTRIP_GRK_GROUP/g) || []).length;
    if (kind9 < 4)
      broken.push(`kind DSTRIP_GRK_GROUP has ${kind9} branch(es) in GearB: the row\u2019s text, face, tip and open-state each answer it`);
    if (!tapCode.includes('if(kind == DSTRIP_GRK_GROUP) return DrawStripGearGroupTap(arg);') ||
        !tapCode.includes('bool DrawStripGearGroupTap('))
      broken.push('a group row\u2019s tap must route to DrawStripGearGroupTap (Biotak/DrawStrip_Tap.mqh) — a header that paints and does not answer is P-DRAW-84');

    // (e) the two cross-checks: the plate\u2019s own grid starts at the HEAD (a raised
    // DSTRIP_GEAR_GRID_TOP is the tab band back, silently), the mirror/gate still own
    // the faces and the hit boxes, and the terminal-side shot still sees the fold.
    if (!/#define DSTRIP_GEAR_GRID_TOP\s+\(DSTRIP_GEAR_HEAD_H\)/.test(headCode))
      broken.push('DSTRIP_GEAR_GRID_TOP must stay the HEAD\u2019s own edge (DSTRIP_GEAR_HEAD_H): a taller value is the retired band, silently');
    const gateCode = codeOf(linesOf(GEAR_GATE) || ['']);
    if (!gateCode.includes('all with a hit box') || !gateCode.includes('GROUP ARITY'))
      broken.push('tools/check-gear-panel.py must keep asserting the hit boxes and the group arity (the dead-button class, P-DRAW-84)');
    const shot = linesOf(path.join(ROOT, 'tests', 'Biotak_StripShot_Test.mq4')) || [];
    if (!shot.some((l) => l.includes('panel_fold')))
      broken.push('tests/Biotak_StripShot_Test.mq4 must shoot the FOLDED group (panel_fold) — the state whose bug is a blank plate');
    if (broken.length) {
      failures.push('P-DRAW-117: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearA.mqh + DrawStrip_GearB.mqh + DrawStrip_Head.mqh)');
    } else {
      console.log('[PASS] P-DRAW-117 the panel\u2019s nav is an accordion of group rows, and its retired band is swept (Biotak/DrawStrip_GearA.mqh)');
    }
  }

  // -- 35. P-DRAW-118: a colour is a SWATCH, and it has ONE owner -----------------
  //
  // User order (2026-10-01): «این color fill از همین جا بشه رنگها شو تغییر داد ... کد
  // رنگ چیکارش کنم ... پنل تنظیمات اصلی ... مثل همون بکنش ... یک جا یک پارچه باشه».
  // The panel's two hex BOXES are deleted and each colour role is the CARDS' own quick
  // row: the colour it holds now, the palette's first row (`QuickPalColor`), and a `+`
  // that opens the board (which keeps the HEX field). Four things a future edit can
  // undo, every one of them green-compiling:
  //
  //   * the row is BUILT once, into the seat arrays the paint and the hit test walk
  //     (`s_dsGG*` + `s_dsGGC`), and its count is the CARDS' `PNL_QSW_N` — a literal 8
  //     here is a second palette row;
  //   * it FITS the column: pad + preview + gap + n*(cell+gap) + plus <= plate - pad.
  //     A row 6px too wide paints past the plate's own edge and no gate sees pixels
  //     (the class the off-plate check belongs to, P-DRAW-110);
  //   * the swatch APPLIES THE COLOUR IT WEARS (`s_dsGGC[g]`), through the colour's
  //     ONE owner — the palette cell and the board's hex call the same write;
  //   * the retired hex fields are swept: the paint's own `!want` branch is what takes
  //     `DrawStripEditName(0)/(4)` off a chart that carried them (Touch rule 2).
  {
    const broken = [];
    const headCode118 = codeOf(stripHead);
    const gearACode118 = codeOf(gearA);
    const gearBCode118 = codeOf(gearB);
    const tapCode118 = codeOf(stripTap);
    const pickCode118 = codeOf(stripPick);

    // (a) the row builder: one preview, the palette's row, one `+`, one y.
    const row = bodyOf(gearA, 'bool DrawStripGearQuickRow(');
    if (!row) {
      broken.push('DrawStripGearQuickRow() is gone: a colour row has no builder (Biotak/DrawStrip_GearA.mqh)');
    } else {
      const r = row.text;
      if (!/qi < DSTRIP_GEAR_SWQ_N/.test(r))
        broken.push('the swatch count must be DSTRIP_GEAR_SWQ_N (the cards\u2019 own PNL_QSW_N), not a literal');
      if (!/s_dsGGKind\[g\] = DSTRIP_GRG_SWATCH/.test(r) || !/s_dsGGArg\[g\] = qi/.test(r))
        broken.push('every swatch must register itself in the grid arrays (kind + index) \u2014 the paint and the hit test read those');
      if (!/s_dsGGC\[g\]\s*= QuickPalColor\(qi\)/.test(r))
        broken.push('a swatch\u2019s colour must be QuickPalColor(qi) \u2014 P-DRAW-24\u2019s ONE palette (BioPal = BioPick row 0)');
      if (!/DSTRIP_GRG_PREV/.test(r) || !/DSTRIP_GRG_PLUS/.test(r))
        broken.push('the row must carry its own colour block AND the `+` opener');
      if (!/DrawStripGearGridStamp\(mark, y, DSTRIP_GRID_MAX\)/.test(r))
        broken.push('the strip must be stamped as ONE row (the grid stamp\u2019s own seat, P-DRAW-111)');
    }
    if (!/#define DSTRIP_GEAR_SWQ_N\s+PNL_QSW_N/.test(headCode118))
      broken.push('DSTRIP_GEAR_SWQ_N must alias the cards\u2019 PNL_QSW_N: two counts for one row is two palettes');

    // (b) the arithmetic: the row fits inside the column it is painted in.
    {
      const defines = {};
      for (const lines of [linesOf(CARD_METRICS), stripHead]) {
        for (const raw of lines || []) {
          const l = stripComment(raw);   // a trailing note is not part of the value
          const m = /^\s*#define\s+([A-Z0-9_]+)\s+([A-Za-z0-9_]+)\s*$/.exec(l);
          if (m) defines[m[1]] = m[2];
        }
      }
      const num = (name) => {
        let v = name, hops = 0;
        while (typeof v === 'string' && !/^\d+$/.test(v) && hops++ < 4) v = defines[v];
        return /^\d+$/.test(v) ? Number(v) : NaN;
      };
      const pad = num('DSTRIP_GEAR_PAD'), w = num('DSTRIP_GEAR_W');
      const prev = num('DSTRIP_GEAR_SWQ_PREV'), gap = num('DSTRIP_GEAR_SWQ_GAP');
      const cell = num('DSTRIP_GEAR_SWQ_CELL'), plus = num('DSTRIP_GEAR_SWQ_PLUS');
      const n = num('DSTRIP_GEAR_SWQ_N');
      if ([pad, w, prev, gap, cell, plus, n].some((v) => Number.isNaN(v)))
        broken.push('the quick row\u2019s geometry must be numbers a gate can read (PAD/W/PREV/GAP/CELL/PLUS/N)');
      else {
        const ink = pad + prev + gap + n * (cell + gap) + plus;
        if (ink > w - pad)
          broken.push(`the colour row is ${ink}px wide inside a ${w - pad}px cell: it paints past the plate\u2019s own pad`);
      }
    }

    // (c) the Color group paints the two ROLES as rows, and no colour caption/box is
    // left behind to type into.
    for (const role of ['BORDER', 'FILL']) {
      if (!gearACode118.includes(`DrawStripGearSection("${role}", y);`))
        broken.push(`the Color group must name the ${role} role on its own band`);
    }
    if (!/DrawStripGearQuickRow\(DRAW_SLOT_COLOR, y\)/.test(gearACode118) ||
        !/DrawStripGearQuickRow\(DRAW_SLOT_FILLCLR, y\)/.test(gearACode118))
      broken.push('both colour roles must be quick rows (the border and the interior)');
    if (/DrawStripGearCaptionIn\("COLOR"/.test(gearACode118) || /DrawStripGearCaptionIn\("FILL"/.test(gearACode118))
      broken.push('a colour CAPTION row is back (the retired hex box\u2019s seat): the row is a swatch strip now');
    if (/\(e == 0 && s_dsGear == DSTRIP_GEAR_PAINT\)/.test(gearBCode118) ||
        /\(e == 4 && s_dsGear == DSTRIP_GEAR_PAINT/.test(gearBCode118))
      broken.push('the panel\u2019s colour edit seats (e0/e4) are back in the paint\u2019s `want` list \u2014 their boxes are retired');
    if (!/if\(!want\)\s*\{[^}]*ObjectDelete\(0, en\)/s.test(gearBCode118))
      broken.push('a retired edit field must be deleted by the paint\u2019s own `!want` branch, or a chart keeps the old box');

    // (d) the faces: three grid kinds, the strip\u2019s own swatch skin, the cards\u2019 rim.
    for (const k of ['DSTRIP_GRG_SWATCH', 'DSTRIP_GRG_PREV', 'DSTRIP_GRG_PLUS'])
      if (!gearBCode118.includes(k))
        broken.push(`Biotak/DrawStrip_GearB.mqh does not paint the ${k} cell`);
    if (!gearBCode118.includes('ds_swatch24') ||
        !/BioSwatchBorder\(sc, BIO_CLR_CARD\)/.test(gearBCode118))
      broken.push('a swatch must wear the strip\u2019s own face (ds_swatch24) and the cards\u2019 rim (BioSwatchBorder)');
    if (!/DrawStripColorRead\(s_dsObj, slot\)/.test(gearBCode118))
      broken.push('the preview and the current-swatch rim must read the colour of THEIR OWN role (slot), not the border\u2019s');

    // (e) the tap: the colour the cell wears, through the ONE owner; the two openers.
    if (!/DrawStripColorCommit\(slot, s_dsGGC\[g\]\)/.test(tapCode118))
      broken.push('a swatch tap must apply the colour the cell PAINTS (s_dsGGC[g]) \u2014 a hit test with its own arithmetic is a second grid');
    const gridTap = bodyOf(stripTap, 'bool DrawStripGridTap(');
    if (!gridTap || !/s_dsPicker = slot;/.test(gridTap.text) || !/DrawStripGearClose\(\);/.test(gridTap.text))
      broken.push('the preview / `+` must open the board on their own role (the strip keeps one popover at a time)');
    if (!tapCode118.includes('bool DrawStripColorCommit('))
      broken.push('DrawStripColorCommit() is gone: the colour has no single owner');
    const callers = (tapCode118.match(/DrawStripColorCommit\(/g) || []).length;
    if (callers < 3)
      broken.push(`only ${callers} call(s) of DrawStripColorCommit: the palette cell, the quick swatch and the board\u2019s hex are three faces of one write`);

    // (f) the hover knows the color group\u2019s swatches, and reads their own role.
    if (!/s_dsGear == DSTRIP_GEAR_STYLE \|\| s_dsGear == DSTRIP_GEAR_PAINT/.test(pickCode118))
      broken.push('the swatch hover must cover the Color group (the fence still names one group only)');
    if (!/DrawStripColorRead\(s_dsObj, s_dsGGSlot\[cell\]\)/.test(pickCode118))
      broken.push('the hover\u2019s current-colour compare must read the CELL\u2019s role (a FILL swatch compared against the border lights the wrong cell)');

    if (broken.length) {
      failures.push('P-DRAW-118: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearA.mqh DrawStripGearQuickRow + DrawStrip_GearB.mqh/_Tap.mqh/_Pick.mqh)');
    } else {
      console.log('[PASS] P-DRAW-118 each colour role is one quick row of swatches, applied through one owner (Biotak/DrawStrip_GearA.mqh DrawStripGearQuickRow)');
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
