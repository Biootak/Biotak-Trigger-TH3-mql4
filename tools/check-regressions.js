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
// P-DRAW-127: STRIP_TAP (declared above) is the ONE path that OPENS the panel, and
// therefore the one place a user action can guarantee the screen shows the panel it
// just asked for — `DrawStripPaint` only redraws `if(dirty)`.
// P-DRAW-118: the card surface's own number table — the panel's quick row reads
// PNL_QSW_N and PNL_WEL from it, so the register resolves those names where the
// compiler does (the entry includes it ABOVE the strip, P-DRAW-116).
const CARD_METRICS = path.join(BIOTAK, 'CardMetrics.mqh');
const STRIP_TAP = path.join(BIOTAK, 'DrawStrip_Tap.mqh');
const STRIP_ROUTER = path.join(BIOTAK, 'DrawStrip_Router.mqh');
const RES_GATE = path.join(__dirname, 'check-resources.js');
const STRIP_PAINT = path.join(BIOTAK, 'DrawStrip_Paint.mqh');
const PANELS_BUILD = path.join(BIOTAK, 'BiotakPanels_Build.mqh');
const STRIP_PICK = path.join(BIOTAK, 'DrawStrip_Pick.mqh');
const BUILD_PS1 = path.join(ROOT, 'compile-th3.ps1');
// P-DRAW-121: the band's own COUNT. The pill's rule lives in DrawStrip_GearB and is
// mirrored (with its flag READ out of the source) in `sim-gear-panel.band_counts`, so
// the register can assert both halves: the rule excludes nav, and the gate says so.
const GEAR_SIM = path.join(__dirname, 'sim-gear-panel.py');
// P-DRAW-122: the layer law's ONE owner — the gate that walks every painter in the
// tree, so the set of sites is derived and never listed here.
const LIFECYCLE_GATE = path.join(__dirname, 'object_lifecycle_check.js');
// P-DRAW-119: the REAL pixels. The harness is the only thing that writes a PNG of
// the actual paint path, and `check-shot-freshness.js` is the only thing that says
// whether the PNGs on this machine are that code's.
const SHOT_HARNESS = path.join(ROOT, 'tests', 'Biotak_StripShot_Test.mq4');
const SHOT_GATE = path.join(__dirname, 'check-shot-freshness.js');
const BEFORE_AFTER = path.join(__dirname, 'before-after.py');
// P-LOG-2: the diag channel's other half. The flushed frame is written per attach,
// so a frame left by a previous session is indistinguishable from a live one; the
// reader is the surface that must rank, flag and prune it.
const DIAG_LIVE = path.join(__dirname, 'diag-live.py');
// P-LOG-3: the frame boundary. One diag file carries whole frames, one per panel
// open, so a reader that diffs the FILE pairs the first open's intent with the last
// open's reality.
const DIAG_DIFF = path.join(__dirname, 'diag-diff.py');

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
      if (/mx >= xa && mx <= xa\s*\+\s*DSTRIP_HD_PGW/.test(at.text))
        broken.push('the page seat is closed again; it must be half-open like the rect it paints');
      //--- P-PAL-16: the width is the SEAT's own macro now (one owner for the header
      //--- cluster), so the law is the half-open test, not the literal 20.
      if (!/mx >= xa && mx < xa\s*\+\s*DSTRIP_HD_PGW/.test(at.text))
        broken.push('the page seat must test `mx < xa + DSTRIP_HD_PGW`');
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

  // -- 36. P-DRAW-119: THE MIRROR IS NOT THE EVIDENCE --------------------------
  // MEASURED 2026-10-01: 25 states in the harness, ZERO of their PNGs anywhere on
  // the machine, and two weeks of reports that called a `tools/sim-*.py` render
  // "verified". A mirror is rebuilt from the same literals the compiler reads, so it
  // is right about the arithmetic and blind about what the blit does (that is
  // P-DRAW-109 exactly). This entry keeps the three ways the truth can go missing:
  // the gate is uncached in the build, the build cannot print PASS while the gate
  // says NOT CURRENT, and a -Shot run is strict.
  {
    const broken = [];
    const gate119 = linesOf(SHOT_GATE) ? fs.readFileSync(SHOT_GATE, 'utf8') : null;
    if (!gate119) {
      broken.push('tools/check-shot-freshness.js is gone \u2014 nothing compares the terminal\u2019s PNGs with the code');
    } else {
      // (a) wanted = the HARNESS's own list, so a new state cannot be unshot.
      if (!/SS\(\?:State\|Kind\)/.test(gate119) || !/HARNESS/.test(gate119))
        broken.push('the gate must parse the state list OUT of tests/Biotak_StripShot_Test.mq4 (a hand-kept list goes stale in silence)');
      // (b) the three verdicts, and the OLDEST copy winning.
      for (const w of ['fresh', 'stale', 'missing'])
        if (!gate119.includes(w)) broken.push(`the gate no longer reports \u201c${w}\u201d`);
      if (!/Math\.min\(prev\.mtime, mt\)/.test(gate119))
        broken.push('the OLDEST copy of a PNG must win: a swept copy carrying its own copy-time makes a previous build\u2019s shot look fresh');
      if (!/--strict/.test(gate119) || !/process\.exit\(strict \? 1 : 2\)/.test(gate119))
        broken.push('NOT CURRENT must be its own exit code (2), and --strict must exit 1 \u2014 a plain run that exits 0 is how a green line got read as \u201cseen\u201d');
    }

    // (c) the build: uncached, warn-not-PASS, and strict after a successful -Shot.
    const ps = linesOf(BUILD_PS1) ? fs.readFileSync(BUILD_PS1, 'utf8') : '';
    if (!/real pixels gate/.test(ps))
      broken.push('compile-th3.ps1 no longer runs the real-pixels gate');
    if (!/Invoke-ProjectGate -Name "real pixels gate"[\s\S]{0,120}-Cache @\{\}/.test(ps))
      broken.push('the real-pixels gate must run with an EMPTY cache: its input is the PNGs\u2019 own mtimes, which the tree fingerprint does not hold');
    if (!/Invoke-ProjectGate -Name "real pixels gate \(strict\)"[\s\S]{0,200}--strict/.test(ps))
      broken.push('a -Shot run must end strict: a capture that left a stale or partial set is a failed build, not a full-looking column');
    if (!/-WarnOnExit2/.test(ps) || !/\$WarnOnExit2 -and \$LASTEXITCODE -eq 2/.test(ps))
      broken.push('exit 2 \u2192 [WARN] must be opt-in per call (-WarnOnExit2): otherwise any gate\u2019s exit 2 stops failing the build');
    for (const g of ['resource gate', 'regression gate', 'gear panel gate', 'object lifecycle gate'])
      if (new RegExp(`-Name "${g}"[^\n]*-WarnOnExit2`).test(ps))
        broken.push(`the ${g} now treats exit 2 as a warning \u2014 only the real-pixels gate defines that code`);
    if (!/if \(\$shotLaunch -and \$shotOk\) \{[\s\S]{0,200}?-Name "real pixels gate \(strict\)"/.test(ps))
      broken.push('the strict run must sit behind \u201cthe shot actually captured something\u201d, else a prepare-only -Shot fails the build');

    // (d) the page: it must say WHICH build its pixels are, and read both places.
    const ba = linesOf(BEFORE_AFTER) ? fs.readFileSync(BEFORE_AFTER, 'utf8') : '';
    if (!ba) broken.push('tools/before-after.py is gone \u2014 the third column has no owner');
    else {
      if (!/def _newest_source_mtime/.test(ba) || !/NEWEST_SOURCE/.test(ba))
        broken.push('before-after.py no longer compares a shot against the code it shows');
      if (!/SHOT_MTIME/.test(ba))
        broken.push('before-after.py dropped the per-tag shot time, so the page cannot flag a previous build\u2019s pixels');
      if (!/build-logs", "shot"\)/.test(ba) || !/Terminal/.test(ba))
        broken.push('the page must read the PNGs from both places the terminal writes them (build-logs/shot and <MQL4>\\Files)');
      if (!/^import datetime/m.test(ba) || !/datetime\.datetime\.fromtimestamp/.test(ba))
        broken.push('_fmt() calls datetime without importing it \u2014 the page dies on the first stale shot');
    }

    // (e) the harness: the list must still be a list, and the zero-width panel_fold
    //     state (the accordion\u2019s own pixel) must still be shot.
    const harn = linesOf(SHOT_HARNESS) ? fs.readFileSync(SHOT_HARNESS, 'utf8') : '';
    const tags = [...harn.matchAll(/SS(?:State|Kind)\s*\(\s*"([A-Za-z0-9_]+)"/g)].map((m) => m[1]);
    if (new Set(tags).size < 10)
      broken.push(`tests/Biotak_StripShot_Test.mq4 asks for ${new Set(tags).size} state(s): the gate would call an empty column \u201ccurrent\u201d`);
    if (!tags.includes('panel_fold'))
      broken.push('the panel_fold state is gone: the accordion\u2019s folded body (P-DRAW-117) would have no pixel again');

    if (broken.length) {
      failures.push('P-DRAW-119: ' + broken.join('; ') + ' (tools/check-shot-freshness.js + compile-th3.ps1 + tools/before-after.py)');
    } else {
      console.log('[PASS] P-DRAW-119 the mirror is not the evidence: the terminal\u2019s own PNGs are gated, uncached, and strict on -Shot (tools/check-shot-freshness.js)');
    }
  }

  // -- 37. P-DRAW-120: an attach owns a chart that carries no panel on it ---------
  //
  // Reported 2026-10-01 («روی stroke که کلیک می‌کنم متن‌ها و غیره این‌طوری ناقص هستش»)
  // with a shot of the open Stroke panel: the left column, the head and the foot bare
  // plate, the right column's rows, chips and switches painted. The terminal held EVERY
  // object of that tab at its own seat with its own ink —
  //   [drawstrip] TABCENSUS obj=PnlDrawS_GR2T type=23 xywh=1461,149,0,0 bgcolor=0
  //               z=1442 ink="50 % line":14865611
  // — and the same log's LAST `[drawstrip]` line is 14:37:08, while the instance the
  // 15:18 shot answers to attached at 15:10:39 with `s_dsOpen = false`, `s_dsGear = 0`:
  // it painted nothing, and with the strip closed no tap branch answered the panel on
  // screen. Two owners exist to make that state impossible, and neither was wired:
  //   * `DrawStripSweepStale()` (P-DRAW-85, "no orphan survives a reattach") documents
  //     its ONE call as "from the entry's OnInit beside the teardown's own
  //     `DrawStripClose()`" and had NO call site at all — the definition, and nothing
  //     else, was all `git grep SweepStale` found in the whole tree;
  //   * `DrawStripOrphanSweep()` (P-DRAW-42) is called from `DrawStripPaint()` BELOW
  //     its `!s_dsOpen` gate, so the session that needs it most — a reload with nothing
  //     open — never reaches it.
  // The reattach is then decided by `ObjectFind(0, nm) < 0` alone, and the painters were
  // not equal about it: `DrawStripBtnZ` re-asserts OBJPROP_ZORDER/STATE every paint
  // (P-DRAW-48) while `DrawStripFaceZ`/`DrawStripLblAt` wrote ZORDER/BACK only inside
  // their birth block — an object that keeps an older rung reads correct in the census
  // and paints under the plate (equal z is settled by creation order).
  {
    const ENTRY = path.join(ROOT, 'Biotak Trigger TH3.mq4');
    const entry = linesOf(ENTRY);
    const broken = [];
    const onInit = entry ? bodyOf(entry, 'int OnInit()') : null;
    if (!onInit || !onInit.text.includes('DrawStripSweepStale();'))
      broken.push("the entry's OnInit must sweep the previous instance's strip family (DrawStripSweepStale)");
    const sweep = bodyOf(gearA, 'void DrawStripSweepStale()');
    if (!sweep || !sweep.text.includes('ObjectsDeleteAll(0, "PnlDrawS_", -1, -1)'))
      broken.push('DrawStripSweepStale() must be the one prefix scan over `PnlDrawS_` (Biotak/DrawStrip_GearA.mqh)');
    const paint = bodyOf(stripPaint, 'void DrawStripPaint()');
    if (!paint) broken.push('DrawStripPaint() is gone from Biotak/DrawStrip_Paint.mqh');
    else {
      const sweepAt = paint.text.indexOf('DrawStripOrphanSweep();');
      const gateAt = paint.text.indexOf('if(!s_dsOpen || s_dsObj == "") return;');
      if (sweepAt < 0) broken.push('the orphan sweep left the painter (P-DRAW-42)');
      else if (gateAt >= 0 && sweepAt > gateAt)
        broken.push('the orphan sweep is behind the `!s_dsOpen` gate again: a reload with nothing open never reaches it');
    }
    const face = bodyOf(gearB, 'bool DrawStripFaceZ(');
    if (!face || !face.text.includes('DrawStripSetInt(nm, OBJPROP_ZORDER, z)') ||
        !face.text.includes('DrawStripSetInt(nm, OBJPROP_BACK, false)'))
      broken.push('a face must re-assert its own layer every paint, not only at birth (DrawStripFaceZ)');
    const lbl = bodyOf(gearB, 'bool DrawStripLblAt(');
    if (!lbl || !lbl.text.includes('DrawStripSetInt(nm, OBJPROP_ZORDER, Z_STRIP_OVER)'))
      broken.push('a caption must re-assert its own layer every paint (DrawStripLblAt)');
    const cens = bodyOf(gearB, 'void DrawStripGearTabCensus()');
    for (const field of ['back=', 'fnt=', 'tf=', 'bmp='])
      if (!cens || !cens.text.includes(field))
        broken.push(`the census must print \`${field}\`: the four properties that decide whether MT4 draws the object at all`);
    if (broken.length) {
      failures.push('P-DRAW-120: ' + broken.join('; ') + ' (Biotak Trigger TH3.mq4 OnInit + Biotak/DrawStrip_Gear*.mqh)');
    } else {
      console.log('[PASS] P-DRAW-120 an attach sweeps the previous instance\u2019s strip family, and every painted layer is re-asserted (Biotak Trigger TH3.mq4 OnInit)');
    }
  }

  // -- 37b. P-DRAW-64a2: THE MERGED COLOUR SEAT HAS TWO FAIR TARGETS ---------------
  // P-DRAW-64a merged the border and the interior into ONE quick-row seat (ring =
  // border, 24px centre = fill) — and the ring is a 1px outline, so the border's whole
  // hit band was 32-24 = 4px («از کجا رنگ بوردر رو عوض کنم» had no visible answer;
  // the popup's `cycle >>` walks all 29 product targets and a drawing's own two are the
  // LAST rungs). The seat now paints TWO bars, each wearing its own colour and each
  // half the cell, and the popup un-merges the same two roles as two named chips.
  // Four mechanical laws: both bars painted, the name router answers the border's name,
  // the border's object has a destroy path, and the chip asks the STRIP for the slot.
  {
    const broken = [];
    const paintB = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || []);
    const routerB = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    const gearBB = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearB.mqh')) || []);
    const palB = codeOf(linesOf(path.join(BIOTAK, 'BiotakPanels_PalB.mqh')) || []);
    const baseB = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Base.mqh')) || []);
    if (!/DrawStripBtn\(ic \+ "R",/.test(paintB) || !/DrawStripBtn\(ic \+ "S", bx, bby/.test(paintB))
      broken.push('the merged colour seat must paint BOTH bars — `ic+"R"` (border) and `ic+"S"` (fill), or one role has no target at all');
    if (!/DrawStripIconName\(i\) \+ "R"/.test(routerB))
      broken.push('the name router does not answer the BORDER bar\'s object — the bar paints but never opens a palette');
    if (!/ObjectDelete\(0, DrawStripIconName\(i\) \+ "R"\)/.test(gearBB))
      broken.push('the border bar has no destroy path — a closed strip would leave its colour on the chart (P-DRAW-14)');
    if (!/id=="tgtB" \|\| id=="tgtF"/.test(palB))
      broken.push('the popup has no role chips — a drawing keeps the 29-target `cycle >>`, and its own two roles are the last rungs');
    if (!/DrawStripPalRoleSet\(wantBorder \? 0 : 1\)/.test(palB))
      broken.push('a role chip must ask the STRIP which SLOT it means — the popup holds the kind, the strip holds the slot');
    const roleSet = bodyOf(linesOf(path.join(BIOTAK, 'DrawStrip_Base.mqh')) || [], 'void DrawStripPalRoleSet(');
    if (!roleSet || !roleSet.text.includes('DRAW_SLOT_COLOR') || !roleSet.text.includes('DRAW_SLOT_FILLCLR'))
      broken.push('DrawStripPalRoleSet must name BOTH slot words — arithmetic here is how a border pick paints the interior');
    if (!/DrawStripPalRoleSet\(/.test(baseB))
      broken.push('DrawStripPalRoleSet is gone from the strip — the chip has no owner for the slot↔role vocabulary');
    //--- the ink ON a control must be painted ABOVE it. Measured: both chips and both
    //--- names were written at Z_PANEL_POP_BG (1601) while their own button sits at
    //--- Z_PANEL_POP_CTL (1602), so the button covered its own words — the report was
    //--- an «APPLY TO» row with two empty boxes and nothing readable in either.
    for (const [tail, what] of [['sfx+"c"', 'the colour chip'], ['sfx+"t"', 'the role name']])
      if (!palB.includes('ObjectSetInteger(0,p+' + tail + ',OBJPROP_ZORDER,Z_PANEL_POP_FG);'))
        broken.push(`${what} must be painted at Z_PANEL_POP_FG — under its own button (CTL) it is invisible, which is how two chips shipped with no words`);
    if (broken.length) {
      failures.push('P-DRAW-64a2: ' + broken.join('; ') + ' (DrawStrip_Paint/Router/GearB/Base + BiotakPanels_PalB)');
    } else {
      console.log('[PASS] P-DRAW-64a2 the merged colour seat is two fair bars (border over fill), the name router answers both, the border bar dies with the strip, and the popup names the same two roles as chips that ask the strip for the slot');
    }
  }

  // -- 38. P-DRAW-121: a band's pill counts MEMBERS, and nav is not a member -------
  //
  // Reported 2026-10-01 («روی stroke که کلیک می‌کنم متن‌ها و غیره این‌طوری ناقص هستش»)
  // with the shot of the open Stroke tab: the SHAPE band's `.cnt` read 2 while LAYER
  // read 4 — for a band that owns TWO rows (`Lock`, `Behind candles`). The row loop of
  // `DrawStripGearSectionCount` filtered by column and y and by nothing else, while the
  // accordion's group headers ride the SAME `s_dsGR*` array in the SAME column
  // (P-DRAW-117): on a wide tab the headers BELOW the open group pack into the last
  // band's range, so `Look` and `Row` were counted as settings. Measured offline, no
  // terminal: the same rule read the Colour tab's FILL band as 5 for its own two, and a
  // fibo's `Levels` header leaked into LAYER (5 for 2).
  //
  // This was not a green-and-wrong gate — it was NO gate: `check-gear-panel.py`
  // rendered the pill and never asserted the digit, so the number could only be SEEN,
  // which is why the report arrived as a screenshot. THREE owners now, and this entry
  // keeps the other two from being quietly dropped: the RULE must exclude the kind, the
  // MIRROR must own the count (one table, read out of the source), and the GEAR GATE
  // must assert it — so deleting either assertion fails HERE, in the build.
  {
    const gearB = linesOf(GEAR_B) || [];
    const broken = [];
    const count = bodyOf(gearB, 'int DrawStripGearSectionCount(');
    if (!count)
      broken.push('DrawStripGearSectionCount() is gone from Biotak/DrawStrip_GearB.mqh');
    else if (!/s_dsGRKind\[r\]\s*!=\s*DSTRIP_GRK_GROUP/.test(count.text))
      broken.push('the row loop must exclude `DSTRIP_GRK_GROUP` (`s_dsGRKind[r] != DSTRIP_GRK_GROUP && ...`): a group header is NAV, not a member');
    const sim = linesOf(GEAR_SIM) ? fs.readFileSync(GEAR_SIM, 'utf8') : '';
    for (const fn of ['def count_rule_excludes_nav()', 'def band_counts('])
      if (!sim.includes(fn))
        broken.push(`tools/sim-gear-panel.py must own the count (\`${fn}\`): the gate reads the rule from the source, never from a second table`);
    const gearGate = linesOf(GEAR_GATE) ? fs.readFileSync(GEAR_GATE, 'utf8') : '';
    if (!gearGate.includes('count_rule_excludes_nav()') || !gearGate.includes('band_counts'))
      broken.push('tools/check-gear-panel.py must assert the rule AND the numbers (P-DRAW-121): a pill no gate measures can only be seen on the chart');
    if (broken.length) {
      failures.push('P-DRAW-121: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh + tools/sim-gear-panel.py + tools/check-gear-panel.py)');
    } else {
      console.log('[PASS] P-DRAW-121 a band\u2019s pill counts members only, and the rule has an owner in the mirror and in the gate (Biotak/DrawStrip_GearB.mqh)');
    }
  }

  // -- 39. P-DRAW-122: a painted layer is re-asserted EVERY pass, tree-wide --------
  //
  // P-DRAW-120 stated the law and healed the SITES a shot convicted (the buttons
  // already complied; the face and the label were made to) — and left five, because the
  // heal went to the sites and not to the rule: `DrawStripRect`, the gear's edit field,
  // the board's hex field, the skin's underlayer and the strip's flat plate each wrote
  // OBJPROP_ZORDER/BACK inside their `ObjectFind < 0` birth block and never again.
  // Equal z is settled by CREATION ORDER, so an object that survives a reattach keeps
  // the rung it was born with: the census reads it at its right seat with its right ink
  // while it paints UNDER the plate — the 2026-10-01 «متن‌ها ناقص است» report as a PAINT
  // ORDER rather than as a missing object. A sixth site lived outside the strip, in the
  // TH3 pattern renderer: an ABCD point is MOVED on every pass and had its rung written
  // once. MEASURED before the fix: 10 painters re-assert, 5 write the layer only at
  // birth; after: 12 and 0.
  //
  // So the LAW has one owner (`object_lifecycle_check.js` derives it from every painter
  // in Biotak/**, one regex pass in the walk it already makes — the next painter is
  // covered the day it is written) and this entry keeps that owner from being emptied:
  // the five healed sites must still carry the re-assert, and the gate must still carry
  // the rule rather than a list of five names.
  {
    const broken = [];
    for (const [file, sig, name] of [
      [GEAR_B, 'bool DrawStripRect(', 'DrawStripRect'],
      [GEAR_B, 'bool DrawStripEdit(', 'DrawStripEdit'],
      [GEAR_B, 'bool DrawStripPopHex(', 'DrawStripPopHex'],
      [STRIP_SKIN, 'bool DrawStripSkinPaintAt(', 'DrawStripSkinPaintAt'],
      [STRIP_PAINT, 'void DrawStripPaint(', 'DrawStripPaint'],
    ]) {
      const fn = bodyOf(linesOf(file) || [], sig);
      if (!fn) { broken.push(`${name} is gone from ${path.basename(file)}`); continue; }
      // the birth block writes the layer with a raw ObjectSetInteger, so a DrawStripSetInt
      // layer write in this body can only be the every-pass re-assert.
      if (!/DrawStripSetInt\s*\(\s*\w+\s*,\s*OBJPROP_ZORDER/.test(fn.text))
        broken.push(`${name} must re-assert its layer every pass (P-DRAW-122): a surviving object keeps its old rung and paints under the plate`);
    }
    const gate = linesOf(LIFECYCLE_GATE) ? fs.readFileSync(LIFECYCLE_GATE, 'utf8') : '';
    for (const needle of ['only at birth', 'P-DRAW-122'])
      if (!gate.includes(needle))
        broken.push(`tools/object_lifecycle_check.js must carry the law (\`${needle}\`): a rule asserted at five names is a to-do list, not a gate`);
    if (broken.length) {
      failures.push('P-DRAW-122: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh + DrawStrip_Paint.mqh + DrawStrip_Skin.mqh + tools/object_lifecycle_check.js)');
    } else {
      console.log('[PASS] P-DRAW-122 every painter re-asserts its layer each pass, and the law is derived tree-wide (tools/object_lifecycle_check.js)');
    }
  }

  // -- 40. P-DRAW-124: a face no branch of THIS paint claims is deleted -------------
  //
  // The 2026-10-01 report («روی stroke که کلیک می‌کنم متن‌ها این‌طوری ناقص هست» /
  // «این هنوز درست نشده») survived four fixes because the terminal's own log was never
  // read as the FACT it is: the census at 18:42:35 holds every hidden object at its right
  // seat, its right text, its right rung — and holds the intruders too. Nine `GG0G..GG8G`
  // glass faces stood at y=186 (the PAINT tab's own swatch row) while this tab's chips
  // sit at 224/308, all at z=1442 — the LABELS' rung — over the band sharing that row;
  // and `GR2D/GR3D/GR4D` still carried the retired `3px · Solid` at the PAINT tab's
  // digest seats. Both are the SAME defect: a cell/row that changed ROLE kept the FACES
  // of its old role, because only the branches that PAINT a face ever deleted one.
  //
  // The law is P-DRAW-42's own (no orphan survives a paint) applied to the two shared
  // arrays: the chip branch deletes the glass + the glyph face, and the path that is not
  // a group deletes the digest. Locked here as needles in the painter — a rule asserted
  // at the two sites and nowhere else is a to-do list.
  {
    const broken = [];
    const fn = bodyOf(linesOf(GEAR_B) || [], 'bool DrawStripGearPaint(');
    if (!fn) {
      broken.push('DrawStripGearPaint is gone from ' + path.basename(GEAR_B));
    } else {
      if (!/ObjectDelete\s*\(\s*0\s*,\s*DrawStripGridGlassName\s*\(\s*g\s*\)\s*\)/.test(fn.text))
        broken.push('the chip branch must delete the swatch glass it does not paint (P-DRAW-124): the previous tab\u2019s face stays at its old seat, on the labels\u2019 rung');
      if (!/ObjectDelete\s*\(\s*0\s*,\s*DrawStripRowDigestName\s*\(\s*r\s*\)\s*\)/.test(fn.text))
        broken.push('a row that is not a group must delete its digest (P-DRAW-124): a header\u2019s retired value hangs over the row that replaced it');
    }
    const census = bodyOf(linesOf(GEAR_B) || [], 'void DrawStripGearTabCensus(');
    if (!census) {
      broken.push('DrawStripGearTabCensus is gone from ' + path.basename(GEAR_B));
    } else {
      if (census.text.includes('"PnlDrawS_G"'))
        broken.push('the census must not scope itself to the gear\u2019s own prefix (P-DRAW-124): the family that can hide this panel\u2019s ink is the one the prefix throws away');
      if (!/idx="/.test(census.text) && !/idx="\s*,/.test(census.text) && !census.text.includes('TABCENSUS idx='))
        broken.push('the census must print the terminal\u2019s own list index (P-DRAW-124): equal z is settled by list order, so z alone can never name the object that wins');
    }
    if (broken.length) {
      failures.push('P-DRAW-124: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh)');
    } else {
      console.log('[PASS] P-DRAW-124 a cell that changed role takes its old faces with it, and the census names the tie it cannot see in z (Biotak/DrawStrip_GearB.mqh)');
    }
  }

  // -- 41. P-DRAW-125: the diagnostic never moves a pixel the product would not ---
  //
  // Two facts, both measured on the terminal's own 2026-10-01 log (the live Experts
  // journal, not a mirror):
  //   * `DrawStripGearDiagDump` is called from `DrawStripActTap` on the GEAR button,
  //     and that path runs on the CLOSE too — `DrawStripGearClose()` sets `s_dsGear=0`
  //     and the call follows. The unguarded `DrawStripGearPaint()` then ran with
  //     `s_dsGRN = s_dsGGN = s_dsGearSecN = 0`: it deleted every grid, section and row
  //     object of the panel and — because the head and the foot paint unconditionally
  //     — left the HEAD and the FOOT of a closed panel standing on the chart at the
  //     stale origin. The log carries that frame whole: `[dsdiag] EXPECT` for
  //     `GHTB..GHXI` and `GF0..GF2T`, twenty objects, head then foot, nothing between.
  //   * every writer asked "create or rewrite?" from `ObjectFind(0, nm) < 0` alone, so
  //     a name already on the chart was reused with whatever TYPE the older build gave
  //     it — an object that answers the name and paints nothing (DrawStripSweepStale's
  //     own note). `DrawStripForeign` is the reader of "is this mine?": the object's
  //     own type against the painter's, with the create kept IN the writer so the
  //     lifecycle gate still sees one block.
  {
    const broken = [];
    const dump = bodyOf(gearB, 'void DrawStripGearDiagDump(');
    if (!dump) broken.push('DrawStripGearDiagDump is gone from ' + path.basename(GEAR_B));
    else if (!/s_dsGear\s*!=\s*0/.test(dump.text) || !/s_dsGearH\s*>\s*0/.test(dump.text))
      broken.push('the dump must repaint ONLY an open, laid-out panel (P-DRAW-125): unguarded it paints a shut panel\u2019s head and foot at the stale origin and deletes the body');
    const foreign = bodyOf(stripBase, 'void DrawStripForeign(');
    if (!foreign) broken.push('DrawStripForeign is gone from ' + path.basename(STRIP_BASE));
    else {
      if (!/\(int\)ObjectGetInteger\s*\(\s*0\s*,\s*nm\s*,\s*OBJPROP_TYPE\s*\)\s*==\s*type/.test(foreign.text))
        broken.push('the reclaim must COMPARE the object\u2019s own TYPE against the painter\u2019s (P-DRAW-125): `ObjectFind >= 0` alone reuses whatever type the older build left');
      if (!foreign.text.includes('ObjectDelete'))
        broken.push('a foreign name must be DELETED so the writer rebuilds it (P-DRAW-125)');
    }
    const writers = [
      ['bool DrawStripBtnZ(', 'OBJ_BUTTON', 'DrawStripForeign(nm, OBJ_BUTTON)'],
      ['bool DrawStripFaceZ(', 'OBJ_BITMAP_LABEL', 'DrawStripForeign(nm, OBJ_BITMAP_LABEL)'],
      ['bool DrawStripLblAt(', 'OBJ_LABEL', 'DrawStripForeign(nm, OBJ_LABEL)'],
      ['bool DrawStripRect(', 'OBJ_RECTANGLE_LABEL', 'DrawStripForeign(nm, OBJ_RECTANGLE_LABEL)'],
    ];
    for (const [def, type, call] of writers) {
      const w = bodyOf(gearB, def);
      if (!w) { broken.push(def + ' is gone from ' + path.basename(GEAR_B)); continue; }
      if (!w.text.includes(call))
        broken.push(def + ' must reclaim a foreign name before it writes (P-DRAW-125): ' + call);
      if (!w.text.includes('ObjectCreate(0, nm, ' + type))
        broken.push(def + ' must keep its own ObjectCreate(' + type + ') (P-DRAW-125): the lifecycle gate reads birth and layer from one block');
    }
    if (broken.length) {
      failures.push('P-DRAW-125: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh + Biotak/DrawStrip_Base.mqh)');
    } else {
      console.log('[PASS] P-DRAW-125 the diagnostic repaints only an open panel, and every writer reclaims a name of another type (Biotak/DrawStrip_GearB.mqh + DrawStrip_Base.mqh)');
    }
  }

  // ── P-LOG-2 (2026-10-01) — A DIAG FRAME BELONGS TO ONE ATTACH ──────────────
  // The flushed frame is truncated only when a NEW attach writes its FIRST line, so
  // between a restart and the first panel open the PREVIOUS session's
  // `biotak_diag_<SYMBOL>.txt` is still on disk and, by mtime, still outranks every
  // other source — a stale frame that reads exactly like a live one. Both halves must
  // say the same thing: newest wins, the rest go. The BUILD deletes every
  // `biotak_diag_*.txt` while terminal.exe is STOPPED (no handle can hold the file
  // open), and the READER ranks by mtime, calls an old frame STALE, and prunes.
  {
    const broken = [];
    const psLines = linesOf(BUILD_PS1) || [];
    const ps = psLines.length ? fs.readFileSync(BUILD_PS1, 'utf8') : '';
    const clear = bodyOf(psLines, 'function Clear-StaleDiagFiles');
    if (!clear) {
      broken.push('Clear-StaleDiagFiles is gone from compile-th3.ps1 — nothing deletes the previous session\u2019s diag frame');
    } else {
      if (!clear.text.includes('biotak_diag_*.txt'))
        broken.push('Clear-StaleDiagFiles must target `biotak_diag_*.txt` (that is the frame it owns)');
      if (!/Remove-Item/.test(clear.text))
        broken.push('Clear-StaleDiagFiles must REMOVE the stale frames, not just find them (P-LOG-2)');
    }
    const restart = bodyOf(psLines, 'function Restart-TradingTerminal');
    const shot = bodyOf(psLines, 'function Invoke-StripShot');
    for (const [name, body] of [['Restart-TradingTerminal', restart], ['Invoke-StripShot', shot]]) {
      if (!body) { broken.push(name + ' is gone from compile-th3.ps1'); continue; }
      const stop = body.text.indexOf('Stop-TerminalProcesses');
      const call = body.text.indexOf('Clear-StaleDiagFiles');
      if (call < 0)
        broken.push(name + ' must delete the stale diag frames after Stop-TerminalProcesses (P-LOG-2): otherwise the previous session\u2019s frame is still there, still newest by mtime');
      else if (stop >= 0 && call < stop)
        broken.push(name + ' must call Clear-StaleDiagFiles AFTER the terminal is stopped — deleting a frame the terminal holds open silently fails on Windows');
    }
    const live = linesOf(DIAG_LIVE) ? fs.readFileSync(DIAG_LIVE, 'utf8') : null;
    if (!live) {
      broken.push('tools/diag-live.py is gone — the flushed channel\u2019s only reader');
    } else {
      if (!live.includes('--prune') || !/def prune_stale\(/.test(live))
        broken.push('tools/diag-live.py must offer --prune / prune_stale (P-LOG-2): the reader is the half that deletes what it does not read');
      if (!/STALE/.test(live))
        broken.push('tools/diag-live.py must call an old diag frame STALE — a frame that reads like a live one must never be presented as one');
      if (!/os\.remove/.test(live) || !/OSError/.test(live))
        broken.push('pruning must remove files and report the ones a terminal still holds open (os.remove / OSError), never silently skip them');
    }
    if (broken.length) {
      failures.push('P-LOG-2: ' + broken.join('; ') + ' (compile-th3.ps1 + tools/diag-live.py)');
    } else {
      console.log('[PASS] P-LOG-2 a diag frame belongs to one attach: the build deletes stale frames while the terminal is stopped, and the reader prunes plus flags STALE (compile-th3.ps1 + tools/diag-live.py)');
    }
  }

  // ── P-LOG-3 (2026-10-01) — A FLUSH IS NOT ENOUGH IF THE HANDLE IS EXCLUSIVE ──
  // MEASURED 2026-10-01 21:52:50: `biotak_diag_EURUSD.txt` WAS written and flushed
  // (62,965 bytes) while every reader failed on it — Python `open()` raised
  // PermissionError 13, `cp`/`head` said "Device or resource busy", `Get-Content`
  // said "being used by another process". A `FileOpen` grants no share by default, so
  // the flushed bytes were current and unreachable at once. The channel's own reader
  // must be able to open the handle the terminal holds, and `FileFlush` must stay:
  // the share flag makes the file reachable, the flush makes it current.
  {
    const broken = [];
    const emit = bodyOf(linesOf(STRIP_BASE) || [], 'void DrawStripDiagEmit(');
    if (!emit) {
      broken.push('DrawStripDiagEmit is gone from ' + path.basename(STRIP_BASE) + ' — the diag channel\u2019s only writer');
    } else {
      if (!emit.text.includes('FILE_SHARE_READ'))
        broken.push('DrawStripDiagEmit must open its file with FILE_SHARE_READ (P-LOG-3): without it the terminal holds the handle exclusively and NO reader can open the flushed bytes (measured: PermissionError 13 / \u201cDevice or resource busy\u201d)');
      if (!emit.text.includes('FileFlush'))
        broken.push('DrawStripDiagEmit must still FileFlush per line (P-DRAW-126): the share flag makes the file reachable, the flush makes it CURRENT');
      if (!emit.text.includes('biotak_diag_'))
        broken.push('DrawStripDiagEmit no longer writes a `biotak_diag_*` frame — the name tools/diag-live.py reads');
      if (!emit.text.includes('ChartID()'))
        broken.push('the diag FILE must be per CHART, not per symbol (P-LOG-3b): `Symbol()` names two charts of one pair the same, so each instance opens its OWN handle to ONE path and writes it from its own position — MEASURED 2026-10-01 21:52..21:58: size frozen at 62,965 bytes while two charts emitted whole frames, and both frames the bytes held were the M1 chart\u2019s while the screen showed H1');
    }
    if (broken.length) {
      failures.push('P-LOG-3: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh DrawStripDiagEmit)');
    } else {
      console.log('[PASS] P-LOG-3 the diag channel is reachable AND current: its handle shares reads and every line is flushed (Biotak/DrawStrip_Base.mqh DrawStripDiagEmit)');
    }
  }

  // ── P-LOG-4 (2026-10-01) — THE UNIT A READER MAY DIFF IS A FRAME ─────────────
  // The writer appends a WHOLE frame per panel open and never truncates, so a file
  // holding two opens carries two declarations and two censuses. Diffing them as one
  // document pairs the FIRST open's intent with the LAST open's reality. MEASURED
  // 2026-10-01 21:58 (`biotak_diag_EURUSD.txt`, two opens): the mixed read reported
  // `DIVERGED: 53 of 187` — SEAT 38, TEXT 15 — and the LAST frame alone reported
  // `declared 91 / held 139, PASS, 0 divergences`. Same bytes, one frame boundary.
  {
    const broken = [];
    const live = linesOf(DIAG_LIVE) ? fs.readFileSync(DIAG_LIVE, 'utf8') : null;
    const ddiff = linesOf(DIAG_DIFF) ? fs.readFileSync(DIAG_DIFF, 'utf8') : null;
    for (const [name, src] of [['diag-live.py', live], ['diag-diff.py', ddiff]]) {
      if (src === null) { broken.push('tools/' + name + ' is gone'); continue; }
      if (!/def split_frames\(/.test(src))
        broken.push('tools/' + name + ' must split frames (P-LOG-4): a whole-file read pairs the FIRST open\u2019s declaration with the LAST open\u2019s census and invents divergences');
    }
    if (live !== null && !/len\(frames\) - 1\) if want == 0/.test(live))
      broken.push('tools/diag-live.py must default to the LAST frame (P-LOG-4): the last frame is the state the screen is showing');
    if (ddiff !== null) {
      if (!/idx = len\(frames\) - 1 if want is None/.test(ddiff))
        broken.push('tools/diag-diff.py must default to the LAST frame (P-LOG-4): the last frame is the state the screen is showing');
      if (!/--frames/.test(ddiff) || !/--frame/.test(ddiff))
        broken.push('tools/diag-diff.py must let the frame be chosen explicitly (--frames / --frame N)');
    }
    if (broken.length) {
      failures.push('P-LOG-4: ' + broken.join('; ') + ' (tools/diag-live.py + tools/diag-diff.py)');
    } else {
      console.log('[PASS] P-LOG-4 both readers split frames and default to the LAST one, so a declaration is never paired with another open\u2019s census (tools/diag-live.py + tools/diag-diff.py)');
    }
  }

  // ── P-LOG-5 (2026-10-01) — EVERY CAPTION IS IN THE INK COLUMN ─────────────
  // MEASURED 2026-10-01 22:10 (`biotak_diag_EURUSD_134342075006101685.txt`): the
  // panel passed the diff 91/91, and the ONE class that diff never tested was a
  // BUTTON's own text — the census wrote `ink` for OBJ_LABEL only. The swatch row's
  // captions (`1px`..`5px`, `Solid`..`D-Dot`) are BUTTON TEXT, so the report «بعضی
  // ردیف‌ها متن نداره» could not be decided from the log: a lost caption and a healthy
  // face both read `ink=-`. The reader answers both roles now, and so does the diff.
  {
    const broken = [];
    const ink = bodyOf(linesOf(STRIP_BASE) || [], 'string DrawStripCensusInk(');
    if (!ink) {
      broken.push('DrawStripCensusInk is gone from ' + path.basename(STRIP_BASE) + ' — the census\u2019s ink column lost its owner');
    } else if (!/oty != OBJ_LABEL && oty != OBJ_BUTTON/.test(ink.text)) {
      broken.push('the ink column must answer LABELS and BUTTONS (P-LOG-5): a button\u2019s caption is the swatch row\u2019s text, and a label-only column makes a lost caption read exactly like a healthy face');
    }
    const census = bodyOf(linesOf(GEAR_B) || [], 'void DrawStripGearTabCensus(');
    if (!census) broken.push('DrawStripGearTabCensus is gone from ' + path.basename(GEAR_B));
    else if (!census.text.includes('DrawStripCensusInk(on, oty)'))
      broken.push('the census must take its ink from DrawStripCensusInk (P-LOG-5), not recompute it inline');
    const ddiff = linesOf(DIAG_DIFF) ? fs.readFileSync(DIAG_DIFF, 'utf8') : null;
    if (ddiff === null) broken.push('tools/diag-diff.py is gone');
    else if (!/e\["role"\] in \("lbl", "btn"\)/.test(ddiff))
      broken.push('tools/diag-diff.py must compare a BUTTON\u2019s caption too (P-LOG-5): the census prints it now, and a TEXT verdict that only fires for labels still cannot see the row the user named');
    if (broken.length) {
      failures.push('P-LOG-5: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh + Biotak/DrawStrip_GearB.mqh + tools/diag-diff.py)');
    } else {
      console.log('[PASS] P-LOG-5 every caption is in the ink column: a button answers with its text the way a label does, and the diff tests both (Biotak/DrawStrip_Base.mqh + DrawStrip_GearB.mqh + tools/diag-diff.py)');
    }
  }

  // ── P-DRAW-127 (2026-10-01) — A PANEL OPEN FLUSHES ITS OWN FRAME ──────────
  // MEASURED on the 22:10/22:13 frames: the WIDE (624px) open declared all 91
  // objects correct and unoccluded while the SCREEN showed its left column empty.
  // The object LIST was right and the PIXELS were one frame behind: `DrawStripPaint`
  // flushes with `if(dirty) ChartRedraw()`, and `DrawStripGearDiagDump` repaints the
  // body LAST (P-DRAW-125a) while DISCARDS its return — so a panel whose geometry
  // moved without any write reporting dirty kept the previous frame, and a second
  // click "fixed" it because that one did write. A user action gets one flush.
  {
    const broken = [];
    const tap = bodyOf(linesOf(STRIP_TAP) || [], 'bool DrawStripActTap(');
    if (!tap) {
      broken.push('DrawStripActTap is gone from ' + path.basename(STRIP_TAP));
    } else {
      const dump = tap.text.indexOf('DrawStripGearDiagDump()');
      const flush = tap.text.lastIndexOf('ChartRedraw()');
      if (dump < 0)
        broken.push('the GEAR branch must still end with DrawStripGearDiagDump() (P-DRAW-123)');
      else if (flush < 0 || flush < dump)
        broken.push('the GEAR branch must FLUSH after the dump (P-DRAW-127): DrawStripPaint only redraws `if(dirty)`, and the dump\u2019s own repaint discards its return, so an open whose geometry moved keeps the previous frame on screen');
    }
    // P-LOG-6: the walk must test the object's OWN box. The plate's box came from the
    // resource table, read 0 for a name that table does not carry, collapsed to a
    // point 14px outside the panel rect and was skipped — so the largest object the
    // panel owns was the one object the census could never print.
    const box = bodyOf(linesOf(STRIP_BASE) || [], 'int DrawStripCensusSize(');
    if (!box) {
      broken.push('DrawStripCensusSize is gone from ' + path.basename(STRIP_BASE) + ' — the census\u2019s size reader lost its owner (P-LOG-6)');
    } else {
      if (!/OBJPROP_XSIZE/.test(box.text) || !/OBJPROP_YSIZE/.test(box.text))
        broken.push('the census must read the object\u2019s OWN XSIZE/YSIZE first (P-LOG-6): a bitmap label sized from its resource table reads 0 for a name that table does not carry (`pnl_cardW*`), and the panel\u2019s plate lives 14px outside the panel rect');
      if (!/DrawStripResW/.test(box.text))
        broken.push('the resource table must stay as the FALLBACK (P-LOG-6): a face that carries no size of its own still answers from its raster');
    }
    if (!bodyOf(linesOf(STRIP_BASE) || [], 'bool DrawStripCensusInPanel('))
      broken.push('DrawStripCensusInPanel is gone from ' + path.basename(STRIP_BASE) + ' (P-LOG-6)');
    const cen6 = bodyOf(linesOf(GEAR_B) || [], 'void DrawStripGearTabCensus(');
    if (cen6 && !cen6.text.includes('DrawStripCensusInPanel('))
      broken.push('DrawStripGearTabCensus must filter through DrawStripCensusInPanel (P-LOG-6), not inline a box the plate can fail');
    if (broken.length) {
      failures.push('P-DRAW-127: ' + broken.join('; ') + ' (Biotak/DrawStrip_Tap.mqh DrawStripActTap + Biotak/DrawStrip_Base.mqh + DrawStrip_GearB.mqh)');
    } else {
      console.log('[PASS] P-DRAW-127 a panel open flushes its own frame: the GEAR branch redraws after the dump, not only when a write reported dirty (Biotak/DrawStrip_Tap.mqh)');
    }
  }

  // ── P-LOG-7 (2026-10-01) — THE CENSUS WALKS THE WHOLE CHART, NOT A PREFIX ──
  // MEASURED on the wide gear frame the report's screenshot belongs to: 40 declared
  // left-column objects hold correct xywh/z/back/win/corner while the screen shows a
  // bare plate under them, and every net the census had worn could NOT name a cover
  // that is not this family (`PnlDrawS_`) or not one of the four types it knows. A
  // cover that hides this panel's ink is by definition not this panel's, so the net
  // is the whole chart bounded by the panel rect, and the two columns that decide
  // WHERE an object draws when xywh is not the whole answer (`win`, `corner`) are
  // printed with every line. The reader answers "who is on top", not a layout guess.
  {
    const broken = [];
    const cen = bodyOf(linesOf(GEAR_B) || [], 'void DrawStripGearTabCensus(');
    if (!cen) {
      broken.push('DrawStripGearTabCensus is gone from ' + path.basename(GEAR_B));
    } else {
      if (/StringFind\(on, "PnlDrawS_"\) != 0/.test(cen.text))
        broken.push('the census still filters by the family prefix (P-LOG-7): a cover that hides this panel\u2019s ink is by definition not named `PnlDrawS_*`, so the net must be the whole chart inside the panel rect');
      if (!cen.text.includes('CENSUS rect='))
        broken.push('the census must print its own rect + the chart\u2019s pixel size (P-LOG-7): a corner-bound `x_distance` is unreadable without the width it is measured from');
      if (!/" win="/.test(cen.text) || !/" corner="/.test(cen.text))
        broken.push('every census line must carry win= and corner= (P-LOG-7): an object in another subwindow or bound to another corner draws somewhere its xywh does not say');
      if (!/DrawStripCensusSize\(on, oty, 0\)/.test(cen.text))
        broken.push('a foreign TYPE must be walked too (P-LOG-7): the old gate `continue`d on every type but label, so a covering rectangle/track object was invisible to the one walk that could name it');
    }
    const dd = linesOf(DIAG_DIFF) || [];
    const ddText = dd.join('\n');
    if (!/CORNER/.test(ddText))
      broken.push('diag-diff.py must carry a CORNER verdict (P-LOG-7): a non-zero corner moves the draw site without moving xywh, and the diff must name it instead of passing');
    if (!/win=\(\?P<win>/.test(ddText) && !/win=\(\?P<win>/i.test(ddText))
      broken.push('diag-diff.py must parse the census\u2019s win=/corner= tail (P-LOG-7): a greedy ink group would swallow them and fail every TEXT compare');
    if (broken.length) {
      failures.push('P-LOG-7: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearB.mqh DrawStripGearTabCensus + tools/diag-diff.py)');
    } else {
      console.log('[PASS] P-LOG-7 the census walks the whole chart inside the panel rect and prints win/corner with every line (Biotak/DrawStrip_GearB.mqh)');
    }
  }

  // ── P-LOG-8 (2026-10-01) — THE AFTER-FRAME: THE SNAPSHOT IS NOT THE SCREEN ──
  // MEASURED on the wide gear frame the report's screenshot belongs to: 91/91 PASS
  // (seat, layer, text, back, win, corner), the whole-chart walk named NO cover, and
  // the screen STILL showed the panel's left column bare after a click. A census is a
  // snapshot taken at dump time; the screenshot is later. Any writer that deletes,
  // moves or re-rungs a name AFTER the dump is invisible to every snapshot — so the
  // dump stores what the census saw and the NEXT paint pass walks that same name list
  // and prints only the delta. `AFTER done … gone=0 moved=0 new=0` is then the witness
  // that the model is still the screen's state, which is the moment the hunt stops
  // reading the object list and starts reading MT4's own draw rules.
  {
    const broken = [];
    const base = linesOf(STRIP_BASE) ? linesOf(STRIP_BASE).join('\n') : '';
    if (!/void DrawStripDiagAfterRun\(/.test(base))
      broken.push('DrawStripDiagAfterRun is gone from ' + path.basename(STRIP_BASE) + ' — the AFTER-frame lost its walker (P-LOG-8)');
    if (!/DSTRIP_DIAG_SNAP/.test(base) || !/bool DrawStripDiagSnapAdd\(/.test(base))
      broken.push('the census\u2019s snapshot store is gone from ' + path.basename(STRIP_BASE) + ' (P-LOG-8)');
    if (!/AFTER GONE obj=/.test(base) || !/AFTER MOVED obj=/.test(base) || !/AFTER NEW obj=/.test(base) || !/AFTER done /.test(base))
      broken.push('the AFTER walk must print all three deltas by name (GONE / MOVED / NEW) plus its done line (P-LOG-8)');
    const gearB = linesOf(GEAR_B) ? linesOf(GEAR_B).join('\n') : '';
    if (!/s_dsDiagAfter = 1;/.test(gearB))
      broken.push('the dump must arm the AFTER walk (P-LOG-8): a snapshot without a later re-walk cannot see a writer that follows it');
    if (!/DrawStripDiagSnapAdd\(on, ox, oy, ow, oh, zz/.test(gearB))
      broken.push('every census line must feed the snapshot (P-LOG-8), or the delta compares a list the census never saw');
    const paint = bodyOf(linesOf(STRIP_PAINT) || [], 'void DrawStripPaint(');
    if (!paint) {
      broken.push('DrawStripPaint is gone from ' + path.basename(STRIP_PAINT));
    } else {
      const hook = paint.text.indexOf('DrawStripDiagAfterRun()');
      const gate = paint.text.indexOf('if(!s_dsOpen');
      if (hook < 0)
        broken.push('DrawStripPaint must fire the AFTER walk (P-LOG-8): the next pass after the dump is the first chance to see a later writer');
      else if (gate >= 0 && gate < hook)
        broken.push('the AFTER hook must sit ABOVE the open gate (P-LOG-8): a panel that closed right after the dump still owes its delta');
    }
    if (broken.length) {
      failures.push('P-LOG-8: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh + DrawStrip_GearB.mqh + DrawStrip_Paint.mqh)');
    } else {
      console.log('[PASS] P-LOG-8 the dump snapshots its census and the next paint pass re-walks it, printing only GONE/MOVED/NEW (Biotak/DrawStrip_Base.mqh)');
    }
  }
  // ── P-LOG-10 (2026-10-02) — PAINT ORDER IS CREATION ORDER; ZORDER RULES CLICKS ──
  // The wide gear panel's left column: census 91/91, no cover, clicks still fired,
  // yet nothing painted — the wide tiles were BORN after the narrow-phase content
  // and MT4 paints by birth order. The law: a plate is born BEFORE its content, and
  // any plate that can be REBORN (branch flip, !fits purge, geometry change) purges
  // the family at the rebirth so everything re-lands plate-first.
  {
    const broken = [];
    const skin = linesOf(STRIP_SKIN) ? linesOf(STRIP_SKIN).join('\n') : '';
    const paint = linesOf(STRIP_PAINT) ? linesOf(STRIP_PAINT).join('\n') : '';
    const pbuild = linesOf(PANELS_BUILD) ? linesOf(PANELS_BUILD).join('\n') : '';
    if (!/s_dsPlatePairN/.test(skin))
      broken.push('DrawStripGearPlate lost its pairN flip guard — the wide tiles can be reborn over their content (P-LOG-10)');
    if ((skin.match(/DrawStripGearObjectsPurge\(\)/g) || []).length < 2)
      broken.push('DrawStripGearPlate must purge the family on BOTH plate rebirths (wide entry + bake return) (P-LOG-10)');
    if (!/s_dsSkinPlateDied = true/.test(skin))
      broken.push('DrawStripSkinPaintAt lost the !fits rebirth flag — a strip/board plate purged by size can be reborn over its content (P-LOG-10)');
    const paintLines = linesOf(STRIP_PAINT) || [];
    const plateAt = indexOfLine(paintLines, 'dirty |= DrawStripSkinPaint();');
    const gp = indexOfLine(paintLines, 'dirty |= DrawStripGearPlate();');
    const gr = indexOfLine(paintLines, 'dirty |= DrawStripGearPaint();');
    if (plateAt < 0 || gp < 0 || gr < 0 || !(plateAt < gp && gp < gr))
      broken.push('DrawStripPaint must keep every PLATE call before its content call (SkinPaint -> GearPlate -> GearPaint) (P-LOG-10)');
    if (!/s_dsSkinPlateDied/.test(paint) || !/ObjectsDeleteAll\(0, "PnlDrawS_", -1, -1\)/.test(paint))
      broken.push('DrawStripPaint lost the top-of-pass purge that answers a dead plate (P-LOG-10)');
    if (!/s_PnlGeoSeen\[item\]/.test(pbuild) || !/ObjectsDeleteAll\(0, g_UI\.btnPrefix \+ "Pnl"/.test(pbuild))
      broken.push('PnlCreate lost its geometry-flip purge — cards 9/12 rebuild spec while open and a grown pairN re-births cardm bands over their rows (P-LOG-10)');
    if (broken.length) {
      failures.push('P-LOG-10: ' + broken.join('; ') + ' (Biotak/DrawStrip_Skin.mqh + DrawStrip_Paint.mqh + BiotakPanels_Build.mqh)');
    } else {
      console.log('[PASS] P-LOG-10 paint order is creation order: every reborn plate purges its family first (gear pairN guard, !fits flag + top-of-pass purge, card geometry flip)');
    }
  }

  // ── P-UI-130 (2026-10-02) — THE HOLD'S TWO WINDOWS: ITS PRESS, AND ITS DRAG ──
  // Measured on the live chart (EURUSD,M1 00:12:57-00:13:01): ONE latch on a box the
  // hand then DRAGGED armed the press cycle for its whole 10 s life — the OPENER
  // window's own budget — and refused FIVE real presses in a row, only one of them
  // 4.4 s later (00:13:01.481) after the box had moved out from under the finger.
  // That is «هولد بعضی وقتها باز نمیشه», and it is one constant: a press that can
  // still become a hold fires at 500 ms, so the cycle's job (refusing the flap that
  // re-times that clock, P-UI-115c) needs milliseconds, not ten seconds.
  // The other half is the user's own sentence — «موقعی که باکس جابجا میکنم یا
  // ری‌ساز میکنم نوار استریپ بالا میاد و مزاحم میشه»: the press that STARTS a drag
  // is a press on the drawing, so it armed the latch like a hold; CHARTEVENT_OBJECT_DRAG
  // is the terminal saying it is moving that drawing (P-BK-19a's owner witness,
  // TH3Tool_C's band lock), so it kills the latch and forbids the next one for the
  // 400 ms heartbeat its own events renew. Gate: the constant, the clear, the four
  // readers and the wiring.
  {
    const broken = [];
    const base = codeOf(stripBase || []);
    const rx = codeOf(stripRouter || []);
    if (!/#define DSTRIP_PRESS_CYCLE_MS\s+\d+/.test(base))
      broken.push('DrawStrip_Base.mqh lost DSTRIP_PRESS_CYCLE_MS — the press cycle is bound to the opener window again (P-UI-130)');
    const cycAt = indexOfLine(stripBase || [], 'void DrawStripPressCycleSet(');
    const cyc = cycAt >= 0 ? codeOf((stripBase || []).slice(cycAt, cycAt + 3)) : '';
    if (!/DSTRIP_PRESS_CYCLE_MS/.test(cyc) || /DSTRIP_OPEN_PRESS_MAX_MS/.test(cyc))
      broken.push('DrawStripPressCycleSet() must live on DSTRIP_PRESS_CYCLE_MS, never on the opener window\u2019s cap (P-UI-130)');
    const forget = bodyOf(stripRouter || [], 'void DrawStripHoldForget(');
    if (!forget || !/s_dsHoldMs = 0/.test(forget.text))
      broken.push('DrawStripHoldForget() must clear the CLOCK with the object — a dropped latch read as live kept the cycle armed past its own release (P-UI-130)');
    const wit = bodyOf(stripRouter || [], 'void DrawStripDragWitness(');
    if (!wit) broken.push('DrawStripDragWitness() is gone from Biotak/DrawStrip_Router.mqh (P-UI-130)');
    else if (!/s_dsHoldMs = 0/.test(wit.text) || !/DrawStripPressCycleClear\(\)/.test(wit.text))
      broken.push('the drag witness must KILL the latch and CLEAR the cycle — a press that moved a drawing is never a hold (P-UI-130)');
    if (!/bool DrawStripDragLive\(\)/.test(rx))
      broken.push('DrawStripDragLive() is gone from Biotak/DrawStrip_Router.mqh (P-UI-130)');
    for (const sig of ['void DrawStripHoldLatch(', 'void DrawStripHoldStep(', 'void DrawStripHoldPollAt(']) {
      const body = bodyOf(stripRouter || [], sig);
      if (!body || !/DrawStripDragLive\(\)/.test(body.text))
        broken.push(`${sig.slice(5, -1)} lost its native-drag gate — the strip can come up mid-drag again (P-UI-130)`);
    }
    const onEvent = bodyOf(stripRouter || [], 'bool DrawStripOnEvent(');
    if (!onEvent || !/DrawStripDragWitness\(sparam\)/.test(onEvent.text))
      broken.push('DrawStripOnEvent() lost the OBJECT_DRAG witness call — nothing stamps the drag heartbeat (P-UI-130)');
    else if (onEvent.text.indexOf('DrawStripDragWitness(sparam)') > onEvent.text.indexOf('if(id == CHARTEVENT_MOUSE_MOVE)'))
      broken.push('the drag witness must stand ABOVE the mouse-move block, where every event passes (P-DRAW-64\u2019s own placement rule) (P-UI-130)');
    const poll = bodyOf(stripRouter || [], 'void DrawStripHoldPollAt(');
    if (!poll || !/DSTRIP_HOLD_TTL\)[^\n]*DrawStripHoldClear\(\);[^\n]*DrawStripPressCycleClear\(\)/.test(poll.text))
      broken.push('the poll\u2019s TTL backstop must end the cycle with the hold — one fact, one clear (P-UI-130)');
    if (broken.length) {
      failures.push('P-UI-130: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh + DrawStrip_Router.mqh)');
    } else {
      console.log('[PASS] P-UI-130 the hold\u2019s cycle dies with its press and a native drag kills + forbids it (press cycle 2 s, drag heartbeat gates the latch/step/poll)');
    }
  }

  // ── P-UI-131 (2026-10-02) — THE CHART READS A DIFFERENT ICON TREE THAN THE BUILD ──
  // The user pointed at two icons in the strip's own row and said «این دوتا ایکون چرا
  // اینطوریه» and «کوچیکه نسبت به بقیه». Measured on the shipped trees, not guessed:
  // 22 of 280 canvases disagreed. gl_pin/gl_layers/gl_textsize served 15x15 where the
  // SOURCE holds 26x26 (exactly the two arrows: the pin and the layers glyph), and
  // bk_w*/bk_style*/bk_ray* served 16x16 where the source holds 24x24 — so P-DRAW-106's
  // retirement of the 16 and P-UI-132's re-bake of the three gl_* families were correct
  // in the repo and INVISIBLE on the chart.
  // The reason is a channel split, and P-DRAFT-01 had already guessed wrong about it:
  // `#resource \Files\Icons\...` is resolved by MetaEditor against the COMPILING UNIT's
  // tree (P-BUILD-03), which is why retiring `Sync-IconsToTerminal` measured INERT and
  // looked like dead weight — but every painter writes
  // `OBJPROP_BMPFILE = "::Files\Icons\x.bmp"`, and `::Files\` is the TERMINAL's
  // MQL4\Files, read at PAINT time. The build embedded the repo's art; the chart drew
  // the terminal's; and `tools/check-resources.js` walks the SOURCE tree, so the one
  // gate that could have named it was reading the same tree as the compiler.
  // Three facts to keep: the delivery is CALLED, it is MANIFEST-bounded (P-DRAFT-01 was
  // right that a directory copy is write amplification), and a gate compares the two
  // trees so the split can never be silent again.
  {
    const broken = [];
    const ps1 = codeOf(linesOf(BUILD_PS1));
    const ICON_GATE = path.join(__dirname, 'check-icon-deploy.js');
    if (!fs.existsSync(ICON_GATE))
      broken.push('tools/check-icon-deploy.js is gone \u2014 nothing compares the tree the chart reads with the tree the compiler reads (P-UI-131)');
    else {
      const g = codeOf(linesOf(ICON_GATE));
      if (!/icon-manifest\.txt/.test(g))
        broken.push('the icon deploy gate must walk the generator\u2019s manifest, not the directory \u2014 a wildcard re-opens P-DRAFT-01\u2019s 10 MB copy (P-UI-131)');
      if (!/MQL4/.test(g) || !/Icons/.test(g))
        broken.push('the icon deploy gate must read the TERMINAL\u2019s MQL4\\Files\\Icons \u2014 that tree is the one the pixels come from (P-UI-131)');
    }
    //--- same lesson again: the gate must be ASSIGNED and INVOKED as live code, so
    //--- commenting either line out fails here (which is how this gate was proved).
    if (!/^[ \t]*\$iconGate\s*=\s*Join-Path[^\n]*check-icon-deploy\.js/m.test(ps1) ||
        !/Invoke-ProjectGate[^\n]*icon deploy gate/.test(ps1))
      broken.push('compile-th3.ps1 does not RUN the icon deploy gate \u2014 a gate nobody runs is a comment (P-UI-131)');
    //--- P-DRAW-108's own lesson, one layer down: a rule that only needs the NAME is
    //--- satisfied by a COMMENT (the mutation that proved this gate commented the call
    //--- out and still passed). The call must be the line\u2019s first token.
    if (!/^[ \t]*Sync-IconsToTerminal\s+-ResolvedMql4Dir/m.test(ps1))
      broken.push('compile-th3.ps1 no longer DELIVERS the icon tree \u2014 the chart keeps drawing whatever the terminal cached (P-UI-131)');
    if (!/icon-manifest\.txt/.test(ps1))
      broken.push('the delivery must be bounded by tools/icon-manifest.txt \u2014 P-DRAFT-01 retired a directory copy for a reason that was only half right (P-UI-131)');
    // the two taps the report names, each with the one flush P-DRAW-127 asks for
    const tapLines = stripTap || [];
    const actAt = indexOfLine(tapLines, 'bool DrawStripActTap(');
    const actLines = actAt >= 0 ? tapLines.slice(actAt) : [];
    const pinAt = actLines.findIndex((l) => /if\(a == DSTRIP_ACT_PIN\)/.test(l));
    if (pinAt < 0) broken.push('the pin\u2019s tap branch is gone from bool DrawStripActTap() (P-UI-131)');
    else if (!/ChartRedraw\(\)/.test(codeOf(actLines.slice(pinAt, pinAt + 14))))
      broken.push('the pin tap must carry its own ChartRedraw() \u2014 P-DRAW-127: «A user action gets one unconditional flush» (P-UI-131)');
    const tglAt = indexOfLine(tapLines, 'if(DrawStripIsToggle(slot))');
    if (tglAt < 0) broken.push('the cell-toggle branch is gone from bool DrawStripTap() (P-UI-131)');
    else {
      // the branch ends where the next function begins \u2014 a fixed window would read
      // the PASS off the branch AFTER this one, which is how a gate learns to lie.
      const tglEnd = tapLines.findIndex((l, i) => i > tglAt && /bool DrawStripActTap\(/.test(l));
      const tgl = codeOf(tapLines.slice(tglAt, tglEnd > tglAt ? tglEnd : tglAt + 60));
      if (!/ChartRedraw\(\)/.test(tgl))
        broken.push('a cell toggle (the BACK/layers glyph) must carry its own ChartRedraw() \u2014 the paint flushes only if(dirty), and the list can be right while the pixels lag (P-DRAW-127) (P-UI-131)');
      if (!/DrawSlotRead\(s_dsObj, slot\)/.test(tgl))
        broken.push('a cell toggle must print its READ-BACK \u2014 «the tap did nothing» is unprovable without it (P-UI-131)');
    }
    //--- the second half: the BACK seat is ONE shape in two inks. It wore
    //--- `gl_layers_m` (grey chevrons, 26) off and `bk_back_on` (amber rects, 24) on,
    //--- so a tap that moved the drawing behind the candles read as another button —
    //--- and for a filled box the interior going behind the bars reads as its colour
    //--- switching off. The live witness proved the WRITE was exact all along
    //--- (`slot=9 name=Behind candles … read=1 fill=1 child=1` / `-> 0 read=0 fill=1`),
    //--- so the defect was the seat, not the slot. Three owners, one fact.
    const backAt = indexOfLine(stripBase || [], 'if(slot == DRAW_SLOT_BACK)');
    const backBranch = backAt >= 0 ? codeOf((stripBase || []).slice(backAt, backAt + 4)) : '';
    if (backAt < 0) broken.push('the BACK slot lost its face branch in Biotak/DrawStrip_Base.mqh (P-UI-131)');
    else {
      if (/gl_layers/.test(backBranch))
        broken.push('the BACK seat must not wear a gl_* face \u2014 a toggle is ONE shape in two inks, and gl_* is the family that broke the scale rule (P-UI-131)');
      if (!/bk_back_off\.bmp/.test(backBranch) || !/bk_back_on\.bmp/.test(backBranch))
        broken.push('the BACK seat must answer bk_back_off/bk_back_on \u2014 two inks of one drawing (P-UI-131)');
    }
    const gen = codeOf(linesOf(path.join(__dirname, 'gen-th3-icons.js')));
    if (!/bk_back_off\.bmp/.test(gen))
      broken.push('tools/gen-th3-icons.js no longer bakes bk_back_off.bmp \u2014 the twin is a generated face, not a hand-made file (P-UI-131)');
    const mock = codeOf(linesOf(path.join(__dirname, 'sim-strip-panels.py')));
    if (/n == "BACK"[^\n]*gl_layers/.test(mock))
      broken.push('tools/sim-strip-panels.py still draws a gl_* face for BACK \u2014 a mock that differs from the chart is how a two-glyph control survives review (P-UI-131)');
    if (broken.length) {
      failures.push('P-UI-131: ' + broken.join('; ') + ' (compile-th3.ps1 + tools/check-icon-deploy.js + Biotak/DrawStrip_Tap.mqh + Biotak/DrawStrip_Base.mqh)');
    } else {
      console.log('[PASS] P-UI-131 the terminal tree is delivered manifest-bounded and compared, the pin/toggle taps flush their own frame, and the BACK seat is one shape in two inks');
    }
  }

  // ── P-UI-132 (2026-10-02) — THE EDGE THE MODE TOOK IS THE EDGE IT GIVES BACK ──
  // User report: «وقتی اکستند کلیک میکنم 50 درصد باکس خاموش و روشن نمیشه چرا تداخل داره
  // و اینکه اکستند خاموش میکنم بر نمیگرده به حالت اول» — one sentence, two facts about ONE
  // missing restore. `DrawSlotWrite`'s EXTEND arm writes `[BXE2]` and nothing else
  // (Biotak/Toolbar_B.mqh), while the tap's own first step (P-DRAW-64c) moves the box's
  // LATER anchor onto the forming bar: arming the mode changes the drawing permanently and
  // disarming it only stops the travel. The 50 % is a LEVEL at the mid PRICE, so it does
  // not fight the edge — it RIDES it to the far end of the chart, and two cells moving
  // together read as one cell interfering with the other.
  // The fix is one memo of two numbers per armed box, spent at the disarm, and the ORDER
  // is the whole fix: remembered BEFORE the first step moves the edge.
  {
    const broken = [];
    const pick = stripPick || [];
    const tap = stripTap || [];
    for (const sig of ['bool BoxEdgeRemember(', 'bool BoxEdgeRestore(', 'void BoxEdgeRememberGroup(', 'void BoxEdgeRestoreGroup(']) {
      if (indexOfLine(pick, sig) < 0)
        broken.push(`${sig.slice(0, -1)}() is gone from Biotak/DrawStrip_Pick.mqh \u2014 nothing gives the edge back (P-UI-132)`);
    }
    const restore = bodyOf(pick, 'bool BoxEdgeRestore(');
    if (restore) {
      if (!/BoxMidSync\(/.test(restore.text))
        broken.push('BoxEdgeRestore() must re-sync the 50 % line \u2014 it rides the edge, so a restored edge would leave the line behind (P-UI-132)');
      if (!/FillChildSync\(/.test(restore.text))
        broken.push('BoxEdgeRestore() must re-sync the interior \u2014 P-DRAW-64a\u2019s own rule for a moved edge (P-UI-132)');
      if (!/ObjectMove\(/.test(restore.text))
        broken.push('BoxEdgeRestore() must put the anchor home with ObjectMove \u2014 MQL4 has no indexed OBJPROP_PRICE setter (P-UI-132)');
    }
    const extAt = indexOfLine(tap, 'if(slot == DRAW_SLOT_EXTEND)');
    if (extAt < 0) broken.push('the toggle branch lost its EXTEND arm in bool DrawStripTap() (P-UI-132)');
    else {
      const arm = codeOf(tap.slice(extAt, extAt + 7));
      const rem = arm.indexOf('BoxEdgeRememberGroup()');
      const step = arm.indexOf('BoxExtendStepGroup()');
      if (rem < 0) broken.push('arming EXTEND must remember the edge \u2014 the first step moves it in the same tap (P-UI-132)');
      else if (step >= 0 && rem > step)
        broken.push('BoxEdgeRememberGroup() must come BEFORE BoxExtendStepGroup() \u2014 a memo written after the move remembers the wrong edge (P-UI-132)');
      if (!/BoxEdgeRestoreGroup\(\)/.test(arm))
        broken.push('disarming EXTEND must restore the edge \u2014 «extending off does not return to the original state» (P-UI-132)');
    }
    const cyc = bodyOf(pick, 'int BoxExtCycle(');
    if (cyc) {
      if (!/BoxEdgeRestore\(/.test(cyc.text))
        broken.push('the \u00ab\u2026\u00bb cycle\u2019s way back to OFF is a disarm too \u2014 it must give the edge back on the same terms (P-UI-132)');
      //--- P-UI-132 addendum: the cycle's ARMING half. The check above only ever asked
      //--- about the way BACK, so a cycle that restored from a memo it never wrote
      //--- passed this register \u2014 the defect, on one of the two doors into EXTEND.
      if (!/BoxEdgeRemember\(/.test(cyc.text))
        broken.push('the \u00ab\u2026\u00bb cycle ARMING must remember the edge \u2014 it stretches the box on the same tap (P-UI-132)');
      else if (!/prev\s*==\s*BOXEXT_OFF\s*&&\s*ext\s*!=\s*BOXEXT_OFF/.test(cyc.text))
        broken.push('BoxEdgeRemember() in the cycle must be guarded on the OFF\u2192ON TRANSITION \u2014 an armed box walking its modes must keep the hand-drawn edge (P-UI-132)');
    }
    //--- P-UI-132 addendum: the gear row is the SAME cell as the quick row, so it
    //--- carries the same memo. Fixing one door and not the other is how a fix reads
    //--- as \u00absometimes works\u00bb, so both doors are named here.
    const gearAt = indexOfLine(tap, 'bool DrawStripGearRowTap(');
    if (gearAt < 0) broken.push('bool DrawStripGearRowTap() is gone from Biotak/DrawStrip_Tap.mqh (P-UI-132)');
    else {
      const gear = codeOf(tap.slice(gearAt, gearAt + 45));
      if (!/if\(\s*arg\s*==\s*DRAW_SLOT_EXTEND\s*\)/.test(gear))
        broken.push('the gear row lost its EXTEND arm \u2014 the panel switch would toggle a mode it cannot give back (P-UI-132)');
      else {
        if (!/BoxEdgeRememberGroup\(\)/.test(gear))
          broken.push('the gear row arming EXTEND must remember the edge, like the quick row (P-UI-132)');
        if (!/BoxEdgeRestoreGroup\(\)/.test(gear))
          broken.push('the gear row disarming EXTEND must restore the edge, like the quick row (P-UI-132)');
        const gRem = gear.indexOf('BoxEdgeRememberGroup()');
        const gStep = gear.indexOf('BoxExtendStepGroup()');
        if (gRem >= 0 && gStep >= 0 && gRem > gStep)
          broken.push('BoxEdgeRememberGroup() must come BEFORE BoxExtendStepGroup() in the gear row too (P-UI-132)');
      }
    }
    const del = bodyOf(tap, 'void DrawStripFireDelete(');
    if (del && !/BoxEdgeForget\(/.test(del.text))
      broken.push('deleting a box must spend its edge memo \u2014 a dead name must not hold one of the eight slots (P-UI-132)');
    if (broken.length) {
      failures.push('P-UI-132: ' + broken.join('; ') + ' (Biotak/DrawStrip_Pick.mqh + Biotak/DrawStrip_Tap.mqh)');
    } else {
      console.log('[PASS] P-UI-132 EXTEND gives the far edge back: remembered before the first step, restored at the disarm, with the mid line and the interior re-synced');
    }
  }

  // ── P-UI-133 (2026-10-02) — RETIRED BY P-UI-134, AND THE RETIREMENT IS THE GATE ──
  // The witness: twelve consecutive taps on one box, `[drawstrip] SLOT slot=11 name=50 %
  // line obj="Rectangle 17077" -> 0 read=1` \u2014 the tap asks for 0, the object answers 1,
  // forever («50 درصد باکس خاموش و روشن نمیشه چرا تداخل داره»). The cut was
  // `StringFind(d, " [BX")`, and that space only exists BETWEEN marks: on a box wearing
  // both (`[BX50] [BXE3:8]` \u2014 the state any use of EXTEND leaves) the first match is the
  // space before the SECOND tag, `pre` came back as `[BX50]`, the mid was re-emitted from
  // the prefix whatever the flag said, and `if(want == d) return;` turned every tap into
  // a no-op. P-UI-133 fixed the cut point \u2014 and the live box then refused BOTH marks to
  // clear (`slot=11 \u2026 -> 0 read=1` AND `slot=12 \u2026 -> 0 read=1`), which is not a third
  // cut point but the shape of the thing: two owners' state inside a string FOUR owners
  // rewrite. So the lesson is retired INTO P-UI-134, and the strongest form of the old
  // gate is the one that says the surgery is GONE: a register entry that keeps demanding
  // a fixed cut point is a register entry that would have demanded the fourth attempt.
  {
    const broken = [];
    const tbA = linesOf(path.join(BIOTAK, 'Toolbar_A.mqh'));
    const whole = codeOf(tbA);
    if (/StringFind\([^,]+,\s*" \[BX/.test(whole))
      broken.push('the marks block is cut with " [BX" again \u2014 P-UI-133\u2019s retired cut point (the marks are a key now, P-UI-134)');
    if (/ObjectSetString\(0,\s*name,\s*OBJPROP_TEXT/.test((bodyOf(tbA, 'void BoxMarkWrite(') || {}).text || ''))
      broken.push('the mark owner writes OBJPROP_TEXT again \u2014 the string has four owners and this one lost three fights over it (P-UI-133 retired into P-UI-134)');
    if (broken.length) {
      failures.push('P-UI-133(retired): ' + broken.join('; ') + ' (Biotak/Toolbar_A.mqh)');
    } else {
      console.log('[PASS] P-UI-133(retired by P-UI-134) the string surgery is gone: no " [BX" cut, and the mark owner never writes OBJPROP_TEXT');
    }
  }

  // ── P-UI-134 (2026-10-02) — THE MARKS ARE A KEY, NOT A SUBSTRING ──
  // P-UI-133 fixed a symptom of a shape: two owners'' state lived inside `OBJPROP_TEXT`,
  // a string FOUR owners rewrite (`[CL…]`, `[OP…]`, `[FL…]`, `[FT…]`), so every mark
  // write re-serialised a string it does not own and cut its own block out of it. After
  // that fix the live box still refused BOTH marks to clear (`slot=11 … -> 0 read=1` AND
  // `slot=12 … -> 0 read=1` — «الان هیچکدوم درست کار نمیکنه»), which is what a shared
  // mutable string with four writers does. The architecture: ONE keyed value per box in
  // the terminal''s own store (the same store `BaseKnotGV` uses for per-box state), a
  // fingerprint in the value so a foreign key is never believed, the legacy tags READ ONCE
  // and left inert, and a delete path that spends the key.
  {
    const broken = [];
    const tbA2 = linesOf(path.join(BIOTAK, 'Toolbar_A.mqh'));
    const read = bodyOf(tbA2, 'void BoxMarkRead(');
    const write = bodyOf(tbA2, 'void BoxMarkWrite(');
    const legacy = bodyOf(tbA2, 'void BoxMarkLegacyRead(');
    if (!read) broken.push('BoxMarkRead() is gone from Biotak/Toolbar_A.mqh (P-UI-134)');
    else {
      if (!/GlobalVariableCheck\(/.test(read.text) || !/GlobalVariableGet\(/.test(read.text))
        broken.push('BoxMarkRead() must read the STORE first \u2014 the description is not the census any more (P-UI-134)');
      if (!/BoxMarkFingerprint\(/.test(read.text))
        broken.push('BoxMarkRead() must VERIFY the fingerprint before believing a key \u2014 a key can outlive its box (P-UI-134)');
      if (!/BoxMarkLegacyRead\(/.test(read.text))
        broken.push('BoxMarkRead() must MIGRATE the legacy tags \u2014 boxes drawn before the store keeps their 50 % and their extend (P-UI-134)');
    }
    if (!write) broken.push('BoxMarkWrite() is gone from Biotak/Toolbar_A.mqh (P-UI-134)');
    else {
      if (/OBJPROP_TEXT/.test(write.text))
        broken.push('BoxMarkWrite() must NEVER touch OBJPROP_TEXT \u2014 that string has four owners and this one lost three fights over it (P-UI-134)');
      if (!/GlobalVariableSet\(/.test(write.text))
        broken.push('BoxMarkWrite() must write the store (P-UI-134)');
      if (!/GlobalVariableDel\(/.test(write.text))
        broken.push('a box with no marks must own NO key \u2014 an empty mark is a deleted key, not a zero (P-UI-134)');
    }
    if (!legacy) broken.push('BoxMarkLegacyRead() is gone \u2014 the legacy format may be READ once, never written again (P-UI-134)');
    else if (/ObjectSetString/.test(legacy.text))
      broken.push('BoxMarkLegacyRead() must be read-only (P-UI-134)');
    // every path that DESTROYS a box destroys its key with it
    const drop = bodyOf(stripTap || [], 'void DrawStripFireDelete(');
    if (drop && !/BoxMarkDrop\(/.test(drop.text))
      broken.push('the strip\'s bin must spend the box\'s key \u2014 MT4 reuses object names, so a dead key would dress a fresh box (P-UI-134)');
    const objDel = bodyOf(stripRouter || [], 'bool DrawStripOnEvent(');
    if (objDel && !/BoxMarkDrop\(/.test(objDel.text))
      broken.push('a drawing deleted on the chart must spend its key too (P-UI-134)');
    // the per-object sweep asks the store, not the retired format
    const sweep = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')));
    if (/StringFind\(ObjectGetString\(0, nm, OBJPROP_TEXT\), "\[BX"\)/.test(sweep))
      broken.push('the per-object sweep still tests the description for `[BX` \u2014 it would skip every box the store already owns (P-UI-134)');
    if (broken.length) {
      failures.push('P-UI-134: ' + broken.join('; ') + ' (Biotak/Toolbar_A.mqh + DrawStrip_Pick/Tap/Router)');
    } else {
      console.log('[PASS] P-UI-134 the box marks live in a keyed store (fingerprint-verified, migrated from the legacy tags, dropped with the box) and OBJPROP_TEXT is never written by the mark owner');
    }
  }

  // ── DIAG-134 (2026-10-02) — ALL THREE BOX-EXTRAS DOORS WITNESS, ON THE FLUSHED CHANNEL ──
  // MEASURED 2026-10-02: the Experts journal stood still for seven minutes while the
  // user's clicks went into MT4's RAM buffer (P-DRAW-126), so a witness written with
  // `Print` answers «nothing happened» long after the tap happened \u2014 and each miss cost
  // a reproduction round-trip. DIAG-131 fixed that for the QUICK CELL and it is what
  // finally closed the 50 % / EXTEND report. The gear switch and the «…» cycle were
  // fixed the same day with NO witness at all \u2014 which is precisely how a fix can be
  // wrong and still look green, and they were in fact wrong until this session closed
  // them. So the rule is over the ACTION, not over one call site: every door that moves
  // the edge WITNESSES through the flushed channel, and the witness names the memo slot
  // (the fact that settles «the box never came back»).
  {
    const broken = [];
    const tap3 = stripTap || [];
    //--- the quick cell (DIAG-131, kept: it is the door a report names most)
    const quick = codeOf(tap3);
    if (!/DrawStripDiagEmit\(\s*"\[drawstrip\] SLOT /.test(quick))
      broken.push('the quick slot cell lost its SLOT witness \u2014 a tap that changes nothing must still leave a record (DIAG-134)');
    //--- door 2: the gear panel's switch
    const gAt = indexOfLine(tap3, 'bool DrawStripGearRowTap(');
    if (gAt < 0) broken.push('bool DrawStripGearRowTap() is gone \u2014 one of the three EXTEND doors is unaccounted for (DIAG-134)');
    else {
      const g = codeOf(tap3.slice(gAt, gAt + 45));
      if (!/DrawStripDiagEmit\(\s*"\[drawstrip\] GEAREXT /.test(g))
        broken.push('the gear switch lost its GEAREXT witness \u2014 it is a door into EXTEND and must answer (DIAG-134)');
      else if (!/BoxEdgeSlot\(/.test(g))
        broken.push('the GEAREXT witness must print the memo slot \u2014 that number is what settles «the box never came back» (DIAG-134)');
    }
    //--- door 3: the picker's «…» cycle
    const b50 = codeOf(tap3.slice(indexOfLine(tap3, 'if(kind == DSTRIP_MK_BOX50)'), indexOfLine(tap3, 'if(kind == DSTRIP_MK_BOX50)') + 22));
    if (!/DrawStripDiagEmit\(\s*"\[drawstrip\] BOX50 /.test(b50))
      broken.push('the 50 % row lost its BOX50 witness \u2014 the cell that failed three times must answer with the mark, not with a re-run (DIAG-134)');
    else if (!/ObjectFind\(0, BoxMidName\(/.test(b50))
      broken.push('the BOX50 witness must report whether the mid LINE object exists \u2014 a mark without a line is the exact defect (DIAG-134)');
    const bx = codeOf(tap3.slice(indexOfLine(tap3, 'if(kind == DSTRIP_MK_BOXEXT)'), indexOfLine(tap3, 'if(kind == DSTRIP_MK_BOXEXT)') + 30));
    if (!/DrawStripDiagEmit\(\s*"\[drawstrip\] BOXEXT /.test(bx))
      broken.push('the «…» cycle lost its BOXEXT witness \u2014 it is a door into EXTEND and must answer (DIAG-134)');
    else {
      if (!/from=/.test(bx) || !/to=/.test(bx))
        broken.push('the BOXEXT witness must name the mode it walked FROM and TO \u2014 one end cannot show a no-op (DIAG-134)');
      if (!/BoxEdgeSlot\(/.test(bx))
        broken.push('the BOXEXT witness must print the memo slot \u2014 armed leaves one, a disarm leaves none (DIAG-134)');
    }
    //--- and the channel itself: a witness must never be routed back through `Print`
    if (/Print\(\s*"\[drawstrip\] (SLOT|GEAREXT|BOX50|BOXEXT)/.test(quick))
      broken.push('a box-extras witness went back to `Print` \u2014 MT4 buffers the journal in RAM, so it cannot be read when it is needed (DIAG-134)');
    if (broken.length) {
      failures.push('DIAG-134: ' + broken.join('; ') + ' (Biotak/DrawStrip_Tap.mqh)');
    } else {
      console.log('[PASS] DIAG-134 all three box-extras doors witness on the flushed channel, each naming the memo slot (Biotak/DrawStrip_Tap.mqh)');
    }
  }

  // ── DIAG-135 (2026-10-02) — THE INTERMITTENT IS INSTRUMENTED, NOT WAITED FOR ──
  // User report: «بعضی وقتان … باکس اصلا رنگ نمیکره … گاهی به ندرت پیش میاد», and then,
  // asked to reproduce it: «الان من هر کاری میکنم اون حالت پیش نمیاد». That pair is an
  // intermittent, and an intermittent cannot be debugged by reproduction — it can only be
  // CAUGHT. MEASURED on the screenshot that came with it: three cells whose interior
  // measured exactly the plate colour (nothing drawn at all) and 148 px of empty row
  // after them, with the icons deployed and carrying ink (both measured, so neither).
  // So the paint checks its OWN invariant and writes the evidence the moment it is false
  // \u2014 months later, from a report nobody thought to mention. Three attempts at this
  // class already cost a day each (the `[BX\u2026]` cuts), every one of them a guess from a
  // model while the live box disagreed.
  {
    const broken = [];
    const head = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Head.mqh')) || []);
    const paint = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || []);
    if (!/dsWitnessSig/.test(head))
      broken.push('the ROWBLANK signature latch is gone from Biotak/DrawStrip_Head.mqh \u2014 one line per state is what keeps the witness from becoming a flood (DIAG-135)');
    // both halves of the row: the screenshot's black square was an ACTION cell, so a
    // quick-row-only check would have called that panel healthy.
    if (!/QUICKCELL/.test(paint) || !/ACTCELL/.test(paint))
      broken.push('the blank-cell check must cover BOTH the quick row and the chrome actions \u2014 measured, the 148 px gap held an action cell (DIAG-135)');
    if (!/ObjectFind\(0, ic\)/.test(paint))
      broken.push('a raster seat must be PROBED, not assumed \u2014 «DrawStripFace returned true» is not «the glyph is on the chart» (DIAG-135)');
    if (!/DrawStripDiagEmit\(\s*"\[drawstrip\] ROWBLANK/.test(paint))
      broken.push('the blank-cell witness lost its line \u2014 nothing else records the rare state (DIAG-135)');
    else {
      if (!/if\(\s*sig\s*!=\s*dsWitnessSig\s*\)/.test(paint))
        broken.push('the ROWBLANK emit must be guarded by the signature compare \u2014 an unguarded one floods the file on every repaint (DIAG-135)');
      if (!/else if\(dsWitnessSig\s*!=\s*""\)/.test(paint))
        broken.push('a recovered panel must RE-ARM the latch \u2014 without it the line is written once and never again, which is the same as having no witness (DIAG-135)');
      if (!/dsBadPainted/.test(paint))
        broken.push('the ROWBLANK line must carry the painted count \u2014 the empty row IS a count disagreement (DIAG-135)');
    }
    if (/Print\(\s*"\[drawstrip\] ROWBLANK/.test(paint))
      broken.push('the ROWBLANK witness went back to `Print` \u2014 MT4 buffers the journal in RAM, so a rare bug is exactly the one that must not wait for a flush (DIAG-135)');
    if (broken.length) {
      failures.push('DIAG-135: ' + broken.join('; ') + ' (Biotak/DrawStrip_Paint.mqh + DrawStrip_Head.mqh)');
    } else {
      console.log('[PASS] DIAG-135 the rare blank-cell state is instrumented: the paint checks its own invariant on both halves of the row and writes one flushed line per distinct state');
    }
  }

  // ── P-PAL (2026-10-02) — WHAT SURVIVED THE BOARD, AND WHY ──
  // The strip's own colour board is GONE (P-PAL-21): DrawStrip_Pal.mqh,
  // DrawStrip_PalCat.mqh and DrawStrip_PalPaint.mqh, its 14-family catalogue, its
  // page table, its RECENT band, its HEX field, its opacity bar and its HSV studio
  // were deleted with their call sites, because a colour cell now opens the
  // CARDS' palette (P-PAL-19) — the ONE colour editor this product has. Every rule
  // this block used to hold (the byte order, the page break, the plate height, the
  // modern face, the captions, the knobs, the empty RECENT well) described a
  // surface that no longer exists, so it went with it; `tools/pal-table-proof.py`
  // and its two mutations went with it too. What remains is the rule the board's
  // death made urgent: the strip OWNS the popup it opens, so a click on that
  // popup is not a click on the chart.
  {
    const broken = [];
    // ── P-PAL-20: THE SURFACE LEDGER AND THE SINGLE DISMISSAL EXIT. The colour board
    //   is gone (P-PAL-19) and its popup now lives in the panels, so `DrawStripPointInside`
    //   — the one function that answers «is this pixel OUR surface» — had no clause for
    //   it. A colour pick is a release on TWO channels: the palette serves it first, then
    //   the strip asks about the release pixel, reads false and `DrawStripClose()` runs
    //   («یک رنگ انتخاب می‌کنم کل استریپ بسته می‌شه»). Four laws, all mechanical:
    //   (a) the oracle consults the ledger, (b) the ledger has an owner + publish + clear,
    //   (c) ONE writer republishes it whole every event (the entry's bridge), and
    //   (d) nobody outside the strip calls `DrawStripPaint()` — the repaint is a REQUEST
    //       the bridge spends (P-PAL-19f).
    {
      const baseP = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Base.mqh')) || []);
      const routerP = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
      const inFn = (() => { const m = baseP.match(/bool DrawStripPointInside\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
      if (!inFn) broken.push('`DrawStripPointInside` is gone or unreadable \u2014 it is the one function that answers «is this pixel ours» (P-PAL-20)');
      else if (!/DrawStripSurfaceAt\(/.test(inFn))
        broken.push('the surface oracle does not consult the LEDGER \u2014 a release on a popup the strip owns reads as a click on the chart and closes the strip (P-PAL-20)');
      for (const sig of ['void DrawStripSurfaceClear()', 'void DrawStripSurfacePublish(', 'bool DrawStripSurfaceAt('])
        if (!baseP.includes(sig)) broken.push(`the ledger has no \`${sig.replace(/\(.*/, '()')}\` \u2014 the registry the oracle asks does not exist (P-PAL-20)`);
      const entry = codeOf(linesOf(path.join(ROOT, 'Biotak Trigger TH3.mq4')) || []);
      const bAt = entry.indexOf('DrawStripSurfaceClear();');
      const pAt = entry.indexOf('DrawStripSurfacePublish(');
      if (bAt < 0 || pAt < 0)
        broken.push('the BRIDGE does not publish the ledger \u2014 the strip cannot see `g_PalX/PalW()`, so the entry is the only writer and skipping it arms nothing (P-PAL-20)');
      else if (bAt > pAt)
        broken.push('the bridge must CLEAR the ledger before it republishes \u2014 one writer, whole truth, every event (P-PAL-20)');
      if (!/DrawStripSurfacePublish\(g_PalX, g_PalY, PalW\(\), PalH\(\)\)/.test(entry))
        broken.push('the bridge must publish the PALETTE\'s own rect \u2014 a ledger fed any other rect guards nothing (P-PAL-20)');
      if (!/if\(DrawStripPalRepaintTake\(\)\)/.test(entry))
        broken.push('nobody SPENDS the repaint flag \u2014 the apply sets it and the strip never learns the colour landed (P-PAL-19f/P-PAL-20)');
      if (!/DrawStripSurfaceAt\(rcx, rcy\)/.test(routerP))
        broken.push('the dismissal branch has no SURFHIT witness \u2014 working is silent, so the ledger cannot be proven from the log (P-PAL-20)');
      // (d) the repaint is a REQUEST: a paint called from inside somebody else\'s route
      // is the P-PAL-19f defect, and the panels are the only caller that can do it.
      for (const f of fs.readdirSync(BIOTAK).filter((n) => /^Biotak.*\.mqh$/.test(n))) {
        const t = codeOf(linesOf(path.join(BIOTAK, f)) || []);
        if (/DrawStripPaint\(\)/.test(t))
          broken.push(`${f} calls DrawStripPaint() from outside the strip \u2014 a repaint is a REQUEST the bridge spends (P-PAL-19f/P-PAL-20)`);
      }
      if (!/DrawStripSurfaceClear\(\)/.test(codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearB.mqh')) || [])))
        broken.push('a closed strip still owns its popup pixels — the ledger must die with its owner (P-PAL-20)');
    }
    if (broken.length) {
      failures.push('P-PAL: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh + Router/GearB + the entry bridge)');
    } else {
      console.log("[PASS] P-PAL the strip owns its popups: one surface ledger (P-PAL-20) that the pixel oracle consults and the entry's bridge rewrites whole every event, one repaint REQUEST the bridge spends, and no panel painting the strip from inside its own route. The strip has NO colour board of its own (P-PAL-21) — the cards' palette is the only colour editor");
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
