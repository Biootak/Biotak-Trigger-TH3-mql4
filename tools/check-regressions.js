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
const EVENT_ROUTER = ROUTER;
const CALC = path.join(BIOTAK, 'EventHandlers_Calc.mqh');
const HTF = path.join(BIOTAK, 'HTFCandles.mqh');
const VIS = path.join(BIOTAK, 'VisibilityManager.mqh');
const APPLY = path.join(BIOTAK, 'BiotakPanels_Apply.mqh');
const PAL_B = path.join(BIOTAK, 'BiotakPanels_PalB.mqh');
const OBJ = path.join(BIOTAK, 'EventHandlers_Objects.mqh');
const NODES = path.join(BIOTAK, 'BaseKnot_Nodes.mqh');
const BK_BASE = path.join(BIOTAK, 'BaseKnot_Base.mqh');
const PLAN = path.join(BIOTAK, 'BaseKnot_Plan.mqh');
const PIPE_A = path.join(BIOTAK, 'LevelPipe_A.mqh');
const PIPE_B = path.join(BIOTAK, 'LevelPipe_B.mqh');
const MENU_D = path.join(BIOTAK, 'BiotakMenu_D.mqh');
const MENU_C = path.join(BIOTAK, 'BiotakMenu_C.mqh');
const MENU_A = path.join(BIOTAK, 'BiotakMenu_A.mqh');
const MENU_B = path.join(BIOTAK, 'BiotakMenu_B.mqh');
const MENU_RING = path.join(BIOTAK, 'BiotakMenu_Ring.mqh');
const SESS_DRAW = path.join(BIOTAK, 'Sessions_Draw.mqh');
const SESS_MODEL = path.join(BIOTAK, 'Sessions_Model.mqh');
// P-UI-163: the per-tick refresh's home — the ring's existence probe must be
// CALLED there (a declared healer that nobody runs is the retired-defect class).
const KIT = path.join(BIOTAK, 'BiotakKit.mqh');
// P-UI-161: the Z ladder's home — the star's own rung is declared beside the
// badge's, and the rung ORDER is the click rule (highest ZORDER under the cursor).
const CONSTANTS = path.join(BIOTAK, 'ConstantsAndEnums.mqh');
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
// P-BK-111: the direction cell's four readers — the strip's own slot table (rows + hit),
// the domain owner, and the icon generator whose baked backdrop must grow with the row.
const PANELS_ROWS = path.join(BIOTAK, 'BiotakPanels_Rows.mqh');
const PANELS_HIT = path.join(BIOTAK, 'BiotakPanels_Hit.mqh');
const BK_DIRECTION = path.join(BIOTAK, 'BaseKnot_Direction.mqh');
const BK_MEASURE = path.join(BIOTAK, 'BaseKnot_Measure.mqh');
const BK_WITNESS = path.join(BIOTAK, 'BaseKnot_Witness.mqh');
const ICON_GEN = path.join(__dirname, 'gen-th3-icons.js');
const STRIP_TAP = path.join(BIOTAK, 'DrawStrip_Tap.mqh');
const STRIP_ROUTER = path.join(BIOTAK, 'DrawStrip_Router.mqh');
const RES_GATE = path.join(__dirname, 'check-resources.js');
const STRIP_PAINT = path.join(BIOTAK, 'DrawStrip_Paint.mqh');
const PANELS_BUILD = path.join(BIOTAK, 'BiotakPanels_Build.mqh');
const STRIP_PICK = path.join(BIOTAK, 'DrawStrip_Pick.mqh');
const PAL_A = path.join(BIOTAK, 'BiotakPanels_PalA.mqh');
// P-DRAW-128/129/130 (2026-10-13): the palette's apply table, the slot writer's
// owner file, and the attach init where the witness walk is primed.
const PAL_STATE = path.join(BIOTAK, 'BiotakPanels_State.mqh');
const TOOLBAR_B = path.join(BIOTAK, 'Toolbar_B.mqh');
const EV_INIT = path.join(BIOTAK, 'EventHandlers_Init.mqh');
const BUILD_PS1 = path.join(ROOT, 'compile-th3.ps1');
// P-LM-25 (2026-10-16): the leg-measure readout's two tenants — the tool half that
// reads the composite (TH3Tool_C) and the drag's release (TH3Tool_B, the commit
// path that must witness). The rule: the ATR is read AT THE LEG'S OWN BAR.
const TH3TOOL_C = path.join(BIOTAK, 'TH3Tool_C.mqh');
const TH3TOOL_B = path.join(BIOTAK, 'TH3Tool_B.mqh');
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

// P-SIZE-1500 (2026-10-04): the strip is a hub (`DrawStrip.mqh`) plus its owner parts,
// exactly like the HTF unit above. `stripFiles()` IS the unit's member set, so a check
// about "the strip" keeps asking the whole unit after a part is renamed or split again -
// and `stripCode()` drops comments, because this project's comments QUOTE the spelling
// they retired (the P-PAL-21 notes name the very owners the retirements below forbid).
function stripFiles() {
  return fs
    .readdirSync(BIOTAK)
    .filter((n) => /^DrawStrip[A-Za-z_]*\.mqh$/.test(n))
    .sort();
}
function stripCode() {
  let out = '';
  for (const f of stripFiles()) out += codeOf(linesOf(path.join(BIOTAK, f)) || []) + '\n';
  return out;
}
// Comments KEPT: a retirement note is a comment, and this asks whether the strip still
// says WHY the board is absent.
function stripText() {
  let out = '';
  for (const f of stripFiles()) out += (linesOf(path.join(BIOTAK, f)) || []).join('\n') + '\n';
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
  // P-BK-105 (2026-10-09): the base note's own unit — the node read, its hover, and the
  // sizing preview's zero block in the plan file.
  const nodes = linesOf(NODES);
  const bkBase = linesOf(BK_BASE);
  const plan = linesOf(PLAN);
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
    ['BaseKnot_Nodes.mqh', nodes], ['BaseKnot_Plan.mqh', plan],
    ['BaseKnot_Base.mqh', bkBase],
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
  //
  // 2026-10-04: the two biggest names on that list drifted AGAIN (Init 1749,
  // Router 1630) and were split along seams they already had - the custom price
  // line (EventHandlers_CustomPrice.mqh) and the line's gesture stream
  // (EventHandlers_Router_Gesture.mqh) - so both left the baseline and the
  // ceiling is the only rule they answer to now. A baseline is a debt, not a
  // licence: raising one is how a ceiling stops existing.
  {
    const SIZE_BASELINE = {
      'EventHandlers_Calc.mqh': 1563,
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

  // -- 14b. P-SIZE-SPLIT (2026-10-04): the two halves the ceiling cut out are members ----
  //
  // `EventHandlers_Init.mqh` (1749 lines) and `EventHandlers_Router.mqh` (1630) both
  // drifted back over the ceiling, and both were cut along a seam they already had: the
  // custom price line (`EventHandlers_CustomPrice.mqh`) and that line's own gesture stream
  // (`EventHandlers_Router_Gesture.mqh`). MQL4 resolves a call top-down, so the hub's ORDER
  // is not cosmetic: the half must precede the file that calls it, or the build stops with
  // `error 168`. Two halves, two members, zero prototypes owed \u2014 this asks all three,
  // because an orphaned half compiles and is dead.
  {
    const broken = [];
    const hub = linesOf(path.join(BIOTAK, 'EventHandlers.mqh'));
    const read = (f) => linesOf(path.join(BIOTAK, f));
    for (const [half, owner, call] of [
      ['EventHandlers_CustomPrice.mqh', 'EventHandlers_Init.mqh', /CreateCustomPriceLine\s*\(/],
      ['EventHandlers_Router_Gesture.mqh', 'EventHandlers_Router.mqh', /RoutCustomPriceGesture\s*\(/],
    ]) {
      const halfLines = read(half);
      const ownerLines = read(owner);
      if (!halfLines) broken.push(`${half} is missing: a half the ceiling cut out left the unit`);
      if (!ownerLines) broken.push(`${owner} is missing: P-SIZE-1500's own split lost a side`);
      if (!hub) {
        broken.push('Biotak/EventHandlers.mqh is missing (the unit has no hub)');
      } else {
        const iHalf = indexOfLine(hub, `#include "${half}"`);
        const iOwner = indexOfLine(hub, `#include "${owner}"`);
        if (iHalf < 0) broken.push(`the hub does not include its own half ${half} \u2014 the unit is incomplete`);
        else if (iOwner < 0) broken.push(`the hub does not include ${owner}`);
        else if (iHalf > iOwner)
          broken.push(`${half} must be included ABOVE ${owner}: MQL4 resolves a call top-down and ${owner} calls into it`);
      }
      if (ownerLines && !call.test(codeOf(ownerLines)))
        broken.push(`${owner} does not call into ${half}: the half was orphaned (a half that compiles and is dead)`);
    }
    if (broken.length) {
      failures.push('P-SIZE-SPLIT: ' + broken.join('; '));
    } else {
      console.log(
        '[PASS] P-SIZE-SPLIT the two halves the ceiling cut out are members of the unit, each included above the file that calls into it (EventHandlers_CustomPrice.mqh, EventHandlers_Router_Gesture.mqh)'
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

  // -- 17. P-DRAW-93/95/97/100/105(retired by P-PAL-21): the board and its five rules --
  //
  // Five entries described the strip's OWN colour board and were green until P-PAL-21
  // (2026-10-02) deleted the board: DrawStrip_Pal.mqh, its catalogue, its page table, its
  // RECENT band, its HEX field and its opacity bar — a colour cell opens the CARDS'
  // palette now (P-PAL-19), the ONE colour editor this product has.
  //
  //   * P-DRAW-93 (the layout ORDER): `DrawStripBoardPlace` scored its four dock
  //     candidates against the strip's own rect BEFORE the pass had derived it, so a fresh
  //     board docked 200px under a 48px strip. The board went; the pass stayed.
  //   * P-DRAW-95 (one FILL-show writer in the recent tap): the recent row is served by the
  //     one pick seat, and the FILL's own show lives in the colour's single owner.
  //   * P-DRAW-97 (the scrub's release on the CLICK channel): the board's scrub went with
  //     the board; the one scrub left is the grip carry, whose ender is
  //     `DrawStripGripRelease` — asked on the same line, for the same P-LM-13 reason.
  //   * P-DRAW-100 (the hex field's empty seed and its release AFTER the parse): the
  //     strip's hex field went with the board, and the product's ONE hex field is the
  //     cards' palette's — which wears the same law (`FlushPalHex` releases the focus
  //     BEFORE it parses, so an unparsable word cannot latch the field).
  //   * P-DRAW-105 (the board's page seats, half-open like the rects they painted): the
  //     seats and their `DSTRIP_HD_PGW` macro went with the header cluster.
  //
  // A retirement is not a deletion. What is asked here is the three halves that can rot:
  // the removal is REAL (no retired owner left to be re-wired into a surface nobody
  // paints, or into a second surface), the editor that REPLACED it is alive, and the ORDER
  // gate this class of defect was measured by still runs in every build.
  {
    const broken = [];
    const stripSrc = stripCode();
    for (const [tag, re] of [
      ['DrawStripBoardPlace', /DrawStripBoardPlace\s*\(/],
      ['DrawStripPickTapRecent', /DrawStripPickTapRecent\s*\(/],
      ['DrawStripPalRelease', /DrawStripPalRelease\s*\(/],
      ['DrawStripPopHexEnd', /DrawStripPopHexEnd\s*\(/],
      ['DrawStripPageAt', /DrawStripPageAt\s*\(/],
      ['DSTRIP_HD_PGW', /DSTRIP_HD_PGW/],
    ])
      if (re.test(stripSrc))
        broken.push(
          `${tag} is back in the strip's code: P-PAL-21 removed the surface it belonged to, so a live owner for it paints nothing (or a second surface)`
        );
    // (a2) and the removal is ON THE RECORD: a note, not silence.
    if (!stripText().includes('P-PAL-21'))
      broken.push(
        'the retirement note (P-PAL-21) is gone from the strip: the next reader sees a strip that never had a board, and the next board gets built again'
      );
    // (b) the ONE hex field left in the product wears the retired field's law.
    const flush = bodyOf(linesOf(PAL_A) || [], 'void FlushPalHex()');
    if (!flush) {
      broken.push('FlushPalHex() is gone from Biotak/BiotakPanels_PalA.mqh: the product\u2019s one hex field has no owner');
    } else {
      const rel = flush.text.search(/g_PalHexFocus\s*=\s*false;/);
      const parse = flush.text.indexOf('ParseHexColor(');
      if (rel < 0) broken.push('the hex commit must release `g_PalHexFocus`');
      else if (parse >= 0 && rel > parse)
        broken.push(
          'the hex commit must release `g_PalHexFocus` BEFORE the parse, or an unparsable word keeps the field (the law P-DRAW-100 was written for)'
        );
      if (!/PaletteApplyColor\s*\(/.test(flush.text))
        broken.push('the hex commit must apply through the palette\u2019s colour owner (`PaletteApplyColor`)');
    }
    // (c) the colour still has ONE owner in the strip, and the one FILL-show writer is
    // inside it: both P-DRAW-95 and P-DRAW-100 named that owner.
    const tap = codeOf(linesOf(STRIP_TAP) || []);
    if (!/bool DrawStripColorCommit\s*\(/.test(tap))
      broken.push('DrawStripColorCommit() is gone from Biotak/DrawStrip_Tap.mqh: the colour has no single owner');
    else if ((tap.match(/DrawStripFillShowGroup\s*\(\);/g) || []).length !== 1)
      broken.push(
        'the interior must be SHOWN through ONE `DrawStripFillShowGroup();` call in the strip: the colour\u2019s owner is where that belongs'
      );
    if (!/return DrawStripColorCommit\(slot, DrawStripPickColor\(slot, row\)\);/.test(tap))
      broken.push('the palette cell must apply through the colour\u2019s owner (DrawStripColorCommit), not its own copy of the writes');
    // (d) the seats those rules named are alive: a rule may be retired by a feature, a
    // seat may not vanish in silence.
    if (!/bool DrawStripPickTap\s*\(/.test(tap))
      broken.push('DrawStripPickTap() is gone from Biotak/DrawStrip_Tap.mqh: the pick seat has no owner');
    const gearBsrc = codeOf(linesOf(GEAR_B) || []);
    if (!/bool DrawStripEdit\s*\(/.test(gearBsrc))
      broken.push('DrawStripEdit() is gone from Biotak/DrawStrip_GearB.mqh');
    if (!/void DrawStripLayout\s*\(/.test(codeOf(linesOf(GEAR_A) || [])))
      broken.push('DrawStripLayout() is gone from Biotak/DrawStrip_GearA.mqh: the pass the retired board was scored against has no owner');
    // (e) the ORDER gate this class was measured by still runs in every build.
    const ps1 = linesOf(BUILD_PS1);
    if (!ps1) broken.push('compile-th3.ps1 is missing (the build is the only entry point)');
    else if (indexOfLine(ps1, 'stale_state_check.js') < 0)
      broken.push(
        'the ORDER gate is not run by the build \u2014 re-add `node tools/stale_state_check.js` to compile-th3.ps1 (or delete this entry and say so in the report)'
      );
    if (broken.length) {
      failures.push('P-DRAW-93/95/97/100/105(retired by P-PAL-21): ' + broken.join('; '));
    } else {
      console.log(
        '[PASS] P-DRAW-93/95/97/100/105(retired by P-PAL-21) the board and its five rules are gone and stay gone: no placer, no scrub release, no board hex, no page seat \u2014 and the cards\u2019 palette owns the colour'
      );
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

  // P-DRAW-95 (retired by P-PAL-21) \u2014 folded into the P-DRAW-93/95/97/100/105 block
  // above: the board it was about is gone, and the law it fixed (ONE FILL-show writer) is
  // asserted there against the owner that has it now (`DrawStripColorCommit`).
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

  // P-DRAW-97 (retired by P-PAL-21) \u2014 folded into the P-DRAW-93/95/97/100/105 block
  // above: the board's scrub went with the board, and the one scrub left (the grip carry)
  // still ends on the CLICK channel \u2014 that line was never edited.
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

  // P-DRAW-100 (retired by P-PAL-21) \u2014 folded into the P-DRAW-93/95/97/100/105 block
  // above: the strip's hex field went with the board, and the product's ONE hex field
  // (the cards' palette, `FlushPalHex`) wears the same law there.
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

  // P-DRAW-105 (retired by P-PAL-21) \u2014 folded into the P-DRAW-93/95/97/100/105 block
  // above: the board's page seats and their `DSTRIP_HD_PGW` macro went with the header
  // cluster, and that block asserts neither comes back.
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
      if (!/SS\(\?:State\|Kind\|FiboLook\|Pen\)/.test(gate119) || !/HARNESS/.test(gate119))
        broken.push('the gate must parse the state list OUT of tests/Biotak_StripShot_Test.mq4 — every ask, the look and pen states included (a hand-kept or partial list goes stale in silence)');
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
    // (f) THE LAUNCH'S OWN WIRING (addendum 2026-10-18 — the -Shot run that would have
    //     shown the 3D look had NEVER run). MEASURED: MT4 reads the ini as a BARE
    //     argument (its own help example is `terminal.exe config\start.ini`). The
    //     colon-suffixed switch of MT5 is silently IGNORED: the profile opened, no
    //     extra chart, no script, and the run died in 120 s of silence. Gate it with
    //     the fix, and mutate it - a rule needs its inverse to fail somewhere.
    if (/\/config:/.test(ps))
      broken.push('the shot launch passes the ini with a colon switch \u2014 MT4 reads a BARE path argument, and the prefixed form is MT5 spelling that MT4 ignores in silence (profile opens, no chart, no script, 120 s wait)');
    if (!/\$shotArgs = \("\$\(\$shotStart\.Args\) `"\$configPath`""\)\.Trim\(\)/.test(ps))
      broken.push('the shot launch no longer hands the ini to the terminal as a bare argument \u2014 the working form is `terminal.exe "<path-to-ini>"`');
    if (!/Write-Host "        terminal\.exe `"\$configPath`""/.test(ps))
      broken.push('the printed NEXT line no longer shows the bare-argument launch \u2014 a user who runs the printed command by hand would get the silent profile launch');

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
    const tags = [...harn.matchAll(/SS(?:State|Kind|FiboLook)\s*\(\s*"([A-Za-z0-9_]+)"/g)].map((m) => m[1]);
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
      console.log('[PASS] P-DRAW-125 the diagnostic repaints only an open panel, and every writer reclaims a name of another type (Biotak/DrawStrip_GearB.mqh + Biotak/DrawStrip_Base.mqh)');
    }
  }

  // -- 42. P-MENU-01: no ring behind an open Tools submenu ----------------------
  //
  // Opening the Tools submenu deletes every main-ring item (CreateToolsMenu) and
  // the hit test refuses the ring while it is open (CircItemAt) — but two
  // rebuild paths recreated the ring on top of the submenu: CreateMenu and the
  // ToggleMenuVisibility show branch painted ring AND submenu together (the
  // 2026-10-07 screenshot). Both must gate their ring loop on !g_ToolsOpen;
  // the one legal resurrection stays DeleteToolsMenu's restore branch.
  {
    const broken = [];
    const menuCLines = linesOf(MENU_C) || [];
    const menuALines = linesOf(MENU_A) || [];
    const menuDLines = linesOf(MENU_D) || [];
    const create = bodyOf(menuCLines, 'void CreateMenu(');
    if (!create) broken.push('CreateMenu is gone from ' + path.basename(MENU_C));
    else if (!create.text.includes('CircCreateItem(i)') || !/!\s*g_ToolsOpen/.test(create.text))
      broken.push('CreateMenu must build the ring ONLY when the Tools submenu is shut (P-MENU-01): an open submenu plus a rebuilt ring painted both');
    const toggle = bodyOf(menuDLines, 'void ToggleMenuVisibility(');
    if (!toggle) broken.push('ToggleMenuVisibility is gone from ' + path.basename(MENU_D));
    else if (!toggle.text.includes('CircCreateItem(i)') || !/!\s*g_ToolsOpen/.test(toggle.text))
      broken.push('ToggleMenuVisibility show must build the ring ONLY when the Tools submenu is shut (P-MENU-01)');
    const hit = bodyOf(menuALines, 'int CircItemAt(');
    if (!hit) broken.push('CircItemAt is gone from ' + path.basename(MENU_A));
    else if (!hit.text.includes('g_ToolsOpen') || !hit.text.includes('return -1'))
      broken.push('CircItemAt must keep refusing the ring while the Tools submenu is open (P-MENU-01): paint and hit-test must agree');
    if (broken.length) {
      failures.push('P-MENU-01: ' + broken.join('; ') + ' (Biotak/BiotakMenu_C.mqh + Biotak/BiotakMenu_D.mqh + Biotak/BiotakMenu_A.mqh)');
    } else {
      console.log('[PASS] P-MENU-01 no ring behind an open Tools submenu (Biotak/BiotakMenu_C.mqh + Biotak/BiotakMenu_D.mqh + Biotak/BiotakMenu_A.mqh)');
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

  // ── P-UI-130 (2026-10-02, click-toggle 2026-10-07) — A PRESS NAMES, A RELEASE
  // TOGGLES, A DRAG NEVER TOGGLES ──
  // Measured on the live chart (EURUSD,M1 00:12:57-00:13:01): ONE latch on a box the
  // hand then DRAGGED armed the press cycle for its whole 10 s life — the OPENER
  // window's own budget — and refused FIVE real presses in a row, only one of them
  // 4.4 s later (00:13:01.481) after the box had moved out from under the finger.
  // That is «هولد بعضی وقتها باز نمیشه», and it is one constant: the cycle lives
  // on DSTRIP_PRESS_CYCLE_MS (2 s), never on the opener window's cap (P-UI-130).
  // The other half is the user's own sentence — «موقعی که باکس جابجا میکنم یا
  // ری‌ساز میکنم نوار استریپ بالا میاد و مزاحم میشه»: CHARTEVENT_OBJECT_DRAG
  // is the terminal saying it is moving that drawing (P-BK-19a's owner witness,
  // TH3Tool_C's band lock), so it stamps a heartbeat that kills the press naming
  // and vetoes the toggle for the 400 ms its own events renew. The 500 ms hold
  // timer is gone (single-click toggles now): what must never come back with it
  // is a release opening anything — a release only ever toggles, and only with
  // no travel and no live drag heartbeat behind it.
  // Gate: the constant, the veto in both fire paths, the wiring, and the
  // absence of the timer.
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
    const wit = bodyOf(stripRouter || [], 'void DrawStripDragWitness(');
    if (!wit) broken.push('DrawStripDragWitness() is gone from Biotak/DrawStrip_Router.mqh (P-UI-130)');
    else if (!/DrawStripPressCycleClear\(\)/.test(wit.text))
      broken.push('the drag witness must CLEAR the cycle — a press that moved a drawing is never a tap (P-UI-130)');
    if (!/bool DrawStripDragLive\(\)/.test(rx))
      broken.push('DrawStripDragLive() is gone from Biotak/DrawStrip_Router.mqh (P-UI-130)');
    for (const sig of ['void DrawStripHoldLatch(', 'bool DrawStripClickToggle(']) {
      const body = bodyOf(stripRouter || [], sig);
      if (!body || !/DrawStripDragLive\(\)/.test(body.text))
        broken.push(`${sig.slice(5, -1)} lost its native-drag gate — the strip can come up mid-drag again (P-UI-130)`);
    }
    for (const gone of ['DSTRIP_HOLD_MS', 'void DrawStripHoldStep(', 'void DrawStripHoldPollAt(', 'void DrawStripHoldFire(']) {
      if (rx.includes(gone))
        broken.push(`${gone} is back in Biotak/DrawStrip_Router.mqh — the hold timer is gone, a release only toggles (P-UI-130)`);
    }
    const onEvent = bodyOf(stripRouter || [], 'bool DrawStripOnEvent(');
    if (!onEvent || !/DrawStripDragWitness\(sparam\)/.test(onEvent.text))
      broken.push('DrawStripOnEvent() lost the OBJECT_DRAG witness call — nothing stamps the drag heartbeat (P-UI-130)');
    else if (onEvent.text.indexOf('DrawStripDragWitness(sparam)') > onEvent.text.indexOf('if(id == CHARTEVENT_MOUSE_MOVE)'))
      broken.push('the drag witness must stand ABOVE the mouse-move block, where every event passes (P-DRAW-64\u2019s own placement rule) (P-UI-130)');
    if (broken.length) {
      failures.push('P-UI-130: ' + broken.join('; ') + ' (Biotak/DrawStrip_Base.mqh + DrawStrip_Router.mqh)');
    } else {
      console.log('[PASS] P-UI-130 click toggles and a native drag vetoes it (press cycle 2 s, drag heartbeat gates latch + toggle, no hold timer)');
    }
    // P-UI-155 hollow-interior clicks open through either channel, and the
    // twin channel can no longer close what the first opened.
    if (!/string nm = \(relHit/.test(codeOf(stripRouter || [])))
      failures.push('P-UI-155: the chart-click fallback is gone — a release inside a hollow drawing names nothing, so rectangles never open while trendlines do (Biotak/DrawStrip_Router.mqh)');
    else if (!/DrawStripTwinArm\(\); return true/.test(codeOf(stripRouter || [])))
      failures.push('P-UI-155: the fallback open arms no twin — whichever channel arrives second closes what the first opened (Biotak/DrawStrip_Router.mqh)');
    else
      console.log('[PASS] P-UI-155 hollow-interior clicks open through either channel, and the twin channel cannot close what the first opened');
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

  // -- 14c. P-SIZE-SPLIT-LBL (2026-10-13): the LABEL hub's own half ------------------
  //
  // P-UI-148 (the TRex brand band's vertical air) needed a few lines in Labels_A.mqh,
  // and that file sat exactly at its grandfathered baseline (1598) — contract §7 says a
  // file over the ceiling never grows, so the split is the answer, not the prose cut:
  // the LIVE PRICE + CLOSE-IN COUNTDOWN owner moved out to Biotak/Labels_Countdown.mqh
  // (the same cut Labels_LegAtr.mqh took before it). Asserted the way the EventHandlers
  // pair is, because a half can be present, compile, and be DEAD: the hub includes it,
  // the hub still includes its owner, the owner still CALLS into it, and the owner is
  // back UNDER the ceiling — which is the only reason the split exists. Its baseline
  // entry is gone with it (a stale grandfather is a note that no longer matches).
  {
    const broken = [];
    const hub = linesOf(path.join(BIOTAK, 'LabelFunctions.mqh'));
    const half = linesOf(path.join(BIOTAK, 'Labels_Countdown.mqh'));
    const owner = linesOf(path.join(BIOTAK, 'Labels_A.mqh'));
    if (!half) broken.push('Biotak/Labels_Countdown.mqh is missing \u2014 a half the ceiling cut out left the unit');
    if (!owner) broken.push('Biotak/Labels_A.mqh is missing \u2014 the split lost a side');
    if (!hub) broken.push('Biotak/LabelFunctions.mqh is missing (the label unit has no hub)');
    else {
      const iHalf = indexOfLine(hub, '#include "Labels_Countdown.mqh"');
      const iOwner = indexOfLine(hub, '#include "Labels_A.mqh"');
      if (iHalf < 0) broken.push('the label hub does not include its own half Labels_Countdown.mqh \u2014 the unit is incomplete');
      else if (iOwner < 0) broken.push('the label hub does not include Labels_A.mqh');
      else if (iHalf < iOwner)
        broken.push('Labels_Countdown.mqh must be included AFTER Labels_A.mqh: its helpers (InitATRChartLabel / LblMark / SetLabelFont) are defined there');
    }
    if (owner && !/RefreshLiveCountdown\s*\(/.test(codeOf(owner)))
      broken.push('Labels_A.mqh no longer calls into Labels_Countdown.mqh \u2014 the half was orphaned (a half that compiles and is dead)');
    if (owner && owner.length > 1500)
      broken.push(`Labels_A.mqh is ${owner.length} lines again \u2014 the half did not give it room (contract §7)`);
    if (broken.length) {
      failures.push('P-SIZE-SPLIT-LBL: ' + broken.join('; ') + ' (Biotak/Labels_A.mqh + Labels_Countdown.mqh + LabelFunctions.mqh)');
    } else {
      console.log('[PASS] P-SIZE-SPLIT-LBL the label hub carries its half: Labels_Countdown.mqh is a member, included after Labels_A, called by it, and Labels_A is back under the ceiling');
    }
  }

  // ── P-DRAW-74b (2026-10-03) — A THICK DASH IS DRAWN, NOT WISHED ──
  // MT4 draws STYLE_* only at width 1, so a thick + non-solid fibo level is a
  // state no terminal can draw («استایل ها فقط روی 1px اعمال میشه»). The pen
  // the terminal cannot draw is built beside it, PER LEVEL: the level keeps
  // its STYLE at visible width 1, and width-1 children carry the SAME style in
  // the SAME ink, centred on the level — full ink, never faint, never fixed.
  // The chosen width lives NOWHERE but the stack (1 + children); every reader
  // of LEVELWIDTH asks FibPenLogicalWidth, never the raw line. Children exist
  // ONLY for a thick + non-solid level: solid and 1px cost zero objects.
  {
    const broken = [];
    const fib = codeOf(linesOf(path.join(BIOTAK, 'FibPen.mqh')) || []);
    const tba = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
    const tbr = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    if (!/StringFind\(name, FIBPEN_SUFFIX/.test(fib))
      broken.push('the leftover test no longer SEARCHES for the suffix — retired strays become served drawings again (P-DRAW-74b)');
    if (/StringSubstr\(name, n - s, s\) != FIBPEN_SUFFIX/.test(fib))
      broken.push('the end-match is back — it never matched a name ending in `<q>`, so the strays are unowned again (P-DRAW-74b)');
    if (!/OBJPROP_LEVELWIDTH, l, vis/.test(fib))
      broken.push('the convergence never writes the visible width — a thick non-solid level paints the terminal\'s solid again (P-DRAW-74b)');
    if (!/FibPenTagDrop/.test(fib))
      broken.push('the transition cleanup is gone — a v2 [FWn] would ride the description for good (P-DRAW-74b)');
    if (/FibPenTagSet/.test(fib))
      broken.push('text memory is back — widths live in the stack (1 + children), never in the description (P-DRAW-74b)');
    if (!/ObjectCreate\(0, nm2, OBJ_TREND/.test(fib))
      broken.push('no child is ever built — without the beside-pen a thick dash is the terminal\'s solid (P-DRAW-74b)');
    if (!/OBJPROP_STYLE, styA\[l2\]/.test(fib))
      broken.push('the stack lost the level\'s style — a fixed pen turns every dash into dots (P-DRAW-74b)');
    if (/FIBPEN_FADE/.test(fib))
      broken.push('faint ink is back — the stack must wear the level\'s FULL ink, or thickness reads as 1px (P-DRAW-74b)');
    if (!/FibPenIsChild\(name\)\) return DK_NONE/.test(tba))
      broken.push('a stacked line is served again — DrawKindOf must answer DK_NONE for it, or hits and presets learn it (P-DRAW-74b)');
    if (!/FibPenLogicalWidth\(name, 0\)/.test(tba))
      broken.push('the width cell reads the thinned 1 — the logical width is 1 + children (P-DRAW-74b)');
    if (!/refLog = FibPenLogicalWidth\(fibo, 0\)/.test(fib))
      broken.push('no reference width — uniformity needs level 0\'s remembered width (P-DRAW-74b)');
    if (!/OBJPROP_LEVELSTYLE, l, refSt/.test(fib))
      broken.push('levels diverge again — every level wears the reference style (P-DRAW-74b)');
    if (!/logW\[l\] = refLog/.test(fib))
      broken.push('the stack feeds per-level widths — every child stack is built from the reference (P-DRAW-74b)');
    // P-LOOK-RAY2 (2026-10-04) — a correction, kept on the record. Its PREMISE was wrong
    // and is retired: it read the master's own `OBJPROP_RAY_LEFT/RIGHT` as the fibo's LEVEL
    // ray ("MT4's fibo owns its level-ray flag, the strip's RAY cell writes it") and
    // mirrored that pair onto every row of the pen. The scene it was measured from — the
    // pen running x=59..721 while the master ran x=681..1079 — was real, but it was never
    // a disagreement between two objects: the read can only ever answer false, so it
    // trimmed the pen to the anchors every single time. Two of its laws SURVIVE and are
    // asserted below: one owner for the pair (no row hardcodes its own), and the heal in
    // BOTH directions. Only the SOURCE of the pair changed — see P-LOOK-RAY3.
    // P-LOOK-RAY3 (2026-10-04) — THE PEN'S SPAN IS MT4'S SPAN, AND MT4 WILL NOT TELL US.
    // P-LOOK-RAY2 mirrored the master's OWN ray pair onto every row, on the belief that
    // `OBJPROP_RAY_LEFT/RIGHT` is the fibo's level ray. It is not: MT4 keeps that ray in a
    // field of its own (`levels_ray` in the chart file — a fibo writes no `ray=` entry at
    // all, while the pen's OBJ_TREND rows carry `ray=1`), MQL4 exposes nothing that reads
    // or writes it, and `OBJPROP_RAY_RIGHT=false` does not stop a fibo's levels reaching
    // the right chart edge (mql5.com/forum/164640, MT4 build 1030+). MEASURED on the hand's
    // own chart, 2026-10-04 12:08 (EURUSD M1): the master's level lines ran x=250..1863
    // while the pen's rows stopped dead at x=595, the second anchor — «چرا امتداد خط ها استایل
    // اعمال نشده باید همه جا باشه دیگه». So the pen STATES MT4's shape (right on, left off)
    // instead of reading a flag that can only ever answer false.
    if (/void FibPenRayPair\([^)]*\)\s*\{[\s\S]{0,400}?ObjectGetInteger\(0, fibo, OBJPROP_RAY_/.test(fib))
      broken.push('the pen reads the master\'s own ray flags again — on OBJ_FIBO that pair is not the level line\'s span (MT4 keeps it in `levels_ray`, which MQL4 neither reads nor writes), so the pen is trimmed to the anchors while the line runs on (P-LOOK-RAY3)');
    if (!/void FibPenRayPair\([^)]*\)\s*\{[\s\S]{0,400}?rl = true;[\s\S]{0,200}?rr = true;/.test(fib))
      broken.push('the pen does not state MT4\'s own level span — a fibo\'s levels run the full chart width both ways whatever any flag says, so the pen must too (P-LOOK-RAY3)');
    // P-LOOK-RAY5 (2026-10-04) — BOTH EXTENSIONS WEAR IT. RAY3 stated MT4's shape
    // as "first anchor → right edge" and RAY4 turned the one ray with the anchors;
    // the hand's own two frames then showed the master spanning the FULL width both
    // ways with the middle thick and BOTH extensions thin — «این امتداد به عقب و جلو
    // چرا استایل و ضخامت نمیگیره». The one-ray law always left one side bare, so the
    // pen states both rays on, in both anchor orders: the style and the thickness ride
    // the line عقب و جلو.
    if (/^[ \t]*rl = false;[^\n]*\n[ \t]*rr = true;/m.test(fib))
      broken.push('the forward-only pair is back — the backward extension wears no style and no thickness (P-LOOK-RAY4)');
    if (/\{\s*rl = true;\s*rr = false;\s*\}/.test(fib))
      broken.push('the single-ray branch is back — one anchor order loses an extension (P-LOOK-RAY4)');
    // P-LOOK-RAY5b (2026-10-04) — THE CHILDREN WEAR ORDERED TIME. Both rays on was
    // not enough: measured with rays=3 on reversed anchors (ta > tb), the pen covered
    // one side only. Every rayed row is seated early→late on BOTH movers (the sync and
    // the drag chase) — one ordered seat is a half fix the next drag undoes.
    if (fib.split('datetime ts0 = (ta < tb ? ta : tb);').length - 1 < 2)
      broken.push('the rows stopped wearing ordered time on both movers — with reversed anchors MT4 extends only one side, so an extension wears no style (P-LOOK-RAY5)');
    if (!/FibPenRayPair\(fibo, penRL, penRR\);/.test(fib))
      broken.push('the span pair is read nowhere — the children\'s span is a guess again (P-LOOK-RAY2)');
    if (!/ObjectSetInteger\(0, nm2, OBJPROP_RAY_LEFT, penRL\)/.test(fib) ||
        !/ObjectSetInteger\(0, nm2, OBJPROP_RAY_RIGHT, penRR\)/.test(fib))
      broken.push('a child is born with a hardcoded ray — the pen\'s span must come from the one owner (P-LOOK-RAY2)');
    if (!/\(\(int\)ObjectGetInteger\(0, nm2, OBJPROP_RAY_RIGHT\) != 0\) != penRR/.test(fib))
      broken.push('the span is only ever RAISED — a row whose span differs never takes it back (P-LOOK-RAY2)');
    if (/ObjectSetInteger\(0, nm2, OBJPROP_RAY_(LEFT|RIGHT), true\)/.test(fib))
      broken.push('a hardcoded TRUE ray is back on the stack — the pen covers a span the line does not have (P-LOOK-RAY2)');
    // P-LOOK-ANCHOR (2026-10-18) — MT4 PUTS 0 % AT THE SECOND ANCHOR. MEASURED on the
    // shot chart (StripShot_fibo_3d3.png, AMarkets A1660; anchors p0=1.12135, p1=1.12298):
    // the band wearing the «0.0» label sits at PRICE,1 (y=445) and «423.6» at
    // PRICE,1 + (PRICE,0 - PRICE,1) * 4.236 = 1.11605 (y=633) — the label text and the
    // pixels agree within 1 px on all nine bands, so the terminal's law is
    // `lv = PRICE,1 + (PRICE,0 - PRICE,1) * v`. The old `p1 + (p2 - p1) * v` wore the
    // mirror twin R(1 - v): every child sat under the wrong level (the «3D واقعی نیست»
    // report — its orphan dashes measured at y=305/376/420) and the press naming
    // (DrawHitLevels) and drag arm (DrawFiboFullHit) measured lines MT4 never draws.
    // Six sites stated the law by hand. P-UNIFY-3 (2026-10-19) moved five of them behind
    // ONE owner — Toolbar_A's `DrawLevelPriceAt` (the terminal's horizontal law is its
    // fallback; a Channel/Fan/Expansion carry laws of their own there) — and the chase
    // keeps its one inline statement (the drag stream is the hot path). The gate asks the
    // owner AND every seat that spends it.
    {
      const tbaA = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
      const tbbA = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
      //--- P-SIZE-1500's split (2026-10-19): the two hit tests left Toolbar_A for
      //--- Toolbar_Hit.mqh, so the law is asked of the file that now owns the pick.
      const tbhA = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_Hit.mqh')) || []);
      const broken = [];
      if (!/return pb \+ \(pa - pb\) \* v;/.test(tbaA))
        broken.push('the one geometry owner lost the terminal\'s horizontal law — 0 % at the second anchor (P-LOOK-ANCHOR)');
      if (!/lvA = DrawLevelPriceAt\(k, v, ta, p1, tb, p2, t3, p3, ts0\)/.test(fib) ||
          !/lvB = DrawLevelPriceAt\(k, v, ta, p1, tb, p2, t3, p3, ts1\)/.test(fib))
        broken.push('the sync rows wear the mirror twin — every child sits at R(1 - v) (P-LOOK-ANCHOR)');
      if (!/lva = pb \+ \(pa - pb\) \* v;/.test(fib))
        broken.push('the chase wears the mirror twin — a dragged family lands under another level (P-LOOK-ANCHOR)');
      if (!/lpA = DrawLevelPriceAt\(k, vv4,/.test(fib) || !/lpB = DrawLevelPriceAt\(k, vv4,/.test(fib))
        broken.push('the caps wear the mirror twin (P-LOOK-ANCHOR)');
      if (!/hpA = lva\[l5\] \+ 2\.0 \* px;/.test(fib) || !/hpB = lvb\[l5\] \+ 2\.0 \* px;/.test(fib))
        broken.push('the wash halo wears the mirror twin (P-LOOK-ANCHOR)');
      if (!/la = DrawLevelPriceAt\(k, v, t1, p1, t2, p2, t3, p3, t1\)/.test(tbhA))
        broken.push('the press naming measures lines MT4 never draws (P-LOOK-ANCHOR)');
      if (!/la = DrawLevelPriceAt\(k, v, t1, p1, t2, p2, t3, p3, t1\)/.test(tbbA))
        broken.push('the drag arm\'s full hit measures lines MT4 never draws (P-LOOK-ANCHOR)');
      if (broken.length) {
        failures.push('P-LOOK-ANCHOR: ' + broken.join('; ') + ' (Biotak/FibPen.mqh + Toolbar_Hit.mqh + Toolbar_B.mqh)');
      } else {
        console.log('[PASS] P-LOOK-ANCHOR every level mapping states the terminal\'s law — 0 % at the second anchor, label-verified to 1 px');
      }
    }
    // ── P-DRAW-BODY (2026-10-04) — THE BODY IS A LINE OF ITS OWN ──
  // «این خط هم جدا باشه تنظیمات و رنگ و استایل و غیره در تنظیمات و تداخل نداشته باشه باهم».
  // A level drawing is TWO pictures — the line MT4 draws between the anchors and the LEVEL
  // family the pen styles — and the strip's colour/width/style cells wrote BOTH halves, so
  // restyling a level restyled the body and a body choice restyled every level. The three
  // cells are now the LEVELS' alone for a level kind; three appended seats are the body's.
  {
    const tbb2 = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const tba2 = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
    const broken = [];
    if (!/#define DRAW_SLOT_BODYCOLOR 13/.test(tba2) || !/#define DRAW_SLOT_N\s+16/.test(tba2))
      broken.push('the body\'s three seats are gone (or moved an index) — the body shares the level cells again (P-DRAW-BODY)');
    if (!/#define DRAW_CAP_BODY\s+\(DRAW_CAP_BODYCOLOR \| DRAW_CAP_BODYWIDTH \| DRAW_CAP_BODYSTYLE\)/.test(tba2))
      broken.push('the body has no capability mask — the settings panel cannot offer it (P-DRAW-BODY)');
    if (!/case DK_FIBO:\s*\r?\n\s*case DK_FIBOFAN:\s*return DRAW_CAP_COMMON \| DRAW_CAP_FILLCLR \| DRAW_CAP_BODY;/.test(tba2))
      broken.push('a level kind no longer carries the body\'s seats — six kinds draw a body and a level family (P-DRAW-BODY)');
    for (const [prop, cell] of [['OBJPROP_COLOR', 'color'], ['OBJPROP_WIDTH', 'width'], ['OBJPROP_STYLE', 'style']]) {
      if (!new RegExp(`if\\(!DrawKindHasLevels\\(k\\)\\) ObjectSetInteger\\(0, name, ${prop},`).test(tbb2) &&
          !new RegExp(`else if\\(!DrawKindHasLevels\\(k\\)\\) ObjectSetInteger\\(0, name, ${prop},`).test(tbb2))
        broken.push(`the ${cell} cell writes the OBJECT again for a level kind — it and the body seat are one seat (P-DRAW-BODY)`);
    }
    const bodyBlk = (() => { const m = tbb2.match(/case DRAW_SLOT_BODYCOLOR:[\s\S]*?\r?\n\s*case DRAW_SLOT_FILL:/); return m ? m[0] : ''; })();
    if (!bodyBlk)
      broken.push('the body\'s write half is unreadable — the seats exist but nothing writes them (P-DRAW-BODY)');
    else if (/DrawLevelsSet/.test(bodyBlk))
      broken.push('a body seat writes the LEVELS — the two pictures are wired together again (P-DRAW-BODY)');
    const bodyRead = (() => { const m = tba2.match(/case DRAW_SLOT_BODYCOLOR: return \(double\)\(color\)\(int\)ObjectGetInteger[\s\S]*?return \(double\)bs;/); return m ? m[0] : ''; })();
    if (!bodyRead)
      broken.push('the body\'s read half is gone — the cell would show the level\'s value (P-DRAW-BODY)');
    const coerce = (() => { const m = tbb2.match(/bool DrawStylePairCoerce\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (coerce && /DrawLevelsSet/.test(coerce))
      broken.push('`DrawStylePairCoerce` reaches for the levels again — it is the BODY\'s law now (P-DRAW-BODY)');
    if (broken.length) {
      failures.push('P-DRAW-BODY: ' + broken.join('; ') + ' (Biotak/Toolbar_A.mqh + Toolbar_B.mqh)');
    } else {
      console.log('[PASS] P-DRAW-BODY the body and the level family are two pictures with two sets of settings: the cells own the levels, three appended seats own the body, and neither writes the other');
    }
  }

    if (!/FIBPENMOV fibo=/.test(fib))
      broken.push('drag moves leave no number — the gesture question needs its sampled witness (P-DRAW-74b)');
    if (!/DRAGSTAT obj=/.test(tbr))
      broken.push('the drag rate is unmeasured — events per second tell queue from paint (P-DRAW-74b)');
    if (!/FibPenStraysDrop\(sparam\)/.test(tbr))
      broken.push('a native delete strands the fibo family — every dependent dies with its object (P-DRAW-74b)');
    if (!/CASCADE obj=/.test(tbr))
      broken.push('a cascade leaves no number — the delete path witnesses what it dropped (P-DRAW-74b)');
    if (!/if\(!s_dsOpen && id != CHARTEVENT_OBJECT_DELETE\) return false;/.test(tbr))
      broken.push('a shut strip eats native deletes — the OBJECT_DELETE branch below the shut-strip gate never runs, so every fill falls to the 2 s orphan sweep (P-DEL-NOWb)');
    if (!/DELFLUSH obj=/.test(tbr))
      broken.push('a familyless hand delete leaves no number and no flush — pixels wait a tick under load (P-DEL-NOWb)');
    if (!/FibPenDragArm\(sparam\)/.test(tbr) || !/void FibPenDragFollow/.test(fib))
      broken.push('the chase is unwired — a fibo drag must arm it, the hand stream must run it (P-DRAW-74b)');
    if (!/FibPenDragFollow\(\(int\)lparam, \(int\)dparam\)/.test(tbr))
      broken.push('moves never chase — the follow belongs on the mouse stream, not the drag event (P-DRAW-74b)');
    if (!/FibPenSync\(sparam, false\);[\s\S]{0,400}?ChartRedraw\(\);/.test(tbr))
      broken.push('the drag branch never flushes — the terminal blits the dragged master live and followers trail a frame (P-DRAW-74b)');
    // P-DRAGF3 (2026-10-17): the release flush is asked INSIDE the release block, not
    // by a sliding window. The button-up door's `else if(fbPrev) ChartRedraw();` sits
    // just past the block's own `}`, so the old window matched IT and kept mutation
    // P-DRAW-74b-g alive with the release's own flush removed (measured: SURVIVED).
    // `tbr` is codeOf-stripped, so the check holds the block's CODE and cannot look
    // for its tag comment. One flush, one owner: the re-stamp flush is this block's.
    const rtrL = linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || [];
    const rpIf = indexOfLine(rtrL, 'if(relPressObj != "")');
    const rpBlk = rpIf >= 0 ? blockAfter(rtrL, rpIf) : null;
    const rpBody = rpBlk ? codeOf(rtrL.slice(rpBlk.from, rpBlk.to + 1)) : '';
    if (!/ChartRedraw\(\);/.test(rpBody))
      broken.push('the release never flushes — a coalesced last drag frame settles in data but not on screen (P-DRAW-74b)');
    if (!/if\(id == CHARTEVENT_CHART_CHANGE\) FibPenSync\(s_dsObj, false\);/.test(tbr))
      broken.push('a zoom never re-syncs the served fibo — pixel offsets go stale until the next touch (P-DRAW-74b)');
    const setC = (() => { const m = tba.match(/void DrawLevelsSetColor\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!/FibPenSync\(name, false\)/.test(setC))
      broken.push('a recolour leaves the stack behind — the colour write must re-sync the children it cannot see (P-DRAW-74b)');
    const pvC = (() => { const m = tba.match(/bool DrawSlotPreviewColor\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    const pvF = (() => { const m = tba.match(/bool DrawSlotPreviewFillColor\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    const rsC = (() => { const m = tba.match(/bool DrawSlotRenderRestore\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!/FibPenSync\(name, false\)/.test(pvC) || !/FibPenSync\(name, false\)/.test(pvF))
      broken.push('a preview leaves the stack behind — hovered ink must reach the children it cannot see (P-DRAW-74b)');
    if (!/if\(changed\) FibPenSync\(name, false\)/.test(rsC))
      broken.push('a restore leaves the stack behind — the pixels tags say must re-ink the children (P-DRAW-74b)');
    const tbb = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const pk = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || []);
    const tpt = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    if (!/FIBPEN_LK/.test(fib))
      broken.push('the look has no tag — personalization must ride the object, never a side store (P-DRAW-74b)');
    if (!/FibPenLookSet\(name, lk\)/.test(tbb))
      broken.push('a look pick never sticks — the STYLE slot must translate 5/6/7 into native plus tag (P-DRAW-74b)');
    // 2026-10-04 — «استایل ها روی ضخامت های بزرگ دیگه اعمال نمیشه». The trick (a thick
    // styled level drawn at width 1 with a width-1 child stack carrying the thickness)
    // was never the problem; TWO writers erased its memory before the pen could read it.
    // (A) the STYLE slot folded the LEVEL widths to 1 BEFORE the style was written — and
    // those LEVEL widths ARE the logical width while no stack stands (`FibPenLogicalWidth`
    // reads them), so the pen read 1, built nothing and the level came out a plain 1 px
    // dash. (B) `DrawStylePairCoerce` read the fibo's OWN pair (a memory) and forced a
    // styled thick fibo back to STYLE_SOLID on every strip open (`DrawStrip_Paint`), which
    // killed the stack. One seat each, and each must stay closed: a pen kind's levels are
    // the pen's business, and its own pair is only a memory.
    if (!/bool penKind = FibPenServesName\(name\) \|\| PenStackServes\(name\);/.test(tbb))
      broken.push('the STYLE slot no longer knows a pen kind — its level widths get folded before the pen can read them (P-DRAW-74b)');
    if (!/if\(!penKind\)[\s\S]{0,30}?DrawLevelsSetWidth\(name, DRAW_WIDTH_MIN\);/.test(tbb))
      broken.push('the STYLE slot folds the level widths on a pen kind — the logical width dies one write early, so a thick styled fibo comes out a plain 1 px dash (P-DRAW-74b)');
    if (!/&& !penKind\) s_dkWidth\[k\] = DRAW_WIDTH_MIN;/.test(tbb))
      broken.push('a dash pick folds a pen kind’s remembered width to 1 — the next fibo is born thin, losing the thickness the hand chose (P-DRAW-74b)');
    const coerceFn = (() => { const m = tbb.match(/bool DrawStylePairCoerce\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!coerceFn)
      broken.push('`DrawStylePairCoerce` is gone or unreadable — it is the seat that resets a thick styled fibo (P-DRAW-74b)');
    else if (!/if\(FibPenServesName\(name\)\) return false;/.test(coerceFn))
      broken.push('DrawStylePairCoerce reads a pen kind again — the strip open forces a thick styled fibo back to solid and the stack dies (P-DRAW-74b)');
    if (!/FibPenCapName/.test(fib) || !/FibPenWashName/.test(fib) || !/FibPenShwName/.test(fib) || !/FibPenFamIsChild/.test(fib))
      broken.push('a look family is unnamed or unowned — caps, wash and shadow need names, sweeps and the DK_NONE test (P-DRAW-74b)');
    if (!/return \(\(int\)STYLE_DASHDOTDOT \+ 1 \+ \(DrawStripPenLook\(k\) \? DrawLookCount\(\) : 0\)\);/.test(pk))
      broken.push('the fibo never sees its looks — the STYLE popover owes it 8 rows (the three looks included), other kinds five (P-DRAW-74b)');
    // P-LOOK-3D RETIRED (2026-10-18) — «3D کلا حذف کن» (user order). The fourth look,
    // its `[LK4]` tag and its `_FSH` shadow are gone end to end: no define, no ninth
    // cell, no caption, no icon seat, no build fence, no harness state. What STAYS is
    // the sweep (the sync's spend pass, the delete hub, HasPen and the early-out probe) —
    // a chart from an older build degrades to the previous look, never to a dangling
    // shadow. Every assert below fails the moment any seat comes back.
    {
      const tbaA = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
      const gSrc = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearA.mqh')) || []);
      const lkSrc = codeOf(linesOf(path.join(BIOTAK, 'DrawLooks.mqh')) || []);
      const prSrc = codeOf(linesOf(path.join(BIOTAK, 'DrawKindProfile.mqh')) || []);
      const harn3d = linesOf(SHOT_HARNESS) ? fs.readFileSync(SHOT_HARNESS, 'utf8') : '';
      const broken3 = [];
      if (/FIBPEN_LOOK_3D|FIBPEN_STYLE_3D|DRAW_LOOK_3D/.test(fib + tbb + tbaA + pk + gSrc + lkSrc + prSrc))
        broken3.push('the 3D look is back — a define, a fence or a cell carries it again');
      if (!/lk > FIBPEN_LOOK_WASH\) return 0;/.test(fib))
        broken3.push('the tag reader lost its WASH fence — a `[LK4]` from a legacy chart is read as a live look');
      if (!/lk > FIBPEN_LOOK_WASH\) return;/.test(fib))
        broken3.push('LookSet lost its WASH fence — 4 would write a tag for a look that does not exist');
      //--- P-UNIFY-4: the cap moved to the one translator. The STYLE writer asks it,
      //--- and its fence is `DrawLookValid` (WASH is the last id), so slot 8 is dead.
      if (!/DrawLookFromSlot\(st\)/.test(tbb) || !/lk >= DRAW_LOOK_NEON && lk <= DRAW_LOOK_WASH/.test(lkSrc))
        broken3.push('the STYLE writer lost its WASH cap — the eighth cell is pickable and dead');
      if (!/FibPenShwName\(fibo, l6\)/.test(fib) || !/ObjectDelete\(0, snm\);/.test(fib))
        broken3.push('the retirement sweep is gone — a legacy `_FSH` shadow stays on the chart forever');
      if (/bool shwOk/.test(fib))
        broken3.push('the 3D build fence is back — the sync can paint a shadow the look no longer offers');
      if (/fibo_3d3/.test(harn3d))
        broken3.push('the 3D shot state is back — a retired look asks for real pixels again');
      if (!/FibPenShwName\(fibo, dl\)/.test(fib))
        broken3.push('the delete sweep forgot the shadow family — a deleted fibo leaves `_FSH` strays on the chart');
      if (!/fc != 'C' && fc != 'W' && fc != 'H'/.test(fib))
        broken3.push('the fam test refuses `_FSH` — a shadow stray is served, hit and learned as a drawing of its own');
      const fibHas = (() => { const m = fib.match(/bool FibPenHasPen\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
      if (!/FibPenShwName\(fibo, 0\)\) >= 0\) return true;/.test(fibHas))
        broken3.push('the pen\'s existence test is blind to the shadow family — a legacy 3D fibo\'s shadow is never swept');
      if (!/FibPenWashName\(fibo, 0\)\) < 0 &&[\s\S]{0,80}?FibPenShwName\(fibo, 0\)\) < 0\) return false;/.test(fib))
        broken3.push('the look-only early-out skips the shadow probe — a look-4 fibo whose levels were deleted keeps its `_FSH` strays forever');
      if (broken3.length)
        failures.push('P-LOOK-3D retired: ' + broken3.join('; ') + ' (Biotak/FibPen.mqh + Toolbar_A/B + DrawStrip_Pick/GearA + shot harness)');
      else
        console.log('[PASS] P-LOOK-3D retired end to end — no define, no cell, no caption, no birth; `_FSH` is swept, never painted');
    }
    if (!/DrawStripPickCount\(k, slot\)/.test(tpt))
      broken.push('a picker row is gated by a second bound — rows the popover paints must pass the popover\'s own count (P-DRAW-74b)');
    if (!/PICK slot=/.test(tpt))
      broken.push('taps leave no number — slot, row, object and read-back ride the flushed channel (P-DRAW-74b)');
    // P-LOOK-RAY2 — AND THE PEN'S OWN NET. Every follower in this repo has one seat that
    // needs no event (the interior and the 50 % line ride this 2 s pass). The pen had only
    // event paths, so a master the terminal landed after the last event kept a stale pen
    // FOREVER: the very scene above, still stale hours later. The pass that already pays
    // one type read per object now asks each fibo — and the orphan rule rides it too.
    if (!/if\(FibPenServesType\(ty\)\) FibPenHeal\(nm\);/.test(pk))
      broken.push('the pen has no net — a master the terminal moves with no event keeps a stale pen until the next touch (P-LOOK-RAY2)');
    if (!/bool FibPenHeal\([^)]*\)\s*\{[\s\S]{0,900}?FibPenNetFind\(fibo\)/.test(fib) ||
        !/bool FibPenHeal\([^)]*\)\s*\{[\s\S]{0,1400}?return FibPenSync\(fibo, false\);/.test(fib))
      broken.push('`FibPenHeal` stopped comparing the master against the memo before it syncs — the net becomes an unconditional sync (P-LOOK-RAY2)');
    if (!/FibPenNetWrite\(fibo, \(long\)ta, \(long\)tb, three \? \(long\)t3 : 0,/.test(fib))
      broken.push('the sync never writes the memo — every 2 s pass would re-run the whole sync per fibo (P-LOOK-RAY2)');
    if (!/FibPenIsChild\(nm\) \|\| FibPenFamIsChild\(nm\)/.test(pk) || !/string FibPenChildParent\(/.test(fib))
      broken.push('the pen\'s children have no parent oracle — a band whose fibo is gone survives a reattach (P-LOOK-RAY2)');
    // P-SIM (2026-10-04) — THE SCENARIOS ARE RUN, NOT ONLY ASSERTED. Every report about
    // this drawing was a scenario, and every one of them was answered from a screenshot:
    // a screenshot can only see the frame the hand happened to catch. `tools/pen-sim.py`
    // runs the matrix OFFLINE, and it is only a test because it READS the rules out of
    // `Biotak/FibPen.mqh` and `Toolbar_A.mqh` as written — a sim that copied them would
    // pass forever against a source that says the opposite. The gate below owns the three
    // halves of that contract; `tools/mutation_gate.py P-SIM` proves it bites.
    {
      const sim = linesOf(path.join(__dirname, 'pen-sim.py')) || [];
      const simText = sim.join('\n');
      if (!sim.length) {
        broken.push('tools/pen-sim.py is gone — the pen\'s scenarios have nothing but a screenshot to answer them (P-SIM)');
      } else {
        for (const rule of ['P-SIM-74b', 'P-SIM-RAY', 'P-SIM-MEM', 'P-SIM-LOOK', 'P-SIM-CAP', 'P-SIM-DRAG']) {
          if (!simText.includes(rule))
            broken.push(`the scenario sim no longer runs ${rule} — the matrix lost the branch that caught it (P-SIM)`);
        }
        if (!/FIB\s*=\s*os\.path\.join\(ROOT, "Biotak", "FibPen\.mqh"\)/.test(simText) ||
            !/TBA\s*=\s*os\.path\.join\(ROOT, "Biotak", "Toolbar_A\.mqh"\)/.test(simText))
          broken.push('the sim no longer reads the two units it models — a copied rule is not a test (P-SIM)');
        if (!/refLog > DRAW_WIDTH_MIN/.test(simText) || !/WANT_MINUS/.test(simText))
          broken.push('the sim quotes the demotion rule no longer as the source states it, or has hardcoded the row count it must derive (P-SIM)');
      }
      const mutText = (linesOf(path.join(__dirname, 'mutation_gate.py')) || []).join('\n');
      if (!mutText.includes('"P-SIM-RAY-a"') || !mutText.includes('"P-SIM-SRC-a"'))
        broken.push('the scenario sim has no kill witness — a gate nobody has broken is a gate nobody knows works (P-SIM)');
    }
    if (broken.length) {
      failures.push('P-DRAW-74b: ' + broken.join('; ') + ' (Biotak/FibPen.mqh + Toolbar_A.mqh)');
    } else {
      console.log('[PASS] P-DRAW-74b a thick dash is drawn: the visible width converges, each child wears the level\'s own style in full ink, the width cell reads 1 + children, and solid costs nothing');
    }
  }

  // ── P-DRAGF2 (2026-10-04) — THE HAND'S ANCHOR IS THE PRESS'S ANSWER ──
  // Report: «هنوز موقع درگ و جابجای فیبو یک فریم عقب هستش خطوط و استایل
  // سفارشی شده» — the fibo's custom stack still trails one frame during a drag.
  // Two defects, both from the chase's own seats. Its anchor question was "the
  // anchor nearest the CURSOR PRICE", asked once per move: the anchor the hand
  // did NOT take is already a drag event old (measured DRAGSTAT 0.6-1.6 s
  // against ~50-130 moves/s) and becomes the FARTHER one as soon as the hand
  // travels, so that test hands the cursor to the stale side. And the chase
  // itself sat BELOW the shut-strip guard: measured 19:49:32-39 in the user's
  // session («Fibo 11000»), the stack was born at :32.396, the strip shut at
  // :34.973, and the drag events at :34.972, :36.573, :38.236 and :39.860 were
  // the ONLY re-seats (moved=14 each) while 252 left-button moves ran between
  // them — four re-seats in five seconds IS the frame the user sees, and it is
  // the same shape P-DRAW-64d fixed for the box's mid line one seat away.
  // The law (Biotak/FibPen.mqh): WHICH anchor the hand took is decided ONCE, at
  // the press, by PIXELS (FIBPEN_GRAB_PX — the repo's own grab radius); the
  // BODY is its own answer, because MT4 translates BOTH anchors there. WHERE
  // the master is is a snapshot resynced on every terminal landing (a live read
  // differs from the probe) with the cursor origin moved with it. And the move
  // channel that re-seats the children flushes its own frame.
  {
    const broken = [];
    const fib = codeOf(linesOf(path.join(BIOTAK, 'FibPen.mqh')) || []);
    if (!/FIBPEN_GRAB_PX/.test(fib) || !/FIBPEN_GRAB_BODY/.test(fib))
      broken.push('the grab radius or the body case is gone — the press cannot answer which anchor the hand took (P-DRAGF2)');
    if (!/if\(s_fibGrab < 0\)/.test(fib))
      broken.push('the anchor question is re-asked mid-gesture — the not-taken anchor is the stale one, and re-guessing IS the frame behind (P-DRAGF2)');
    if (/MathAbs\(cp - p1\)/.test(fib))
      broken.push('the anchor is picked by CURSOR PRICE again — once the hand travels, that test hands the cursor the stale side (P-DRAGF2)');
    if (!/ChartTimePriceToXY\(0, 0, \(int\)t1, p1, ax, ay\)/.test(fib) || !/dA <= FIBPEN_GRAB_PX && dA <= dB/.test(fib))
      broken.push('the press test is no longer pixels against FIBPEN_GRAB_PX — a price test cannot know where the hand is (P-DRAGF2)');
    if (!/pa = s_fibP0\[0\] \+ dp; pb = s_fibP0\[1\] \+ dp;/.test(fib))
      broken.push('a body drag stopped translating BOTH anchors — MT4 moves the whole pair, and one substitution bends the fibo (P-DRAGF2)');
    if (!/p1 != s_fibProbeP\[0\]/.test(fib) || !/s_fibCurP0 = cp;/.test(fib))
      broken.push('no landing probe — the snapshot drifts against the master until release instead of resyncing (P-DRAGF2)');
    // P-LOOK-RAY2: and the SPAN is never the chase's own. The children's times are the
    // two anchors the master has right now — an estimated span (dtS) is what let a pen
    // stop short of the line it is the style of. The PRICES ride ahead; the span does not.
    if (!/datetime ta = t1, tb = t2;/.test(fib))
      broken.push('the chase writes its own span into the children — the pen\'s extent then drifts from the line\'s (P-LOOK-RAY2)');
    if (/dtS/.test(fib))
      broken.push('an estimated span is back in the chase — the pen\'s times are the master\'s own (P-LOOK-RAY2)');
    if (!/FibPenChaseReset\(\);/.test(fib) || !/void FibPenDragArm\([^)]*\)\s*\{[\s\S]{0,900}?FibPenChaseReset\(\);/.test(fib))
      broken.push('a gesture can inherit the last snapshot — the arm itself must open a chase (P-DRAGF2)');
    if (!/if\(name != "" && name == s_fibDragObj\) return;/.test(fib))
      broken.push('a mid-gesture drag event re-arms — the landing then re-asks the anchor at a travelled cursor (P-DRAGF2)');
    if (!/if\(nMov > 0\) ChartRedraw\(\);/.test(fib))
      broken.push('the move channel never flushes — the children wait for the terminal repaint, which IS the frame behind (P-DRAGF2)');
    // The seat, not just the call: the follow must stand ABOVE the shut-strip guard.
    // It sat below it once (the second MOUSE_MOVE branch, with the grip carry), so
    // with the strip shut a dragged fibo moved only on the terminal drag events —
    // measured DRAGSTAT 0.6-1.6 s apart — and the box's mid line had the identical
    // shape before P-DRAW-64d moved it up.
    const tbr2 = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    const iChase = tbr2.indexOf('FibPenDragFollow((int)lparam, (int)dparam)');
    const iGuard = tbr2.indexOf('if(!s_dsOpen) return false;');
    if (iChase < 0 || iGuard < 0 || iChase > iGuard)
      broken.push('the chase is back under the shut-strip guard — a drawing dragged with the strip shut moves on the terminal drag events alone (P-DRAGF2)');
    if (broken.length) {
      failures.push('P-DRAGF2: ' + broken.join('; ') + ' (Biotak/FibPen.mqh)');
    } else {
      console.log('[PASS] P-DRAGF2 the anchor question is asked once, by pixels: the snapshot resyncs on every landing and the move channel flushes its own frame');
    }
  }

  // ── P-DRAW-75 (2026-10-03) — A COLOUR NEVER CHOSEN IS NEVER WRITTEN ──
  // `s_dkValid[k]` is set by ANY slot write, but `s_dkColor[k]` stays clrNONE
  // (-1, white on the chart) until a colour is picked: the create path wrote
  // it onto every fresh drawing of the kind («ابزار که رسم میکنه رنگش میره» —
  // white with the anchors alone). The FILLCLR slot already guards this way;
  // the BORDER half did not.
  {
    const broken = [];
    const tbb = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const apFn = (() => { const m = tbb.match(/bool DrawStyleApplyOnCreate\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!apFn) broken.push('`DrawStyleApplyOnCreate` is gone or unreadable — it is the one writer onto a fresh drawing (P-DRAW-75)');
    else {
      // P-DRAW-INK (2026-10-04): the VALUE the guard guards changed when the hand’s own
      // report arrived — «چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود». A kind with no
      // colour of its own now takes the LAST ink the hand picked ANYWHERE before it takes
      // the terminal’s factory white. What has not changed is the law this entry exists
      // for: the value that reaches the object is never clrNONE.
      if (!/color want = s_dkColor\[k\];/.test(apFn) || !/if\(\(int\)want < 0\) want = s_dkAnyClr;/.test(apFn))
        broken.push('the create path no longer falls back to the last ink — a fibo of a kind never coloured is born factory-white while the hand is drawing in blue (P-DRAW-INK)');
      if (!/DRAW_CAP_COLOR\) != 0 && \(int\)want >= 0/.test(apFn))
        broken.push('the create path writes an unchosen colour — clrNONE (-1) paints white, anchors alone (P-DRAW-75)');
    }
    if (broken.length) {
      failures.push('P-DRAW-75: ' + broken.join('; ') + ' (Biotak/Toolbar_B.mqh)');
    } else {
      console.log('[PASS] P-DRAW-75/P-DRAW-INK the create path writes only a colour the hand chose: the kind’s own memory first, else the last ink picked anywhere, else the terminal default');
    }
  }

  // ── P-DRAW-09b-RETIRED (2026-10-03) — THE STRIP SERVES ONE OBJECT ──
  // Report: «مثلا من اگر دوتا فيبو داشته باشم بخوام رنگ يک شو عوض کنم روي ديگر هم
  // اعمال ميشه» — two fibos, one colour tap, the second fibo changed too. The
  // writer was not the colour writer: `DrawSelSnapshot` walked the chart and
  // collected every drawing of the held kind whose `OBJPROP_SELECTED` was true,
  // so one Ctrl+click made hours earlier became a standing instruction that every
  // later tap lands on all of them. MT4 keeps those flags long after the gesture.
  //
  // The inverse that must fail HERE: the selection walk coming back, and any store
  // that can hold more than the served name.
  {
    const broken = [];
    const tbb = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const snap = (() => { const m = tbb.match(/int DrawSelSnapshot\([^)]*\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!snap) broken.push('`DrawSelSnapshot` is gone or unreadable — it is the one owner of the served set (P-DRAW-09b)');
    else {
      if (/ObjectsTotal|ObjectName/.test(snap))
        broken.push('`DrawSelSnapshot` walks the object list again — the selection-based group is the exact defect («رنگ يک شو عوض کنم روي ديگر هم اعمال ميشه»)');
      if (/OBJPROP_SELECTED/.test(snap))
        broken.push("`DrawSelSnapshot` reads `OBJPROP_SELECTED` again — MT4 keeps that flag long after the gesture, so it is never the user pointing at these drawings now");
    }
    if (!/#define\s+DRAW_SEL_MAX\s+1\b/.test(tbb))
      broken.push('`DRAW_SEL_MAX` is not 1 — the store can hold names again, and every fan-out loop in the strip can run more than once');
    // The two multi-object writes that SURVIVE, and why. Each is asserted so a
    // reviewer cannot mistake them for the retired automatic fan-out.
    if (!/if\(nm == "" \|\| nm == fromName \|\| DrawIsIndicatorObject\(nm\)\) continue;/.test(tbb))
      broken.push('`DrawStyleApplyToKind` no longer skips the source / the indicator\'s objects — «Apply to all <Kind>» would dye objects it never listed');
    if (!/int DrawStyleKindCount\(/.test(tbb))
      broken.push('`DrawStyleKindCount` is gone — the «Apply to all <Kind>» label would print the selection size again, which is not what that row touches');
    // The scope/tips: a strip that serves one object must not claim otherwise.
    const pick = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || []);
    const scope = (() => { const m = pick.match(/string DrawStripTipScope\(\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!scope) broken.push('`DrawStripTipScope` is gone — every tip appends it, so a removal is a second-writer-sized break');
    else if (/applies to all/.test(scope))
      broken.push('`DrawStripTipScope` promises «applies to all N selected» again — the strip serves ONE drawing, so the suffix can never be true');
    const title = (() => { const m = pick.match(/string DrawStripTitle\(\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (title && /x" *\+ *IntegerToString/.test(title))
      broken.push('`DrawStripTitle` prints the `xN` group count again — the strip serves one drawing and could never honour that number');
    if (broken.length) {
      failures.push('P-DRAW-09b-RETIRED: ' + broken.join('; ') + ' (Biotak/Toolbar_B.mqh + DrawStrip_Pick.mqh)');
    } else {
      console.log('[PASS] P-DRAW-09b-retired the strip serves one object: no selection walk, a one-name store, and «Apply to all <Kind>» stays as the one explicit multi-object command');
    }
  }

  // ── P-DRAW-09c (2026-10-04) — THE LAST LOOK IS THE DEFAULT, ACROSS ATTACHES ──
  // «همیشه آخرین تغییرات روی ابجکت پیش‌فرض بشه و هر سری نیاز نباشه تنظیم بکن» — the kind
  // memory already made the last look the default of the NEXT DRAWING; what it did not do
  // was survive an attach, so the first fibo of every session was born factory-fresh and
  // the user set it again. The rows now ride the presets' own file, through the presets'
  // own single writer, under ONE reserved slot. Four things can rot, and each is asked:
  //   (a) the pack and the unpack agree on the BIT LAYOUT — they are one contract in two
  //       functions, and a shift edited on one side reads the colour as the width;
  //   (b) the save really writes a last-look row (else nothing is ever persisted);
  //   (c) the load really restores one, and reads it BEFORE the preset bands reject
  //       slot 255 (a row no reader accepts is a row that was never written);
  //   (d) the ONE slot writer persists what it learned — a look learned and not saved is
  //       the exact sentence this entry is about.
  {
    const broken = [];
    const tbbLines = linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || [];
    const tplLines = linesOf(path.join(BIOTAK, 'Toolbar_Tpl.mqh')) || [];
    const tpl = codeOf(tplLines);
    if (!/define DRAW_LASTLOOK_SLOT/.test(tpl))
      broken.push('the reserved last-look slot is gone — the save and the load would read each other\u2019s rows');
    const packA = bodyOf(tplLines, 'double DrawStylePackA(');
    const packB = bodyOf(tplLines, 'double DrawStylePackB(');
    const unpack = bodyOf(tplLines, 'void DrawStyleUnpack(');
    if (!packA || !packB || !unpack) {
      broken.push('the last-look pack/unpack pair is gone from Biotak/Toolbar_Tpl.mqh — the look has no way to disk');
    } else {
      const shifts = (t, re) => (t.match(re) || []).map((s) => parseInt(s.match(/\d+/)[0], 10));
      const aS = shifts(packA.text, /<< \d+/g);
      const bS = shifts(packB.text, /<< \d+/g);
      const bAt = unpack.text.indexOf('long b = (long)rawB;');
      const uA = shifts(bAt >= 0 ? unpack.text.slice(0, bAt) : '', />> \d+/g);
      const uB = shifts(bAt >= 0 ? unpack.text.slice(bAt) : '', />> \d+/g);
      // P-DRAW-INK (2026-10-04): the contract is the BIT MAP, not the order the two
      // functions happen to name their fields in — the unpack reads the presence bit it
      // was given by P-DRAW-INK first, and that is a field, not a disagreement. The
      // comparison is a set for that reason, and it still catches the defect it was
      // written for: a shift edited on ONE side (a number that appears in one list and
      // not the other).
      const sameBits = (x, y) => x.slice().sort((p, q) => p - q).join(',') === y.slice().sort((p, q) => p - q).join(',');
      if (bAt < 0) broken.push('DrawStyleUnpack() no longer splits its two numbers — half the look would be read out of the other half’s bits');
      else if (!sameBits(aS, uA))
        broken.push(`the pack and the unpack disagree on A\u2019s bit map (pack << ${aS.join(',')} vs unpack >> ${uA.join(',')}): one of the two reads another slot\u2019s bits`);
      else if (!sameBits(bS, uB))
        broken.push(`the pack and the unpack disagree on B\u2019s bit map (pack << ${bS.join(',')} vs unpack >> ${uB.join(',')})`);
      if (
        !/& 0xFFFFFF/.test(packA.text) ||
        !/& 0xFFFFFF/.test(packB.text) ||
        !/0x1FFFFFF/.test(unpack.text)
      )
        broken.push('the colour masks are gone — clrNONE (-1) would be stored as 0xFFFFFFFF and come back as a colour nobody chose (P-DRAW-75\u2019s rule, one file over)');
    }
    const save = bodyOf(tplLines, 'void DrawTplSave()');
    if (!save) broken.push('DrawTplSave() is gone: the file has no writer');
    else if (!/DRAW_LASTLOOK_SLOT/.test(save.text))
      broken.push('the save never writes a last-look row — the look is learned and then lost at the next attach');
    const load = bodyOf(tplLines, 'void DrawTplLoad()');
    if (!load) broken.push('DrawTplLoad() is gone: the file has no reader');
    else {
      const at = load.text.indexOf('i == DRAW_LASTLOOK_SLOT');
      const band = load.text.indexOf('i < 0 || i >= DRAW_TPL_MAX');
      if (at < 0) broken.push('the load never restores the reserved last-look slot');
      else if (band >= 0 && at > band)
        broken.push('the last-look row must be read BEFORE the preset bands reject it — slot 255 is outside every preset band on purpose');
      if (!/DrawStyleUnpack\(/.test(load.text))
        broken.push('the load does not unpack the last look into the kind memory');
    }
    const write = bodyOf(tbbLines, 'bool DrawSlotWrite(');
    if (!write) broken.push('DrawSlotWrite() is gone from Biotak/Toolbar_B.mqh — the kind memory has no writer');
    else if (!/s_dkValid\[k\] = true;[\s\S]{0,400}?DrawTplSave\(\);/.test(write.text))
      broken.push('the ONE slot writer must persist what it learned — the last change is the default only if it survives the session');
    if (broken.length) {
      failures.push('P-DRAW-09c: ' + broken.join('; ') + ' (Biotak/Toolbar_Tpl.mqh: the last look rides the template file, one writer, one reserved slot)');
    } else {
      console.log('[PASS] P-DRAW-09c the last look is the default across attaches: one reserved slot in the templates\u2019 own file, written by the same single writer, and the pack and the unpack agree on every bit');
    }
  }

  console.log('');
  // ── P-DRAW-INK (2026-10-04) — THE LAST INK THE HAND CHOSE IS THE ONE IT DRAWS WITH ──
  // Report, on a chart whose fibos had been given a width and a look but never a colour:
  // «چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود این هم درست کن برای همه جاها» — and the hand’s own
  // disk said why. `Biotak\DrawPresets.csv` carried `5;255;550091358208;771751935`: kind 5
  // (fibo), the last-look row, colour field 0xFFFFFF. P-DRAW-09c masked clrNONE with
  // `& 0xFFFFFF`, and -1 masks to WHITE — so the memory’s emptiness came back from the
  // file as a colour nobody chose, the create path wrote it (it IS >= 0), and every fibo
  // born afterwards was white. Also measured in MQL4/Files: `Fibo 56218` and `Fibo 58985`
  // were born white this way, their whole `_FSD` pen included. Three things must hold:
  //   (a) the pack SAYS whether a colour is present (bit 33) and the unpack believes it,
  //       so a row written by the build without the bit reads as “no colour of its own”
  //       and P-DRAW-75’s rule heals instead of painting white;
  //   (b) the one ink every kind shares is noted on every colour the hand picks, saved in
  //       a reserved slot of the same file, and restored BEFORE the preset bands (254 is
  //       outside every band on purpose, exactly like 255);
  //   (c) the create path wears it (P-DRAW-75 asserts the guard on the value it reaches).
  {
    const broken = [];
    const tbbLines = linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || [];
    const tplLines = linesOf(path.join(BIOTAK, 'Toolbar_Tpl.mqh')) || [];
    const tpl = codeOf(tplLines);
    const packA = bodyOf(tplLines, 'double DrawStylePackA(');
    const unpack = bodyOf(tplLines, 'void DrawStyleUnpack(');
    if (!packA || !unpack) {
      broken.push('the look pack/unpack pair is gone from Biotak/Toolbar_Tpl.mqh — a colour and a missing colour could not be told apart at all');
    } else {
      if (!/<< 33/.test(packA.text))
        broken.push('“no colour of its own” is masked as white again — the presence bit (33) left the pack, and `-1 & 0xFFFFFF` is 0xFFFFFF');
      if (!/>> 33/.test(unpack.text) || !/clrNONE/.test(unpack.text))
        broken.push('the unpack ignores the presence bit and reads the masked field as a colour — a kind that never had one comes back WHITE');
    }
    if (!/define DRAW_LASTINK_SLOT/.test(tpl))
      broken.push('the reserved last-ink slot is gone — the ink cannot survive an attach');
    const save = bodyOf(tplLines, 'void DrawTplSave()');
    if (save && !/DRAW_LASTINK_SLOT/.test(save.text))
      broken.push('the save never writes the last ink — the next attach starts on the terminal default again');
    const load = bodyOf(tplLines, 'void DrawTplLoad()');
    if (load) {
      const at = load.text.indexOf('i == DRAW_LASTINK_SLOT');
      const band = load.text.indexOf('i < 0 || i >= DRAW_TPL_MAX');
      if (at < 0) broken.push('the load never restores the last ink');
      else if (band >= 0 && at > band)
        broken.push('the last-ink row is read BELOW the preset bands — slot 254 is outside every band on purpose, so that guard eats the row');
    }
    const write = bodyOf(tbbLines, 'bool DrawSlotWrite(');
    if (write && !/s_dkAnyClr = c;/.test(write.text))
      broken.push('the one colour writer stopped noting the last ink — the fallback would answer with a stale colour forever');
    if (broken.length) {
      failures.push('P-DRAW-INK: ' + broken.join('; ') + ' (Biotak/Toolbar_Tpl.mqh + Toolbar_B.mqh: one presence bit in A, one reserved row, one ink for the kinds that never had a colour)');
    } else {
      console.log('[PASS] P-DRAW-INK the last colour the hand picks is the one a fresh drawing wears: the presence bit keeps clrNONE out of the file, and the shared ink is noted, saved and restored');
    }
  }

  // ── P-ORPHAN-ALL (2026-10-04) — NO REMNANT OUTLIVES ITS MASTER ──
  // «این بقایش چرا حذف نمیشه؟ برای کل پروژه رو چک کن که مثل این نباشه» — and MT4’s own chart file agreed with the
  // screenshot: `profiles/default/chart01.chr` (written at the terminal’s shutdown,
  // 2026-10-04 09:45) still carried all 36 `_FSD` pen rows of TWO fibos that were gone from
  // it (`Fibo 54705`, `Fibo 58985`). The pen had no orphan rule of its own until
  // P-LOOK-RAY2; the interior’s and the 50 % line’s had one each. What none of the three
  // had was a WITNESS, so a cleanup was invisible and could only be believed. Three laws
  // now hold for every companion family the drawing tool builds — the interior’s child,
  // the box’s 50 % line, the fibo pen’s rows, the line pen’s rows (`_PSKq`, P-DRAW-74c):
  //   (a) the pass that already walks every object every 2 s answers “is your master
  //       still here?” for each of them, through ONE deleter;
  //   (b) that deleter names the drop (and its missing master) on the flushed diag
  //       channel, so the cleanup is evidence rather than faith;
  //   (c) both delete routes — the strip’s bin and the terminal’s own native delete —
  //       drop the family in the event itself, not 2 s later.
  // The inverse that must fail here: a family with a suffix, a builder and a parent
  // parser but no orphan rule on the pass.
  {
    const broken = [];
    const pickLines = linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || [];
    const pump = bodyOf(pickLines, 'void BoxExtrasPump()');
    const drop = bodyOf(pickLines, 'void DrawOrphanDrop(');
    if (!pump) broken.push('BoxExtrasPump() is gone from Biotak/DrawStrip_Pick.mqh — it is the chart-side pass every orphan rule rides');
    else {
      const families = [
        ['FillIsChild', 'the interior’s child (`FillIsChild`/`FillChildParent`)'],
        ['BoxIsMidChild', 'the box’s 50 % line (`BoxIsMidChild`/`BoxMidParent`)'],
        ['FibPenIsChild', 'the fibo pen’s rows (`FibPenIsChild`/`FibPenFamIsChild`/`FibPenChildParent`)'],
        ['PenStackIsChild', 'the line pen’s rows (`PenStackIsChild`/`PenStackChildParent`)'],
      ];
      // P-ORPHAN-ALL-a (2026-10-17): the seat is the family's OWN rule — from its marker
      // to the NEXT family's marker. The old fixed 900-char window also held the next
      // family's `DrawOrphanDrop`, so replacing this rule's call with a silent
      // `ObjectDelete` still matched and the mutation SURVIVED (measured, full run).
      for (let f = 0; f < families.length; f++) {
        const [test, what] = families[f];
        const at = pump.text.indexOf(test);
        if (at < 0) { broken.push(`the orphan rule for ${what} left the pass`); continue; }
        const next = f + 1 < families.length ? pump.text.indexOf(families[f + 1][0], at + test.length) : -1;
        const seat = pump.text.slice(at, next >= 0 ? next : at + 900);
        if (!/ObjectFind\(0, par\) < 0\)/.test(seat) || !/DrawOrphanDrop\(nm, par\)/.test(seat) || /ObjectDelete\(/.test(seat))
          broken.push(`the orphan rule for ${what} no longer deletes through DrawOrphanDrop — the companion of a deleted master survives the pass`);
      }
    }
    if (!drop) broken.push('DrawOrphanDrop() is gone — the one deleter, and the only witness a drop has');
    else if (!/ObjectDelete\(0, nm\)/.test(drop.text) || !/DrawStripDiagEmit\(/.test(drop.text) || !/ORPHAN/.test(drop.text))
      broken.push('DrawOrphanDrop() no longer deletes AND names the drop — the cleanup is invisible again');
    const tbr = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    if (!/FibPenStraysDrop\(sparam\)/.test(tbr) || !/BoxMidDrop\(sparam\)/.test(tbr) || !/FillChildDrop\(sparam\)/.test(tbr) || !/PenStackStraysDrop\(sparam\)/.test(tbr))
      broken.push('the terminal’s own delete branch stopped dropping the deleted drawing’s families — a native delete leaves them on the chart');
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    if (!/FibPenSync\(DrawSelAt\(j\), true\)/.test(tap) || !/FibPenSync\(s_dsObj, true\)/.test(tap) || !/PenStackSync\(DrawSelAt\(j\), true\)/.test(tap) || !/PenStackSync\(s_dsObj, true\)/.test(tap))
      broken.push('the strip’s bin stopped dropping the drawing’s pens — the rows outlive the drawing they were built for');
    if (broken.length) {
      failures.push('P-ORPHAN-ALL: ' + broken.join('; ') + ' (Biotak/DrawStrip_Pick.mqh + Biotak/DrawStrip_Router.mqh + Biotak/DrawStrip_Tap.mqh)');
    } else {
      console.log('[PASS] P-ORPHAN-ALL no remnant outlives its master: all four companion families answer for themselves on the 2 s pass through one deleter that witnesses every drop, and both delete routes drop them in the event itself');
    }
  }

  // ── P-LVL (2026-10-04) — FIBO LEVELS ARE RATIOS, AND EACH WEARS ITS OWN LOOK ──
  // «این سطح درست اضافه نمیشه» — MT4 stores ratios (0.236) while the panel showed
  // percent labels (23.6): the old common list stored 23.6 (=2360%, off-chart) and
  // the add field's own example ("88.6") stored 8860%. «رنگ هر سطح مخصوص خودش»
  // — the level row's chip painted the family icon over its own swatch. Three laws:
  //   (a) commons are stored ratios, labels are percent, one normalizer rides every
  //       write path (toggle/add/edit/collect) and migrates old percent sets;
  //   (b) texts ride index-aligned with values through every rewrite, undo and copy;
  //   (c) each level row wears its own swatch (same seat, same names — never a new
  //       object) and the swatch, not the row, opens the palette on that level.
  {
    const broken = [];
    const pick = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || []);
    if (!/case 1: return 0\.236;/.test(pick) || !/default: return 1\.618;/.test(pick))
      broken.push('the common levels are not stored ratios again — percent values draw off-chart (P-LVL-SCALE)');
    if (!/DrawStripLevelNorm/.test(pick) || !/v \/ 100\.0/.test(pick))
      broken.push('DrawStripLevelNorm() is gone — typed percent ("88.6") lands at 8860% again');
    if (!/nv \* 100\.0/.test(pick))
      broken.push('DrawStripLevelName() no longer shows percent — labels and storage speak one scale again');
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    if (!/ObjectSetString\(0, s_dsObj, OBJPROP_LEVELTEXT, i, txts\[i\]\)/.test(tap))
      broken.push('DrawStripLevelsRewrite() stopped carrying texts index-aligned — notes glue onto the wrong levels');
    if (!/DrawStripGearLevelColorTap/.test(tap) || !/DrawStripGearLevelDescTap/.test(tap))
      broken.push('a level row lost its swatch/note tap — color and description have no door');
    if (!/DrawStripPalAskLevel\(DRAW_SLOT_COLOR, idx\)/.test(tap))
      broken.push('the swatch no longer asks the palette on the stored level — one color lands on all levels');
    const gearA = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearA.mqh')) || []);
    if (!/bool DrawStripGearLevelSwatch\(/.test(gearA) || !/DrawStripGearLevelText\(/.test(gearA))
      broken.push('the level row helpers left GearA — the swatch or the note text has no painter');
    const gearB = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearB.mqh')) || []);
    if (!/DrawStripGearLevelSwatch\(r, rx, py, dirty\)/.test(gearB))
      broken.push('the gear paint stopped calling the swatch — rows wear the family icon again');
    const base = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Base.mqh')) || []);
    if (!/DrawStripGearLevelColorTap\(r\); return true;/.test(base) || !/DrawStripGearLevelDescTap\(r\); return true;/.test(base))
      broken.push('the hit test lost the swatch/label zones — taps land on the toggle instead');
    if (broken.length) {
      failures.push('P-LVL: ' + broken.join('; ') + ' (Biotak/DrawStrip_Pick.mqh + DrawStrip_Tap.mqh + DrawStrip_GearA.mqh + DrawStrip_GearB.mqh + DrawStrip_Base.mqh)');
    } else {
      console.log('[PASS] P-LVL fibo levels are stored ratios shown as percent, texts ride values, and each level row wears its own swatch, note and palette target');
    }
  }

  {
    // P-PRICE-01 — PRICE_WEIGHTED (6) is a case, not the default. The input exposes
    // the whole ENUM_APPLIED_PRICE, and without this case Weighted served Close as
    // the TH base price, repricing every TH level off the wrong base.
    const broken = [];
    const hist = codeOf(linesOf(path.join(BIOTAK, 'HistoricalDataFunctions.mqh')) || []);
    if (!/case 6:/.test(hist))
      broken.push('GetPriceForPreviousDay lost case 6 — PRICE_WEIGHTED falls into default and serves Close');
    if (!/cachedPrices\[2\]\+cachedPrices\[3\]\+cachedPrices\[0\]\+cachedPrices\[0\]/.test(hist))
      broken.push('the Weighted base is no longer (H+L+C+C)/4 off the cached day');
    if (broken.length) {
      failures.push('P-PRICE-01: ' + broken.join('; ') + ' (Biotak/HistoricalDataFunctions.mqh)');
    } else {
      console.log('[PASS] P-PRICE-01 Weighted is priced (H+L+C+C)/4, never Close by default-fallthrough');
    }
  }

  {
    // P-PAL-22 — the palette tail round-trips over the kind-25 gap. Kind 25 does not
    // exist (0-24 contiguous, then 26/27 edges, 28/29 strip). The ToKind guard must be
    // the last contiguous kind, and IndexOfKind its inverse ladder; identity mapping
    // parks the cycler on a dead kind and captions one slot down.
    const broken = [];
    const st = codeOf(linesOf(path.join(BIOTAK, 'BiotakPanels_State.mqh')) || []);
    if (!/if\(k <= PAL_ATR_SPREAD\) return k;/.test(st))
      broken.push('PalTgtToKind guard is not the last contiguous kind — the tail falls back to identity');
    if (!/if\(k == 25\) return 26;/.test(st) || !/return 28 \+ \(k - 27\);/.test(st))
      broken.push('PalTgtToKind tail ladder is gone — slots 25-28 no longer map over the gap');
    if (!/if\(k == 26\) return 25;/.test(st) || !/if\(k == 28\) return 27;/.test(st))
      broken.push('PalTgtIndexOfKind inverse ladder is gone — captions read one slot down');
    if (broken.length) {
      failures.push('P-PAL-22: ' + broken.join('; ') + ' (Biotak/BiotakPanels_State.mqh)');
    } else {
      console.log('[PASS] P-PAL-22 palette tail round-trips: 26↔25, 27↔26, 28↔27, 29↔28');
    }
  }

  {
    // P-TH3-PT — the ABCD floor never reads a zero point. Raw Point is 0 until the
    // contract loads (P-UI-57b): a zero floor accepts a degenerate AB and plants D
    // off noise. The file stays compilable standalone (the TH3 harness includes
    // only this chain), so the fallback derives from Digits, which is fixed.
    const broken = [];
    const th3math = codeOf(linesOf(path.join(BIOTAK, 'TH3/TH3Math.mqh')) || []);
    if (!/th3pt = MathPow\(10, -Digits\)/.test(th3math))
      broken.push('CalculateABCDPointD lost its Digits fallback — a zero Point accepts a degenerate AB again');
    if (/double minDistance = Point \* ABCD_MIN_DISTANCE_POINTS;/.test(th3math))
      broken.push('CalculateABCDPointD floors on raw Point again — degenerate AB passes while the contract loads');
    if (broken.length) {
      failures.push('P-TH3-PT: ' + broken.join('; ') + ' (Biotak/TH3/TH3Math.mqh)');
    } else {
      console.log('[PASS] P-TH3-PT ABCD floor never reads a zero point');
    }
  }

  console.log('');
  // ── P-BK-105 (2026-10-09) — A CLOSED KNOT'S STEP IS THE KNOT'S OWN, NOT TODAY'S ──
  // Report: «atr با مربوط به همون گذشته باشه که گره هستش … برای لایو حساب شده، بدرد اونجا
  // نمیخوره». P-BK-92 moved the TYPE onto the rung's own TH at the box' own anchor and
  // P-BK-79 moved the risk with it, so the STEP was the ONE number a closed knot still
  // divided by the LIVE chart-TF TH the pump pushes at anchor 0 (`s_bkStepTH`): a base
  // that closed forty bars ago had its own height, its break and its return measured in
  // TODAY'S step. The inverse that must fail here: any of the three divisors in
  // `BaseKnotNodeRead` reading `s_bkStepTH` again, or the hover quoting a step the node
  // record never carried (which is how it read the live one).
  {
    const broken = [];
    const nodesLines = nodes || [];
    const nodesCode = codeOf(nodesLines);
    const read = bodyOf(nodesLines, 'void BaseKnotNodeRead(');
    if (!read) {
      broken.push('BaseKnotNodeRead is gone from Biotak/BaseKnot_Nodes.mqh');
    } else {
      // The READER's name is not the law (P-BK-106 split the ability table into two
      // columns and gave the step its own reader): what must hold is that the step is
      // read from a row keyed on (nodeTimeMin, anchor) into nd.stepTH.
      if (!/\(\s*nodeTimeMin\s*,\s*nd\.anchor\s*,\s*nd\.stepTH\s*\);/.test(read.text))
        broken.push('BaseKnotNodeRead must read its step off the (nodeTimeMin, anchor) row the pump already pushed (P-BK-105) — the SAME key the type was decided against, so the step costs nothing the type did not already cost and can never be another bar');
      for (const div of ['nd.baseStep = (top - bot) / nd.stepTH;',
                         'nd.breakStep = maxBreak / nd.stepTH;',
                         'nd.retStep   = maxRet   / nd.stepTH;']) {
        if (!read.text.includes(div))
          broken.push('the divisor in ' + div.split('=')[0].trim() + ' no longer divides by nd.stepTH — a closed knot sizes its own story with today\'s price again (P-BK-105)');
      }
      if (/\/\s*s_bkStepTH/.test(read.text))
        broken.push('a divisor inside BaseKnotNodeRead reads s_bkStepTH again — that is the LIVE chart-TF TH at anchor 0 (P-BK-105)');
      if (!/nd\.stepTH = 0\.0;/.test(read.text))
        broken.push('BaseKnotNodeRead no longer zeroes nd.stepTH — a local BaseKnotNode is not zeroed by MQL4, so a hover could quote an undefined step (P-BK-105)');
    }
    if (!/double stepTH;/.test(codeOf(bkBase || [])))
      broken.push('the node record no longer publishes the step it divided by (P-BK-105): the hover would quote a number nothing carries, or read the live one again');
    const hover = bodyOf(nodesLines, 'string BaseKnotNodeLine(');
    if (!hover) broken.push('BaseKnotNodeLine is gone from Biotak/BaseKnot_Nodes.mqh');
    else {
      if (!/step \(TH " \+ BaseKnotTFName\(nd\.nodeTF\) \+ ", at the box' own bar\) = " \+/.test(hover.text))
        broken.push("the hover no longer names the node's OWN TF beside its step (P-BK-105): a size without the bar it was read on is a number nobody can check");
      if (!/else if\(s_bkStepTH > 0\)/.test(hover.text))
        broken.push('the sizing preview lost its LIVE row (P-BK-105): a box being drawn has no story yet, and its step is the pump\'s live chart-TF row by design');
    }
    const planCode = codeOf(plan || []);
    if (!/ndLive\.stepTH = 0\.0;/.test(planCode))
      broken.push('BaseKnotSyncLive no longer zeroes ndLive.stepTH — the preview\'s local record is not zeroed by MQL4, so its hover could quote an undefined step (P-BK-105)');
    if (broken.length) {
      failures.push('P-BK-105: ' + broken.join('; ') + ' (Biotak/BaseKnot_Nodes.mqh + Biotak/BaseKnot_Plan.mqh)');
    } else {
      console.log('[PASS] P-BK-105 a closed knot\'s step is its own: read off the (node, anchor) row the type was decided against, published on the record, and named with the TF it was measured on (Biotak/BaseKnot_Nodes.mqh)');
    }
  }

  console.log('');
  // ── P-BK-111 (2026-10-09) — THE SIDE IS THE USER'S TO TURN, AND THE PRICE MAY NOT TAKE IT BACK ──
  // Report: «یک چیزی باشه که کاربر خواست جهت سل و بای گره عوض بکن چ.ن بعضی گره به صورت مارکر
  // هستش که مثل سل هستش ولی در جهت بای وقتی که ایگنور شد میشه استفاده کرد ازش» — then, on
  // seeing the strip: «روی نوار استریپ بزاری بهتره». The side is read from the market or from
  // the break's story, so the control has to live on the BOX and not in a settings card; and
  // the follow runs every 500 ms, so a bare click would be undone in half a second.
  //
  // FOUR THINGS MUST HOLD, and each has an inverse that failed a green build once:
  //   1. THE FOLLOW IS GATED. `BaseKnotRefreshDirection` returns on a non-zero `dirLock`.
  //      Without it the cell answers «done», the note redraws the same side, and the next
  //      pump puts it back — a control that compiles, paints, hits, and changes nothing.
  //   2. THE CELL IS A REAL SEAT IN THE STRIP'S OWN TABLE: name, rect, icon and tooltip all
  //      answer for slot 5, and BK_TB_N counts it. A cell added to the press route without
  //      the count is a hit test with nothing to paint.
  //   3. THE BACKDROP GROWS WITH THE ROW. `bkStripSkin()`'s W and `PNL_TB_W` are one seat
  //      (a backdrop that did not grow leaves the last cell standing off its own card), and
  //      both are read HERE rather than believed: the strip's last slot's right edge must
  //      land inside the width the code declares and inside the width the generator bakes.
  //   4. THE FLIP IS WITNESSED ON THE FLUSHED CHANNEL WITH A READ-BACK. The flip cannot emit
  //      from its own layer (it compiles before DrawStrip), so it records and the pumped
  //      witness reports `was`/`now`/`lock`/`read`/`gv`. A `Print` here reads as «nothing
  //      happened» (P-DRAW-126) and a witness without a read-back cannot tell a write from
  //      a lie.
  {
    const broken = [];
    const measure = linesOf(BK_MEASURE) || [];
    const dirLines = linesOf(BK_DIRECTION) || [];
    const rowsLines = linesOf(PANELS_ROWS) || [];
    const hitLines = linesOf(PANELS_HIT) || [];
    const witLines = linesOf(BK_WITNESS) || [];
    const metrics = codeOf(linesOf(CARD_METRICS) || []);

    // 1 — EVERY WRITER OF THE SIDE YIELDS TO THE USER'S CALL, and there are exactly two
    //     of them, both of which shipped broken once:
    //       a. THE PRICE FOLLOW (`BaseKnotRefreshDirection`), which runs every 500 ms.
    //       b. THE BREAK'S STORY (inside `BaseKnotSync`, P-BK-46), which runs on the very
    //          `BaseKnotSync` the flip itself calls to rebuild the family — so the rebuild
    //          the cell NEEDS was what took the side back, in the same event. Gating only
    //       (a) is the mistake this entry exists for: MEASURED on the flushed witness after
    //       six clicks, `was=BUY now=SELL lock=-1 read=BUY gv=-1`. The write was exact and
    //       the box never moved.
    //     The law is derived, not listed: every `.dir =` outside the registry's own
    //     birth (`BaseKnotRegister` / `BaseKnotLazyInit`) must sit in a dirLock-guarded
    //     branch, and the flip action is the only place allowed to SET the lock.
    const follow = bodyOf(measure, 'bool BaseKnotRefreshDirection(');
    if (!follow) {
      broken.push('BaseKnotRefreshDirection is gone from Biotak/BaseKnot_Measure.mqh');
    } else if (!/dirLock\s*!=\s*0\)\s*return false/.test(follow.text)) {
      broken.push('BaseKnotRefreshDirection no longer returns on a locked side (P-BK-111): the follow reads the price every 500 ms and would undo the user\'s click, so the cell would answer «done» and paint the same side');
    }
    const sync = bodyOf(plan || [], 'void BaseKnotSync(');
    if (!sync) {
      broken.push('BaseKnotSync is gone from Biotak/BaseKnot_Plan.mqh');
    } else {
      const story = /ndDir\s*!=\s*0\s*&&\s*ndDir\s*!=\s*dir[^;]*;/.exec(sync.text);
      if (!story)
        broken.push('the story\'s side write is gone from BaseKnotSync (P-BK-111) - check that it is still the only thing that publishes a break\'s own answer');
      else if (!/dirLock\s*==\s*0/.test(story[0]))
        broken.push('the BREAK\'S STORY no longer yields to the user\'s call (P-BK-111): Sync runs on the very BaseKnotSync the flip calls to rebuild the box, so the rebuild the cell needs would take the side straight back - the write is exact and the box never moves, which is the defect the flushed witness read back as `now=SELL read=BUY`');
      if (!/nodeSide\s*=\s*ndDir/.test(sync.text))
        broken.push('BaseKnotSync no longer publishes nodeSide (P-BK-111): the story is a fact about the BREAK and the pump\'s gates read it - only the drawn side yields, never the story\'s own answer');
    }
    // derived, not listed: no third writer may appear behind the gate
    for (const [f, lines] of [['BaseKnot_Measure.mqh', measure], ['BaseKnot_Plan.mqh', plan], ['BaseKnot_Direction.mqh', dirLines]]) {
      const code = codeOf(lines || []);
      const writes = (code.match(/g_bkBoxes\[[^\]]+\]\.dir\s*=[^=]/g) || []).length;
      if (f === 'BaseKnot_Measure.mqh' && writes > 2)
        broken.push(`Biotak/${f} writes the side ${writes} times (P-BK-111): the birth (Register/LazyInit) and the price follow are two - a third writer is a second place the market can undo the user's call`);
      if (f === 'BaseKnot_Plan.mqh' && writes > 1)
        broken.push(`Biotak/${f} writes the side ${writes} times (P-BK-111): the story's own write is one - a second writer here is a third path around the lock`);
    }
    const lockSetters = (codeOf(dirLines).match(/g_bkBoxes\[[^\]]+\]\.dirLock\s*=[^=]/g) || []).length;
    if (lockSetters < 1)
      broken.push('nothing sets dirLock any more (P-BK-111): the cell would have no state to keep, and the two follow gates would be dead code');

    // 2 — the cell is a real seat in the DRAW-STRIP's command group, which is where a
    //     side belongs: the quick slots are the served drawing's own properties
    //     (DRAW_SLOT_*, read and written on the object), and a side is not a property of
    //     any drawing. So the four tables that make a seat real must all answer for it —
    //     the id, the raster, the caption and the tap — and the count must include it,
    //     because the layout derives the seats from DSTRIP_ACT_N.
    const dirCode = codeOf(rowsLines);
    const headLines = linesOf(STRIP_HEAD) || [];
    const baseS = linesOf(STRIP_BASE) || [];
    const pickS = linesOf(STRIP_PICK) || [];
    const tapS = linesOf(STRIP_TAP) || [];
    const headCode = codeOf(headLines);
    if (!/#define DSTRIP_ACT_DIR\s+\d+/.test(headCode))
      broken.push('the draw-strip has no DSTRIP_ACT_DIR (P-BK-111): the cell would paint nothing and no tap would reach it - a command with no seat is a comment');
    // EVERY seat must be inside the count, and no two may share a number. Checking only
    // the direction seat was not enough, and the mutation gate proved it: shrinking N by
    // one leaves DSTRIP_ACT_DIR (3) still inside the count and pushes the NEXT seat out -
    // so the check passed while the bin lost its own seat. The law is the whole id set.
    const seats = {};
    for (const m of headCode.matchAll(/#define DSTRIP_ACT_([A-Z]+)\s+(\d+)/g)) seats[m[1]] = Number(m[2]);
    const actN = seats.N;
    if (actN === undefined)
      broken.push('DSTRIP_ACT_N is gone from Biotak/DrawStrip_Head.mqh (P-BK-111): the layout sizes its seat array by the count, so the row has no width without it');
    else {
      const names = Object.keys(seats).filter(k => k !== 'N');
      for (const k of names) {
        if (seats[k] < 0 || seats[k] >= actN)
          broken.push(`the ${k} seat is ${seats[k]} and DSTRIP_ACT_N is ${actN} (P-BK-111): a seat outside the count is never reserved by the layout, never hit-tested and never swept - the strip would paint a row with a hole in it`);
      }
      const seen = {};
      for (const k of names) {
        if (seen[seats[k]] !== undefined)
          broken.push(`${k} and ${seen[seats[k]]} are both seat ${seats[k]} (P-BK-111): two commands on one object name, so one tap answers for the other`);
        seen[seats[k]] = k;
      }
      if (names.length !== actN)
        broken.push(`${names.length} seat(s) are declared and DSTRIP_ACT_N is ${actN} (P-BK-111): the count and the ids are two numbers for one group, and only one of them reserves a row`);
    }
    // 3 - AND THE MIRROR ANSWERS THE SAME COUNT. MEASURED 2026-10-18: the direction
    //     seat raised DSTRIP_ACT_N to 5 while tools/sim-strip-panels.py kept four act
    //     faces, so before-after.py died with an IndexError (sim-strip-panels.py:539)
    //     in the page rebuild at the END of every -Shot run - a green capture reported
    //     as a failed build. The mock indexes its faces by seat: its list is a second
    //     count for the same row, and it is gated like one.
    const simStrip = path.join(ROOT, 'tools', 'sim-strip-panels.py');
    const simSrc = linesOf(simStrip) ? fs.readFileSync(simStrip, 'utf8') : '';
    if (!simSrc)
      broken.push('tools/sim-strip-panels.py is gone (P-BK-111): the before/after page has no middle column');
    else if (typeof actN === 'number') {
      const actList = /DEMO_ACT = \[([^\]]*)\]/.exec(simSrc);
      const onList = /DEMO_ACT_ON = \[([^\]]*)\]/.exec(simSrc);
      const nAct = actList ? (actList[1].match(/\.bmp/g) || []).length : -1;
      const nOn = onList ? (onList[1].match(/\b(?:True|False)\b/g) || []).length : -1;
      if (nAct !== actN)
        broken.push(`tools/sim-strip-panels.py's DEMO_ACT holds ${nAct < 0 ? 'no list' : nAct + ' face(s)'} against DSTRIP_ACT_N=${actN} (P-BK-111): the mock indexes its faces by seat, so before-after.py dies with an IndexError at the end of every -Shot run`);
      if (nOn !== actN)
        broken.push(`tools/sim-strip-panels.py's DEMO_ACT_ON holds ${nOn < 0 ? 'no list' : nOn + ' flag(s)'} against DSTRIP_ACT_N=${actN} (P-BK-111): the demo state is per seat too`);
    }
    const actRes = bodyOf(baseS, 'string DrawStripActRes(');
    if (!actRes || !/bk_dirflip\.bmp/.test(actRes.text))
      broken.push('DrawStripActRes no longer answers a raster for the direction seat (P-BK-111): an empty string paints NO face, and the icon gate reads the same table so it cannot see the loss');
    const actTip = bodyOf(pickS, 'string DrawStripActTip(');
    if (!actTip) {
      broken.push('DrawStripActTip is gone (P-BK-111)');
    } else {
      if (!/DSTRIP_ACT_DIR/.test(actTip.text))
        broken.push('the direction seat has no caption (P-BK-111): the cell would be a mute icon, and the three-state cycle is exactly what a caption has to explain');
      if (!/BaseKnotDirBoxFor/.test(actTip.text))
        broken.push('the caption no longer asks whether the served drawing is a Base Box (P-BK-111): it would promise a side change on a fib, where nothing would happen');
      if (!/let the price/.test(actTip.text))
        broken.push('the caption no longer states how the box goes BACK to the market (P-BK-111): «flip» alone leaves the user guessing that a second click restores it');
    }
    const actTap = bodyOf(tapS, 'bool DrawStripActTap(');
    if (!actTap) {
      broken.push('DrawStripActTap is gone (P-BK-111)');
    } else {
      if (!/BaseKnotFlipDirection/.test(actTap.text))
        broken.push('the direction tap no longer reaches BaseKnotFlipDirection (P-BK-111): the cell would paint, hover and do nothing');
      if (!/BaseKnotSync/.test(actTap.text))
        broken.push('the direction tap no longer rebuilds the box (P-BK-111): the side is a published fact (marker, note caption, family colours), so a flip with no repaint is a flip nobody can see');
      if (!/BaseKnotDirBoxFor/.test(actTap.text))
        broken.push('the direction tap no longer checks what the strip serves (P-BK-111): a press on a fib would reach the knot layer with no box to answer for');
    }
    // AND THE MINI-STRIP MUST NOT HAVE GROWN A SECOND CELL FOR IT. Two strips carrying
    // the same action is two places to learn and two chances to disagree about which box
    // is meant; the user named ONE surface, and the register is where that stays one.
    if (/#define BK_TB_N\s+9\b/.test(dirCode) || /"TBdir"/.test(dirCode))
      broken.push('the Base Box mini-strip carries a second direction cell (P-BK-111): the control lives on ONE surface - the draw-strip the hand is already holding');
    if (/BaseKnotFlipDirection/.test(codeOf(linesOf(PANELS_HIT) || [])))
      broken.push('the Base Box mini-strip press route still reaches BaseKnotFlipDirection (P-BK-111): a second press site is a second place that can flip a side');
    // the bake must agree with the card the mini-strip actually has - read off the disk,
    // because the generator's literal and the raster are two files (see the bake check).
    const bake = path.join(ROOT, 'Files', 'Icons', 'bk_strip.bmp');
    const margin = /#define PNL_MARGIN\s+(\d+)/.exec(metrics);
    const tbW = /#define PNL_TB_W\s+(\d+)/.exec(metrics);
    try {
      const w = fs.readFileSync(bake).readInt32LE(18);
      if (tbW && margin) {
        const want = Number(tbW[1]) + 2 * Number(margin[1]);
        if (w !== want)
          broken.push(`bk_strip.bmp on disk is ${w}px wide and the card needs ${want}px (PNL_TB_W ${tbW[1]} + 2x PNL_MARGIN ${margin[1]}) - a width was changed and the backdrop was never re-baked: run \`node tools/gen-th3-icons.js\`. The generator's literal and the raster are two files, and only one of them is what the terminal draws`);
      }
    } catch (e) {
      broken.push('Files/Icons/bk_strip.bmp could not be read - the strip backdrop must be measured, not assumed');
    }

    // 4 — the witness is flushed, pumped, and carries a read-back.
    const dw = bodyOf(witLines, 'void BaseKnotDirWitness(');
    if (!dw) {
      broken.push('BaseKnotDirWitness is gone from Biotak/BaseKnot_Witness.mqh (P-BK-111): the flip would answer nothing at all');
    } else {
      if (!/DrawStripDiagEmit/.test(dw.text))
        broken.push('the flip\'s witness no longer goes through DrawStripDiagEmit (P-BK-111): a Print witness sits in MT4\'s RAM buffer and reads as «nothing happened» (P-DRAW-126)');
      if (!/\[P-BK-111\]/.test(dw.text))
        broken.push('the flip\'s witness lost its [P-BK-111] tag (P-BK-111): a flushed line nobody can grep is not a witness');
      for (const f of ['was=', 'now=', 'lock=', 'read=', 'gv=']) {
        if (dw.text.indexOf(f) < 0)
          broken.push(`the flip's witness no longer prints ${f} (P-BK-111): «کلیک کردم هیچی نشد» is unprovable without the read-back`);
      }
      // THE READ-BACK MUST READ THE BOX, NOT THE WRITE. Printing the field's name is not
      // enough: a witness that prints `now` — the value the flip just computed — is a
      // transcript of the intention, and it would print «SELL» for a side the follow undid
      // 400 ms later. This is the P-DRAW-125a lesson (a writer discarding its own return)
      // applied to a witness.
      if (!/" read=" \+ \(k < 0 \? "gone" : \(g_bkBoxes\[k\]\.dir/.test(dw.text))
        broken.push('the flip\'s witness prints the WRITE instead of reading the BOX back (P-BK-111): it would report the side the flip intended, and stay green while the follow undid it - a witness with no eyes is a transcript');
    }
    const dirBody = codeOf(dirLines);
    if (!/BaseKnotDirFlipNote\(/.test(dirBody))
      broken.push('the flip no longer records for the witness (P-BK-111): the read-back would have nothing to report');
    if (!/GlobalVariableSet\(BaseKnotGVTwin\(id\)/.test(dirBody))
      broken.push('the flip no longer writes the side\'s TWIN GV (P-BK-111): the user\'s own call would not survive the restart that the side itself survives');
    if (!/BaseKnotDirBoxFor/.test(dirBody))
      broken.push('the served object\'s box is no longer resolvable (P-BK-111): the draw-strip serves an object by NAME, and without this the cell cannot tell a Base Box from a fib');
    if (!/BaseKnotDirWitness\(\)/.test(codeOf(linesOf(path.join(BIOTAK, 'EventHandlers_Objects.mqh')) || [])))
      broken.push('the pump no longer calls BaseKnotDirWitness (P-BK-111): the flip would record into a ring nobody reads - a witness channel with no reader is silence');
    if (broken.length) {
      failures.push('P-BK-111: ' + broken.join('; ') + ' (Biotak/BaseKnot_Direction.mqh + BaseKnot_Measure.mqh + DrawStrip_Head/Base/Pick/Tap.mqh + BiotakPanels_Rows/Hit.mqh + CardMetrics.mqh + tools/gen-th3-icons.js)');
    } else {
      console.log('[PASS] P-BK-111 the side is the user\'s to turn: the follow yields to the lock, the draw-strip\'s command group carries the cell (raster + caption + tap + count, one surface only), and the flip is witnessed flushed with a read-back');
    }
  }

  // ── P-UI-144 (2026-10-13) — THE GHOST SWEEP: NO SURFACE COMES BACK TWICE ──
  // «پنل‌ها، لوگو و منوها بعد از ری‌استارت ترمینال یا بستن و باز کردن پنجره از جاش
  // تکون میخوره، روی هم میافته». MEASURED, not guessed: the live terminal's
  // `profiles/default/chart03.chr` (DXY H4, written 2026-10-12 15:58:11) holds
  // `object_name=BiotakMenuV2_134342075006101685_CircOrbBg` at x_distance=70
  // y_distance=79 — a chart id from a session that no longer exists. Every
  // object this family paints carries `BiotakMenuV2_<ChartID>` and a chart id is
  // per session, so MT4's own profile restore puts the previous session's names
  // back on the chart at their stale ABSOLUTE pixels, where no purge of the live
  // prefix can reach them: the surface stands in a different relative place
  // (the «از جاش تکون میخوره»), beside the fresh one the home paints (the «روی
  // هم افتاده»), and it re-saves itself on every close. ONE prefix walk per
  // attach — the exact shape `DrawStripSweepStale` took for the strip family,
  // which never carried a chart id and is therefore immune. Asserted: the owner
  // exists, it covers BOTH spellings the family ever painted, and
  // `InitializeUIStates` — the one init path every attach, TF switch and re-add
  // goes through — actually CALLS it (P-DRAW-120's lesson: an owner without a
  // caller is a rule nobody delivers).
  {
    const broken = [];
    const homes = codeOf(linesOf(path.join(BIOTAK, 'BiotakHomes.mqh')) || []);
    if (!/void BiotakMenuGhostSweep\(\)/.test(homes))
      broken.push('BiotakMenuGhostSweep() is gone from Biotak/BiotakHomes.mqh — a foreign-chart-id ghost has no owner again (P-UI-144)');
    else {
      if (!/ObjectsDeleteAll\(0, "BiotakMenuV2_"/.test(homes))
        broken.push('the sweep lost the V2 spelling — every live object name starts with it (P-UI-144)');
      if (!/ObjectsDeleteAll\(0, "BiotakMenu_"/.test(homes))
        broken.push('the sweep lost the V1 spelling — an older build\u2019s ghost survives the sweep again (P-UI-144)');
    }
    const init = bodyOf(linesOf(MENU_A) || [], 'void InitializeUIStates()');
    if (!init || !/BiotakMenuGhostSweep\(\);/.test(init.text))
      broken.push('InitializeUIStates() does not CALL the sweep — the owner exists and nobody runs it, the exact P-DRAW-120 failure (P-UI-144)');
    if (broken.length) {
      failures.push('P-UI-144: ' + broken.join('; ') + ' (Biotak/BiotakHomes.mqh + BiotakMenu_A.mqh InitializeUIStates)');
    } else {
      console.log('[PASS] P-UI-144 the ghost sweep exists, covers both name spellings, and is called from the one init path every attach runs (Biotak/BiotakHomes.mqh + BiotakMenu_A.mqh)');
    }
  }
  // ── P-UI-142b (2026-10-18) — THE TOOLS CHROME DOES NOT SURVIVE AN ATTACH ──
  // «گاهی اوقات ... با اینکه منو اصلی بسته هستش» + the screenshot: a light tools
  // column (sub_panel_r<N>.bmp + one page of cells) standing WITH the orb while no
  // ring is drawn anywhere. That is the P-UI-142 snapshot doing its job too well: a
  // restart landing while the Tools page was open re-created the chrome at the next
  // init, and by law the ring stays suppressed behind an open Tools submenu — so
  // the user reads the menu as closed while the page floats. The MEN snapshot keeps
  // restoring the ring; the tools page is a momentary view opened from the ring's
  // door, and it starts shut at EVERY attach. Asserted: LoadUIState shuts it with a
  // LITERAL false (never a snapshot read) and the suppressed restore is witnessed
  // on the flushed channel (P-LOG-3), so the next report of the column is decidable
  // from the diag alone. The inverse mutation must fail THIS gate
  // (tools/mutation_gate.py, P-UI-142b).
  {
    const broken = [];
    const load = bodyOf(linesOf(MENU_A) || [], 'void LoadUIState()');
    if (!load)
      broken.push('LoadUIState() is gone from Biotak/BiotakMenu_A.mqh (P-UI-142b)');
    else {
      if (!/g_ToolsOpen\s*=\s*false;/.test(load.text))
        broken.push('LoadUIState no longer shuts the tools chrome with a literal false — an attach can paint the page under a closed menu (P-UI-142b)');
      if (!load.text.includes('[P-UI-142] tools chrome starts shut'))
        broken.push('the suppressed-restore witness is gone from LoadUIState — a floating tools page is unprovable from the diag (P-UI-142b)');
    }
    if (broken.length) {
      failures.push('P-UI-142b: ' + broken.join('; ') + ' (Biotak/BiotakMenu_A.mqh LoadUIState)');
    } else {
      console.log('[PASS] P-UI-142b the tools chrome starts shut at every attach (a literal, never the snapshot), and the suppressed restore is witnessed on the flushed channel');
    }
  }

  // ── P-UI-145 (2026-10-13) — NO UI CONTROL MAY BE DRAGGED OFF ITS SEAT ──
  // «ممکن است به‌اشتباه درگ شده … روی هم افتاده». The project's own measured law
  // (P-UI-48 / P-BK-15, BaseKnot_Base.mqh:848) says `OBJPROP_SELECTABLE` IS the
  // drag: MT4 grabs a selectable object on the press that lands on it, and a
  // selected object rides every later drag (the hijack). Every card and palette
  // control is born selectable for the name router, so a hand that travels 3–10
  // px — below the card's own PNL_DRAG_CTRL_PX proof — native-drags the BUTTON
  // itself, and the displaced control then rides the chart profile into the next
  // session as a ghost at its dragged absolute pixels. The seat registry is the
  // answer: filled by the ONE factory (`PnlSetButton`), kept in lockstep by the
  // one mover (`PnlMoveOne`), spent by the terminal's own OBJECT_DRAG channel,
  // and forgotten per family at teardown. Asserted: the registry, the remember
  // at the paint, the revert at the drag (scoped to our family, sparing the
  // mixer knobs that ARE the drag), the lockstep, and the forget.
  {
    const broken = [];
    const apply = codeOf(linesOf(APPLY) || []);
    const life = codeOf(linesOf(path.join(BIOTAK, 'BiotakPanels_Life.mqh')) || []);
    const build = codeOf(linesOf(path.join(BIOTAK, 'BiotakPanels_Build.mqh')) || []);
    if (!/void PnlSeatRemember\(/.test(apply))
      broken.push('the seat registry is gone from Biotak/BiotakPanels_Apply.mqh — a natively dragged control has no memory to return to (P-UI-145)');
    if (!/bool PnlSeatRevert\(/.test(apply))
      broken.push('PnlSeatRevert() is gone — the revert write has no owner (P-UI-145)');
    const btn = bodyOf(linesOf(APPLY) || [], 'void PnlSetButton(');
    if (!btn || !/PnlSeatRemember\(n, x, y\);/.test(btn.text))
      broken.push('PnlSetButton() no longer remembers the seat it writes — a registry filled anywhere else is a second grid (P-UI-145)');
    if (!/PnlSeatRevert\(sparam\)/.test(life))
      broken.push('the OBJECT_DRAG branch does not revert our own control — MT4 grabs a selectable object on the press and the button stays crooked (P-UI-145)');
    if (!/StringFind\(sparam, g_UI\.btnPrefix\) == 0/.test(life))
      broken.push('the revert is not scoped to our family — it would fight the mixer knobs and the hand-set lines (P-UI-145)');
    if (!/StringFind\(sparam, "mknb"\) < 0/.test(life))
      broken.push('the mixer knobs are not spared — the palette\u2019s own drag would be reverted (P-UI-145)');
    const move = bodyOf(linesOf(path.join(BIOTAK, 'BiotakPanels_Hit.mqh')) || [], 'void PnlMoveOne(');
    if (!move || !/PnlSeatRemember\(/.test(move.text))
      broken.push('PnlMoveOne() does not keep the registry in lockstep — a card carry would re-seat a revert to the pre-drag place (P-UI-145)');
    if (!/PnlSeatForget\(head\)/.test(build))
      broken.push('PnlDestroy() does not forget the card\u2019s seats — the registry fills with dead names and stops reverting the live ones (P-UI-145)');
    if (broken.length) {
      failures.push('P-UI-145: ' + broken.join('; ') + ' (Biotak/BiotakPanels_Apply.mqh PnlSetButton + Hit.mqh PnlMoveOne + Build.mqh PnlDestroy + Life.mqh OBJECT_DRAG)');
    } else {
      console.log('[PASS] P-UI-145 a natively dragged control is reverted to the seat the paint itself wrote, the registry rides the carry, and the knobs keep their drag (Biotak/BiotakPanels_Apply.mqh + Life.mqh)');
    }
  }

  // ── P-UI-146 (2026-10-13) — THE STRIP COMES BACK THE WAY IT WAS LEFT ──
  // «وضعیت باز/بسته بودن همه پنجره‌ها و پنل‌ها در هر اجرای مجدد دقیقاً بازیابی
  // شده». The panels had a snapshot/restore since P-UI-142 and the strip — the
  // one surface the panels' restore never covered — shut at every attach with
  // nothing bringing it back. Five keys per symbol+period (O open · N the served
  // drawing's hash pair · G the gear tab · C its collapse · P the pin), written
  // at teardown START where the live statics are still intact, restored ONCE on
  // the first tick after a FRESH attach under PnlRestoreSaved's own gate. The
  // name rides as a double (a GV is a double) through ONE encoding in the
  // strip's own state file, and a match is verified with DrawKindOf before
  // anything opens. The gear tab is re-opened through the strip's OWN door —
  // a repaint from outside the strip is a REQUEST the bridge spends
  // (P-PAL-19f/P-PAL-20). And the ratchet half: the home is the hand's place, so
  // the clamp may never write back into it (the P-UI-131e law said in fractions,
  // docs/th3-ui-placement.md's "not yet covered" for the strip).
  {
    const broken = [];
    const lifeLines = linesOf(path.join(BIOTAK, 'BiotakPanels_Life.mqh')) || [];
    const life = codeOf(lifeLines);
    const head = codeOf(linesOf(STRIP_HEAD) || []);
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    const snap = bodyOf(lifeLines, 'void SnapshotOpenSurfaces()');
    if (!snap || !/DSNamePack\(s_dsObj\)/.test(snap.text))
      broken.push('SnapshotOpenSurfaces() no longer records the strip\u2019s served drawing — the identity rides the record as a hash pair (P-UI-146)');
    for (const k of ['sfx + "O"', 'sfx + "G"', 'sfx + "C"', 'sfx + "P"'])
      if (!snap || snap.text.indexOf('GetGVName(' + k + ')') < 0)
        broken.push(`the strip state lost its ${k} key (P-UI-146)`);
    if (!/void DrawStripStateRestore\(\)/.test(life))
      broken.push('DrawStripStateRestore() is gone — the strip reopens nothing (P-UI-146)');
    const kit = bodyOf(lifeLines, 'void RefreshKitOnBar()');
    if (!kit || !/DrawStripStateRestore\(\);/.test(kit.text))
      broken.push('RefreshKitOnBar() does not call the restore — an owner without a caller is a rule nobody delivers (P-UI-146)');
    const rest = bodyOf(lifeLines, 'void DrawStripStateRestore()');
    if (!rest || !/DSNameMatches\(want, nm\)/.test(rest.text))
      broken.push('the restore does not MATCH the served drawing by its hash pair — a target the user deleted would be guessed (P-UI-146)');
    else if (!/DrawKindOf\(nm\) == DK_NONE/.test(rest.text))
      broken.push('the restore does not verify the match with DrawKindOf — a hash hit alone is not a drawing (P-UI-146)');
    if (!/void DrawStripGearRestoreTab\(/.test(tap))
      broken.push('DrawStripGearRestoreTab() is gone from Biotak/DrawStrip_Tap.mqh — the gear tab would be repainted from outside the strip (P-PAL-19f/P-UI-146)');
    if (!/double DSNamePack\(/.test(head) || !/bool DSNameMatches\(/.test(head))
      broken.push('the identity encoding is gone from Biotak/DrawStrip_Head.mqh — the strip\u2019s state has no single spelling (P-UI-146)');
    const clamp = bodyOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || [], 'void DrawStripHomeClamp()');
    if (!clamp || /s_dsHomeX = nx/.test(clamp.text))
      broken.push('DrawStripHomeClamp() writes the clamped pair back into the home — the P-UI-131e ratchet is back for the strip (P-UI-146)');
    const open = bodyOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || [], 'bool DrawStripOpenAt(');
    // P-UI-157 strengthened this from "only on the fresh placement" to "only on the fresh
    // placement AND only from a measured window" — so the check counts the writes as well
    // as pinning their guard: a second, unguarded `DrawStripHomeSet` is the regression the
    // old exact-text test could not see.
    const homeSets = open ? (open.text.match(/DrawStripHomeSet\s*\(/g) || []).length : 0;
    if (!open || homeSets !== 1 ||
        !/if\(dsFreshHome\s*&&\s*dsBox\)\s*\{[^}]*DrawStripHomeSet\(s_dsX, s_dsY\);/.test(open.text))
      broken.push('DrawStripOpenAt() must set the home EXACTLY ONCE, only on the fresh placement and only from a measured window — a clamped open rewrites the hand\u2019s place (P-UI-146/P-UI-157)');
    if (broken.length) {
      failures.push('P-UI-146: ' + broken.join('; ') + ' (Biotak/BiotakPanels_Life.mqh SnapshotOpenSurfaces + DrawStrip_Head/Tap/Paint.mqh)');
    } else {
      console.log('[PASS] P-UI-146 the strip\u2019s open state, served drawing, gear tab and pin are recorded at teardown and restored once on a fresh attach, and the home never stores the clamp');
    }
  }

  // ── P-UI-145c (2026-10-13) — A DEAD FAMILY HANDS ITS SLOT BACK ──
  // P-UI-145 gave every card and palette control a seat registry so a native drag
  // is undone in the same event. It bounded the registry with `PNL_SEAT_MAX` and
  // its comment justified the ceiling with a CONCURRENT count ("one card + one
  // palette cannot reach 192") — but the counter only ever grew: `PnlSeatForget`
  // blanked the NAME and kept the entry, and its only caller was the CARD teardown,
  // so the palette never released anything either. The bound was therefore on the
  // number of DISTINCT NAMES ever painted in one indicator lifetime, and one card
  // with 24 rows teaches more than a hundred of them. Two cards reached 192 and from
  // then on `PnlSeatRemember` returned early for EVERY later control: the protection
  // died silently, in a fix whose whole point was to stop a silent displacement.
  {
    const broken = [];
    const applyLines = linesOf(APPLY) || [];
    const apply = codeOf(applyLines);
    const forget = bodyOf(applyLines, 'void PnlSeatForget(const string prefix)');
    if (!forget) {
      broken.push('PnlSeatForget() is gone — a dead family never releases its slots (P-UI-145c)');
    } else {
      if (!/s_pnlSeatN = w;/.test(forget.text))
        broken.push('PnlSeatForget() no longer DECREMENTS the counter — the ceiling bounds every name ever painted instead of the live controls, and the registry dies silently (P-UI-145c)');
      if (!/s_pnlSeatNm\[w\] = s_pnlSeatNm\[i\];/.test(forget.text))
        broken.push('PnlSeatForget() blanks the name instead of compacting the tail — the slot is kept forever (P-UI-145c)');
    }
    if (!/s_pnlSeatFullSaid/.test(apply))
      broken.push('the FULL registry is silent again — a control past the ceiling loses its revert with nothing said (P-UI-145c)');
    const palClose = bodyOf(linesOf(PAL_A) || [], 'void PalClose()');
    if (!palClose || !/PnlSeatForget\(g_UI\.btnPrefix\+"Pal_"\);/.test(palClose.text))
      broken.push('PalClose() does not release the popup\u2019s seats — every open left its ~44 entries permanently dead in the registry (P-UI-145c)');
    if (broken.length) {
      failures.push('P-UI-145c: ' + broken.join('; ') + ' (Biotak/BiotakPanels_Apply.mqh PnlSeatForget + PalA.mqh PalClose)');
    } else {
      console.log('[PASS] P-UI-145c a dead family hands its slots back: the registry is bounded by the LIVE controls, not by every name ever painted, and a FULL one says so');
    }
  }

  // ── P-UI-149 (2026-10-13) — A GATE NOBODY RUNS IS A RULE NOBODY KEEPS ──
  // `tools/skin_metrics_check.js` and `tools/ui_parity_audit.py` were both written,
  // both correct in intent, and both absent from `compile-th3.ps1` AND from
  // AGENTS.md's build list — so neither ran in any build and nothing noticed that
  // both had gone blind in the meantime:
  //   * the skin gate scanned the generator with a `const`-only regex while
  //     `DS_CAP` had become a `let`, and read the runtime with a digits-only regex
  //     while `DSTRIP_SKIN_M` had become the alias `PNL_MARGIN`. It reported two
  //     defects that did not exist, and would have reported nothing if the bake and
  //     the crop had really drifted.
  //   * the parity gate resolved the panel side through `DrawStrip.mqh` alone, but
  //     the strip's chrome is deliberately an ALIAS of the cards' constants
  //     (P-DRAW-116) and `PNL_*` lives in `CardMetrics.mqh`, which is not in that
  //     include chain — so five seats came back `None`, and an unmeasured seat prints
  //     exactly like an agreeing one (the P-DRAW-120 class).
  // Both are wired now, and this entry keeps them wired AND keeps their readers able
  // to see their own constants: a gate that cannot read its input is not a gate.
  {
    const broken = [];
    const ps1 = linesOf(BUILD_PS1);
    if (!ps1) {
      broken.push('compile-th3.ps1 is missing (the build is the only entry point)');
    } else {
      for (const tool of ['skin_metrics_check.js', 'ui_parity_audit.py'])
        if (indexOfLine(ps1, tool) < 0)
          broken.push(`the build does not run \`${tool}\` — re-add it to compile-th3.ps1 (or delete this entry and say so in the report) (P-UI-149)`);
    }
    const agentsTxt = fs.existsSync(path.join(ROOT, 'AGENTS.md')) ? fs.readFileSync(path.join(ROOT, 'AGENTS.md'), 'utf8') : '';
    for (const tool of ['skin_metrics_check.js', 'ui_parity_audit.py'])
      if (agentsTxt.indexOf(tool) < 0)
        broken.push(`AGENTS.md's build list does not name \`${tool}\` (P-UI-149)`);

    const skinTxt = fs.readFileSync(path.join(ROOT, 'tools', 'skin_metrics_check.js'), 'utf8');
    if (!/\(\?:const\|let\)/.test(skinTxt))
      broken.push('the skin gate scans the generator for `const` only — a `let` declaration (DS_CAP) is invisible to it and the corner cap goes ungated (P-UI-149)');
    if (!/\[\^\\r\\n\]\+/.test(skinTxt))
      broken.push('the skin gate\u2019s #define reader has a `$` anchor again — every file here is CRLF, JS `.` matches neither `\\n` nor `\\r`, and `$` will not match before a trailing `\\r`, so the reader comes back EMPTY and the gate reports a defect that does not exist (P-UI-149)');

    const parityTxt = fs.readFileSync(path.join(ROOT, 'tools', 'ui_parity_audit.py'), 'utf8');
    if (!/define\(CARD, name\)/.test(parityTxt) || !/define\(CARD, ident\)/.test(parityTxt))
      broken.push('the parity gate cannot resolve the strip\u2019s aliases — `DSTRIP_GEAR_*` IS `PNL_*` (P-DRAW-116) and its home `CardMetrics.mqh` is not in the strip\u2019s include chain, so the panel side reads `None` and the seat is never compared (P-UI-149)');

    if (broken.length) {
      failures.push('P-UI-149: ' + broken.join('; ') + ' (compile-th3.ps1 + AGENTS.md + tools/skin_metrics_check.js + tools/ui_parity_audit.py)');
    } else {
      console.log('[PASS] P-UI-149 the skin and parity gates are run by every build, and both can read their own constants (a `let` in the generator, a CRLF line, an alias into the cards\u2019 unit)');
    }
  }

  // ── P-BE-03 / P-BE-04 (2026-10-13) — DEAD CODE IS A DEFECT, AND ONE FACTOR HAS
  // ── ONE OWNER ──
  // `CalculateShortStep`, `CalculateLongStep` and `CalculateSharedPatternStep` were
  // defined in `THCalculations.mqh` and called from nowhere in the whole tree. They
  // compiled clean, because MQL does not warn on an unused non-static function.
  //   * `CalculateShortStep` returned `thValue * SS_MULTIPLIER` while the LIVE
  //     SS_LS_STEP path in `Util_A.mqh` wrote `structureValue * 1.5` inline — two
  //     owners for one factor, and the one carrying the owner's NAME was the one
  //     nobody called.
  //   * `CalculateSharedPatternStep` returned `(2 * SS) - P` under a name that
  //     promises a *step*; the live pattern step is `TH3PatternStepRungTF`. A reader
  //     who trusted the name would have wired the wrong formula.
  // This project already treats "compiles and is dead" as a defect (the two halves
  // checked at :2890 and the `dirLock` rule at :3692), so the trio is gone and the
  // live SS factor reads the constant. P-UI-153's own `DSTRIP_GEAR_PAD` check below
  // exists because a spliced edit can DELETE a define and still look right.
  {
    const broken = [];
    const thCalc = fs.readFileSync(path.join(ROOT, 'Biotak', 'THCalculations.mqh'), 'utf8');
    for (const dead of ['CalculateShortStep', 'CalculateLongStep', 'CalculateSharedPatternStep'])
      if (thCalc.indexOf('double ' + dead) >= 0)
        broken.push(`\`${dead}\` is back in THCalculations.mqh — it has no caller in the tree, and \`CalculateSharedPatternStep\` promises a *step* while returning a pattern value (P-BE-03)`);

    const utilA = fs.readFileSync(path.join(ROOT, 'Biotak', 'Util_A.mqh'), 'utf8');
    if (utilA.indexOf('structureValue * SS_MULTIPLIER') < 0)
      broken.push('Util_A.mqh\u2019s SS_LS_STEP no longer reads `SS_MULTIPLIER` — the live factor lost its owner in MathConstants.mqh (P-BE-04)');
    if (utilA.indexOf('structureValue * 1.5') >= 0)
      broken.push('Util_A.mqh\u2019s SS_LS_STEP is the bare literal `1.5` again — two owners for one factor, and a retune stops at one of them (P-BE-04)');

    if (broken.length) {
      failures.push('P-BE-03/P-BE-04: ' + broken.join('; ') + ' (Biotak/THCalculations.mqh + Biotak/Util_A.mqh)');
    } else {
      console.log('[PASS] P-BE-03/P-BE-04 the dead trio stays deleted, and the live SS factor reads its one owner (SS_MULTIPLIER, not a bare 1.5)');
    }
  }

  // ── P-UI-152 (2026-10-13) — THE MIXER'S TRACK, ONE OWNER ──
  // `trackX = g_PalX + PAL_PAD + 30` / `trackW = PalW() - 2*PAL_PAD - 34` was written
  // out FOUR times — the paint, the live knob move and both mixer readers — while the
  // footer's track right above it already had `PalTrX()`/`PalTrW()` and a P-DRAW-49
  // note saying why. Two owners that agree today are one retune away from a press
  // landing on a track the paint no longer draws.
  {
    const broken = [];
    const palA = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakPanels_PalA.mqh'), 'utf8');
    const palB = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakPanels_PalB.mqh'), 'utf8');
    if (!/int PalMixTrackX\(\)/.test(palA) || !/int PalMixTrackW\(\)/.test(palA))
      broken.push('the mixer track has no owner — `PalMixTrackX()`/`PalMixTrackW()` are gone from BiotakPanels_PalA.mqh (P-UI-152)');
    const both = palA + palB;
    // Comments are stripped first: the P-UI-152 note QUOTES the old expression on
    // purpose, and a quoted literal is not a second owner. What must not come back is
    // the number next to PAL_PAD in CODE — however the receiver is spelled. The first
    // version of this check looked for `g_PalX+PAL_PAD+30` alone, and a mutation that
    // wrote `px+PAL_PAD+30` slipped past it: the rule died on the reader count while
    // the literal it exists to forbid was sitting right there (the P-DRAW-120 class).
    const codeOnly = both.split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');
    const lits = codeOnly.match(/PAL_PAD\s*[+\-]\s*(?:30|34)\b/g) || [];
    if (lits.length)
      broken.push(`the mixer track is a literal again (${lits.length}: ${lits.join(', ')}) — the paint and its four readers must read ONE owner (P-UI-152)`);
    const reads = both.split('PalMixTrackX()').length - 1;
    if (reads < 5)
      broken.push(`only ${reads} reader(s) of \`PalMixTrackX()\` — the paint plus the three live readers is 5 (definition + 4 sites) (P-UI-152)`);

    if (broken.length) {
      failures.push('P-UI-152: ' + broken.join('; ') + ' (Biotak/BiotakPanels_PalA.mqh PalMixTrackX/W + BiotakPanels_PalB.mqh)');
    } else {
      console.log('[PASS] P-UI-152 the mixer track has one owner: the paint and all four readers call PalMixTrackX()/PalMixTrackW(), and no literal copy of the old expression is left');
    }
  }

  // ── P-UI-153 (2026-10-13) — THE GEAR CLOSE SEAT, ONE OWNER ──
  // The 26 was written three times — the paint (`DrawStrip_GearB.mqh`), the hit test
  // (`DrawStrip_Base.mqh`) and the carry's own stop (`DrawStrip_Tap.mqh`). The parity
  // gate already asserted the VALUE matched the cards' `PNL_XBTN_VIS`, but a
  // value-to-literal comparison can only report drift after it has happened; the seat
  // now compares name-to-name. The `DSTRIP_GEAR_PAD` check is deliberate: a spliced
  // edit that replaces the anchor line instead of inserting after it DELETES the
  // define, the "side pad" seat then reads `None`, and that is exactly how this rule
  // was caught while it was being written.
  {
    const broken = [];
    const headTxt = fs.readFileSync(path.join(ROOT, 'Biotak', 'DrawStrip_Head.mqh'), 'utf8');
    const gearB = fs.readFileSync(path.join(ROOT, 'Biotak', 'DrawStrip_GearB.mqh'), 'utf8');
    const baseTxt = fs.readFileSync(path.join(ROOT, 'Biotak', 'DrawStrip_Base.mqh'), 'utf8');
    const tapTxt = fs.readFileSync(path.join(ROOT, 'Biotak', 'DrawStrip_Tap.mqh'), 'utf8');
    if (!/#define\s+DSTRIP_GEAR_XW\s+26/.test(headTxt))
      broken.push('the gear close seat has no name — `#define DSTRIP_GEAR_XW 26` is gone from DrawStrip_Head.mqh (P-UI-153)');
    if (!/#define\s+DSTRIP_GEAR_PAD\s/.test(headTxt))
      broken.push('DrawStrip_Head.mqh lost `#define DSTRIP_GEAR_PAD` — the parity gate\u2019s "side pad" seat reads it and every column depends on it (P-UI-153)');
    if (gearB.indexOf('- DSTRIP_GEAR_PAD - 26;') >= 0 ||
        baseTxt.indexOf('const int xbtn = 26') >= 0 ||
        tapTxt.indexOf('- DSTRIP_GEAR_PAD - 26 - DSTRIP_GEAR_PAD') >= 0)
      broken.push('a gear-close site writes the bare `26` again — the paint, the hit test and the carry must all read the one name (P-UI-153)');
    const parityTxt2 = fs.readFileSync(path.join(ROOT, 'tools', 'ui_parity_audit.py'), 'utf8');
    if (parityTxt2.indexOf('"DSTRIP_GEAR_XW"') < 0)
      broken.push('the parity gate compares the close seat as a literal again — a number against a name can only report drift after it has happened (P-UI-153)');

    if (broken.length) {
      failures.push('P-UI-153: ' + broken.join('; ') + ' (DrawStrip_Head/GearB/Base/Tap + tools/ui_parity_audit.py)');
    } else {
      console.log('[PASS] P-UI-153 the gear close seat has one owner: paint, hit test and carry read `DSTRIP_GEAR_XW`, and the parity gate compares that name against the cards\u2019 `PNL_XBTN_VIS`');
    }
  }

  // ── P-PERF-40 (2026-10-13) — THE CENSUS'S BOUND IS ON EVENTS, NEVER ON RATE ──
  // MEASURED on the live journal: one day held 22,281 lines and 17,547 of them (79%)
  // were `[gest]`, at up to 160 lines in ONE SECOND and 634 in ten. The census's own
  // note claimed it was «bounded by design» — but that bound is on WHICH events pass,
  // never on HOW MANY per second, so a single press re-armed three seconds of one
  // flushed line per mouse-move. Each line is a `Print()` (journal write) PLUS a
  // `FileWrite` + `FileFlush` on the per-chart diag file, on the chart thread, during
  // the user's own gesture — the exact cost P-LOG-3 already ruled on in
  // `BuildConfig.mqh:28-36`.
  // The census keeps its standing rule (`DSTRIP_DIAG` stays 1, contract.md:321) and
  // gains a RATE bound. This entry locks BOTH halves: the bound exists, and it sits
  // BELOW the drag/create edge, because a coalesced discriminator cannot answer the
  // order question it was built for.
  {
    const broken = [];
    const gv = fs.readFileSync(path.join(ROOT, 'Biotak', 'GlobalVariables.mqh'), 'utf8');
    if (!/#define\s+GEST_CENSUS_MIN_MS\s+\d+/.test(gv))
      broken.push('the gesture census has no rate bound — `GEST_CENSUS_MIN_MS` is gone, so one press re-arms three seconds of one flushed line per mouse-move (P-PERF-40)');
    const edgeAt = gv.indexOf('if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CREATE) return true;');
    const rateAt = gv.indexOf('>= GEST_CENSUS_MIN_MS');
    if (edgeAt < 0)
      broken.push('the census no longer answers the terminal\u2019s own drag/create unconditionally — that IS the P-UI-142 discriminator, and a rate bound must never swallow it (P-PERF-40)');
    else if (rateAt < 0)
      broken.push('the census\u2019s rate bound is gone from the move path — every mouse-move inside the window prints again (P-PERF-40)');
    else if (rateAt < edgeAt)
      broken.push('the census\u2019s rate bound moved ABOVE the drag/create edge — the discriminator is coalesced, so "before or after our first write" can no longer be read off the frame (P-PERF-40)');
    // The needle carries its own comment on purpose: `g_gestCensusDown = false;` alone
    // also matches the DECLARATION (`static bool g_gestCensusDown = false;`), so the
    // first version of this check passed with the refusal branch deleted — a mutation
    // that removes the clearing survived a rule that exists to keep it (P-PERF-40c).
    if (gv.indexOf('g_gestCensusDown = false;   // a refusal ends the stroke') < 0)
      broken.push('the census\u2019s edge detector is never cleared by a refusal — a stale `true` swallows the next press, and the press edge is the one line the order question needs (P-PERF-40)');

    if (broken.length) {
      failures.push('P-PERF-40: ' + broken.join('; ') + ' (Biotak/GlobalVariables.mqh GestureCensusWanted)');
    } else {
      console.log('[PASS] P-PERF-40 the gesture census keeps its edges and gains a rate bound: drag/create and the press always print, the repeated moves inside a live window coalesce to 10 Hz');
    }
  }

  // -- 43. P-BUILD-12: a relaunch is a claim, so it is checked ----------------
  // ── P-BUILD-12 (2026-10-13) — A RELAUNCH IS A CLAIM, SO IT IS CHECKED ──
  // MEASURED 2026-10-13: `compile-th3.ps1 -Project all -Restart` printed
  // «Terminal restarted» while the terminal's own journal held «stopped» at
  // 15:22:17.888 and NO «started» after it, and `Get-Process terminal` found
  // nothing — yet the build exited 0. The next build then found no terminal to
  // restart, and every chart kept the PREVIOUS ex4 while the report claimed the
  // deploy had landed. `Start-Process` on a GUI app returns as soon as the
  // process object exists, so «we asked» was never «it runs». The caller already
  // turns $false into a failed build (`if (-not (Restart-TradingTerminal))`), so
  // the fix is one honest look at the process table. This entry locks BOTH: the
  // look exists, and the green line sits BELOW it.
  {
    const broken = [];
    const ps = fs.readFileSync(path.join(ROOT, 'compile-th3.ps1'), 'utf8');
    const fnAt = ps.indexOf('function Restart-TradingTerminal');
    if (fnAt < 0) {
      broken.push('the restart deploy is gone from compile-th3.ps1 (P-BUILD-12)');
    } else {
      const checkAt = ps.indexOf('if ($up -lt $want)', fnAt);
      const okAt = ps.indexOf('Terminal restarted (', fnAt);
      if (checkAt < 0)
        broken.push('the relaunch is never verified — `Restart-TradingTerminal` prints «Terminal restarted» without looking for the process, so a launch that never came up still exits 0 and the charts keep the previous ex4 (P-BUILD-12)');
      else if (okAt < 0)
        broken.push('the restart deploy no longer reports success at all (P-BUILD-12)');
      else if (okAt < checkAt)
        broken.push('the green «Terminal restarted» line moved back ABOVE the process check — the claim is printed before it can be wrong (P-BUILD-12)');
      if (ps.indexOf('[FAIL] the relaunch did not come up') < 0)
        broken.push('a failed relaunch no longer says so — a silent failure is what let a stale ex4 pass for a landed deploy (P-BUILD-12)');
    }
    if (broken.length) {
      failures.push('P-BUILD-12: ' + broken.join('; ') + ' (compile-th3.ps1 Restart-TradingTerminal)');
    } else {
      console.log('[PASS] P-BUILD-12 the deploy checks its own claim: `Restart-TradingTerminal` looks for the relaunched process and fails the build if it never came up');
    }
  }

  // -- 44. P-UI-154: every card has a row definition in PnlSetDef --------------
  // ── P-UI-154 (2026-10-13) — EVERY CARD HAS A ROW DEFINITION ──
  // MEASURED: `PnlSetDef` carried a branch for every card EXCEPT 4 (Hover Chip), so
  // the chip's one row fell through to the opening defaults set at the top of that
  // function — `kind=0` (PNL_K_SL, a slider) and `label=""`. The card the user opens
  // to configure the chip therefore showed a NAMELESS 0..100 SLIDER where its single
  // ON/OFF switch belongs. Nothing else could notice: every OTHER path was already
  // right (`PnlCurrent` case 4 reads it, `PnlApply` case 4 writes it and calls
  // `CircTipModeChanged`, `PnlDefValSet` falls through to `return 0` — which IS the
  // shipped default), and in MQL an absent descriptor is not an error at all: it is
  // a row that renders as whatever the defaults happen to be.
  // The card count is READ from its owner (`PNL_COUNT`), never restated here.
  {
    const broken = [];
    const kit = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakKit.mqh'), 'utf8');
    const cnt = /#define\s+PNL_COUNT\s+(\d+)/.exec(kit);
    const palB = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakPanels_PalB.mqh'), 'utf8');
    const fnAt = palB.indexOf('void PnlSetDef(');
    if (!cnt)
      broken.push('`#define PNL_COUNT` is gone from BiotakKit.mqh — the card count has no owner (P-UI-154)');
    else if (fnAt < 0)
      broken.push('`PnlSetDef` is gone from BiotakPanels_PalB.mqh — no card has a row definition any more (P-UI-154)');
    else {
      const body = palB.slice(fnAt, palB.indexOf('\n}', fnAt));
      // comments are stripped: a branch SPELLED in prose is not a branch, and the
      // project has already paid for that lesson once (see the note above item==3).
      const codeOnly = body.split('\n').map(l => l.replace(/\/\/.*$/, '')).join('\n');
      const have = new Set();
      const re = /item\s*==\s*(\d+)/g;
      let m;
      while ((m = re.exec(codeOnly)) !== null) have.add(Number(m[1]));
      const n = Number(cnt[1]);
      const missing = [];
      for (let i = 0; i < n; i++) if (!have.has(i)) missing.push(i);
      if (missing.length)
        broken.push('card(s) ' + missing.join(', ') + ' have no branch in `PnlSetDef` — their rows fall through to that function\u2019s opening defaults (`kind=0` slider, `label=""`), so the card renders a nameless slider instead of its own control (P-UI-154)');
    }
    if (broken.length) {
      failures.push('P-UI-154: ' + broken.join('; ') + ' (Biotak/BiotakPanels_PalB.mqh PnlSetDef)');
    } else {
      console.log('[PASS] P-UI-154 every card has its own row definition: `PnlSetDef` answers for all ' + cnt[1] + ' cards, so no card renders on the opening defaults');
    }
  }

  // -- 45. P-UI-156: a home reader refuses an unmeasured box -------------------
  // ── P-UI-156 (2026-10-13) — A READER WITH NO BOX DERIVES NOTHING ──
  // The reader used to fall back to 1920x1080 whenever the terminal reported 0 for the
  // chart box — which it does at attach and during a CHART_CHANGE. That fallback is a
  // denominator the pixels did not come from, so the pair it produced was not a place;
  // it was the same place said with the wrong divisor. `CircHomesRefresh` handed that
  // pair to the in-memory HOME and the next `SaveUIStates` persisted it against the REAL
  // box. The writer has always refused this (`HomeChartSizeRaw`); the reader had no such
  // rule, and THAT ASYMMETRY was the ratchet. MEASURED and still in the store:
  // `BIOMENU_HOME_STRIP_FX` = 1.000000 exactly (a saturated out-of-box value), with
  // `CHIP_FX = 1.1075` and `ORB_FY = 1.613` recorded on 2026-10-05.
  {
    const broken = [];
    const homes = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakHomes.mqh'), 'utf8');
    const readAt = homes.indexOf('bool GVHomeFracRead(');
    const saveAt = homes.indexOf('void GVHomeSaveFrac(');
    if (readAt < 0) {
      broken.push('`GVHomeFracRead` is gone from BiotakHomes.mqh (P-UI-156)');
    } else {
      const readBody = homes.slice(readAt, homes.indexOf('\n}', readAt));
      if (readBody.indexOf('HomeChartSizeRaw(cw, ch)') < 0)
        broken.push('the reader invents a denominator again — `GVHomeFracRead` derives pixels from a box it never measured, so a read at attach hands the WRITER a pair from the wrong window and the store ratchets (P-UI-156)');
      if (/HomeChartSize\s*\(/.test(readBody))
        broken.push('the reader falls back to the 1920x1080 box again — that fallback IS the poisoned denominator (P-UI-156)');
    }
    if (saveAt < 0) {
      broken.push('`GVHomeSaveFrac` is gone from BiotakHomes.mqh (P-UI-156)');
    } else {
      // P-UI-158 split the writer in three: the automatic door (`GVHomeSaveFrac`) now only
      // decides WHETHER to write, and `GVHomeWriteFrac` is the one place that does. The
      // out-of-box rule lives there, with the denominator rule it belongs to.
      const writeAt = homes.indexOf('void GVHomeWriteFrac(');
      if (writeAt < 0) {
        broken.push('`GVHomeWriteFrac` is gone — it is the ONE place a fraction is written, so the denominator rules can no longer be forgotten at a call site (P-UI-156)');
      } else {
        const writeBody = homes.slice(writeAt, homes.indexOf('\n}', writeAt));
        if (writeBody.indexOf('if(x > rcw || y > rch) return;') < 0)
          broken.push('a place outside the box is written again — the clamp saturates it into the store, which is how `STRIP_FX` became a permanent 1.0 (P-UI-156)');
        if (writeBody.indexOf('HomeChartSizeRaw(rcw, rch)') < 0)
          broken.push('the writer invents a denominator again — a fraction divided by a box the pixels did not come from (P-UI-156)');
      }
    }
    if (broken.length) {
      failures.push('P-UI-156: ' + broken.join('; ') + ' (Biotak/BiotakHomes.mqh GVHomeFracRead + GVHomeWriteFrac)');
    } else {
      console.log('[PASS] P-UI-156 a place is only read against a box that was measured: the reader refuses an unknown denominator and the one writer refuses a pair outside the box, so neither end can ratchet the other');
    }
  }

  // -- 46. P-UI-158: only the hand moves a home (the ring's method) -------------
  // ── P-UI-158 (2026-10-13) — ONLY THE HAND MOVES A HOME ──
  // The user asked for the RING's method («پنل رینگ از چه روشی استفاده کرده مثل همون بشه»).
  // The ring stores no place of its own: `CircMoveItem` derives every item from the orb on
  // every paint, so it cannot drift. The one place it does store is the ORB's, and that is
  // written in exactly one situation — the hand's own release. The chip had the other
  // shape: a stored fraction AND an automatic re-derivation that wrote it back, so a
  // derivation made in one window and saved in another REWROTE the fraction — MEASURED as
  // CHIP_FX 0.942731 -> 0.618392 across one close/open, a 589 px jump. P-UI-156/157 closed
  // the two doors that could feed it a wrong denominator; they did not remove the door.
  // The rule now: the AUTOMATIC path may not write a home at all. A home changes only when
  // a NEW ANSWER produced it, claimed with `GVHomeAnswerNew(id)` at the release, the
  // strip's first measured placement, or the legacy migration. A derived pair PAINTS and
  // is never STORED — exactly the ring's property.
  {
    const broken = [];
    const homes = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakHomes.mqh'), 'utf8');
    for (const fn of ['void GVHomeAnswerNew(', 'bool GVHomeAnswerAny(', 'void GVHomeAnswerClear(', 'bool GVHomeFracSeed(']) {
      if (homes.indexOf(fn) < 0)
        broken.push(`\`${fn.slice(0, -1)}\` is gone from BiotakHomes.mqh — the claim that authorises a home write no longer exists, so nothing distinguishes the hand's answer from a derivation (P-UI-158)`);
    }
    // The dead mechanism must not come back: a remembered derivation box is a second piece
    // of state that has to stay in step with the writer, and P-UI-158 removed it entirely.
    for (const dead of ['GVHomeDerivedIn', 'GVHomeBoxIs', 'GVHomeDeclareBox']) {
      const hit = fs.readdirSync(path.join(ROOT, 'Biotak'))
        .filter((f) => f.endsWith('.mqh'))
        .find((f) => fs.readFileSync(path.join(ROOT, 'Biotak', f), 'utf8').indexOf(dead) >= 0);
      if (hit)
        broken.push(`\`${dead}\` is back (${hit}) — the derivation-box record P-UI-158 deleted; a home is authorised by a CLAIM, not by remembering which window a read happened in (P-UI-158)`);
    }
    const saveAt = homes.indexOf('void GVHomeSaveFrac(');
    if (saveAt < 0) {
      broken.push('`GVHomeSaveFrac` is gone from BiotakHomes.mqh (P-UI-158)');
    } else {
      const saveBody = homes.slice(saveAt, homes.indexOf('\n}', saveAt));
      if (saveBody.indexOf('GVHomeAnswerTake(id)') < 0)
        broken.push('the automatic door writes without a claim again — `SaveUIStates` re-derives all three homes on every attach and teardown, so a derivation in one window gets saved against another and the fraction creeps (P-UI-158)');
      if (saveBody.indexOf('GVHomeWriteFrac(id, x, y)') < 0)
        broken.push('the automatic door no longer goes through `GVHomeWriteFrac`, so the denominator and out-of-box rules can be skipped (P-UI-158)');
      if (saveBody.indexOf('GlobalVariableSet') >= 0)
        broken.push('the automatic door writes the fraction itself again instead of delegating — the rules would then live in two places (P-UI-158)');
    }
    const handAt = homes.indexOf('void GVHomeSaveFracHand(');
    if (handAt < 0) {
      broken.push('`GVHomeSaveFracHand` is gone — the hand, the strip first measurement and the migration have no door of their own (P-UI-158)');
    } else {
      const handBody = homes.slice(handAt, homes.indexOf('\n}', handAt));
      if (handBody.indexOf('GVHomeAnswerNew(id)') < 0 || handBody.indexOf('GVHomeWriteFrac(id, x, y)') < 0)
        broken.push('the hand\'s door no longer makes its own claim, so a release would be refused like a derivation (P-UI-158)');
    }
    // `SaveUIStates` must still ask for all three (the shadow ledger owns the flush) and
    // must SPEND a claim it did not honour, or a stale claim authorises a later automatic
    // save to store a derived pair.
    const menuA = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakMenu_A.mqh'), 'utf8');
    const saveUIAt = menuA.indexOf('void SaveUIStates(');
    if (saveUIAt < 0) {
      broken.push('`SaveUIStates` is gone from BiotakMenu_A.mqh (P-UI-158)');
    } else {
      const saveUI = menuA.slice(saveUIAt, menuA.indexOf('\n}', saveUIAt));
      for (const id of ['ORB', 'STRIP', 'CHIP']) {
        if (saveUI.indexOf(`GVHomeSaveFrac("${id}", `) < 0)
          broken.push(`\`SaveUIStates\` no longer asks for ${id} — the hand's answer for it would never be published (P-UI-158)`);
      }
      if (!/if\(haveBox\)\s*GVHomeAnswerClear\s*\(\s*\)\s*;/.test(saveUI))
        broken.push('`SaveUIStates` no longer spends an unhonoured claim (or no longer guards it on `haveBox`) — a stale claim then authorises the NEXT automatic save to store a derived pair, which is the creep (P-UI-158)');
    }
    // Every claim site, counted per file: losing one silently refuses that surface's answer.
    const claimSites = [
      ['Biotak/BiotakMenu_C.mqh', 'ORB', 2, 'the orb reap and the orb drag release'],
      ['Biotak/BiotakPanels_Build.mqh', 'ORB', 1, 'the stationary orb release'],
      ['Biotak/DrawStrip_Router.mqh', 'STRIP', 1, 'the strip drag'],
      ['Biotak/BiotakMenu_B.mqh', 'CHIP', 1, 'the chip drag'],
    ];
    for (const [rel, id, want, label] of claimSites) {
      const src = fs.readFileSync(path.join(ROOT, rel), 'utf8');
      const got = (src.match(new RegExp(`GVHomeAnswerNew\\s*\\(\\s*"${id}"\\s*\\)`, 'g')) || []).length;
      if (got < want)
        broken.push(`${label} no longer claims its answer (${got} of ${want} \`GVHomeAnswerNew("${id}")\`) — the store would refuse the hand's own move (${rel}) (P-UI-158)`);
    }
    // The strip's fresh placement is a new answer like a release is, and it writes at once.
    const stripPaint = fs.readFileSync(path.join(ROOT, 'Biotak', 'DrawStrip_Paint.mqh'), 'utf8');
    if (!/if\(dsFreshHome\s*&&\s*dsBox\)/.test(stripPaint))
      broken.push('the strip writes a fresh home without a measured box again — a fresh placement measured in the 1920x1080 fallback stored as a fraction of the real window (P-UI-158)');
    if (stripPaint.indexOf('GVHomeSaveFracHand("STRIP"') < 0)
      broken.push('the strip\'s first placement no longer writes through the hand\'s door, so its home would never be published (P-UI-158)');
    // The chip drag measures the LIVE window and claims; a home clamped against a stale box
    // is a place the plate is not in.
    const menuB = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakMenu_B.mqh'), 'utf8');
    const dragAt = menuB.indexOf('void CircTipDragTo(');
    if (dragAt < 0) {
      broken.push('`CircTipDragTo` is gone from BiotakMenu_B.mqh (P-UI-158)');
    } else {
      const dragBody = menuB.slice(dragAt, menuB.indexOf('\n}', dragAt));
      if (dragBody.indexOf('HomeChartSizeRaw(cw, ch)') < 0)
        broken.push('the chip drag measures the cached metrics again — a home clamped against a stale box is a place the plate is not in (P-UI-158)');
      if (dragBody.indexOf('GVHomeAnswerNew("CHIP")') < 0)
        broken.push('the chip drag no longer claims its answer, so the release\'s save is refused (P-UI-158)');
    }
    // The seed: all three surfaces get one, so the FIRST paint lands in the right spot and
    // there is no visible jump for the 250 ms refresh to correct.
    const loadAt = menuA.indexOf('void LoadUIPlaces(');
    if (loadAt < 0) {
      broken.push('`LoadUIPlaces` is gone from BiotakMenu_A.mqh (P-UI-158)');
    } else {
      const loadBody = menuA.slice(loadAt, menuA.indexOf('\n}', loadAt));
      for (const id of ['ORB', 'STRIP', 'CHIP']) {
        if (loadBody.indexOf(`GVHomeFracSeed("${id}"`) < 0)
          broken.push(`${id} has no fraction seed — at attach the terminal reports no box, so it paints at its DEFAULT and the first 250 ms pass jumps it to its real home (P-UI-158)`);
      }
    }
    // The one refresh pass: its gate must be the reader's own measure, and the orb must
    // follow its home even with the ring shut (P-UI-157, kept).
    const menuC = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakMenu_C.mqh'), 'utf8');
    const refreshAt = menuC.indexOf('void CircHomesRefresh(');
    if (refreshAt < 0) {
      broken.push('`CircHomesRefresh` is gone from BiotakMenu_C.mqh (P-UI-158)');
    } else {
      const refreshBody = menuC.slice(refreshAt, menuC.indexOf('\n}', refreshAt));
      if (refreshBody.indexOf('HomeChartSizeRaw(cw, ch)') < 0)
        broken.push('the refresh gate reads a substituted box again — it records a box the reader refuses, so the early return can fire forever and the home is never applied (P-UI-158)');
      if (/HomeChartSize\s*\(/.test(refreshBody))
        broken.push('the refresh gate falls back to 1920x1080 again — the gate and the reader must ask the same question (P-UI-158)');
      if (!/UpdateCircularMenuPosition\s*\(\s*\)\s*;/.test(refreshBody))
        broken.push('the orb no longer follows its home — the refresh only repaints the ring, so with the ring shut the orb keeps the seed (P-UI-158)');
      if (/if\s*\(\s*g_UI\.menuVisible\s*\)\s*UpdateCircularMenuPosition/.test(refreshBody))
        broken.push('the orb repaint is gated on the ring again — the normal state is a shut ring, and that is exactly when the orb must still move (P-UI-158)');
      // And the refresh must NOT write: it is a derivation, and P-UI-158 lets only a claim through.
      if (refreshBody.indexOf('GVHomeSaveFrac') >= 0)
        broken.push('the refresh saves a home again — it is a DERIVATION, and a derivation must paint without ever reaching the store (P-UI-158)');
    }
    if (broken.length) {
      failures.push('P-UI-158: ' + broken.join('; ') + ' (Biotak/BiotakHomes.mqh + BiotakMenu_A/B/C.mqh + DrawStrip_Paint/Router.mqh + BiotakPanels_Build.mqh)');
    } else {
      console.log('[PASS] P-UI-158 only the hand moves a home: the automatic door refuses every write without a claim, the claim is made at each real answer (both orb paths, the chip drag, the strip drag, the strip\'s first placement, the migration), `SaveUIStates` spends what it did not honour, and every surface is seeded from its fraction so the first paint lands in the right place');
    }
  }

  // ── P-LOG-02b (2026-10-13) — EVERY INVALIDATOR IS A LIFECYCLE EVENT ──
  // P-LOG-02 (this file's sibling note, CalculationCache.mqh:105) fixed TWO of the
  // eight invalidators and left SIX at `_LOG_GATE_E`. ERROR is never gated
  // (`Logger.mqh:382`, `g_runtimeLogLevel <= LOG_LEVEL_ERROR`, and the production
  // level is INFO, so `2 <= 4` is always true). MEASURED on the live journal:
  // 130 `[E][SYNC]` lines in one day, FIVE per timeframe switch — the exact
  // "fake errors bury a real one" defect P-LOG-02 exists to remove. This entry
  // locks the whole file, not the two sites that happened to get fixed.
  {
    const broken = [];
    const cc = fs.readFileSync(path.join(ROOT, 'Biotak', 'CalculationCache.mqh'), 'utf8');
    const INVALIDATORS = [
      'TH Cache Invalidated', 'Factor Cache Invalidated', 'Timeframe Cache Invalidated',
      'PeriodSeconds Cache Invalidated', 'Geometry Cache Invalidated',
      'Extension Multiplier Cache Invalidated', 'Timeframe-Dependent Caches Invalidated',
      'Settings-Dependent Caches Invalidated',
    ];
    if (/_LOG_GATE_E\s+Print\("\[E\]\[SYNC\]/.test(cc))
      broken.push('an invalidation is back at ERROR — ERROR is never gated, so it prints at production log level and buries a real error in Experts (P-LOG-02b)');
    for (const msg of INVALIDATORS) {
      if (cc.indexOf(`_LOG_GATE_I Print("[I][SYNC] ${msg}")`) < 0)
        broken.push(`"${msg}" is not on the INFO gate — a half-applied P-LOG-02 is the same defect one level up (P-LOG-02b)`);
    }
    if (broken.length) {
      failures.push('P-LOG-02b: ' + broken.join('; ') + ' (Biotak/CalculationCache.mqh)');
    } else {
      console.log('[PASS] P-LOG-02b all 8 cache invalidators are INFO, not ERROR: the two P-LOG-02 fixed are no longer alone, so a timeframe switch cannot print five fake [E] lines');
    }
  }

  // ── P-PERF-45c (2026-10-13) — THE BY-DEFINITION BRANCH SETS THE FLAG TOO ──
  // MEASURED: `[W][PERF] coop job=heavy-frame waited=-16ms ran=16ms` (also -31, -32,
  // -47). A negative wait is impossible (`waited = t0 - owedMs`, `t0 >= owedMs`), so
  // the ledger was lying. The branch set the CLOCK but left `s_coopOwed[job]` FALSE,
  // so the frame it runs re-armed itself and overwrote the clock with a LATER tick.
  {
    const broken = [];
    const tail = fs.readFileSync(path.join(ROOT, 'Biotak', 'EventHandlers_Tail.mqh'), 'utf8');
    const at = tail.indexOf('if(job == COOP_JOB_HEAVY_FRAME && !owed &&');
    if (at < 0) {
      broken.push('the frame-is-the-progress-maker branch is gone — the pump can no longer owe the rebuild by definition (P-PERF-45c)');
    } else {
      const body = tail.slice(at, at + 3000);
      const flagAt = body.indexOf('s_coopOwed[job] = true;');
      const clockAt = body.indexOf('s_coopOwedMs[job] = GetTickCount();');
      if (clockAt < 0)
        broken.push('the branch no longer stamps the owed clock — the wait it reports has no origin (P-PERF-45c)');
      if (flagAt < 0 || (clockAt >= 0 && flagAt < clockAt))
        broken.push('the branch stamps the clock WITHOUT setting the flag again — a self-re-arming frame then overwrites the clock and `waited` goes negative, i.e. the ledger lies (P-PERF-45c)');
    }
    if (broken.length) {
      failures.push('P-PERF-45c: ' + broken.join('; ') + ' (Biotak/EventHandlers_Tail.mqh CoopPump)');
    } else {
      console.log('[PASS] P-PERF-45c the by-definition frame sets its owed flag with its clock: the re-arm cannot overwrite the ask, so `waited` can no longer go negative and the starvation counter sees the progress-maker');
    }
  }

  // ── P-BE-05 (2026-10-13) — THE DEAD SECOND COPY STAYS DELETED ──
  // `GetOrCreateSymbolState` carried a SECOND, unreachable copy of its own creation
  // block BELOW `return newIndex;` (a second `g_symbolStateCount++` and its own
  // `return`). MQL4 does not warn on unreachable statements, so a green compile said
  // nothing — the same reason P-BE-03's dead trio survived two builds.
  {
    const broken = [];
    const bp = fs.readFileSync(path.join(ROOT, 'Biotak', 'BasePrice_A.mqh'), 'utf8');
    const at = bp.indexOf('return newIndex;');
    if (at < 0) {
      broken.push('the bounds-checked creation path is gone from BasePrice_A.mqh (P-BE-05)');
    } else {
      const end = bp.indexOf('\n}', at);
      const tailBody = end < 0 ? '' : bp.slice(at, end);
      // COMMENT-STRIPPED: the tombstone comment above the deleted block NAMES the
      // very tokens this check looks for, so a prose mention would read as a
      // resurrected copy (the P-PERF-40c lesson: a needle must not match a
      // declaration or a note about the thing).
      const code = tailBody.split('\n').map(stripComment).join('\n');
      if (/g_symbolStateCount\s*\+\+/.test(code))
        broken.push('a second `g_symbolStateCount++` is back below the return — the unreachable duplicate creation block is a copy the next reader will follow (P-BE-05)');
      if (/ArrayResize\s*\(\s*g_symbolStates\s*,/.test(code))
        broken.push('the unreachable second `ArrayResize(g_symbolStates, ...)` is back — the dead copy of the creation block returned (P-BE-05)');
    }
    if (broken.length) {
      failures.push('P-BE-05: ' + broken.join('; ') + ' (Biotak/BasePrice_A.mqh GetOrCreateSymbolState)');
    } else {
      console.log('[PASS] P-BE-05 the unreachable second creation block after `return newIndex` stays deleted: one path creates, initialises and counts the symbol state');
    }
  }

  // ── P-PERF-53 (2026-10-19) — THE COST HAS A PHASE; THE PHASE HAS A CAUSE ──
  // MEASURED 2026-10-19: 49 CPU warnings in one day of logs, and every single one read
  //   [base=0 atr=0 hist=0 levels=94..125 labels=0 overlay=0 pre=0 post=0 rest=0]
  // The phase ledger (P-PERF-03/49) had done its job: the WHOLE frame was the level
  // family render. What it could not say is why that frame ran at all - and a 94 ms
  // render every couple of seconds is either the price of a real edit or a rebuild
  // nothing asked for, two different fixes. The reader's only route was to guess
  // between the 38 writers of `g_redrawTHLevelsNeeded` alone. So the ledger now carries
  // the arming flag beside the price: one string built on the frames that pass the
  // gates, no chart write, no pixel moved.
  {
    const broken53 = [];
    const gv53 = linesOf(path.join(ROOT, 'Biotak', 'GlobalVariables.mqh'))
      ? fs.readFileSync(path.join(ROOT, 'Biotak', 'GlobalVariables.mqh'), 'utf8') : '';
    const ec53 = linesOf(path.join(ROOT, 'Biotak', 'EventHandlers_Calc.mqh'))
      ? fs.readFileSync(path.join(ROOT, 'Biotak', 'EventHandlers_Calc.mqh'), 'utf8') : '';
    const eo53 = linesOf(path.join(ROOT, 'Biotak', 'EventHandlers_Objects.mqh'))
      ? fs.readFileSync(path.join(ROOT, 'Biotak', 'EventHandlers_Objects.mqh'), 'utf8') : '';
    if (!gv53.includes('static int g_p3ArmMask = 0;'))
      broken53.push('the ledger has no arming-flag mask - the next 94 ms frame names its phase and not its cause (P-PERF-53)');
    if (!gv53.includes('string PerfArmWhy(const int m)'))
      broken53.push('the mask has no owner that turns it back into names - a number nobody decodes is not a witness (P-PERF-53)');
    const namedWhy = (gv53.match(/s \+= "/g) || []).length;
    if (namedWhy < 9)
      broken53.push(`only ${namedWhy} of the frame's arming flags have a name - the reader is back to guessing which of them ran (P-PERF-53)`);
    for (const f of ['force', 'labels', 'th', 'histRange', 'base', 'stage', 'heavy', 'renderAll', 'clear']) {
      if (!gv53.includes(`s += "${f} "`))
        broken53.push(`the flag ${f} is no longer named - a frame it armed reports a shorter cause than it had (P-PERF-53)`);
    }
    if (!gv53.includes('if(s == "") s = "sig";'))
      broken53.push('a frame armed only by the geometry signature reports an empty cause - "sig" is the one cause with no writer to point at (P-PERF-53)');
    if (!ec53.includes('g_p3ArmMask = (force_redraw?1:0)'))
      broken53.push('the frame does not capture its arming flags - the mask is read after the frame consumed them (P-PERF-53)');
    for (const bit of ['(g_redrawTHLevelsNeeded?4:0)', '(historicalRefreshDue?8:0)', '(basePriceBoundary?16:0)',
                       '(g_buildStage!=0?32:0)', '(g_heavyFramePending?64:0)', '(g_renderAllNeeded?128:0)',
                       '(g_forceClearOnNextDraw?256:0)']) {
      if (!ec53.includes(bit))
        broken53.push(`the mask dropped ${bit} - that flag's frames will report a cause shorter than the truth (P-PERF-53)`);
    }
    if (!eo53.includes('" why=" + PerfArmWhy(g_p3ArmMask) + "]"'))
      broken53.push('the CPU warning does not print the arming flags - the line that proves the cost still cannot name what asked for it (P-PERF-53)');
    if (broken53.length) {
      failures.push('P-PERF-53: ' + broken53.join('; ') + ' (Biotak/GlobalVariables.mqh + EventHandlers_Calc.mqh + EventHandlers_Objects.mqh)');
    } else {
      console.log('[PASS] P-PERF-53 the CPU ledger names its cause: the arming flags are collected on every frame that passes the gates and printed beside the phase that spent the time');
    }
  }

  // ── P-PERF-55 (2026-10-13) — THE FOREIGN SWEEP ASKS ITS QUESTION OF A SET ──
  // The sweep's own note called `produced[]` "tens of entries"; the live chart made it
  // `lineCount*2 + zoneCount` (450 lines + 289 zones ≈ 1,189 names) and the walk visits
  // every chart object, so one frame paid ~1.4M string compares. The same frame carries
  //   [P-LEVEL-FOREIGN-02: deleted 450 ladder object(s)]
  //   [W][PERF] coop job=heavy-frame ran=125ms
  //   [E][GEN] [CRIT] CRITICAL CPU: OnCalculate took 453ms! [levels=453]
  // This entry locks BOTH halves: the set is used, AND the exact linear scan stays as
  // the fallback — a shape change must never become a verdict change.
  {
    const broken = [];
    const lpb = fs.readFileSync(path.join(ROOT, 'Biotak', 'LevelPipe_B.mqh'), 'utf8');
    if (!/#define\s+LADDER_SET_SIZE\s+\d+/.test(lpb))
      broken.push('the sweep\'s membership set is gone — the O(n\u00b2) scan is back on a 1,189-name list (P-PERF-55)');
    if (lpb.indexOf('const bool producedSet = LadderSetBuild(produced, pc);') < 0)
      broken.push('the set is no longer built once before the walk (P-PERF-55)');
    const uses = (lpb.match(/producedSet \? LadderSetHas\(nm\) : ProducedLadderName\(nm, produced, pc\)/g) || []).length;
    if (uses < 2)
      broken.push(`only ${uses} of the sweep's 2 membership tests use the set — the rest pay the full scan (P-PERF-55)`);
    if (lpb.indexOf('bool ProducedLadderName(const string nm, const string &produced[], const int producedCount)') < 0)
      broken.push('the exact linear scan is gone — the set is now the ONLY answer, so a list too big for the table would silently become "nothing was produced" (P-PERF-55)');
    if (lpb.indexOf('pc * 2 > LADDER_SET_SIZE) return false;') < 0)
      broken.push('the set no longer refuses a list it cannot hold — an oversized ladder would be answered by a half-filled table (P-PERF-55)');
    if (broken.length) {
      failures.push('P-PERF-55: ' + broken.join('; ') + ' (Biotak/LevelPipe_B.mqh ProducedLadderName + the foreign-ladder sweep)');
    } else {
      console.log('[PASS] P-PERF-55 the foreign-ladder sweep answers membership with a hash set (one probe per name, built once) and keeps the exact linear scan as the fallback, so the verdict cannot change with the shape');
    }
  }

  // ── P-BUILD-13 (2026-10-13) — `-Project all` COMPILES BOTH PRODUCTS ──
  // MEASURED 2026-10-13 (four source files edited at ~18:05):
  //   18:13  -Project all              -> Full ex4 18:13:24, Lite ex4 still 13:52:19
  //   18:16  -SourceFile "...Lite.mq4" -> Lite ex4 18:16:21 (0 errors, 0 warnings)
  //   18:23  -Project all              -> Full ex4 18:23:47, Lite ex4 still 18:16:21
  // `-Project all` is THE documented build and it printed «All compilations PASSED!»
  // while `Biotak Trigger TH3 Lite.mq4` was in NO project at all: the `$PROJECTS`
  // table held only the two FULL entries (and the second is the same file through the
  // junction), so a change to a shared `.mqh` shipped a STALE Lite ex4 behind a green
  // summary. The fix has TWO halves and BOTH are locked here: the `"lite"` entry
  // exists, AND the `all` set actually names it (the literal `@("workspace",
  // "installed")` was the second half — a table entry nobody compiles is still a lie).
  {
    const broken = [];
    const ps = fs.readFileSync(path.join(ROOT, 'compile-th3.ps1'), 'utf8');
    if (!/\[ValidateSet\([^)]*"lite"[^)]*\)\]/.test(ps))
      broken.push('`lite` is not an accepted -Project value — the product exists but cannot be named (P-BUILD-13)');
    const liteEntry = /"lite"\s*=\s*@\{([\s\S]*?)\n\s*\}/.exec(ps);
    if (!liteEntry)
      broken.push('the `"lite"` entry is gone from the $PROJECTS table — `-Project all` no longer knows Lite is a product (P-BUILD-13)');
    else if (liteEntry[1].indexOf('Biotak Trigger TH3 Lite.mq4') < 0)
      broken.push('the `"lite"` entry does not point at `Biotak Trigger TH3 Lite.mq4` (P-BUILD-13)');
    const order = /\$ALL_PROJECT_ORDER\s*=\s*@\(([^)]*)\)/.exec(ps);
    if (!order)
      broken.push('the `all` set is gone — re-checked by hand is how Lite got orphaned the first time (P-BUILD-13)');
    else if (!/"lite"/.test(order[1]))
      broken.push('`all` no longer includes `lite` — a green «All compilations PASSED!» would ship a stale Lite ex4 again (P-BUILD-13)');
    if (ps.indexOf('does not cover:') < 0)
      broken.push('the completeness assertion is gone — a future table entry could be silently orphaned from `all` (P-BUILD-13)');
    if (broken.length) {
      failures.push('P-BUILD-13: ' + broken.join('; ') + ' (compile-th3.ps1 $PROJECTS + $ALL_PROJECT_ORDER)');
    } else {
      console.log('[PASS] P-BUILD-13 `-Project all` covers both products: Lite is a table entry, `all` names it, and a table entry missing from `all` fails the build instead of shipping stale');
    }
  }

  // ── P-BUILD-14 (2026-10-13) — A CASE-DUPLICATE ENV KILLS Start-Process ──
  // MEASURED 2026-10-13 18:31: the running process env carried the SAME variable under
  // two spellings (Git Bash / MSYS and this agent runtime both do):
  //   [HTTP_PROXY]=http://127.0.0.1:4187  [http_proxy]=http://127.0.0.1:4187
  //   [HTTPS_PROXY]=…                     [https_proxy]=…
  // Windows env blocks are case-INSENSITIVE, so `Start-Process` threw
  //   "Item has already been added. Key in dictionary: 'http_proxy'"
  // BEFORE spawning metaeditor.exe: four source files edited, `-Project all` run, and
  // BOTH ex4 timestamps unchanged (Full 18:23:47, Lite 18:16:21) while the gate layer
  // still printed its PASS lines. A build that reports gates while compiling nothing
  // is the defect this file exists to catch. The lock: the normalization exists AND
  // runs BEFORE the first Start-Process in the file.
  {
    const broken = [];
    const ps = fs.readFileSync(path.join(ROOT, 'compile-th3.ps1'), 'utf8');
    const fnAt = ps.indexOf('function Remove-CaseDuplicateEnv');
    if (fnAt < 0) {
      broken.push('the case-duplicate env normalization is gone — Start-Process throws again and the compiler is never launched (P-BUILD-14)');
    } else {
      if (ps.indexOf('[System.Environment]::GetEnvironmentVariables()', fnAt) < 0)
        broken.push('the normalizer no longer reads the process environment (P-BUILD-14)');
      if (ps.indexOf("SetEnvironmentVariable($keepName, $keepValue, 'Process')", fnAt) < 0)
        broken.push('the normalizer no longer re-adds the surviving spelling — it would delete BOTH copies and lose the value (P-BUILD-14)');
      const callAt = ps.indexOf('$script:EnvDeduped = Remove-CaseDuplicateEnv');
      if (callAt < 0) {
        broken.push('the normalizer is DEFINED but never CALLED — a fix that does not run is a comment (P-BUILD-14)');
      } else {
        //--- anchor on the real cmdlet invocation, NOT the word: this very block's
        //--- prose says "Start-Process" several times, and a mention is not a call.
        const firstSpawn = ps.indexOf('Start-Process -FilePath');
        if (firstSpawn >= 0 && callAt > firstSpawn)
          broken.push('the normalizer runs AFTER the first Start-Process — the compiler still dies on a case-duplicate env (P-BUILD-14)');
      }
    }
    if (broken.length) {
      failures.push('P-BUILD-14: ' + broken.join('; ') + ' (compile-th3.ps1 Remove-CaseDuplicateEnv)');
    } else {
      console.log('[PASS] P-BUILD-14 the build collapses case-duplicate env keys before any Start-Process, so a POSIX-ish parent cannot stop the compiler from launching');
    }
  }

  // -- 47. P-DRAW-128/129/130: a hover preview is not a choice, and the native
  //        surface's pick is a pick --------------------------------------------
  // MEASURED 2026-10-13 on the live build (EURUSD): the palette's DRAWING pages
  // re-ordered the RECENT strip under the pointer («موس روش میبیم عوض میشه یک
  // چیزی دیگه جاش میاد»), every hover crossing taught the kind's memory a colour
  // the hand only passed over, and a copy of a drawing recoloured through MT4's
  // OWN dialog/toolbar came back wearing the old colour («برمیگرده به رنگ خودش
  // مثلا اگر از جای غیره به جز نوار استرینگ تغییر بکنه»). Three laws, one shape:
  // `remember` is the popup's own word for "the hand chose this", and it now rides
  // from the palette's apply all the way down to the slot writer's learn-and-
  // persist half; the native colour arrives as OBJECT_CHANGE and is taught
  // through the memory's ONE owner, behind a witness that can tell a colour edit
  // from a move-drop.
  {
    const broken = [];
    // (a) the palette's apply: the DRAW branch was the one kind that ignored remember.
    // `case PAL_DRAW_BORDER` labels TWO branches in this file — the kind's colour
    // READER (`PaletteKindColor`) and the APPLY (`PaletteApplyColor`) — so the branch
    // under test is anchored on the apply call itself, never on the first label match.
    const stateCode = linesOf(PAL_STATE) ? codeOf(linesOf(PAL_STATE)) : null;
    if (!stateCode) broken.push('Biotak/BiotakPanels_State.mqh is gone');
    else {
      const at = stateCode.indexOf('DrawStripPalTargetApply(');
      const branch = at >= 0 ? stateCode.slice(at, at + 160) : '';
      if (!/DrawStripPalTargetApply\(clr, remember\)/.test(branch))
        broken.push('PaletteApplyColor applies a DRAWING pick without passing remember down — the preview still learns the kind memory');
      if (!/if\(remember\) PushPalRecent\(clr\);/.test(branch))
        broken.push('the DRAW branch pushes to RECENT unconditionally again — a hover preview is not a choice (P-UI-131h)');
    }
    // (b) the bridge gates the strip's own ring and threads the flag. `bodyOf` hands
    // back the BODY; the `const bool remember` lives on the signature line (`at`).
    const baseBody = bodyOf(linesOf(STRIP_BASE), 'int DrawStripPalTargetApply(');
    if (!baseBody) broken.push('DrawStripPalTargetApply() is gone from Biotak/DrawStrip_Base.mqh');
    else {
      const baseLines = linesOf(STRIP_BASE) || [];
      if (!/const bool remember/.test(baseLines[baseBody.at] || ''))
        broken.push('DrawStripPalTargetApply no longer takes remember — a preview re-orders the strip\u2019s own ring');
      const bare = baseBody.text.replace(/if\(remember\) DrawStripRecentPush\(c\);/g, '');
      const pushes = (bare.match(/DrawStripRecentPush\(c\)/g) || []).length;
      if (pushes > 0)
        broken.push(`${pushes} ungated DrawStripRecentPush call(s) in the bridge — the ring moves under the hand`);
    }
    // (c)+(d) the two writers between the bridge and the slot owner thread it on.
    const tapBody = bodyOf(linesOf(STRIP_TAP), 'bool DrawStripColorCommit(');
    if (!tapBody || !/DrawStripWriteValue\(slot, \(double\)\(int\)c, remember\)/.test(tapBody.text))
      broken.push('DrawStripColorCommit no longer threads remember into DrawStripWriteValue');
    const writeBody = bodyOf(linesOf(STRIP_PAINT), 'int DrawStripWriteValue(');
    if (!writeBody || !/DrawSlotWrite\(\w+, slot, v, remember\)/.test(writeBody.text))
      broken.push('DrawStripWriteValue no longer threads remember into DrawSlotWrite');
    // (e) the slot owner: a preview writes the drawing and learns nothing.
    const slotBody = bodyOf(linesOf(TOOLBAR_B), 'bool DrawSlotWrite(');
    if (!slotBody) broken.push('DrawSlotWrite() is gone — the kind memory has no writer');
    else {
      if (!/if\(remember\)\s*\{\s*s_dkColor\[k\] = c;/.test(slotBody.text))
        broken.push('DrawSlotWrite learns the kind colour on a preview (remember=false) — the next drawing is born wearing a hovered colour');
      if (!/s_dkAnyClr = c;/.test(slotBody.text))
        broken.push('the shared ink (P-DRAW-INK) is no longer noted where every pick arrives');
      if (!/if\(remember\) s_dkFillClr\[k\] = ic;/.test(slotBody.text))
        broken.push('a preview learns the interior colour');
      if (!/if\(remember\)\s*\{\s*s_dkValid\[k\] = true;/.test(slotBody.text))
        broken.push('a preview marks the kind as styled and persists to disk on every hover crossing');
    }
    // (f) the native surface's pick: OBJECT_CHANGE teaches through the one owner.
    const routerCode = linesOf(STRIP_ROUTER) ? codeOf(linesOf(STRIP_ROUTER)) : null;
    if (!routerCode) broken.push('Biotak/DrawStrip_Router.mqh is gone');
    else if (!/if\(id == CHARTEVENT_OBJECT_CHANGE\) DrawInkLearnNative\(sparam\);/.test(routerCode))
      broken.push('the OBJECT_CHANGE branch never calls DrawInkLearnNative — a colour set in MT4\u2019s own dialog/toolbar is still invisible to the kind memory');
    const learnBody = bodyOf(linesOf(TOOLBAR_B), 'void DrawInkLearnNative(');
    if (!learnBody) broken.push('DrawInkLearnNative() is gone — the native surface\u2019s pick has no learner');
    else {
      if (!/DrawInkMemoDelta\(name, c\)/.test(learnBody.text))
        broken.push('the learner has no move-vs-colour witness — a drop would teach the kind a factory colour');
      if (!/\(int\)s_dkColor\[k\] < 0 && c == s_dkAnyClr/.test(learnBody.text))
        broken.push('the learner would freeze a BORROWED ink as the kind\u2019s own colour (P-DRAW-INK)');
      if (!/DrawTplSave\(\);/.test(learnBody.text))
        broken.push('the native pick persists through a second path — the memory has two owners');
      // (f2) the witness refuses a level kind: a level drawing's colours live in the
      // LEVEL family (`OBJPROP_LEVELCOLOR`), so the object's own `OBJPROP_COLOR` there
      // answers a property it does not hold (P-DRAW-BODY).
      const witBody = bodyOf(linesOf(TOOLBAR_B), 'color DrawInkWitnessRead(');
      if (!witBody) broken.push('DrawInkWitnessRead() is gone — the learner has nothing to compare against');
      else if (!/if\(DrawKindHasLevels\(k\)\) return clrNONE;/.test(witBody.text))
        broken.push('the witness reads a level kind\u2019s OBJPROP_COLOR — a property that object does not own, so a factory zero would be learned as a pick (P-DRAW-BODY)');
    }
    // (g) the witness is primed from birth and forgotten at death.
    const evRouter = linesOf(ROUTER) ? codeOf(linesOf(ROUTER)) : null;
    if (!evRouter) broken.push('Biotak/EventHandlers_Router.mqh is gone');
    else {
      if (!/DrawInkMemoPrime\(sparam\);/.test(evRouter))
        broken.push('a new drawing is never witnessed — its first native change reads as a move-drop and is missed');
      if (!/DrawInkMemoForget\(sparam\);/.test(evRouter))
        broken.push('a deleted drawing keeps its witness — the memo answers for names that no longer exist');
    }
    const evInit = linesOf(EV_INIT) ? codeOf(linesOf(EV_INIT)) : null;
    if (!evInit) broken.push('Biotak/EventHandlers_Init.mqh is gone');
    else if (!/DrawInkMemoInit\(\);/.test(evInit))
      broken.push('the attach-time witness walk is gone — the first native change after a reload is missed');
    if (broken.length) {
      failures.push('P-DRAW-128/129/130: ' + broken.join('; ') + ' (Biotak/BiotakPanels_State.mqh PaletteApplyColor + Biotak/DrawStrip_Base.mqh DrawStripPalTargetApply + Biotak/Toolbar_B.mqh DrawSlotWrite/DrawInkLearnNative)');
    } else {
      console.log('[PASS] P-DRAW-128/129/130 a hover preview writes the drawing and learns nothing (remember threads down to the slot owner), and a colour set in MT4\u2019s own surfaces teaches the kind memory through its one owner');
    }
  }

  // -- 48. P-LM-25: the leg's ATR is read AT THE LEG'S OWN BAR -----------------
  // MEASURED 2026-10-16: a leg drawn over history (Oct 16 12:00–12:53) printed
  // TODAY's live ATR — H1 143 / H4 327 / D1 999, the live strip row to the digit
  // — because `LegAtr14` called `CalculateWeightedATR` (the chart's NOW). The
  // user: «این لگ ها که اندازه میزنم باید محاسبات atr همون زمان باشه یعنی لایو
  // گذشته». The fix routes every read through the as-of sibling
  // `CalculateWeightedATRAt` (P-BK-79) at `LegReadAnchor`'s bar (the LATER of the
  // two anchors — BaseKnot's storyT rule), so a finished leg freezes the numbers
  // it was measured with, and the commit paths flush a `[P-LM-25]` witness
  // carrying the anchor they read at — the probe line: only the file shows WHICH
  // bar a reported number came from.
  {
    const broken = [];
    const toolC = linesOf(TH3TOOL_C);
    if (!toolC) broken.push('Biotak/TH3Tool_C.mqh is gone');
    else {
      const toolCcode = codeOf(toolC);
      // (a) the read itself: as-of, never live.
      const atrBody = bodyOf(toolC, 'double LegAtr14(');
      if (!atrBody) broken.push('LegAtr14() is gone — the readout has no reader');
      else {
        if (!/CalculateWeightedATRAt\(CompatTF\(tf\), anchor\)/.test(atrBody.text))
          broken.push('LegAtr14 reads the LIVE composite again — a historical leg prints today\u2019s ATR (the reported defect)');
        if (/CalculateWeightedATR\(/.test(atrBody.text))
          broken.push('LegAtr14\u2019s body carries a live CalculateWeightedATR( call beside the as-of one');
      }
      // (b) the anchor rule: ONE owner, and it is "the later time".
      const anchorBody = bodyOf(toolC, 'datetime LegReadAnchor(');
      if (!anchorBody || !/\(t1 > t2\) \? t1 : t2/.test(anchorBody.text))
        broken.push('LegReadAnchor is gone or is no longer the later-time rule — the readout and its witness can disagree about the anchor');
      // (c) the owner walk reads at the same bar.
      const ownerBody = bodyOf(toolC, 'int TH3LegOwnerTF(');
      if (!ownerBody) broken.push('TH3LegOwnerTF() is gone — the owner TF has no walk');
      else {
        if (!/const datetime anchor/.test(toolC[ownerBody.at] || ''))
          broken.push('TH3LegOwnerTF no longer takes the anchor — the owner walk judges the leg with the live ATR');
        if (!/LegAtr14\(tf, anchor\)/.test(ownerBody.text))
          broken.push('the owner walk calls LegAtr14 without the anchor');
      }
      // (d) the readout: the anchor is derived ONCE and every read carries it.
      const readBody = bodyOf(toolC, 'void LegMeasureReadout(');
      if (!readBody) broken.push('LegMeasureReadout() is gone — the readout has no owner');
      else {
        if (!/LegReadAnchor\(t1, t2\)/.test(readBody.text))
          broken.push('LegMeasureReadout no longer derives its anchor from LegReadAnchor');
        if (!/TH3LegOwnerTF\(legSize, anchor, trusted\)/.test(readBody.text))
          broken.push('LegMeasureReadout calls the owner walk without the anchor');
        const bareAtr = readBody.text.match(/LegAtr14\([^,()]+\)/g);
        if (bareAtr)
          broken.push(bareAtr.length + ' bare LegAtr14(...) read(s) in the readout — a live ATR beside the as-of ones');
      }
      // (e) the whole tool half: no live composite read remains anywhere.
      const liveSites = (toolCcode.match(/CalculateWeightedATR\(/g) || []).length;
      if (liveSites > 0)
        broken.push(liveSites + ' live CalculateWeightedATR( call(s) in TH3Tool_C — the leg tool reads the chart\u2019s NOW again');
      // (f) the witness: defined here, on the flushed channel, and it asks the
      // SAME anchor owner the readout asked (a witness with its own arithmetic
      // is a second grid).
      const wit = bodyOf(toolC, 'void LegReadWitness(');
      if (!wit) broken.push('LegReadWitness() is gone — a reported number has no anchor witness (the probe line is lost)');
      else {
        if (!/DrawStripDiagEmit\(/.test(wit.text))
          broken.push('the witness does not use DrawStripDiagEmit — a Print witness waits in MT4\u2019s RAM buffer (P-DRAW-126)');
        if (!/\[P-LM-25\]/.test(wit.text) || !/anchor=/.test(wit.text))
          broken.push('the witness line no longer carries [P-LM-25] and anchor=');
        if (!/LegReadAnchor\(t1, t2\)/.test(wit.text))
          broken.push('the witness computes its own anchor — a second grid (the readout and the file can disagree)');
      }
    }
    // (g) both COMMIT paths witness: a fresh draw and a drag's release. The
    // per-move pass must NOT (a flushed line per move is a file write in the
    // mouse stream, contract §5).
    const drawBody = toolC ? bodyOf(toolC, 'string LegMeasureDraw(') : null;
    if (!drawBody || !/LegReadWitness\("draw", t1, t2, legTxt, ownerTF, trusted\)/.test(drawBody.text))
      broken.push('a fresh draw never witnesses its anchor ([P-LM-25] \u201cdraw\u201d)');
    const toolB = linesOf(TH3TOOL_B);
    if (!toolB) broken.push('Biotak/TH3Tool_B.mqh is gone');
    else {
      const endBody = bodyOf(toolB, 'void LegMeasureDragEnd(');
      if (!endBody || !/LegReadWitness\("drag", t1, t2, txt, otf, trusted\)/.test(endBody.text))
        broken.push('the drag\u2019s release commits without the [P-LM-25] witness — the committed anchors are unwitnessed');
    }
    if (broken.length) {
      failures.push('P-LM-25: ' + broken.join('; ') + ' (Biotak/TH3Tool_C.mqh LegAtr14/LegReadAnchor/TH3LegOwnerTF/LegMeasureReadout/LegReadWitness + Biotak/TH3Tool_B.mqh LegMeasureDragEnd)');
    } else {
      console.log('[PASS] P-LM-25 every leg ATR is read at LegReadAnchor\u2019s bar through CalculateWeightedATRAt (never the live composite), and both commit paths flush the [P-LM-25] anchor witness');
    }
  }

  // -- 49. P-UI-160b (2026-10-16): the F mute takes the DRAWING families too ---
  // The report: «دکمه f که فقط زون ها رو خاموش و روشن میکنه پیس همه رو باید خاموش
  // بکنه». MEASURED on the live chart: F darkened the level families and left the
  // leg meter, the ABCD family, the rays and the paths standing — the cache walk
  // cannot see them (they are not in the object cache) and their writers are
  // action-driven, so every one of them needed a seat on the mute. This entry
  // locks the SEATS, not the shape of the code: the hide half runs once per
  // transition in the pass (with the four armed-session doors cancelling), the
  // show half in one function beside it (P-SIZE-1500 sent it out of Objects),
  // each family answers through its own owner (mask what a mask can reach, park
  // what it cannot — the pattern/leg-meter owners live in TH3Tool_Mute.mqh), the
  // riders carry the hidden term so no channel can re-show what the mute took,
  // and every arming/grab door refuses while hidden. The witness
  // ([P-UI-160b] drawings hide=… pat/lm/hr/pa) is the flushed proof both halves
  // ran — a Print witness waits in MT4's RAM buffer (P-DRAW-126).
  {
    const broken = [];
    const mute = linesOf(path.join(BIOTAK, 'TH3Tool_Mute.mqh'));
    if (!mute) broken.push('Biotak/TH3Tool_Mute.mqh is gone — the pattern/leg-meter mute owners left the unit');
    else {
      const patternsHide = bodyOf(mute, 'int TH3PatternsHideAll(');
      if (!patternsHide || !/TH3LadderSetVisible\(.*false/.test(patternsHide.text) || !/TH3InfoFamilySetVisible\(.*false/.test(patternsHide.text))
        broken.push('TH3PatternsHideAll no longer masks the ladders and the info families');
      const patternsShow = bodyOf(mute, 'int TH3PatternsShowAll(');
      if (!patternsShow || !/TH3LadderSetVisible\([^;]*==\s*g_activeABCDPattern/.test(patternsShow.text))
        broken.push('TH3PatternsShowAll lost the one-lit ladder rule (base == g_activeABCDPattern, P-TH3-P6f)');
      const legsHide = bodyOf(mute, 'int LegMeasureHideAll(');
      if (!legsHide || !/LegMeasureHandles\(/.test(legsHide.text) || !/LegMeasurePlateHide\(/.test(legsHide.text))
        broken.push('LegMeasureHideAll no longer parks the icons and drops the plate');
      const legsShow = bodyOf(mute, 'int LegMeasureShowAll(');
      if (!legsShow || !/LegMeasureRideChart\(/.test(legsShow.text))
        broken.push('LegMeasureShowAll no longer re-places the icons through the ride');
    }
    const cp = linesOf(path.join(BIOTAK, 'EventHandlers_CustomPrice.mqh'));
    if (!cp) broken.push('Biotak/EventHandlers_CustomPrice.mqh is gone — the hide pass and the show half have no owner');
    else {
      const hideBody = bodyOf(cp, 'void HideAllTHObjectsPass(');
      if (!hideBody) broken.push('HideAllTHObjectsPass is gone — the mute has no hide pass');
      else {
        for (const call of ['TH3PatternsHideAll()', 'LegMeasureHideAll()', 'HRayHideAll()', 'PathHideAll()'])
          if (!hideBody.text.includes(call))
            broken.push(`the hide pass lost ${call} — that family stays lit under the mute (the reported defect)`);
        for (const term of ['TH3BaseMarkArmed()', 'LegMeasureSessionActive()', 'HRaySessionActive()', 'PathSessionActive()'])
          if (!hideBody.text.includes(term))
            broken.push(`the hide pass stopped cancelling an armed session (${term}) — a click under the mute would draw`);
        if (!hideBody.text.includes('[P-UI-160b] drawings hide=1'))
          broken.push('the hide half lost its flushed witness — the mute is unprovable without it');
      }
      const showBody = bodyOf(cp, 'void ShowAllDrawingFamilies(');
      if (!showBody) broken.push('ShowAllDrawingFamilies is gone — F-show would leave the drawings dark');
      else {
        for (const call of ['TH3PatternsShowAll()', 'LegMeasureShowAll()', 'HRayShowAll()', 'PathShowAll()'])
          if (!showBody.text.includes(call))
            broken.push(`the show half lost ${call}`);
        if (!showBody.text.includes('[P-UI-160b] drawings hide=0'))
          broken.push('the show half lost its flushed witness');
      }
    }
    const ob = linesOf(path.join(BIOTAK, 'EventHandlers_Objects.mqh'));
    if (!ob) broken.push('Biotak/EventHandlers_Objects.mqh is gone');
    else {
      const applyBody = bodyOf(ob, 'int ApplyHideAllState(');
      if (!applyBody || !applyBody.text.includes('ShowAllDrawingFamilies();'))
        broken.push('the show branch stopped calling ShowAllDrawingFamilies() — F-show leaves the drawings dark');
    }
    // The riders carry the hidden term; every arming/grab door refuses while hidden.
    const RIDER_SEATS = [
      ['TH3Tool_B.mqh', 'void LegMeasureHandles('],
      ['TH3Tool_B.mqh', 'void LegMeasureInk('],
      ['TH3Tool_B.mqh', 'bool LegMeasureHitTest('],
      ['TH3Tool_C.mqh', 'void LegMeasureToggle('],
      ['TH3Tool_C.mqh', 'void TH3BaseMarkToggle('],
      ['TH3Tool_A.mqh', 'void RepositionABCDInfoLabels('],
      ['HRayTool.mqh', 'void HRayArm('],
      ['HRayTool.mqh', 'void HRayHandleFollow('],
      ['HRayTool.mqh', 'bool HRayPressHit('],
      ['HRayTool.mqh', 'bool HRayDotHit('],
      ['PathTool.mqh', 'void PathArm('],
      ['PathTool.mqh', 'void PathHandleAt('],
      ['PathTool.mqh', 'bool PathPressHit('],
      ['PathTool.mqh', 'bool PathDotHit('],
      ['PathTool.mqh', 'void PathMidApply('],
      ['TH3/TH3Renderer_A.mqh', 'void TH3InfoCaptionHeal('],
      ['TH3/TH3Renderer_B.mqh', 'void DrawABCDPattern('],
      ['TH3/TH3Renderer_C.mqh', 'void TH3HitPivotForward('],
      ['TH3/TH3Controller.mqh', 'void TH3SessionStart('],
    ];
    for (const [rel, def] of RIDER_SEATS) {
      const src = linesOf(path.join(BIOTAK, rel));
      if (!src) { broken.push(`Biotak/${rel} is gone`); continue; }
      const body = bodyOf(src, def);
      if (!body) { broken.push(`${rel}: ${def} is gone — a seat the mute answers through`); continue; }
      if (!body.text.includes('IsIndicatorHidden()'))
        broken.push(`${rel}: ${def.slice(5)} no longer reads IsIndicatorHidden — the mute can be bypassed`);
    }
    if (broken.length) {
      failures.push('P-UI-160b: ' + broken.join('; ') + ' (Biotak/EventHandlers_CustomPrice.mqh + Biotak/TH3Tool_Mute.mqh + the drawing tools)');
    } else {
      console.log('[PASS] P-UI-160b the F mute takes the drawing families: both halves of the transition run (hide once, show through one owner), the four armed-session doors cancel, every rider carries the hidden term, and every arming/grab door refuses while hidden');
    }
  }

  // -- 50. P-TH-VOLNORM-COMBO (2026-10-16): the combo components wear V ----
  // The report: «این نرمال سازی مثل بقیه موده در مود کامبو کار نمیکنه سطوح
  // درست نیست نگاه کن بقیه مودها رو و درستش کن». MEASURED in the sources: the
  // TH/SS-LS ladders wear the block V (EventHandlers_Calc.mqh:550) and every TH
  // label column wears its own rung's V (Labels_B.mqh:374/474), but the combo
  // engine read the RAW table (ComputeComboComponentStep -> GetStepSizeForBasis*
  // -> GetTimeframeTHForPeriod), so combo levels sat ~2x off the normalized
  // ones. This entry locks the ONE owner (ComputeComboComponentStep) and the
  // rule the component's V pair follows: the rung whose pct IS the component's
  // pct (the same pair identity the label columns use — no second rung map),
  // an extrapolated pct falling back to the nearest rung in log-span (4^k), and
  // OFF answering 1.0 before any read (byte-identical numbers).
  {
    const broken = [];
    const ce = linesOf(path.join(BIOTAK, 'ComboEngine.mqh'));
    if (!ce) broken.push('Biotak/ComboEngine.mqh is gone — the combo step engine has no owner');
    else {
      const src = codeOf(ce);
      if (!src.includes('#include "THVolNorm.mqh"'))
        broken.push('ComboEngine stopped including THVolNorm.mqh — the V owner leaves the unit');
      const volNorm = bodyOf(ce, 'double ComboComponentVolNorm(');
      if (!volNorm) broken.push('ComboComponentVolNorm is gone — a combo component cannot wear its rung\'s V');
      else {
        if (!volNorm.text.includes('if(!inpTHVolNorm || !(pct > 0.0)) return 1.0;'))
          broken.push('ComboComponentVolNorm lost its OFF/first guard — OFF must answer 1.0 before any read');
        if (!/MathAbs\(rp - pct\)/.test(volNorm.text) || !volNorm.text.includes('FractalPercentScaled(r)'))
          broken.push('ComboComponentVolNorm no longer matches the rung by the pct the step used (a second rung map would drift)');
        if (!volNorm.text.includes('THVolNormTFForFractalRung(idx)') || !volNorm.text.includes('THVolNormDrawnV(inpTHVolNorm'))
          broken.push('ComboComponentVolNorm stopped reading the pair through THVolNormTFForFractalRung + THVolNormDrawnV (the label columns\' own identity)');
      }
      const comp = bodyOf(ce, 'double ComputeComboComponentStep(');
      if (!comp) broken.push('ComputeComboComponentStep is gone');
      else {
        if (!comp.text.includes('ComboComponentVolNorm(thPercent)'))
          broken.push('the extrapolated path lost its V — sub-minute/continuous combo levels are raw again (the reported defect)');
        if (!comp.text.includes('ComboComponentVolNorm(GetTimeframeTHForPeriod(timeframe))'))
          broken.push('the standard path lost its V — combo levels are raw again (the reported defect)');
      }
    }
    if (broken.length) {
      failures.push('P-TH-VOLNORM-COMBO: ' + broken.join('; ') + ' (Biotak/ComboEngine.mqh)');
    } else {
      console.log('[PASS] P-TH-VOLNORM-COMBO the combo components wear the normalization: every component multiplies its own rung\'s V (the rung its pct IS, the label columns\' own pair identity; extrapolated pcts take the nearest 4^k rung), and OFF answers 1.0 before any read');
    }
  }

  // -- 51. P-UI-161 (2026-10-17): the main ring grows by SHRINKING, and the
  // -- membership STAR is its only door ----------------------------------------
  // The user's model, verbatim: «خودش رینگ اصلی رو بچینه و کم و زیاد بکنه و هرچی
  // خواست اضافه بکنه و هرچی بود به بخش تولز اونایی که نمیخوادش» + «توی همون تولز که
  // هستش یک علامت ستاره باشه که بهتر و سریع تره». The Tools menu shows the WHOLE
  // catalog and every cell wears a star (top-right, Z_MENU_STAR a rung ABOVE the
  // badge — MT4 delivers a click to the highest ZORDER under the cursor, so the
  // 16px box must own its own rung or the badge answers instead); the ring shows
  // the starred subset in catalog order with the CIR_TOOLS door LAST (the only
  // place a star exists must never be unreachable). Growth: S(n) holds the shipped
  // 44 through nine seats (byte-identical), tapers 43→35 and floors at 35 (P-UI-166
  // raised the floor from 30), seats twelve at most, the radius follows the chord
  // law, the fit cap still rules, and excess stays in Tools with its star ON. What
  // a green compile cannot see, and this entry
  // locks: the mask's persistence slot (12, ledger 13), the orphan sweep (a name
  // a PREVIOUS larger mask wrote must not survive the star that removed its
  // seat), the star's create/move/delete seats, the click route sitting BEFORE
  // the long-press latch, the ONE feature switch (RingFeatureClick), the seat-set
  // freeze + CircRelayoutIfNeeded on the release/chart-change, and the FLUSHED
  // witness (a Print witness waits in MT4's RAM buffer, P-DRAW-126).
  {
    const broken = [];
    // -- the Z rung: distinct and ABOVE the badge ------------------------------
    const constants = linesOf(CONSTANTS);
    if (!constants) broken.push('Biotak/ConstantsAndEnums.mqh is gone — the Z ladder has no home');
    else {
      const constCode = codeOf(constants);
      const starZ = Number((constCode.match(/#define\s+Z_MENU_STAR\s+(\d+)/) || [])[1]);
      const badgeZ = Number((constCode.match(/#define\s+Z_MENU_BADGE\s+(\d+)/) || [])[1]);
      if (!starZ) broken.push('Z_MENU_STAR is gone — the star has no rung of its own');
      else if (!badgeZ || !(starZ > badgeZ))
        broken.push(`Z_MENU_STAR (${starZ}) is not above Z_MENU_BADGE (${badgeZ || '?'}) — a badge and a star fight over the corner, and the badge wins the click`);
    }
    // -- the mask: one owner (BiotakMenu_Ring.mqh), one slot, one ledger total -
    const menuRing = linesOf(MENU_RING);
    if (!menuRing) broken.push('Biotak/BiotakMenu_Ring.mqh is gone — the mask has no owner');
    else {
      const ringCode = codeOf(menuRing);
      if (!/#define\s+CIRC_STAR_DEFAULT\s+\(0xFF80\s*\|\s*CIRC_STAR_STAMP\)/.test(ringCode))
        broken.push('CIRC_STAR_DEFAULT is gone or moved — a missing key no longer restores the shipped 9-feature ring with its handoff stamp (bits 7..15 | stamp, P-SESS)');
      if (!/#define\s+CAT_SESSIONS\s+15\b/.test(ringCode) || !/#define\s+CAT_COUNT\s+16\b/.test(ringCode))
        broken.push('the sessions catalog cell (CAT_SESSIONS 15, CAT_COUNT 16) left BiotakMenu_Ring.mqh — the ring can never seat it while the Tools menu still shows it');
      if (!/if\(toolIdx == CAT_SESSIONS\)\s+return CIR_SESSIONS;/.test(ringCode))
        broken.push('ToolFeature stopped mapping CAT_SESSIONS -> CIR_SESSIONS — the Tools cell opens nothing');
      const setBody = bodyOf(menuRing, 'bool CircStarSet(');
      if (!setBody || !setBody.text.includes('g_CircStarMask |=') || !setBody.text.includes('g_CircStarMask &='))
        broken.push('CircStarSet lost a half — the mask\'s only writer cannot flip both ways');
      const ringCount = bodyOf(menuRing, 'int RingCount()');
      if (!ringCount || !ringCount.text.includes('CircStarCount() + 1'))
        broken.push('RingCount no longer counts stars + the door — the door can fall off the ring');
      const ringFeat = bodyOf(menuRing, 'int RingFeature(');
      if (!ringFeat || !ringFeat.text.includes('CircPlacedCount() - 1') || !ringFeat.text.includes('CIR_TOOLS'))
        broken.push('RingFeature lost the door-last law — the door rides the LAST PLACED seat (P-UI-164); off the placed set it is a menu with no way back to the stars');
      const btnN = bodyOf(menuRing, 'int CircBtnSizeForN(');
      if (!btnN || !btnN.text.includes('return CIRC_BTN_SIZE') || !btnN.text.includes('return CIRC_BTN_MIN'))
        broken.push('CircBtnSizeForN lost the shipped 44 or the 35 floor — the growth law is not the one that was measured');
      const live = bodyOf(menuRing, 'int CircPlacedCountLive()');
      if (!live || !live.text.includes('RingCount()') || !live.text.includes('CircRadiusForN(k) <= fit') || !live.text.includes('CircRailShape('))
        broken.push('CircPlacedCountLive lost the fit walk or the shape decision — the ring can stack past the fit, or a fitting train is rebuilt as nine (P-UI-164)');
    }
    // -- the persistence: slot 12 + the ledger at 13, owned by BiotakMenu_A ----
    const menuA = linesOf(MENU_A);
    if (!menuA) broken.push('Biotak/BiotakMenu_A.mqh is gone — SaveUIStates has no home');
    else {
      const saveBody = bodyOf(menuA, 'void SaveUIStates(');
      if (!saveBody) broken.push('SaveUIStates is gone');
      else {
        if (!saveBody.text.includes('GVSlotChanged(s_uiEpoch, s_uiKnown, s_uiShadow, 12, (double)g_CircStarMask)'))
          broken.push('the STAR slot (12) left SaveUIStates — every restart forgets the user\'s ring');
        if (!saveBody.text.includes('GetGVName("STAR")'))
          broken.push('the STAR key left SaveUIStates');
        if (!saveBody.text.includes('GVLedgerReport(GV_BLOCK_UI, uiChanged, 13)'))
          broken.push('the ledger total no longer counts the STAR slot — the ledger under-reports the block');
      }
      const loadBody = bodyOf(menuA, 'void LoadUIState()');
      if (!loadBody || !loadBody.text.includes('CircStarLoad(GetGVName("STAR"))'))
        broken.push('LoadUIState stopped reading the STAR key through CircStarLoad — the persisted ring never comes back (P-SESS-04)');
    }
    // -- the built-seat freeze: the frozen half, its readers, the star park ----
    const menuB = linesOf(MENU_B);
    if (!menuB) broken.push('Biotak/BiotakMenu_B.mqh is gone — the built-seat freeze has no owner');
    else {
      const placed = bodyOf(menuB, 'int CircPlacedCount()');
      if (!placed || !placed.text.includes('g_OrbDragging') || !placed.text.includes('s_circBuiltSeats'))
        broken.push('CircPlacedCount lost the mid-drag freeze — geometry rebuilds under the hand (the SubMode rule)');
      const btn = bodyOf(menuB, 'int CircBtnSize()');
      if (!btn || !btn.text.includes('CircBtnSizeForN(CircPlacedCount())'))
        broken.push('CircBtnSize no longer reads the placed count — the paint and the hit test can disagree about the side');
      const layout = bodyOf(menuB, 'void CircLayout(');
      if (!layout || !layout.text.includes('CircPlacedCount()') || !layout.text.includes('CircBtnSize()'))
        broken.push('CircLayout went back to a constant side — every seat sits on the old grid while the ring shrank');
      const park = bodyOf(menuB, 'void SubParkItem(');
      if (!park || !park.text.includes('ToolsMoveStar('))
        broken.push('SubParkItem no longer parks the star — a starred off-page cell leaves its star floating over the page');
    }
    // -- the star's lifecycle + the ring's sweep + the relayout doors ----------
    const menuC = linesOf(MENU_C);
    if (!menuC) broken.push('Biotak/BiotakMenu_C.mqh is gone — the star has no painter');
    else {
      const createStar = bodyOf(menuC, 'void ToolsCreateStar(');
      if (!createStar || !createStar.text.includes('star_on.bmp') || !createStar.text.includes('star_off.bmp') ||
          !createStar.text.includes('OBJPROP_ZORDER, Z_MENU_STAR'))
        broken.push('ToolsCreateStar lost its ink or its rung — the star paints wrong or loses its click');
      const createItem = bodyOf(menuC, 'void ToolsCreateItem(');
      if (!createItem || !createItem.text.includes('ToolsCreateStar('))
        broken.push('ToolsCreateItem stopped creating the star — the membership mark never appears');
      const moveItem = bodyOf(menuC, 'void ToolsMoveItem(');
      if (!moveItem || !moveItem.text.includes('ToolsMoveStar('))
        broken.push('ToolsMoveItem stopped moving the star — the mark stays at the old seat while its cell moves');
      const delTools = bodyOf(menuC, 'void DeleteToolsMenu(');
      if (!delTools) broken.push('DeleteToolsMenu is gone');
      else {
        if (!delTools.text.includes('ObjectDelete(0, ToolsStar(t))'))
          broken.push('the Tools sweep stopped deleting ToolsStar — the star survives its cell (an orphan paints beside the ring)');
        if (!delTools.text.includes('CircPlacedCount()') || !delTools.text.includes('CircCreateItem(i)') ||
            !delTools.text.includes('CircNoteBuilt()'))
          broken.push('DeleteToolsMenu\'s restore no longer rebuilds the ring from the mask — a star toggled in Tools never reaches the ring');
      }
      const subRebuild = bodyOf(menuC, 'void SubRebuild()');
      if (!subRebuild || !subRebuild.text.includes('ObjectDelete(0, ToolsStar(t))'))
        broken.push('SubRebuild\'s sweep stopped deleting ToolsStar — a page reshape leaves a stale star');
      const delRing = bodyOf(menuC, 'void DeleteRing()');
      if (!delRing || !delRing.text.includes('RING_MAX_SEATS'))
        broken.push('DeleteRing went back to the live count — a name a previous larger mask wrote survives the star that removed its seat');
      const relayout = bodyOf(menuC, 'void CircRelayoutIfNeeded()');
      if (!relayout || !relayout.text.includes('g_OrbDragging') || !relayout.text.includes('CircPlacedCountLive()') ||
          !relayout.text.includes('DeleteRing()'))
        broken.push('CircRelayoutIfNeeded lost its guard or its rebuild — the seat set never answers a resize or a release');
      const cCode = codeOf(menuC);
      if ((cCode.match(/CircRelayoutIfNeeded\(\);/g) || []).length < 2)
        broken.push('CircRelayoutIfNeeded has fewer than two call sites in the menu unit — the release and the chart-change path are the doors it must answer');
      const buildLines = linesOf(PANELS_BUILD);
      if (!buildLines || !codeOf(buildLines).includes('CircRelayoutIfNeeded();'))
        broken.push('the stationary-release finalizer lost CircRelayoutIfNeeded — a release with no movement never re-derives the seat set');
      const starToggle = bodyOf(menuC, 'void CircStarToggle(');
      if (!starToggle) broken.push('CircStarToggle is gone — the star has no writer');
      else {
        if (!starToggle.text.includes('CircStarSet(') || !starToggle.text.includes('SaveUIStates()'))
          broken.push('CircStarToggle no longer flips+persists — a star click that forgets is the reported defect');
        if (!starToggle.text.includes('DrawStripDiagEmit(') || !starToggle.text.includes('[P-UI-161]'))
          broken.push('CircStarToggle lost its FLUSHED witness (DrawStripDiagEmit, P-LOG-3) — a Print witness waits in MT4\'s RAM buffer (P-DRAW-126)');
      }
    }
    // -- the click route + the ONE feature switch ------------------------------
    const menuD = linesOf(MENU_D);
    if (!menuD) broken.push('Biotak/BiotakMenu_D.mqh is gone — the star has no route');
    else {
      const click = bodyOf(menuD, 'int HandleButtonClick(');
      if (!click) broken.push('HandleButtonClick is gone');
      else {
        const starAt = click.text.indexOf('ToolsStar');
        const latchAt = click.text.indexOf('g_LongPressFired');
        if (starAt < 0 || !click.text.includes('CircStarToggle(tidx)'))
          broken.push('the Tools section lost the star branch — a star click falls through to the cell (a long-press latch or a feature toggle)');
        else if (latchAt >= 0 && starAt > latchAt)
          broken.push('the star branch sits AFTER the long-press latch — a stale latch eats the star click (the badge\'s own lesson)');
        if (!click.text.includes('RingFeatureClick(tfeat)'))
          broken.push('the Tools feature cells stopped routing to RingFeatureClick — a second switch copy is how the two surfaces drift');
        if (!click.text.includes('RingFeatureClick(feat)'))
          broken.push('the ring stopped routing to RingFeatureClick');
      }
      const feat = bodyOf(menuD, 'int RingFeatureClick(');
      if (!feat) broken.push('RingFeatureClick is gone — the feature switch has no ONE owner');
      else {
        if (!feat.text.includes('ReleaseIndicatorMute()'))
          broken.push('RingFeatureClick lost the mute preamble — a press under the mute cannot show the family again (P-UI-93)');
        if (feat.text.includes('CircUpdateItemState(') || feat.text.includes('ToolsUpdateItemState('))
          broken.push('RingFeatureClick grew a tail — the caller owns the ring\'s and the Tools\' own update, and both running is the drift this split retired');
      }
    }
    // -- the icon generator bakes both inks ------------------------------------
    const iconGen = linesOf(ICON_GEN);
    if (!iconGen) broken.push('tools/gen-th3-icons.js is gone — the star art has no baker');
    else {
      const g = codeOf(iconGen);
      if (!g.includes('star_off') || !g.includes('star_on'))
        broken.push('the icon generator lost star_off/star_on — a rebuild of the tree silently drops the star art (P-UI-131)');
    }
    if (broken.length) {
      failures.push('P-UI-161: ' + broken.join('; ') + ' (Biotak/BiotakMenu_A/B/C/D.mqh + BiotakMenu_Ring.mqh + ConstantsAndEnums.mqh + tools/gen-th3-icons.js)');
    } else {
      console.log('[PASS] P-UI-161 the ring grows by shrinking: the membership star is the only door (Z_MENU_STAR above the badge, its click before the latch), the mask persists in slot 12 with the ledger at 13, the taper floors at 35 and the ring seats twelve at most (P-UI-166) with the fit walk and the mid-drag freeze, the orphan sweep is RING_MAX_SEATS, the star is created/moved/deleted with its cell, and the ONE feature switch (RingFeatureClick) is shared by the ring and the Tools cells');
    }
  }

  // -- 52. P-SESS (2026-10-17): the Sessions menu cell -------------------------
  // The sessions family ships cards 15/16 (held by the panel gates); THIS is the
  // menu half: the ring/Tools cell must exist, carry the master switch it shares
  // with the card, wear the clock, and route through the same ONE feature switch
  // every other family uses. What a green compile cannot see and this entry
  // locks: the identity fallback (CIR_SESSIONS=19 is ABOVE the card-number
  // space, so FeaturePanel MUST answer 15 or the press opens no card), the light
  // (g_sessMaster, mute-folded like the other family lights), the icon base +
  // its #resource pair (an undeclared raster is a silent runtime no-op,
  // P-UI-131), the click branch (state + persisted key + the render tick —
  // exactly ONE copy, the drift this project keeps paying for), and the Tools
  // route (the cell runs RingFeatureClick, never a second switch).
  {
    const broken = [];
    const sessA = linesOf(MENU_A);
    if (!sessA) broken.push('Biotak/BiotakMenu_A.mqh is gone — the sessions cell has no face');
    else {
      const aCode = codeOf(sessA);
      if (!/#define\s+CIR_SESSIONS\s+19\b/.test(aCode))
        broken.push('CIR_SESSIONS left BiotakMenu_A.mqh — the ring has no identity for the Sessions cell');
      if (!/#resource\s+"\\\\Files\\\\Icons\\\\sessions_off\.bmp"/.test(aCode) ||
          !/#resource\s+"\\\\Files\\\\Icons\\\\sessions_on\.bmp"/.test(aCode))
        broken.push('the sessions_off/on #resource pair left BiotakMenu_A.mqh — the terminal paints nothing (a silent no-op, P-UI-131)');
      const sessFp = bodyOf(sessA, 'int FeaturePanel(');
      if (!sessFp || !sessFp.text.includes('if(feat == CIR_SESSIONS)') || !sessFp.text.includes('return 15;'))
        broken.push('FeaturePanel stopped answering CIR_SESSIONS -> 15 — the identity fallback returns 19 and the press opens no card');
      const sessOn = bodyOf(sessA, 'bool CircFeatureOn(');
      if (!sessOn || !sessOn.text.includes('g_sessMaster'))
        broken.push('CircFeatureOn no longer reads g_sessMaster — the light and the switch can disagree');
      const sessLit = bodyOf(sessA, 'bool CircFeatureLit(');
      if (!sessLit || !sessLit.text.includes('CIR_SESSIONS'))
        broken.push('CircFeatureLit no longer folds the mute for CIR_SESSIONS — a muted sessions family stays dark after the showing press (P-UI-93)');
      const sessRes = bodyOf(sessA, 'string CircIconRes(');
      if (!sessRes || !sessRes.text.includes('CIR_SESSIONS') || !sessRes.text.includes('"sessions"'))
        broken.push('CircIconRes lost the sessions base — the cell wears the fallback glyph');
      const sessSt = bodyOf(sessA, 'string CircTooltipStatus(');
      if (!sessSt || !sessSt.text.includes('CIR_SESSIONS'))
        broken.push('CircTooltipStatus lost the sessions state fragment — the chip cannot say what the NEXT press does');
    }
    const sessD = linesOf(MENU_D);
    if (!sessD) broken.push('Biotak/BiotakMenu_D.mqh is gone — the sessions click has no route');
    else {
      const dCode = codeOf(sessD);
      if (!/tfeat == CIR_SESSIONS/.test(dCode))
        broken.push('the Tools feature ladder stopped passing CIR_SESSIONS — the catalog cell falls through to nothing');
      const sessFeat = bodyOf(sessD, 'int RingFeatureClick(');
      if (!sessFeat) broken.push('RingFeatureClick is gone — the feature switch has no ONE owner');
      else {
        if (!sessFeat.text.includes('feat == CIR_SESSIONS') || !sessFeat.text.includes('g_sessMaster = wantOn'))
          broken.push('RingFeatureClick lost the sessions branch — the press cannot flip the master');
        if ((sessFeat.text.match(/g_sessMaster\s*=/g) || []).length !== 1)
          broken.push('g_sessMaster is written more than once in RingFeatureClick — the master must have ONE writer');
        if (!sessFeat.text.includes('RuntimeSettingsSaveOverridesThrottled()') || !sessFeat.text.includes('SessionsTick()'))
          broken.push('the sessions branch lost its persisted key or its render tick — the master flips in RAM only');
        if (!sessFeat.text.includes('familyToggle'))
          broken.push('the sessions branch left the familyToggle fold — a muted press cannot show the family again (P-UI-93)');
      }
    }
    const sessRing = linesOf(MENU_RING);
    if (!sessRing) broken.push('Biotak/BiotakMenu_Ring.mqh is gone — the saved-mask handoff has no home');
    else {
      const rCode = codeOf(sessRing);
      if (!/#define\s+CIRC_STAR_STAMP\s+0x10000\b/.test(rCode))
        broken.push('CIRC_STAR_STAMP is gone — an unstamped pre-SESSIONS mask and an explicit unstar become the same number');
      const sessLoad = bodyOf(sessRing, 'uint CircStarLoad(');
      if (!sessLoad) broken.push('CircStarLoad is gone — the saved mask has no ONE handoff writer');
      else {
        if (!sessLoad.text.includes('v |= (uint)(0x8000 | CIRC_STAR_STAMP)'))
          broken.push('the handoff stopped starring bit 15 — an upgraded chart keeps a clockless ring (the report this entry was born from)');
        if (!sessLoad.text.includes('GlobalVariableSet(key, (double)v)'))
          broken.push('the handoff stopped writing its stamp — every attach re-migrates');
        if (!sessLoad.text.includes('DrawStripDiagEmit'))
          broken.push('the handoff lost its flushed witness — a repeat migration is unprovable (P-DRAW-126)');
      }
    }
    if (sessA) {
      const aLoad = bodyOf(sessA, 'void LoadUIState(');
      if (!aLoad || !aLoad.text.includes('CircStarLoad(GetGVName("STAR"))'))
        broken.push('LoadUIState stopped calling CircStarLoad — the saved mask is read raw again (P-SESS-04)');
    }
    const sessGen = linesOf(ICON_GEN);
    if (!sessGen) broken.push('tools/gen-th3-icons.js is gone — the sessions art has no baker');
    else if (!codeOf(sessGen).includes('sessions:'))
      broken.push('the icon generator lost ART.sessions — a rebuild of the tree silently drops the clock (P-UI-131)');
    // -- the box body is build-proof (P-SESS-05, 2026-10-17) --------------------
    // MEASURED on the reporting chart: every session box shipped as a SOLID
    // saturated slab — a rectangle renders filled whatever FILL says on some
    // MT4 builds, the same law ZoneFactory.mqh:143 pays with border segments.
    // MEASURED AGAIN 16:31 after the deploy: the FILLED path (BGCOLOR = the
    // 14% tint, FILL written true) still shipped as a solid slab — this build
    // fills a rectangle with its COLOR; BGCOLOR and FILL are both unconsumed.
    // So the renderer routes by kind — HOLLOW = the four edge segments (the
    // only body that cannot slab), FILLED = the one rectangle with its fill
    // CLAIMED (FILL written true) — and the FACTORY ships HOLLOW: the calm
    // look may only ride the edges.
    const sessDraw = linesOf(SESS_DRAW);
    if (!sessDraw) broken.push('Biotak/Sessions_Draw.mqh is gone — the session boxes have no renderer');
    else {
      const dCode = codeOf(sessDraw);
      if (!['ET', 'EB', 'EL', 'ER'].every(t => dCode.includes('nm + "' + t + '"')))
        broken.push('the hollow box left its four edge segments — the rectangle renders as a solid slab again (the report this entry was born from, ZoneFactory.mqh:143)');
      if (!/ObjectSetInteger\(0, nm, OBJPROP_FILL, true\)/.test(dCode))
        broken.push('the filled box stopped claiming its fill — OBJPROP_FILL is written true, never assumed (P-SESS-05)');
    }
    const sessModel = linesOf(SESS_MODEL);
    if (!sessModel) broken.push('Biotak/Sessions_Model.mqh is gone — the session factory has no home');
    else if (!/s\.style\s*=\s*SESS_STYLE_OUTLINE;/.test(codeOf(sessModel)))
      broken.push('the factory session box left OUTLINE — FILLED slabs a fresh chart on the reporting build (ZoneFactory.mqh:143): the busy chart this entry was born from');

    // -- the LIVE session is bold, the past ones fade (P-SESS-06, 2026-10-17) -----
    // The user's ask: «سشن که لایو درش هستشم فرق بکنه استایل و غیره که بولد بشه و
    // قدیمها جوری متمایز باشه». ONE ink rule over the started windows: the LIVE
    // one keeps the base ink at width 2, every PAST one fades to SESS_PAST_ALPHA at
    // width 1, and the live window's H/L lines take the same width. The ghost rung
    // (dotted, 62) stays the weaker one below past. The muted palette (steel/gold/
    // sage) rides SessColorOf alone — indices never move, no persisted bit stirs.
    if (sessDraw) {
      const p6 = codeOf(sessDraw);
      if (!/bool\s+wLive\s*=\s*\(SessWindowState\(wins\[w\], now\) == SESS_WS_LIVE\);/.test(p6))
        broken.push('the box loop lost its live test — past and live windows paint alike again (the report this entry was born from)');
      if (!/color\s+ink\s*=\s*wLive\s*\?\s*base\s*:\s*SessBlend\(base,\s*SESS_PAST_ALPHA\);/.test(p6))
        broken.push('the box ink lost the live/past split — past windows keep the base ink (P-SESS-06)');
      if (!/int\s+bW\s*=\s*wLive\s*\?\s*2\s*:\s*1;/.test(p6))
        broken.push('the box width lost the live/past split — the session you are in is no longer bold (P-SESS-06)');
      if (!/SessZoneTag\(s\.zone\), ink, SESS_PT_LBL/.test(p6))
        broken.push('the box tag left the live/past ink — the label keeps full ink on faded past boxes (P-SESS-06)');
      if (!/bool\s+wLinLive\s*=\s*\(wins\[wLin\]\.kk == 0 && SessWindowState\(wins\[wLin\], now\) == SESS_WS_LIVE\);/.test(p6))
        broken.push('the live-window test vanished from the H/L block — the live cache and the bold width lost their ONE owner (P-SESS-06)');
      if (!/int\s+lw\s*=\s*wLinLive\s*\?\s*2\s*:\s*1;/.test(p6))
        broken.push("the live window's H/L lines lost their bold width (P-SESS-06)");
      if (!/#define\s+SESS_PAST_ALPHA\s+45\b/.test(p6))
        broken.push('SESS_PAST_ALPHA left Sessions_Draw.mqh — the past fade has no owner constant (P-SESS-06)');
    }
    if (broken.length) {
      failures.push('P-SESS: ' + broken.join('; ') + ' (Biotak/BiotakMenu_A/D.mqh + BiotakMenu_Ring.mqh + Biotak/Sessions_Model.mqh + Biotak/Sessions_Draw.mqh + tools/gen-th3-icons.js)');
    } else {
      console.log('[PASS] P-SESS the Sessions cell is wired end to end: identity 19 with FeaturePanel -> 15 (never the identity fallback), the light is g_sessMaster (mute-folded), the clock icon base with its #resource pair, ONE writer per fact in RingFeatureClick (state + OV_SSON + SessionsTick), the Tools cell runs the same switch, and the factory box ships hollow (OUTLINE — the only body that cannot slab); the LIVE window is bold (box w2 + its H/L, base ink) while every PAST window fades (SESS_PAST_ALPHA) — ghosts stay the weaker rung');
    }
  }

  // -- 52b. P-UI-137 (2026-10-20): a HOLD on a card-less tool owns no card -----
  // The four tools that own no card (Horizontal Ray, Path, Chart Scale, Hide)
  // fell through FeaturePanel's IDENTITY fallback, so a hold opened somebody
  // else's card (15 = Sessions, 16 = Session Editor) or none at all (17/18 are
  // past PNL_COUNT) - and the release was eaten by UISuppressNextClick, so the
  // cell's own action (arm the ray, the scale-fix, the F mute) never ran.
  {
    const broken = [];
    const fp = bodyOf(linesOf(MENU_A) || [], 'int FeaturePanel(');
    if (!fp) broken.push('FeaturePanel is gone from BiotakMenu_A.mqh - the feature->card map has no owner');
    else {
      for (const f of ['CIR_HRAY', 'CIR_PATH', 'CIR_SCALE', 'CIR_HIDE'])
        if (!fp.text.includes(f)) broken.push(`FeaturePanel stopped answering ${f} - the hold falls through to the identity fallback and opens a card that belongs to somebody else`);
      if (!/return -1;/.test(fp.text)) broken.push('FeaturePanel never answers -1 - "no card" has no spelling');
    }
    const mc = codeOf(linesOf(MENU_C) || []);
    if (!/if\(rp < 0\) return;/.test(mc)) broken.push("the ring's hold arm stopped refusing a card-less item - a hold on it opens nothing and eats the release");
    if (!/if\(ToolPanel\(toolHit\) < 0\) return;/.test(mc)) broken.push("the Tools hold arm stopped refusing a card-less item");
    if (!/if\(g_LongPressItem < 0 \|\| g_LongPressItem >= PNL_COUNT\) \{ g_LongPressFired = false; return; \}/.test(mc))
      broken.push('the hold FIRE stopped refusing a card-less item - the release is eaten and the cell reads as dead');
    if (broken.length) {
      failures.push('P-UI-137: ' + broken.join('; ') + ' (Biotak/BiotakMenu_A.mqh + Biotak/BiotakMenu_C.mqh)');
    } else {
      console.log('[PASS] P-UI-137 a hold on a card-less tool opens no card and eats no click: FeaturePanel answers -1 for the four tools that own none, both hold arms refuse it, and the fire refuses an out-of-range card without suppressing the release');
    }
  }

  // -- 52c. P-UI-138 (2026-10-20): the strip's text fields own the keyboard ----
  // MT4 delivers the key stream to a focused OBJ_EDIT, so every letter hotkey
  // fired while the user typed into the strip's own four text fields (the level
  // input, the caption, the template name, the level note).
  {
    const broken = [];
    const er = linesOf(EVENT_ROUTER);
    if (!er) broken.push('Biotak/EventHandlers_Router.mqh is gone - the KEYDOWN guard has no home');
    else {
      const rCode = codeOf(er);
      if (!/bool AnyStripTextFieldFocused\(\)/.test(rCode))
        broken.push('the strip-field focus probe is gone - the hotkeys fire while the user types');
      if (!/if\(g_PalHexFocus \|\| g_BkTextFocus \|\| AnyStripTextFieldFocused\(\)\) return;/.test(rCode))
        broken.push('the KEYDOWN guard stopped asking the strip fields - a letter typed into a name toggles a product hotkey');
      const probe = bodyOf(er, 'bool AnyStripTextFieldFocused(');
      if (!probe || !probe.text.includes('OBJPROP_STATE') || !probe.text.includes('DrawStripEditName(e)'))
        broken.push('the probe stopped reading the field\'s own STATE - a latched flag would swallow the hotkeys for as long as the panel is open');
    }
    if (broken.length) {
      failures.push('P-UI-138: ' + broken.join('; ') + ' (Biotak/EventHandlers_Router.mqh)');
    } else {
      console.log('[PASS] P-UI-138 the strip\'s own text fields own the keyboard: the KEYDOWN guard asks the fields\' own STATE (the terminal\'s answer, not a latched flag), so a letter typed into a level, a caption, a template name or a level note fires no hotkey');
    }
  }

  // -- 53. P-UI-162 (2026-10-17): the ring's art is the BOX's size --------------
  // The user's report: «چرا اینطوری میشه این ایکون ها دیگه دایره نیست» — after
  // P-UI-161's taper entered the teens (13 seats -> S=32), every disc read as a
  // rounded SQUARE with a flat right edge. Measured cause: MT4 blits an
  // OBJ_BITMAP_LABEL's BMP 1:1 from the object's top-left and CLIPS it at
  // XSIZE/YSIZE — it never scales — while circ_off/on.bmp stayed a 52px canvas
  // in the taper's s+2*CIRC_BG_MARGIN box: at 13 seats the box is 40px, so the
  // disc's right and bottom arcs were cut (the face's right edge measured
  // constant at the box boundary, x=208, for 17 rows). This entry locks the one
  // law that closes it: for EVERY side CircBtnSizeForN can return, a
  // circ_*_<s>.bmp exists and measures exactly s + 2*CIRC_BG_MARGIN (canvas ==
  // box), CircBgRes resolves the painter's skin (no painter names a canvas), and
  // the GLYPH keeps ONE size on every path — create, update and move all seat
  // the 28px glyph canvas in a 28px box (the tapered CircIconSize() box clipped
  // the pin's tip at 10+ seats and healed only by CircUpdateItemState's default).
  {
    const broken = [];
    const ICONS = path.join(ROOT, 'Files', 'Icons');
    const bmpWH = (p) => {
      try {
        const b = fs.readFileSync(p);
        return [b.readUInt32LE(18), b.readUInt32LE(22)];
      } catch {
        return null;
      }
    };
    // -- one list: the taper's sides and the art that must exist for them ------
    const ringLines = linesOf(MENU_RING);
    let sides = [];
    if (!ringLines) broken.push('Biotak/BiotakMenu_Ring.mqh is gone — the taper and its art resolver have no home');
    else {
      const btnBody = bodyOf(ringLines, 'int CircBtnSizeForN(');
      const menuALinesForMin = linesOf(MENU_A);
      const minDef = Number((codeOf(menuALinesForMin || []).match(/#define\s+CIRC_BTN_MIN\s+(\d+)/) || [])[1]);
      if (!btnBody) broken.push('CircBtnSizeForN is gone — the taper has no owner');
      else {
        const numeric = (btnBody.text.match(/return\s+\d+;/g) || []).map((m) => Number(m.match(/\d+/)[0]));
        sides = [...new Set([...numeric, minDef])].filter((v) => Number.isFinite(v) && v > 0 && v < 44);
        if (!sides.length) broken.push('CircBtnSizeForN no longer returns any numeric taper side below 44 — the art set cannot be derived from the one list');
      }
      // the canvases: one baked pair per side, at exactly s + 2*CIRC_BG_MARGIN
      for (const s of sides) {
        const w = s + 8;
        for (const ink of ['on', 'off']) {
          const wh = bmpWH(path.join(ICONS, `circ_${ink}_${s}.bmp`));
          if (!wh) broken.push(`Files/Icons/circ_${ink}_${s}.bmp is missing — a ${s}px seat would clip the shipped 52px canvas again (the reported defect)`);
          else if (wh[0] !== w || wh[1] !== w)
            broken.push(`Files/Icons/circ_${ink}_${s}.bmp measures ${wh[0]}x${wh[1]}, not ${w}x${w} (side + 2*CIRC_BG_MARGIN) — canvas != box is the clip that shipped round tiles as cut squares`);
        }
      }
      const shipped = bmpWH(path.join(ICONS, 'circ_on.bmp'));
      if (!shipped || shipped[0] !== 52 || shipped[1] !== 52)
        broken.push(`Files/Icons/circ_on.bmp measures ${shipped ? shipped[0] + 'x' + shipped[1] : 'nothing'}, not 52x52 — the nine-seat look must stay the byte-identical shipped canvas`);
      // the resolver: a literal for every side, the 44 pair as the fallback
      const resBody = bodyOf(ringLines, 'string CircBgRes(');
      if (!resBody) broken.push('CircBgRes is gone — the painter has no per-side art resolver');
      else {
        for (const s of sides) {
          if (!resBody.text.includes(`circ_on_${s}.bmp`) || !resBody.text.includes(`circ_off_${s}.bmp`))
            broken.push(`CircBgRes cannot hand out the ${s}px pair — that seat falls back to a canvas its box cuts`);
        }
        if (!resBody.text.includes('circ_on.bmp') || !resBody.text.includes('circ_off.bmp'))
          broken.push('CircBgRes lost the shipped 44 pair — the fallback canvas has no declaration left');
      }
    }
    // -- the #resource pairs (an undeclared raster is a silent no-op, P-UI-131) -
    const menuALines = linesOf(MENU_A);
    if (!menuALines) broken.push('Biotak/BiotakMenu_A.mqh is gone — the art has no #resource');
    else {
      const aCode = codeOf(menuALines);
      for (const s of sides) {
        for (const ink of ['on', 'off']) {
          if (!aCode.includes(`#resource "\\\\Files\\\\Icons\\\\circ_${ink}_${s}.bmp"`))
            broken.push(`the circ_${ink}_${s} #resource left BiotakMenu_A.mqh — the terminal paints nothing (a silent no-op, P-UI-131)`);
        }
      }
    }
    // -- the painters read the resolver; the glyph keeps ONE size ---------------
    const menuC = linesOf(MENU_C);
    if (!menuC) broken.push('Biotak/BiotakMenu_C.mqh is gone — the ring has no painter');
    else {
      const create = bodyOf(menuC, 'void CircCreateItem(');
      if (!create || !create.text.includes('CircBgRes(on)'))
        broken.push('CircCreateItem stopped resolving its skin through CircBgRes — a fixed canvas name is the reported defect');
      else if (!create.text.includes('CircConfigureIcon(icon, feat, on, x, y)'))
        broken.push('CircCreateItem no longer seats the glyph at CIRC_ICON_SIZE (no size argument)');
      const update = bodyOf(menuC, 'void CircUpdateItemState(');
      if (!update || !update.text.includes('CircBgRes(on)'))
        broken.push('CircUpdateItemState stopped resolving its skin through CircBgRes — an update re-writes a wrong canvas onto a correct box');
      const move = bodyOf(menuC, 'void CircMoveItem(');
      if (!move || !move.text.includes('CIRC_ICON_SIZE / 2'))
        broken.push('CircMoveItem stopped seating the glyph by CIRC_ICON_SIZE/2 — a drag shifts the glyph off its disc');
      if (codeOf(menuC).includes('CircIconSize'))
        broken.push('CircIconSize is back — a tapered glyph box clips the 28px glyph canvas (create/update/move must all agree on CIRC_ICON_SIZE)');
    }
    const menuB = linesOf(MENU_B);
    if (!menuB) broken.push('Biotak/BiotakMenu_B.mqh is gone');
    else if (codeOf(menuB).includes('CircIconSize'))
      broken.push('CircIconSize is back in BiotakMenu_B.mqh — the glyph box must not taper with the disc');
    // -- the baker still bakes the whole family --------------------------------
    const iconGen = linesOf(ICON_GEN);
    if (!iconGen) broken.push('tools/gen-th3-icons.js is gone — the ring art has no baker');
    else {
      const g = codeOf(iconGen);
      if (!g.includes('function circSkin(on, s = 44)'))
        broken.push('circSkin lost its side parameter — every bake is the 44 canvas again (a taper seat clips)');
      for (const s of sides) {
        if (!g.includes(`circSkin(false, ${s})`) || !g.includes(`circSkin(true, ${s})`))
          broken.push(`the generator stopped baking the ${s}px pair — a rebuild of the tree silently drops it (P-UI-131)`);
      }
    }
    if (broken.length) {
      failures.push('P-UI-162: ' + broken.join('; ') + ' (Biotak/BiotakMenu_A/B/C.mqh + BiotakMenu_Ring.mqh + tools/gen-th3-icons.js)');
    } else {
      console.log('[PASS] P-UI-162 the ring\'s art is the box\'s size: every taper side owns a circ_*_<s>.bmp baked at s+8 (canvas == box, no clip), CircBgRes hands it out with the 44 fallback, the glyph is CIRC_ICON_SIZE (28) on create/update/move alike, and the generator still bakes the family');
    }
  }

  // -- 54. P-UI-163 (2026-10-17): a missing glyph is repaired, never skipped ----
  // The user's report: the frame captured at 12:05:39 after remove & re-add showed
  // ring seats with their glass discs ON the chart and NO glyph inside, and the
  // state survived until a chart change rebuilt the ring from scratch. Measured
  // cause: every ring path agreed that a MISSING icon is invisible —
  // CircCreateItem's icon was delete+recreate in ONE tick (the bg path was already
  // create-if-missing) and returned silently when the re-create failed mid-burst;
  // CircUpdateItemState configured the icon only `if(ObjectFind >= 0)`, i.e. only
  // when it EXISTS; the P-UI-161 sync's hash fingerprints the DESIRED state, never
  // the chart; CircRelayoutIfNeeded compares seat COUNTS. Nothing wrote a missing
  // icon back, so only a full rebuild healed it. This entry locks the law: the
  // icon is created-if-missing on every writer (never deleted), a failed create
  // says so through the flushed channel, and CircHealRingStep() probes ONE seat
  // per tick (round-robin) so any hole is rebuilt within CircPlacedCount() ticks —
  // 2 ObjectFind per tick, 0 writes while the ring is whole (the tip's own
  // P-PERF-17 shape).
  {
    const broken = [];
    const menuC54 = linesOf(MENU_C);
    if (!menuC54) broken.push('Biotak/BiotakMenu_C.mqh is gone — the ring has no painter');
    else {
      const create54 = bodyOf(menuC54, 'void CircCreateItem(');
      if (!create54) broken.push('CircCreateItem is gone — the ring has no creator');
      else {
        if (!create54.text.includes('[P-UI-163] icon create FAILED'))
          broken.push('CircCreateItem lost its failed-create witness — a silent hole is unprovable again');
        if (create54.text.includes('ObjectDelete(0, icon)'))
          broken.push('CircCreateItem deletes its icon again — same-tick delete+recreate is the measured hole class');
      }
      const tcreate54 = bodyOf(menuC54, 'void ToolsCreateItem(');
      if (!tcreate54) broken.push('ToolsCreateItem is gone — the tools cells have no creator');
      else if (!tcreate54.text.includes('[P-UI-163] tools icon create FAILED'))
        broken.push('ToolsCreateItem lost the same create-if-missing law — the second live writer of the defect class');
      const update54 = bodyOf(menuC54, 'void CircUpdateItemState(');
      if (!update54) broken.push('CircUpdateItemState is gone — the sync pass has no per-seat owner');
      else if (!update54.text.includes('[P-UI-163] icon heal seat='))
        broken.push('CircUpdateItemState skips a missing glyph again — the one state that needed the pass is the one it ignores');
      // -- P-UI-163c (MEASURED 2026-10-17, the 17:07 frame): while the Tools fan
      // was open a state change ran the sync loop, CircUpdateItemState re-created
      // every swept icon WITHOUT its bg (13 × icon heal), and the chart showed the
      // bare-glyph ring the user photographed. The loop lacked the g_ToolsOpen
      // guard every other ring writer carries; the open sweep took icon+bg but left
      // the badge family; and a seat/cell tip could outlive its surface.
      const states54 = bodyOf(menuC54, 'void UpdateCircularItemStates(');
      if (!states54) broken.push('UpdateCircularItemStates is gone — the sync pass has no owner');
      else {
        // P-UI-167 owns the CLOSED half of the same test (section 64); the fan half is
        // asserted without the `if(` prefix so adding a guard in front cannot silence
        // this assertion — the inverse that removes the fan test still fails HERE.
        if (!states54.text.includes('!g_ToolsOpen'))
          broken.push('UpdateCircularItemStates paints the ring while the Tools fan owns the screen again — the 17:07 bare-glyph resurrection');
        if (!states54.text.includes('ToolsUpdateItemState(t)'))
          broken.push('UpdateCircularItemStates stopped serving the open fan\'s cells');
      }
      const open54 = bodyOf(menuC54, 'void CreateToolsMenu(');
      if (!open54) broken.push('CreateToolsMenu is gone — the Tools fan has no opener');
      else {
        if (!open54.text.includes('CircBadgeBg(i)') || !open54.text.includes('CircBadgeTxt(i)'))
          broken.push('the open sweep left the badge family behind — bare badge art over the chart');
        if (!open54.text.includes('CircTipDisarm()'))
          broken.push('a seat tip survives the ring it describes — the open edge must disarm');
      }
      const close54 = bodyOf(menuC54, 'void DeleteToolsMenu(');
      if (!close54) broken.push('DeleteToolsMenu is gone — the Tools fan has no closer');
      else if (!close54.text.includes('CircTipDisarm()'))
        broken.push('the close edge leaves a cell tip describing a deleted cell — the twin-edge disarm is gone');
      const menuD54 = linesOf(MENU_D);
      const heal54 = menuD54 ? bodyOf(menuD54, 'void CircHealRingStep(') : null;
      if (!heal54) broken.push('CircHealRingStep is gone — a hole no state change announces has no healer');
      else {
        if (!heal54.text.includes('CircCreateItem(i)'))
          broken.push('CircHealRingStep stopped rebuilding the holed seat');
        if (!heal54.text.includes('[P-UI-163] ring heal seat='))
          broken.push('CircHealRingStep lost its flush witness — a heal nobody can count');
        if (!heal54.text.includes('g_ToolsOpen') || !heal54.text.includes('g_OrbDragging') || !heal54.text.includes('menuVisible'))
          broken.push('CircHealRingStep lost a guard — healing fights the tools menu (which owns no ring) or a live drag');
        if (!heal54.text.includes('ToolsCreateItem(t)') || !heal54.text.includes('[P-UI-163] tools heal cell='))
          broken.push('CircHealRingStep stopped serving the fan\'s cells — a cell\'s failed create is a permanent hole again');
        if (!heal54.text.includes('CircBadgeBg(i)'))
          broken.push('the ring probe no longer sees a badge hole — half the seat family went blind');
      }
    }
    const kit54 = linesOf(KIT);
    if (!kit54) broken.push('Biotak/BiotakKit.mqh is gone — the per-tick refresh has no home');
    else if (!codeOf(kit54).includes('CircHealRingStep();'))
      broken.push('the per-tick refresh stopped calling CircHealRingStep() — the probe is declared but never runs');
    if (broken.length) {
      failures.push('P-UI-163: ' + broken.join('; ') + ' (Biotak/BiotakMenu_C/D.mqh + BiotakKit.mqh)');
    } else {
      console.log('[PASS] P-UI-163 a missing glyph is repaired, never skipped: the icon is created-if-missing on the ring and the tools cells, a failed create heals through CircUpdateItemState/CircHealRingStep with flushed witnesses, and the per-tick probe runs (2 ObjectFind/tick, 0 writes while whole). P-UI-163c: the sync stands down while the fan is open, the open sweep takes the whole seat family (badge included), both tip edges disarm, and the per-tick probe serves the fan\'s cells meanwhile');
    }
  }

  // -- 55. P-UI-164 (2026-10-17): the capacity is the DRAWN layout's own -------
  // The user's report («من اینو جابجا و رها میکنم بقیه ایتم ها چرا گم میشن و
  // نیستش»): a 13-seat ring dragged to a chart edge and released came back as 9
  // seats — the tail stars AND the Tools door. MEASURED in
  // biotak_diag_EURUSD_134362571361933137.txt: the DELFLUSH sweep carries 13
  // seats (0..12) and a re-create that follows writes 9 (0..8). Cause: the
  // capacity answered CircFitLimit's ray-vs-bounds — a RING's question — while
  // the DRAWN layout at an edge is the TRAIN, whose room is the edge's free run.
  // This entry locks the one law that closes it: ONE shape decision
  // (CircRailShape) read by the capacity AND the paint, the train's own fit walk
  // (CircRailCapacity — every candidate at ITS OWN side, the door-alone floor),
  // the chord gate (the ring is drawn only where CircRingFits proves no P-UI-13
  // stack: never a capped circle below its chord), and the door riding the LAST
  // PLACED seat so it can never fall off with the tail.
  {
    const broken = [];
    const menuRing = linesOf(MENU_RING);
    if (!menuRing) broken.push('Biotak/BiotakMenu_Ring.mqh is gone — the shape law has no owner');
    else {
      const shape = bodyOf(menuRing, 'bool CircRailShape(');
      if (!shape || !shape.text.includes('CircRingFits()') || !shape.text.includes('CIRC_EDGE_TRIGGER'))
        broken.push('CircRailShape is gone or no longer rides the near-edge trigger with the ring-fit gate — the paint and the capacity can disagree again');
      const ringFits = bodyOf(menuRing, 'bool CircRingFits()');
      if (!ringFits || !ringFits.text.includes('CircChordRadiusForN(n)') || !ringFits.text.includes('CircChordRadiusForN(9)'))
        broken.push('CircRingFits lost the chord gate — the squeeze band draws a capped circle BELOW its chord (44px seats 32px apart, the P-UI-13 stack)');
      const cap = bodyOf(menuRing, 'int CircRailCapacity(');
      if (!cap || !cap.text.includes('CircBtnSizeForN(k)') || !cap.text.includes('CIRC_PAD') || !cap.text.includes('return 1'))
        broken.push('CircRailCapacity lost its own-side walk or its door-alone floor — a seat measured at a side it is not drawn at, or a door that can vanish with the tail');
      const live = bodyOf(menuRing, 'int CircPlacedCountLive()');
      if (!live || !live.text.includes('CircRailShape(') || !live.text.includes('CircRailCapacity('))
        broken.push('CircPlacedCountLive stopped asking the DRAWN layout — the release rebuilds a fitting train as nine seats and the tail (door included) vanishes (the reported defect)');
      const ringFeat = bodyOf(menuRing, 'int RingFeature(');
      if (!ringFeat || !ringFeat.text.includes('CircPlacedCount() - 1') || !ringFeat.text.includes('CIR_TOOLS'))
        broken.push('RingFeature stopped seating the door on the LAST PLACED seat — the door is unreachable wherever the cap seats fewer than the mask');
    }
    const menuB = linesOf(MENU_B);
    if (!menuB) broken.push('Biotak/BiotakMenu_B.mqh is gone — the paint has no home');
    else {
      const layout = bodyOf(menuB, 'void CircLayout(');
      if (!layout || !layout.text.includes('CircRailShape(vertical, dir)'))
        broken.push('CircLayout does not ask CircRailShape — the painted layout and the capacity are two grids again');
      else if (layout.text.includes('nearLeft || nearRight || nearTop || nearBottom'))
        broken.push('CircLayout grew its own near-edge branch back — a second shape decision is a second grid');
    }
    if (broken.length) {
      failures.push('P-UI-164: ' + broken.join('; ') + ' (Biotak/BiotakMenu_Ring.mqh + BiotakMenu_B.mqh)');
    } else {
      console.log('[PASS] P-UI-164 the capacity is the drawn layout\'s own: ONE shape decision (CircRailShape) is read by the capacity and the paint alike, the train seats at its own side (CircRailCapacity, door-alone floor), the ring draws only where CircRingFits proves the chord (P-UI-13), and the door rides the LAST PLACED seat');
    }
  }

  // -- 56. P-UI-165 (2026-10-17): the place belongs to the PAIR ---------------
  // User report: several instances on different pairs «تداخل نداشته باشیم باهم و
  // همین باعث میشه این مشکلات پیش بیاد». P-UI-131e's chart-free home key made ONE
  // pair's hand land EVERY other pair at its next attach/refresh — an orb parked
  // near an edge came back near the edge everywhere, and P-UI-164's squeezed ring
  // (or vanished tail) followed it. The keys now carry the SYMBOL; the CHART ID
  // still may not (it is per SESSION — a home would be lost on every restart, the
  // defect 131e fixed). The pre-165 spellings are READ-ONLY migration sources:
  // GVHomeLoadFrac snapshots the shared pair into the pair's own key once, in a
  // measured window, InitializeUISupport does the same for the panel cards, and no
  // writer ever writes or deletes the shared keys — every other pair still needs
  // them until it migrates.
  {
    const broken = [];
    const homes165 = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakHomes.mqh'), 'utf8');
    const declLine = (fn) => { const at = homes165.indexOf(fn); return at < 0 ? null : homes165.slice(at, homes165.indexOf('\n', at)); };
    const fnBody = (fn) => { const at = homes165.indexOf(fn); return at < 0 ? null : homes165.slice(at, homes165.indexOf('\n}', at)); };
    const fkey = declLine('string GVHomeFracName(');
    const pkey = declLine('string GVHomeName(');
    if (!fkey || fkey.indexOf('_Symbol + "_HOME_"') < 0)
      broken.push('`GVHomeFracName` carries no symbol again — a place chosen on EURUSD lands on GBPUSD, and the squeeze the user reports follows it (P-UI-165)');
    if (!pkey || pkey.indexOf('_Symbol + "_HOME_"') < 0)
      broken.push('`GVHomeName` carries no symbol again — the pixel fallback is shared by every pair (P-UI-165)');
    if ((fkey && fkey.indexOf('ChartID') >= 0) || (pkey && pkey.indexOf('ChartID') >= 0))
      broken.push('a home key carries a chart id — an id is per SESSION, so the place would be lost on every restart (P-UI-131e, P-UI-165)');
    const fshared = declLine('string GVHomeFracNameShared(');
    const pshared = declLine('string GVHomeNameShared(');
    if (!fshared || fshared.indexOf('_Symbol') >= 0 || fshared.indexOf('"BIOMENU_HOME_" + id') < 0)
      broken.push('`GVHomeFracNameShared` — the pre-165 read-only spelling — is gone or off `BIOMENU_HOME_<id>`, so an upgrade cannot find the place the hand already chose (P-UI-165)');
    if (!pshared || pshared.indexOf('_Symbol') >= 0 || pshared.indexOf('"BIOMENU_HOME_" + id') < 0)
      broken.push('`GVHomeNameShared` — the pre-165 read-only spelling — is gone or moved (P-UI-165)');
    const kn = fnBody('bool GVHomeFracKnown(');
    if (!kn || kn.indexOf('GVHomeFracNameShared(id,false)') < 0 || kn.indexOf('GVHomeFracNameShared(id,true)') < 0)
      broken.push('`GVHomeFracKnown` lost the shared fallback — a pre-165 store answers «no home» and every surface drops to its default on the upgrade (P-UI-165)');
    const rd = fnBody('bool GVHomeFracRead(');
    if (!rd || rd.indexOf('GVHomeFracGet(id,false)') < 0 || rd.indexOf('GVHomeFracGet(id,true)') < 0)
      broken.push('the reader no longer asks `GVHomeFracGet` — the pre-165 value can never be seen or migrated (P-UI-165)');
    const wf = fnBody('void GVHomeWriteFrac(');
    if (!wf || wf.indexOf('Shared') >= 0)
      broken.push('the ONE writer touches the shared pre-165 keys — writing them moves every other pair, deleting them strands it (P-UI-165)');
    const lf = fnBody('bool GVHomeLoadFrac(');
    if (!lf || lf.indexOf('GVHomeFracKnownOwn(id)') < 0 || lf.indexOf('GVHomeSaveFracHand(id, x, y)') < 0)
      broken.push('`GVHomeLoadFrac` no longer snapshots the shared pair into the pair\'s own key — every pair reads the shared one forever, and the next hand move on ANY pair would move them all (P-UI-165)');
    const panels165 = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakPanels_Build.mqh'), 'utf8');
    const pkAt = panels165.indexOf('string PnlFracKey(');
    const pk = pkAt < 0 ? null : panels165.slice(pkAt, panels165.indexOf('\n', pkAt));
    if (!pk || pk.indexOf('_Symbol + "_PNL_"') < 0)
      broken.push('`PnlFracKey` carries no symbol again — a panel dragged on one pair lands on every pair (P-UI-165)');
    if (pk && pk.indexOf('ChartID') >= 0)
      broken.push('the panel key carries a chart id — per session; the place would be lost on every restart (P-UI-131e, P-UI-165)');
    const kit165 = fs.readFileSync(path.join(ROOT, 'Biotak', 'BiotakKit.mqh'), 'utf8');
    const initAt = kit165.indexOf('void InitializeUISupport(');
    const init = initAt < 0 ? null : kit165.slice(initAt, kit165.indexOf('\n}', initAt));
    if (!init || init.indexOf('PnlFracKeyShared(') < 0)
      broken.push('`InitializeUISupport` no longer reads the pre-165 shared panel key — every panel starts at its default after the upgrade (P-UI-165)');
    else {
      if (init.indexOf('GlobalVariableDel(sfk)') >= 0)
        broken.push('the migration DELETES the shared panel key — every other pair still needs it until it migrates (P-UI-165)');
      if (init.indexOf('GlobalVariableSet(cfk, PnlFracPack(fx, fy));') < 0)
        broken.push('the migration no longer snapshots the shared panel place into the pair\'s own key (P-UI-165)');
    }
    if (broken.length) {
      failures.push('P-UI-165: ' + broken.join('; ') + ' (Biotak/BiotakHomes.mqh GVHomeName/GVHomeFracName + BiotakKit.mqh InitializeUISupport + BiotakPanels_Build.mqh PnlFracKey)');
    } else {
      console.log('[PASS] P-UI-165 the place belongs to the pair: the home and panel keys carry the SYMBOL (never a chart id), the pre-165 spellings are read-only migration sources, the load snapshots them once in a measured window, and no writer touches the shared keys');
    }
  }

  // -- 57. P-UI-166 (2026-10-17): twelve seats at most, 35px at least -----------
  // The user's report («ایکون ها یک ذره کوچیک شدن اگر تعداد ایتم ها زیاد بشه باز
  // خیلی کوچیک میشن»): every star past the ninth shrank the WHOLE circle —
  // 43→39→35→32→30 — so a full catalog seated sixteen 30px discs beside a 28px
  // glyph and the ring read as a debris field while a drag to an edge could seat
  // a longer tail on the train. The law this entry locks: the ladder now ENDS on
  // the 35 floor (CIRC_BTN_MIN is the one owner of it) and the surface seats at
  // most CIRC_SEAT_CAP (12, door included) — in the ring AND on the train — with
  // the excess staying in the Tools menu, its star ON (P-UI-13's degrade, now at
  // the cap boundary instead of the fit boundary).
  {
    const broken = [];
    const menuALines166 = linesOf(MENU_A);
    const minDef166 = Number((codeOf(menuALines166 || []).match(/#define\s+CIRC_BTN_MIN\s+(\d+)/) || [])[1]);
    if (!(minDef166 >= 35))
      broken.push(`CIRC_BTN_MIN is ${minDef166 || '?'} — a side below 35 reads as a glyph in a frame, not an icon`);
    const ringLines166 = linesOf(MENU_RING);
    if (!ringLines166) broken.push('Biotak/BiotakMenu_Ring.mqh is gone — the seat cap has no owner');
    else {
      const ringCode166 = codeOf(ringLines166);
      const capDef166 = Number((ringCode166.match(/#define\s+CIRC_SEAT_CAP\s+(\d+)/) || [])[1]);
      if (capDef166 !== 12)
        broken.push(`CIRC_SEAT_CAP is ${capDef166 || 'missing'}, not 12 — the count the user measured is not the count that ships`);
      const btn166 = bodyOf(ringLines166, 'int CircBtnSizeForN(');
      if (!btn166) broken.push('CircBtnSizeForN is gone — the taper has no owner');
      else {
        const numeric166 = (btn166.text.match(/return\s+\d+;/g) || []).map((m) => Number(m.match(/\d+/)[0]));
        const low166 = numeric166.filter((v) => v < 35);
        if (low166.length)
          broken.push(`CircBtnSizeForN still returns ${low166.join(', ')} — a side below the 35 floor shrinks the ring again`);
        if (!btn166.text.includes('return CIRC_BTN_MIN'))
          broken.push('CircBtnSizeForN no longer ends on CIRC_BTN_MIN — the floor has a second owner');
      }
      const fits166 = bodyOf(ringLines166, 'bool CircRingFits()');
      if (!fits166 || !fits166.text.includes('MathMin(RingCount(), CIRC_SEAT_CAP)'))
        broken.push('CircRingFits lost the seat cap — the shape gate tests counts the ring will never draw');
      const live166 = bodyOf(ringLines166, 'int CircPlacedCountLive()');
      if (!live166) broken.push('CircPlacedCountLive is gone — the capacity has no owner');
      else {
        if (!live166.text.includes('int top = MathMin(n, CIRC_SEAT_CAP)'))
          broken.push('the ring\'s fit walk lost the seat cap — a fuller mask re-seats the tiny circle (the reported defect)');
        if (!live166.text.includes('CircRailCapacity(MathMin(n, CIRC_SEAT_CAP)'))
          broken.push('the train walk stopped honouring the cap — a drag to an edge seats a thirteenth tail the ring would not');
      }
    }
    if (broken.length) {
      failures.push('P-UI-166: ' + broken.join('; ') + ' (Biotak/BiotakMenu_A.mqh CIRC_BTN_MIN + BiotakMenu_Ring.mqh CIRC_SEAT_CAP/CircBtnSizeForN/CircRingFits/CircPlacedCountLive)');
    } else {
      console.log('[PASS] P-UI-166 twelve seats at most, 35px at least: the taper\'s ladder ends on the 35 floor, the ring and the train both cap at CIRC_SEAT_CAP, and the excess stays in the Tools menu with its star ON (P-UI-13)');
    }
  }

  // -- 58. P-DRAGF3 (2026-10-17): the gesture belongs to the terminal ----------------
  // Report: a patterned thick fibo still reads one frame behind during a drag. The
  // numbers were already in hand (P-DRAGF2): OBJECT_DRAG fires ~1-2/s while the
  // hand's moves arrive ~60-100/s, and the demoted master's children are re-seated
  // by US on every move — painted a frame AFTER the terminal's own blit of the
  // master, which is structural: a follower can never be in the frame it follows.
  // The law: WHILE A GESTURE IS IN FLIGHT the unit stands down and the terminal's
  // native blit carries the body. At the arm (the gesture's first drag event) every
  // stacked level goes back to its logical width (MT4 draws SOLID at width>1 — the
  // law this unit exists around) and the stack (rows, caps, wash) hides once;
  // Follow/Sync/Heal are gated by `s_fibPreview`; at the release ONE FibPenSync
  // converges (un-hide + re-demote + re-seat + re-memoize), through the click door
  // AND the button-up door, both idempotent. PenStack is BORN with the same preview
  // (its integration may not ship the chase without it).
  {
    const broken = [];
    const fib = codeOf(linesOf(path.join(BIOTAK, 'FibPen.mqh')) || []);
    if (!/void FibPenPreviewArm\(\)/.test(fib) || !/bool FibPenPreviewEnd\(\)/.test(fib))
      broken.push('the preview pair is gone — a patterned thick fibo has no way to hand the body back (P-DRAGF3)');
    if (!/void FibPenDragArm\([^)]*\)\s*\{[\s\S]{0,600}?FibPenPreviewEnd\(\);/.test(fib))
      broken.push('the arm no longer ends a stale preview — a missed release holds the old body native with its stack hidden (P-DRAGF3)');
    if (!/void FibPenDragArm\([^)]*\)\s*\{[\s\S]{0,1500}?FibPenPreviewArm\(\);/.test(fib))
      broken.push('the arm no longer opens the preview — the gesture falls back to the chase, which IS the frame behind (P-DRAGF3)');
    // P-DRAGF3a (2026-10-17): A LOOK'S CHILDREN EXIST WITH NO STACK. CAPS and WASH ride
    // a SOLID level (`want` is 0), so the stack-gated loop never saw them and the halo
    // chased the hand one frame behind — the defect this preview exists to end, one look
    // over. The arm asks the look tag before any width fence, no level skips its
    // caps/wash, and the arm's own gate counts hidden look children (nH) beside demoted
    // levels (nW) — or the END never runs to un-hide what the arm hid.
    if (fib.includes('if(refLog <= DRAW_WIDTH_MIN) return;'))
      broken.push('the arm refuses a look-only fibo on width again — CAPS/WASH children exist with no stack and their halo is back to the chase (P-DRAGF3a)');
    if (!fib.includes('if(nW <= 0 && nH <= 0) return;'))
      broken.push('the arm gate counts only demoted levels — a look-only fibo would hide its children and never flip the flag, and the END never runs to un-hide them (P-DRAGF3a)');
    if (fib.includes('if(c <= 0) continue;'))
      broken.push('a level with no stack skips its caps/wash again — the look children are re-seated per move by the chase, one frame behind (P-DRAGF3a)');
    // P-LOOK-3D retired (2026-10-18): the shadow's arm/end/chase seats went with the look
    // — their inverse asserts are gone, and the retirement gate (P-LOOK-3D, below) now
    // fails if any of them comes back. The hand-back asserts above stay caps/wash-only.
    if (!/bool FibPenPreviewEnd\(\)\s*\{[\s\S]{0,700}?s_fibPreview = false;[\s\S]{0,4000}?FibPenSync\(fibo, false\);/.test(fib))
      broken.push('the end no longer clears the flag before its own sync — the convergence call would read its own gate and write nothing (P-DRAGF3)');
    if (!/void FibPenDragFollow\([^)]*\)\s*\{[\s\S]{0,300}?if\(s_fibPreview\) return;/.test(fib))
      broken.push('the chase is not gated by the preview — every move re-seats the stack the preview just handed back (P-DRAGF3)');
    if (!/bool FibPenSync\([^)]*\)\s*\{[\s\S]{0,700}?if\(s_fibPreview && !dropAll && fibo == s_fibPreviewObj\) return false;/.test(fib))
      broken.push('the sync is not gated by the preview (or dropAll was gated with it) — mid-gesture syncs re-demote the body, and gating dropAll would strand a deleted fibo\'s children (P-DRAGF3)');
    if (!/bool FibPenHeal\([^)]*\)\s*\{[\s\S]{0,400}?if\(s_fibPreview && fibo == s_fibPreviewObj\) return false;/.test(fib))
      broken.push('the 2 s heal is not gated — its memo mismatch snaps the body back mid-gesture (P-DRAGF3)');
    if (!/FIBPENPRE view=on/.test(fib) || !/FIBPENPRE view=off/.test(fib))
      broken.push('the preview writes no flushed witness — «sometimes works» is unprovable without one (P-DRAGF3)');
    const rtr = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    const iEnd = rtr.indexOf('bool fbPrev = FibPenPreviewEnd();');
    const iSync = rtr.indexOf('FibPenSync(relPressObj, false);');
    if (iEnd < 0 || iSync < 0 || iEnd > iSync)
      broken.push('the release no longer ends the preview before it re-states the pair — the un-hide would land in a later frame than the sync it must accompany (P-DRAGF3)');
    if (!/if\(FibPenPreviewEnd\(\)\) ChartRedraw\(\);/.test(rtr))
      broken.push('the button-up door is gone — a release off-chart leaves the preview armed until the next gesture (P-DRAGF3)');
    if (!/else if\(fbPrev\) ChartRedraw\(\);/.test(rtr))
      broken.push('an unnamed release no longer flushes its own un-hide — the body stays native with hidden children until an unrelated repaint (P-DRAGF3)');
    // P-DRAGF3c (2026-10-17): THE FIRST TRAVELED MOVE ARMS WHAT THE TERMINAL NAMES TOO
    // LATE. MEASURED (the user's 20:17 flick, biotak_diag_EURUSD_134362571361933137):
    // id=2 arrived in the SAME TICK as the release at three gestures in a row
    // (t=45431750 / 45434156 / 45435718), the preview lived ~10 ms per gesture
    // (view=on -> view=off) and the stack stood frozen through the motion. The press
    // names (s_dsPressObj), the travel vetoes (DSTRIP_CLICK_SLOP — a hold or a click
    // never arms), the memo is per press (reset on BOTH edges), and the trip must
    // stand BEFORE the chase call it feeds.
    const iTrip = rtr.indexOf('FibPenDragArm(armAsk);');
    const iFollow = rtr.indexOf('if(tleft) FibPenDragFollow(');
    if (!/static string s_dsArmTried = "";/.test(rtr))
      broken.push('the press-move arm has no per-press memo — every traveled move would re-ask the arm (P-DRAGF3c)');
    if (iTrip < 0 || iFollow < 0 || iTrip > iFollow)
      broken.push('the first traveled move no longer arms before the chase — a flick\'s terminal drag event arrives at the release, so the stack stays frozen through the whole motion (P-DRAGF3c)');
    if (!/s_dsTravel > DSTRIP_CLICK_SLOP/.test(rtr))
      broken.push('the arm trip lost its travel veto — a plain hold or click would blank the stack (P-DRAGF3c)');
    if (!/FIBPENARM obj=/.test(rtr))
      broken.push('the press-move arm writes no flushed witness — «preview never armed» is unarguable at the next capture (P-DRAGF3c)');
    if ((rtr.match(/s_dsArmTried = "";/g) || []).length < 2)
      broken.push('the arm memo is not reset on both press and release edges — one gesture would spend the next one\'s arm (P-DRAGF3c)');
    // P-DRAGF3d (2026-10-17): THE PRESS THAT NAMED NOTHING CAN STILL BE THE PEN'S.
    // MEASURED (the 20:51 frame, biotak_diag_EURUSD_134362571361933137): FIBPENPRE
    // view=on 25 against FIBPENARM 22 — 4 of the 25 real drags armed only at the
    // release door (the user's own «بعضی وقتا که سریع»): a fast flick grabs the fibo
    // by its DIAGONAL, which DrawHitLevels never measures, so the press named nothing
    // and the trip never fired. The trip asks the terminal's SELECTED fibo through a
    // geometry fence; the fence itself lives in Toolbar_B and measures the full
    // grabbable shape (anchor handles, the ray-paired diagonal, ray-extended levels).
    // The probe is spent on a miss too, so a pan pays one walk per press, not per move.
    const tbb = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    if (!/string DrawSelectedFiboAt\(/.test(tbb) || !/bool DrawFiboFullHit\(/.test(tbb))
      broken.push('the pen\'s third pick is gone — a diagonal grab names nothing and the flick falls back to the release door (P-DRAGF3d)');
    if (!/ObjectGetInteger\(0, name, OBJPROP_RAY_LEFT\)/.test(tbb) ||
        !/DrawSegDist\(px, py, x1, y1, x2, y2, oA, oB\)/.test(tbb))
      broken.push('the third pick no longer measures the diagonal with the object\'s own rays — only the press-named body would arm (P-DRAGF3d)');
    if (!/string armAsk = s_dsPressObj;/.test(rtr) || !/armAsk = DrawSelectedFiboAt\(tmx, tmy\);/.test(rtr))
      broken.push('the trip no longer asks the terminal\'s selection when the press named nothing — the fast flick loses its arm (P-DRAGF3d)');
    if (!/if\(armAsk == ""\) s_dsArmTried = "@";/.test(rtr))
      broken.push('the unnamed-press probe is never spent on a miss — a pan re-walks the chart on every move (P-DRAGF3d)');
    const psk = codeOf(linesOf(path.join(BIOTAK, 'PenStack.mqh')) || []);
    if (!/void PenStackPreviewArm\(/.test(psk) || !/bool PenStackPreviewEnd\(\)/.test(psk))
      broken.push('the stacked pen is not born with the preview law — its integration would ship the same frame behind (P-DRAGF3)');
    if (!/void PenStackDragArm\([^)]*\)\s*\{[\s\S]{0,900}?PenStackPreviewArm\(name\);/.test(psk) ||
        !/void PenStackDragFollow\([^)]*\)\s*\{[\s\S]{0,300}?if\(s_psPreview\) return;/.test(psk) ||
        !/if\(s_psPreview && !dropAll && name == s_psPreviewObj\) return false;/.test(psk) ||
        !/if\(s_psPreview && name == s_psPreviewObj\) return false;/.test(psk))
      broken.push('the stacked pen\'s gates are incomplete — its arm must open the preview and Sync, Heal and Follow must all stand down while it owns the gesture (P-DRAGF3)');
    if (broken.length) {
      failures.push('P-DRAGF3: ' + broken.join('; ') + ' (Biotak/FibPen.mqh + Biotak/DrawStrip_Router.mqh + Biotak/PenStack.mqh + Biotak/Toolbar_B.mqh)');
    } else {
      console.log('[PASS] P-DRAGF3 the gesture belongs to the terminal: the arm hands the body back (logical widths + one hide), Follow/Sync/Heal stand down, the witness is flushed, both release doors converge with ONE sync, a look-only fibo hands its caps/wash back too (P-DRAGF3a), and an unnamed press asks the terminal\'s selected fibo through its full shape (P-DRAGF3d)');
    }
  }

  // ── P-DRAW-74c (2026-10-17) — THE LINE PEN, WIRED ──
  // The module (PenStack.mqh) was born beside the fibo's pen, gated by P-DRAGF3, and
  // WIRED NOWHERE — zero callers, so a thick dashed HLINE/VLine/trendline stayed a
  // demoted 1 px line at best and every reader lied about its width. The wiring is
  // the rule: the width cell reads 1 + rows, a row is never served (DrawKindOf), the
  // slot writers converge the stack in the SAME pass they write the master (or the
  // remembered thickness dies one write early — the fibo's own P-DRAW-74b defect),
  // the open/release/zoom/delete paths re-state or drop the rows, the 2 s heal is
  // the net, and the duplicate takes the LOGICAL width, not the demoted 1.
  {
    const broken = [];
    const ps = codeOf(linesOf(path.join(BIOTAK, 'PenStack.mqh')) || []);
    const tba = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
    const tbb = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const tbr = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    const pk = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || []);
    const tpt = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    const pnt = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || []);
    const dtb = codeOf(linesOf(path.join(BIOTAK, 'DrawToolbar.mqh')) || []);
    if (!/#include "PenStack\.mqh"/.test(dtb))
      broken.push('the module is not included — every call below resolves to nothing and the terminal paints the demoted 1 (P-DRAW-74c)');
    if (!/if\(PenStackIsChild\(name\)\) return DK_NONE;/.test(tba))
      broken.push('a stacked row is served again — DrawKindOf must answer DK_NONE for it, or hits, presets and the strip learn the rows (P-DRAW-74c)');
    if (!/ObjectFind\(0, PenStackName\(name, 0\)\) >= 0\)/.test(tba) || !/return \(double\)PenStackLogicalWidth\(name\);/.test(tba))
      broken.push('the width cell reads the demoted 1 — the logical width is 1 + children (P-DRAW-74c)');
    if (!/if\(PenStackServes\(name\)\) return false;/.test(tbb))
      broken.push('DrawStylePairCoerce reads a line pen again — the strip open forces a stacked line back to a 1 px pen and the rows die (P-DRAW-74c)');
    if (!/\|\| PenStackServes\(name\);/.test(tbb))
      broken.push('the STYLE/FOLD path no longer knows the line pen — its own width gets folded to 1 before the sync can read it, so a thick dashed line comes out a plain 1 px dash (P-DRAW-74c)');
    if (!/if\(!penKind && \(int\)ObjectGetInteger\(0, name, OBJPROP_WIDTH\) != DRAW_WIDTH_MIN\)/.test(tbb))
      broken.push('the STYLE slot folds the object width on a pen kind — the logical memory dies one write early (P-DRAW-74c)');
    if (!/if\(penKind\)\s*\{[\s\S]{0,150}?if\(w <= DRAW_WIDTH_MIN\) PenStackStraysDrop\(name\);/.test(tbb))
      broken.push('a width-1 pick cannot come back — the rows outrank the read, so they must die where the hand\'s intent is known (P-DRAW-74c)');
    if (!/case DRAW_SLOT_COLOR:[\s\S]{0,1400}?if\(DrawKindHasFillBody\(k\)\) FillChildSync\(name\);[\s\S]{0,120}?PenStackSync\(name, false\);/.test(tbb))
      broken.push('the COLOUR slot no longer converges the stack — a recoloured line keeps its old-ink rows (P-DRAW-74c)');
    if (!/s_dkStyle\[k\] = memSt;[\s\S]{0,80}?PenStackSync\(name, false\);[\s\S]{0,60}?DrawStylePairCoerce\(name\);/.test(tbb))
      broken.push('the STYLE slot no longer converges the stack — a dashed line keeps solid rows (P-DRAW-74c)');
    if (!/FibPenSync\(name, false\);[\s\S]{0,100}?PenStackSync\(name, false\);/.test(pnt))
      broken.push('an open never re-converges the rows — the stack trails the drawing until the next touch (P-DRAW-74c)');
    if (!/PenStackSync\(sparam, false\);/.test(tbr))
      broken.push('the drag/change event never reaches the rows — a dragged line\'s stack trails the hand\'s own event (P-DRAW-74c)');
    if (!/void PenStackDragFollow/.test(ps) || !/PenStackDragArm\(sparam\);/.test(tbr))
      broken.push('the chase is unwired — a line drag must arm it, the hand stream must run it (P-DRAW-74c)');
    if (!/PenStackDragArm\(armAsk\);/.test(tbr))
      broken.push('the move-stream trip never arms the line pen — a fast flick freezes the rows through the whole motion (P-DRAW-74c)');
    if (!/if\(tleft\) PenStackDragFollow\(\(int\)lparam, \(int\)dparam\);/.test(tbr))
      broken.push('moves never chase — the follow belongs on the mouse stream, not the drag event (P-DRAW-74c)');
    if (!/if\(PenStackPreviewEnd\(\)\) ChartRedraw\(\);/.test(tbr))
      broken.push('the button-up door never ends the line preview (P-DRAW-74c)');
    if (!/if\(PenStackPreviewEnd\(\)\) fbPrev = true;/.test(tbr))
      broken.push('the click door never ends the line preview — the rows stay hidden until an unrelated repaint (P-DRAW-74c)');
    if (!/PenStackSync\(relPressObj, false\);/.test(tbr))
      broken.push('the release never re-states the rows on the final seat (P-DRAW-74c)');
    if ((tbr.match(/PenStackDragDisarm\(\);/g) || []).length < 2)
      broken.push('a release door forgot its disarm — the next gesture inherits a stale chase (P-DRAW-74c)');
    if (!/if\(PenStackStraysDrop\(sparam\)\) casc = true;/.test(tbr))
      broken.push('a native delete strands the rows — every dependent dies with its object (P-DRAW-74c)');
    if (!/if\(id == CHARTEVENT_CHART_CHANGE\) PenStackSync\(s_dsObj, false\);/.test(tbr))
      broken.push('a zoom never re-syncs the served line — the pixel ring goes stale until the next touch (P-DRAW-74c)');
    // P-PEN-ALL (2026-10-19): the walk's type list MOVED into the pen. It was a second
    // owner of "which kinds the pen serves" — the module's Serves() and this literal had
    // to be edited together, and the shape kinds were about to make that literal wrong.
    // The walk now asks `PenStackServesType(ty)`; a list back in the walk fails here.
    if (/if\(ty == OBJ_HLINE[\s\S]{0,80}?PenStackHeal\(nm\);/.test(pk))
      broken.push('the 2 s walk holds its own list of pen types again — the served set has ONE owner, `PenStackServesType` (P-PEN-ALL)');
    if (!/if\(PenStackServesType\(ty\)\) PenStackHeal\(nm\);/.test(pk) || !/bool PenStackServesType\(const int ty\)/.test(ps))
      broken.push('the pen has no net — a master the terminal moves with no event keeps a stale pen until the next touch (P-DRAW-74c)');
    if (!/if\(PenStackIsChild\(nm\)\)/.test(pk) || !/string PenStackChildParent\(/.test(ps))
      broken.push('the rows have no parent oracle — a row whose master is gone survives a reattach (P-DRAW-74c)');
    if (!/PenStackLogicalWidth\(s_dsObj\)/.test(tpt))
      broken.push('a duplicate copies the demoted 1 — the clone of a 3 px line shrinks to a dash (P-DRAW-74c)');
    if (!/PenStackSync\(nm, false\);/.test(tpt) || !/PenStackSync\(s_dsObj, true\);/.test(tpt) || !/PenStackSync\(DrawSelAt\(j\), true\);/.test(tpt))
      broken.push('the tap paths never reach the rows — the copy must re-form beside itself and both delete doors must drop the family (P-DRAW-74c)');
    if ((tba.match(/PenStackSync\(name, false\);/g) || []).length < 3)
      broken.push('a hover preview leaves the rows behind — previewed ink must reach the children it cannot see (P-DRAW-74c)');
    if (!/ObjectSetInteger\(0, name, OBJPROP_STYLE, native\);[\s\S]{0,400}?DrawStylePairCoerce\(name\);[\s\S]{0,120}?PenStackSync\(name, false\);/.test(tbb))
      broken.push('a line is born un-stacked — a remembered thick + dash pair flashes solid at birth until the 2 s heal (P-DRAW-74c)');
    if (broken.length) {
      failures.push('P-DRAW-74c: ' + broken.join('; ') + ' (Biotak/PenStack.mqh + Toolbar_A.mqh + Toolbar_B.mqh + DrawStrip_Router.mqh)');
    } else {
      console.log('[PASS] P-DRAW-74c the line pen is wired: width reads 1 + rows, a row is never served, every writer converges the stack in its own pass, all three doors release it, deletes drop the family and the 2 s heal is the net');
    }
  }

  // ── P-PEN-ALL (2026-10-19) - THE SHAPE PEN: THE FIBO'S OWN FIX, ONE ANCHOR SET OVER ──
  // The line pen served the three kinds whose drawing is ONE line. Every other kind the
  // strip styles stayed on the native fold at (pattern, width > 1): MT4 draws STYLE_* only
  // at width 1 (P-DRAW-74's measured law), so a thick dashed rectangle came out a solid
  // thick outline and the report «استایل ها در ضخامت های بالا درست کار نمیکنه» had one
  // family left. The fix is the same pen pointed at the shapes: a copy of the master with
  // EVERY anchor shifted by the same pixel vector is the same shape moved, so the master is
  // demoted to the pattern at width 1 and `logical-1` rows carry the thickness.
  // This section gates the WIRING, not the law:
  //   * the served set has ONE owner (`PenStackShapeKind`, asked by `PenStackServes` and by
  //     the 2 s walk through `PenStackServesType`) - never a second list;
  //   * a row is born the master's own TYPE (a rect row is a RECT; an OBJ_TREND row would
  //     draw a diagonal line the master never had);
  //   * a row carries NO interior (the fill is the fill child's pixel, P-DRAW-64);
  //   * the three-point shapes keep their third anchor in the seat AND in the net, or a
  //     moved corner leaves every row stale;
  //   * a fill child appearing after the rows rebuilds them ABOVE it (MT4 paints in
  //     CREATION order, P-LOG-10 - otherwise the thickness survives on the outer half only).
  {
    const brokenPA = [];
    const psp = codeOf(linesOf(path.join(BIOTAK, 'PenStack.mqh')) || []);
    const tbbp = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const pkp = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || []);
    if (!/bool PenStackShapeKind\(const EDrawKind k\)\s*\{[\s\S]{0,260}?DK_RECT[\s\S]{0,80}?DK_ELLIPSE[\s\S]{0,80}?DK_TRIANGLE[\s\S]{0,80}?DK_CHANNEL[\s\S]{0,80}?DK_GANN/.test(psp))
      brokenPA.push('the shape set has no owner - the five whole-object kinds must be named in ONE function or every reader invents its own list (P-PEN-ALL)');
    //--- P-PEN-ALL: the served set's LINE half, in one owner (P-UNIFY-2 added the
    //--- trend-by-angle to it, and a literal list here would have to be edited twice).
    //--- P-UNIFY-4: both halves are the PROFILE's answer now. The shape test in
    //--- PenStack stays the seat that spends it, but the rows it may serve are the
    //--- profile's `DKPEN_OBJECT` block, asked through the same owner as the walk.
    const profPA = codeOf(linesOf(path.join(BIOTAK, 'DrawKindProfile.mqh')) || []);
    if (!/bool PenStackServes\(const string name\)[\s\S]{0,300}?return \(DrawKindPenFamily\(DrawKindOf\(name\)\) == DKPEN_OBJECT\);/.test(psp) ||
        !/case DK_CHANNEL:[\s\S]{0,400}?p\.pen = DKPEN_OBJECT;/.test(profPA))
      brokenPA.push('the shapes are out of the pen again - a thick dashed rect/triangle/ellipse/channel/gann keeps the solid native fold (P-PEN-ALL)');
    if (!/bool PenStackServesType\(const int ty\)[\s\S]{0,200}?return \(DrawTypePenFamily\(ty\) == DKPEN_OBJECT\);/.test(psp))
      brokenPA.push('the TYPE half of the served set is gone - the 2 s walk must ask the pen, not hold a list (P-PEN-ALL)');
    if (!/ObjectCreate\(0, nm, ty, 0, t0, p0, t1c, p1c, t2c, p2c\)/.test(psp) || !/ObjectCreate\(0, nm, ty, 0, t0, p0, t1c, p1c\)/.test(psp))
      brokenPA.push('a shape row is not born the masters own type - a rectangle would be drawn as a diagonal line (P-PEN-ALL)');
    if (!/bool PenStackShapeSeat\(const string m, const string nm, const int nA,/.test(psp) || !/for\(int a = 0; a < nA; a\+\+\)/.test(psp))
      brokenPA.push('a shape row does not carry EVERY anchor - a triangle/channel row is seated on two corners and opens up (P-PEN-ALL)');
    if (!/if\(shape\) ObjectSetInteger\(0, nm2, OBJPROP_FILL, false\);/.test(psp))
      brokenPA.push('a shape row can wear an interior - it would cover the very thickness it was born to draw (P-PEN-ALL)');
    if (!/if\(shape\)\s*\{\s*if\(PenStackShapeSeat\(name, nm2, nA, off, px, secPx\)\) nMov\+\+;\s*\}/.test(psp))
      brokenPA.push('the sync never seats a shape row - the rows are built once and never follow their master (P-PEN-ALL)');
    if (!/int nA = shape \? PenStackAnchorCount\(ty\) : 0;/.test(psp) || !/return \(ty == OBJ_TRIANGLE \|\| ty == OBJ_CHANNEL\) \? 3 : 2;/.test(psp))
      brokenPA.push('the anchor count is guessed instead of read off the TYPE - an equidistant channel is three points, a regression two (P-PEN-ALL)');
    if (!/s_psNetT2\[at\] == t3 && s_psNetP2\[at\] == p3 && s_psNetFill\[at\] == fl/.test(psp))
      brokenPA.push('the net ignores the third anchor or the interior - a moved corner or a new fill child keeps stale rows (P-PEN-ALL)');
    if (!/PenStackNetWrite\(name, \(long\)t1, \(long\)t2, p1, p2, t3, p3, log, st, want, back, ray, fillNow\);/.test(psp))
      brokenPA.push('the sync records a state the heal cannot rebuild from - the memo and the compare must name the same fields (P-PEN-ALL)');
    if (!/if\(!dropAll && shape && fillNow == 1 && fillWas == 0 && cur > 0\)[\s\S]{0,120}?PenStackStraysDrop\(name\);/.test(psp))
      brokenPA.push('a fill child appearing after the rows never rebuilds them - the thickness dies on the inner half of every edge (P-PEN-ALL)');
    if (!/bool PenStackNetForget\(const string m\)/.test(psp))
      brokenPA.push('the net cannot be spent - a state changed underneath the memo is never re-examined (P-PEN-ALL)');
    if (!/if\(PenStackLineKind\(k\) \|\| shape\)/.test(psp))
      brokenPA.push('a shape rows ray pair is not mirrored - a gann line runs on and its row stops at the anchor (P-PEN-ALL)');
    if (!/if\(PenStackShapeKind\(\(EDrawKind\)s_psKind\)\)/.test(psp) || !/if\(PenStackShapeSeat\(m, nmq, nAs, FibPenOffPx\(logs, q\), pxs, secs\)\) nMovS\+\+;/.test(psp))
      brokenPA.push('the chase never carries a shape - a dragged rect leaves its rows behind (P-PEN-ALL)');
    //--- the code, not the comment: `codeOf` strips comments, so an assertion that
    //--- anchors on a comment line can never match (it is a check that always fails).
    if (!/FillChildDrop\(name\);[\s\S]{0,200}?PenStackSync\(name, false\);[\s\S]{0,60}?break;/.test(tbbp))
      brokenPA.push('the FILL switch does not re-state the pen in its own frame - the interior is born over the rows and they only return at the next 2 s pass (P-PEN-ALL)');
    if (!/if\(remember\) s_dkFillClr\[k\] = ic;[\s\S]{0,220}?FillChildSync\(name\);[\s\S]{0,140}?PenStackSync\(name, false\);/.test(tbbp))
      brokenPA.push('the interior colour does not re-state the pen - the fill child it ensures is a later pixel than the rows (P-PEN-ALL)');
    if (!/if\(PenStackServesType\(ty\)\) PenStackHeal\(nm\);/.test(pkp))
      brokenPA.push('the 2 s walk never heals a shape - a rect the terminal moved keeps its rows on the old seat (P-PEN-ALL)');
    if (brokenPA.length) {
      failures.push('P-PEN-ALL: ' + brokenPA.join('; ') + ' (Biotak/PenStack.mqh + Toolbar_B.mqh + DrawStrip_Pick.mqh)');
    } else {
      console.log('[PASS] P-PEN-ALL the shape pen is wired: one owner for the served set, a row is born the master\'s own type with every anchor and no interior, the three-point third anchor rides the seat and the net, a fresh fill child rebuilds the rows above it and the chase carries a dragged shape');
    }
  }

  // ── P-UNIFY-2 (2026-10-19) - THE TWO KINDS THAT HAD NO KIND ──
  // `OBJ_TRENDBYANGLE` and `OBJ_CYCLES` are MT4's own toolbar tools and the strip spoke
  // NEITHER: `DrawKindOf` fell to DK_NONE, so a pick on one opened the strip with zero
  // cells and the drawing answered nothing — the "invisible" end of the same report the
  // FIBO's cells came from («همه جا یکپارچه»). This section gates every door that must
  // name a kind, because a kind is not one edit: the enum, the type->kind map, the
  // capability table (the cells), the display name, the HIT TEST (the drawn shape is
  // what the hand can click) and the pen's two families (the line family for the
  // by-angle line, the shape family for a cycles fan).
  //   * The enum values are APPENDED before DK_COUNT: every index a build before this
  //     one wrote (template rows, remembered looks) keeps its number.
  //   * No RAY seat is minted for either kind: a cell is only added where a write is
  //     proven to draw (C-04 / P-DRAW-145), and the type's ray support is unmeasured.
  {
    const brokenU2 = [];
    const tba2 = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
    const tbb2 = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    const ps2 = codeOf(linesOf(path.join(BIOTAK, 'PenStack.mqh')) || []);
    //--- the pick owner: P-SIZE-1500 moved the two hit tests out of Toolbar_A while
    //--- this rule was being written, so the door is asked of the file that owns it.
    const th2 = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_Hit.mqh')) || []);
    if (!/DK_TEXT,[\s\S]{0,900}?DK_TANGLE,[\s\S]{0,400}?DK_CYCLES,[\s\S]{0,80}?DK_COUNT/.test(tba2))
      brokenU2.push('the two kinds are not appended before DK_COUNT - an inserted value renumbers every remembered look');
    for (const [ty, kd] of [['OBJ_TRENDBYANGLE', 'DK_TANGLE'], ['OBJ_CYCLES', 'DK_CYCLES']]) {
      if (!new RegExp('case ' + ty + ':\\s*return ' + kd + ';').test(tba2))
        brokenU2.push(ty + ' maps to no kind again - the strip opens on nothing for that drawing');
    }
    if (!/case DK_TANGLE:\s*\r?\n\s*case DK_CYCLES:\s*return DRAW_CAP_COMMON;/.test(tba2))
      brokenU2.push('the two kinds lost their six cells - the strip is a name with no controls');
    if (!/case DK_TANGLE:\s*return "Trend by Angle";/.test(tbb2) || !/case DK_CYCLES:\s*return "Cycles";/.test(tbb2))
      brokenU2.push('a kind without its own name falls to "Drawing" in every panel, template and tooltip');
    if (!/case DK_LINE:\s*\r?\n\s*case DK_TANGLE:/.test(th2))
      brokenU2.push('a trend-by-angle answers no pick - it draws one segment and the hand can click it');
    if (!/case DK_CYCLES:/.test(th2) || !/if\(!ChartXYToTimePrice\(0, px, py, sub, tc, pc\)\) return false;/.test(th2) ||
        !/ChartTimePriceToXY\(0, 0, \(datetime\)\(\(long\)ta \+ \(d \+ ci\) \* per\), pa, vx, vy\)/.test(th2))
      brokenU2.push('a cycles object is picked by a chart-wide sweep or by nothing - its verticals stand at t1 + k*P and the pick must ask the terminal where THOSE are');
    if (!/bool PenStackLineKind\(const EDrawKind k\)[\s\S]{0,120}?k == DK_TANGLE/.test(ps2) ||
        !/if\(want > 0 && PenStackLineKind\(k\)\) step = PenStackLineStep\(t1, p1, t2, p2\);/.test(ps2))
      brokenU2.push('the by-angle line is served by the pen but never gets its perpendicular step - its rows land ON the master and paint nothing');
    //--- P-UNIFY-4: the two types live in the PROFILE now (`DK_CYCLES` in the
    //--- shape block, `DrawTypePenFamily` asking it), not in a second list here.
    const prof2 = codeOf(linesOf(path.join(BIOTAK, 'DrawKindProfile.mqh')) || []);
    if (!/DK_GANN \|\| k == DK_CYCLES/.test(ps2) ||
        !/case DK_CYCLES:[\s\S]{0,80}?p\.pen = DKPEN_OBJECT;/.test(prof2) ||
        !/return DrawKindPenFamily\(DrawKindOfType\(t\)\);/.test(prof2))
      brokenU2.push('the two types are missing from a pen family - served on the write, stale on the next frame (the 2 s walk asks PenStackServesType)');
    //--- P-SIZE-1500 forced Toolbar_A (1526 lines) to give the pick owner its own file.
    //--- A half is a MEMBER of the unit, included above the file that calls into it, and
    //--- it must be CALLED - an orphaned half compiles and is dead (14b's rule, one
    //--- ceiling later). Without this, the pick both new kinds answer could vanish.
    const hubLines = linesOf(path.join(BIOTAK, 'DrawToolbar.mqh'));
    const hitLines = linesOf(path.join(BIOTAK, 'Toolbar_Hit.mqh'));
    const tbbLines = linesOf(path.join(BIOTAK, 'Toolbar_B.mqh'));
    if (!hitLines) brokenU2.push('Toolbar_Hit.mqh is missing - the pick the two kinds answer is not in the build');
    if (!hubLines) brokenU2.push('Biotak/DrawToolbar.mqh is missing (the toolbar unit has no hub)');
    else {
      const iHit = indexOfLine(hubLines, '#include "Toolbar_Hit.mqh"');
      const iOwner = indexOfLine(hubLines, '#include "Toolbar_A.mqh"');
      const iCaller = indexOfLine(hubLines, '#include "Toolbar_B.mqh"');
      if (iHit < 0) brokenU2.push('the hub does not include Toolbar_Hit.mqh - the unit is incomplete');
      else if (iOwner < 0 || iCaller < 0 || iHit < iOwner || iHit > iCaller)
        brokenU2.push('Toolbar_Hit.mqh must be included between Toolbar_A.mqh (what it reads) and Toolbar_B.mqh (which calls it): MQL4 resolves a call top-down');
    }
    if (tbbLines && !/DrawObjectAt\(px, py\)/.test(codeOf(tbbLines)))
      brokenU2.push('nothing calls into Toolbar_Hit.mqh - the half was orphaned (it compiles and is dead)');
    if (brokenU2.length) {
      failures.push('P-UNIFY-2: ' + brokenU2.join('; ') + ' (Biotak/Toolbar_A.mqh + Toolbar_B.mqh + PenStack.mqh)');
    } else {
      console.log('[PASS] P-UNIFY-2 the two kinds with no kind are served end to end: appended enum seats, both type maps, six cells each, their own names, a pick that answers the DRAWN shape (segment / t1+k*P verticals) and both pen families');
    }
  }

  // ── P-SHOT-1 (2026-10-19) - THE SHOT'S DONE VERDICT IS A FLUSHED FILE, NOT A JOURNAL LINE ──
  // MEASURED 2026-10-19 09:55: `-Shot -RestartTerminal` wrote all 30 PNGs and still ended
  // `[FAIL] the harness never reached DONE` — that verdict was read out of the Experts
  // journal, which MT4 buffers in RAM (P-DRAW-126, MEASURED at seven minutes). A reader
  // that can only see the buffered channel cannot tell "not finished" from "not flushed",
  // and the honest verdict ("the pixels are here") became the one verdict it could not
  // report. The harness now writes `<MQL4>\Files\StripShot.done` through the terminal's own
  // file API on EVERY exit door (DONE and each SKIP), the build deletes a stale marker
  // before the launch (P-LOG-2's rule, one channel over), the wait checks the marker FIRST,
  // and the verdict reads it. The journal stays as the human-readable record.
  {
    const brokenS1 = [];
    const hz = codeOf(linesOf(path.join(ROOT, 'tests', 'Biotak_StripShot_Test.mq4')) || []);
    const ps1 = linesOf(BUILD_PS1) ? fs.readFileSync(BUILD_PS1, 'utf8') : '';
    if (!ps1) brokenS1.push('compile-th3.ps1 is missing (the build is the only entry point)');
    if (!/void SSMarker\(const string verdict\)/.test(hz))
      brokenS1.push('the harness has no flushed DONE marker - the capture can only be judged through the RAM-buffered journal (P-SHOT-1)');
    if (!/int h = FileOpen\(f, FILE_WRITE \| FILE_TXT \| FILE_ANSI\);/.test(hz) ||
        !/FileFlush\(h\);[\s\S]{0,60}?FileClose\(h\);/.test(hz))
      brokenS1.push('the marker is left to the terminal\'s buffer - a write without flush+close is the same unseen channel one layer down (P-SHOT-1)');
    if (!/SSMarker\("DONE"\);/.test(hz))
      brokenS1.push('the harness never marks a finished run - the build would wait out its whole timeout on a complete capture (P-SHOT-1)');
    if (!/SSMarker\("START"\);/.test(hz))
      brokenS1.push('the harness leaves no START door - a reader cannot tell "still working" from "never ran" during the two-minute bar wait (P-SHOT-1)');
    if ((hz.match(/SSMarker\("SKIP/g) || []).length < 4)
      brokenS1.push('a SKIP door leaves no marker - the build cannot tell "the harness refused this chart" from "the harness never ran" (P-SHOT-1)');
    if (!/\$marker = Join-Path \(Join-Path \$deployDir "Files"\) "StripShot\.done"/.test(ps1))
      brokenS1.push('the build does not look for the marker where the harness writes it (<MQL4>\\Files) (P-SHOT-1)');
    if (!/if \(Test-Path -LiteralPath \$marker\) \{ Remove-Item -LiteralPath \$marker -Force/.test(ps1))
      brokenS1.push('a stale marker from an earlier run survives into the next one - an old file would answer for a new run (P-SHOT-1)');
    if (!/-SkipLines \$skip -Marker \$marker/.test(ps1) ||
        !/\$mtxt\.StartsWith\("DONE"\) -or \$mtxt\.StartsWith\("SKIP"\)/.test(ps1))
      brokenS1.push('the wait never reads the marker, or it ends on the START line alone - START says "working", only DONE/SKIP say "finished" (P-SHOT-1)');
    if (!/\$markerText -notmatch '\^DONE'/.test(ps1))
      brokenS1.push('the verdict ignores the marker - a complete capture whose journal lagged reads as "never reached DONE" (P-SHOT-1)');
    //--- MEASURED 2026-10-19 11:03: the harness waits up to 120 s for bars and 32 states
    //--- take ~85 s, so a 120 s budget cut a COMPLETE capture off at its last state
    //--- (StripShot_pen.png was never written and the build reported "never reached
    //--- DONE"). The wait must outlast the harness's own bar wait with room to shoot.
    {
      const tm = ps1.match(/\$ShotTimeoutSec = (\d+)/);
      if (!tm || Number(tm[1]) < 240)
        brokenS1.push('the shot timeout cannot outlast the harness\'s own 120 s bar wait plus the states - a 120 s budget ends a complete capture early (P-SHOT-1)');
    }
    if (brokenS1.length) {
      failures.push('P-SHOT-1: ' + brokenS1.join('; ') + ' (compile-th3.ps1 + tests/Biotak_StripShot_Test.mq4)');
    } else {
      console.log('[PASS] P-SHOT-1 the shot\'s DONE verdict is a flushed file: the harness marks every exit door (write+flush+close), the build deletes a stale marker before the launch, the wait polls it first and the verdict reads it');
    }
  }

  // ── P-SHOT-2 (2026-10-19) — A GENERATED FILE IS NOT A WITNESS FOR THE PIXELS ──
  // MEASURED 2026-10-19 11:10:37: Biotak/BuildHash.mqh — the stamp tools/gen-build-hash.js
  // rewrites on EVERY compile — was the newest .mqh on disk, so all 33 PNGs captured at
  // 11:08:09 read as `fresh 0 · stale 33 · missing 0` although no source changed between the
  // shot and that build. -Shot's strict leg had just gone green on those same pixels, and the
  // next ordinary build turned them red — a red produced by the build's own artifact, so the
  // reader would answer "the code moved" where nothing had. The walk now reads the head of the
  // file that would win and skips one that declares itself GENERATED (the property, not the
  // name, so renaming the generator cannot slip past it), and gen-build-hash keeps emitting
  // that declaration — which is the whole reason the skip can be trusted.
  {
    const brokenS2 = [];
    const frzTxt = linesOf(path.join(ROOT, 'tools', 'check-shot-freshness.js'))
      ? fs.readFileSync(path.join(ROOT, 'tools', 'check-shot-freshness.js'), 'utf8') : '';
    const genTxt = linesOf(path.join(ROOT, 'tools', 'gen-build-hash.js'))
      ? fs.readFileSync(path.join(ROOT, 'tools', 'gen-build-hash.js'), 'utf8') : '';
    const bhTxt = linesOf(path.join(ROOT, 'Biotak', 'BuildHash.mqh'))
      ? fs.readFileSync(path.join(ROOT, 'Biotak', 'BuildHash.mqh'), 'utf8') : '';
    if (!frzTxt) brokenS2.push('tools/check-shot-freshness.js is missing (the only reader of the real pixels)');
    if (!/if \(head\.indexOf\('GENERATED FILE'\) >= 0\) \{/.test(frzTxt))
      brokenS2.push('the walk counts a generated file as a source - the build rewrites its own stamp on every run, so every capture reads stale the moment anything is built again (P-SHOT-2)');
    if (!/if \(st\.mtimeMs <= best\.mtime\) return;/.test(frzTxt) ||
        !/const n = fs\.readSync\(fd, buf, 0, 512, 0\);/.test(frzTxt))
      brokenS2.push('the head is not read for the would-be winner only - every .mqh pays an open on every gate run where one would do (P-SHOT-2)');
    if (!/GENERATED FILE\. DO NOT EDIT\./.test(genTxt))
      brokenS2.push('tools/gen-build-hash.js no longer declares its output GENERATED - the skip answers to a declaration the generator stopped writing (P-SHOT-2)');
    if (!/GENERATED FILE\. DO NOT EDIT\./.test(bhTxt))
      brokenS2.push('Biotak/BuildHash.mqh does not declare itself GENERATED - the skip trusts a header the file does not carry (P-SHOT-2)');
    if (brokenS2.length) {
      failures.push('P-SHOT-2: ' + brokenS2.join('; ') + ' (tools/check-shot-freshness.js + tools/gen-build-hash.js)');
    } else {
      console.log('[PASS] P-SHOT-2 a generated stamp is not a witness: the real-pixels gate reads the head of the file that would win (1 open, never 460) and skips one that declares itself GENERATED, and the generator still emits that declaration');
    }
  }

  // ── P-DRAGF4 (2026-10-17) — THE BOX'S INTERIOR RIDES THE TERMINAL, LIKE THE PEN ──
  // The interior (`_FL` child) and the 50 % mid (`_BX50`) are followers re-seated by
  // US from the event stream, so they are always one frame behind the terminal's own
  // native blit of the dragged master — the fibo's lag law, one family over. P-DRAGF4
  // is the same answer: during the gesture the master takes the interior BACK
  // (`OBJPROP_FILL` + `BGCOLOR` = the child's own rendered ink) and both followers
  // hide; the two syncs stand down under `BoxPreviewOwns`; at the release ONE pass
  // re-seats them on the final seat. The arm rides both the drag event and the
  // first traveled move (P-DRAGF3c's lesson), and the doors end it.
  {
    const broken = [];
    const tba = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
    const bp = codeOf(linesOf(path.join(BIOTAK, 'BoxPreview.mqh')) || []);
    const pk = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || []);
    const tbr = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    const dtb = codeOf(linesOf(path.join(BIOTAK, 'DrawToolbar.mqh')) || []);
    if (!/#include "BoxPreview\.mqh"/.test(dtb))
      broken.push('the module is not included — every arm/end call resolves to nothing and the child lag survives (P-DRAGF4)');
    if (!/bool BoxPreviewOwns\(/.test(bp) || !/bool BoxPreviewEnd\(/.test(bp) || !/void BoxPreviewArm\(/.test(bp))
      broken.push('the preview has no owner functions (P-DRAGF4)');
    if (!/if\(BoxPreviewOwns\(obj\)\) return false;/.test(tba))
      broken.push('the interior\'s hand-sync does not stand down during the preview — two writers re-seat one child (P-DRAGF4)');
    if (!/if\(BoxPreviewOwns\(box\)\) return false;/.test(pk))
      broken.push('the mid\'s sync does not stand down during the preview — it would fight the hidden mid (P-DRAGF4)');
    if (!/if\(obj == "" \|\| !DrawTypeHasFillChild\(DrawObjectType\(obj\)\)\) return;/.test(bp))
      broken.push('the arm lost its family fence — a stranger\'s object gets a fill it never had (P-DRAGF4)');
    if (!/ObjectSetInteger\(0, obj, OBJPROP_FILL, true\);/.test(bp))
      broken.push('the interior is never handed to the terminal — the child lag survives (P-DRAGF4)');
    if (!/OBJPROP_BGCOLOR, \(color\)ObjectGetInteger\(0, fil, OBJPROP_COLOR\)/.test(bp))
      broken.push('the native fill guesses its ink — it must wear the child\'s own rendered colour (P-DRAGF4)');
    if (!/ObjectSetInteger\(0, fil, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS\);/.test(bp))
      broken.push('the child is not hidden during the gesture — two interiors paint at once (P-DRAGF4)');
    if (!/ObjectSetInteger\(0, fil, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS\);/.test(bp))
      broken.push('the child never comes back (P-DRAGF4)');
    if (!/FillChildSync\(master\);/.test(bp) || !/BoxMidSync\(master\);/.test(bp))
      broken.push('the end never re-seats the followers on the final seat (P-DRAGF4)');
    if (!/BOXPRE view=on/.test(bp) || !/BOXPRE view=off/.test(bp))
      broken.push('the preview leaves no flushed witness — «یک فریم عقب» is unprovable without its numbers (P-DRAGF4)');
    if (!/BoxPreviewArm\(sparam\);/.test(tbr) || !/BoxPreviewArm\(armAsk\);/.test(tbr))
      broken.push('nothing arms the preview on the drag event or the move-stream trip — a fast flick keeps the lag (P-DRAGF4)');
    if (!/if\(BoxPreviewEnd\(\)\) ChartRedraw\(\);/.test(tbr))
      broken.push('the button-up door never ends the box preview (P-DRAGF4)');
    if (!/if\(BoxPreviewEnd\(\)\) fbPrev = true;/.test(tbr))
      broken.push('the click door never ends the box preview (P-DRAGF4)');
    if (!/if\(armAsk == ""\) armAsk = DrawSelectedObjectAt\(tmx, tmy\);/.test(tbr))
      broken.push('the trip never asks the terminal\'s own selection for a box/line — the press that named nothing loses the arm (P-DRAGF4)');
    if (broken.length) {
      failures.push('P-DRAGF4: ' + broken.join('; ') + ' (Biotak/Toolbar_A.mqh + DrawStrip_Pick.mqh + DrawStrip_Router.mqh)');
    } else {
      console.log('[PASS] P-DRAGF4 the box\'s interior rides the terminal: the arm hands it back natively in the child\'s own ink, both followers hide, Sync stands down, the release re-seats them in one pass, and both doors end it');
    }
  }

  // -- 59. P-DRAW-131 (2026-10-18): the save's name field is FOCUSED the moment
  //        either door arms it, and the pending save COMMITS through one owner on
  //        every exit. «این نحوه ذخیره تمپلت‌ها به نظر مشکل داره» — walked from the
  //        user's side, the two Save doors (the more popover's "Save current look",
  //        the Look tab's Save row) armed an edit field that (a) was born UNFOCUSED —
  //        nothing wrote OBJPROP_STATE for `PnlDrawS_GE3`, while the level-note field
  //        has shipped that write since P-LVL-TEXT — and (b) had exactly ONE commit
  //        door, ENDEDIT (Enter): MT4 drops an OBJ_EDIT's focus without firing
  //        ENDEDIT when the user clicks away, so tap-Save → type → tap-anything
  //        wrote NOTHING, silently. The rule: the field opens FOCUSED at both doors,
  //        and every door the field can leave by routes the pending save through ONE
  //        commit (`DrawStripTplCommit`: ENDEDIT "enter", the panel close "close" —
  //        the widest door, every close funnels through DrawStripGearClose — and the
  //        group tap "group"), whose file write is the command and whose typed name
  //        is a detail. Both halves witness on the flushed channel (TPLARM after the
  //        focus write, TPLSAVE with its door). The welded
  //        `s_dsTplNameArmed = false;` had to leave DrawStripGearClose with it — one
  //        owner, or two writers (contract §9).
  //        P-DRAW-131b (the same day, the second report «مینویسم ولی چیزی برا سیو
  //        نداره که»): the focus half worked and the row still offered NOTHING TO
  //        PRESS — Enter committed invisibly and the exits looked like exits. The
  //        armed row now carries its own Save button (the foot's anatomy at the
  //        row's control seat, its owners in GearA beside the commit), its seat
  //        owned ONCE (DrawStripTplSaveW, read by the paint and the hit test), its
  //        commit the SAME DrawStripTplCommit ("save"), and its family swept at the
  //        arm's one end (DrawStripTplSaveSweep: the commit and the gear purge).
  {
    const broken = [];
    const ga = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearA.mqh')) || []);
    const gbLines = linesOf(path.join(BIOTAK, 'DrawStrip_GearB.mqh')) || [];
    const ta = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    const bs = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Base.mqh')) || []);
    const rd = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    if (!/void DrawStripTplNameFocus\(\)/.test(ga))
      broken.push('the focus half is gone from GearA — the armed field is born unfocused (P-DRAW-131)');
    if (!/ObjectSetInteger\(0, nm, OBJPROP_STATE, true\);/.test(ga))
      broken.push('the focus half never writes OBJPROP_STATE on the field — the user must find and click it before Enter means anything (P-DRAW-131)');
    if (!/\[drawstrip\] TPLARM /.test(ga))
      broken.push('the focus write has no flushed witness — «تایپ کردم نرفت» is unanswerable without it (P-DRAW-131)');
    if (!/bool DrawStripTplCommit\(const string why\)/.test(ga))
      broken.push('the commit has no one owner in GearA (P-DRAW-131)');
    if (!/s_dsTplNameArmed = false;[\s\S]{0,200}?DrawTplSaveAs\(s_dsObj, t\)/.test(ga))
      broken.push('the commit no longer clears the armed flag before its one file write (P-DRAW-131)');
    if (!/\[drawstrip\] TPLSAVE /.test(ga) || !/why=/.test(ga))
      broken.push('the commit writes without its flushed witness or without naming its door (P-DRAW-131)');
    if ((ta.match(/DrawStripTplNameFocus\(\);/g) || []).length < 2)
      broken.push('a save door arms its field unfocused — both doors (the more popover and the Look tab row) must focus it (P-DRAW-131)');
    if (!/DrawStripTplCommit\("enter"\);/.test(ta))
      broken.push('Enter no longer routes through the one commit — the write has two owners again (P-DRAW-131)');
    if (/DrawTplSaveAs\(/.test(ta))
      broken.push('a direct DrawTplSaveAs call is back in Tap — the commit must be the ONE caller (P-DRAW-131)');
    if (!/DrawStripTplCommit\("group"\);/.test(ta))
      broken.push('a group tap drops the armed field without committing it — the save evaporates on a fold/switch (P-DRAW-131)');
    const gcloseIdx = indexOfLine(gbLines, 'void DrawStripGearClose()');
    if (gcloseIdx < 0) {
      broken.push('DrawStripGearClose is gone (P-DRAW-131)');
    } else {
      const cIdx = indexOfLine(gbLines, 'DrawStripTplCommit("close");', gcloseIdx);
      const pIdx = indexOfLine(gbLines, 'DrawStripGearObjectsPurge();', gcloseIdx);
      if (cIdx < 0)
        broken.push('the close door no longer commits a pending save — every close (head X, gear/more toggles, Esc, object switch) drops it silently (P-DRAW-131)');
      else if (pIdx >= 0 && cIdx > pIdx)
        broken.push('the close door commits AFTER the purge — the field and its text are already gone (P-DRAW-131)');
      const b = blockAfter(gbLines, gcloseIdx);
      if (b && /s_dsTplNameArmed = false;/.test(codeOf(gbLines.slice(b.from, b.to + 1))))
        broken.push('DrawStripGearClose clears s_dsTplNameArmed again — the commit is its one owner (P-DRAW-131)');
    }
    // P-DRAW-131b (2026-10-18): «مینویسم ولی چیزی برا سیو نداره که» — the armed row's
    // OWN Save. Enter worked and was invisible; the exits worked and looked like exits.
    // The button is the fourth door into the same commit, its seat owned once, and it
    // dies with the arm (the commit's own sweep + the gear purge).
    if (!/int DrawStripTplSaveW\(\)/.test(ga))
      broken.push('the armed row\'s Save control lost its seat owner — the paint and the hit test would each guess a width (P-DRAW-131)');
    if (!/int DrawStripTplSavePaint\(/.test(ga))
      broken.push('the armed row\'s Save control has no painter — the row offers nothing to press again (P-DRAW-131)');
    if (!/ew - sw - DSTRIP_ROW_GAP/.test(codeOf(gbLines)) || !/DrawStripTplSavePaint\(ex \+ ew - sw,/.test(codeOf(gbLines)))
      broken.push('the armed row no longer seats the Save control inside its own row — the field and the button would overlap (P-DRAW-131)');
    if (!/DrawStripTplSaveHit\(e, mx, ex, ew\)/.test(bs))
      broken.push('the armed row\'s Save control lost its commit door — the button the user presses does nothing (P-DRAW-131)');
    if (!/int sw = DrawStripTplSaveW\(\);[\s\S]{0,220}?DrawStripTplCommit\("save"\);/.test(ga))
      broken.push('the Save hit test no longer reads the paint\'s own seat owner — a second grid (P-DRAW-131)');
    if (!/DrawStripTplSaveName\(\)[\s\S]{0,120}?DrawStripTplCommit\("save"\);/.test(rd))
      broken.push('the Save button\'s native click has no router branch — a press on the button itself reaches nothing (P-DRAW-131)');
    const svCalls = (ga.match(/DrawStripTplSaveSweep\(\)/g) || []).length;
    if (svCalls < 3 || !/ObjectDelete\(0, sb \+ "T"\)/.test(ga))
      broken.push('the Save control outlives its row — the sweep must be defined and run at both of the arm\'s ends (the commit and the gear purge) (P-DRAW-131)');
    if (broken.length) {
      failures.push('P-DRAW-131: ' + broken.join('; ') + ' (Biotak/DrawStrip_GearA.mqh + DrawStrip_GearB.mqh + DrawStrip_Tap.mqh)');
    } else {
      console.log('[PASS] P-DRAW-131 the save\'s name field is focused the moment either door arms it, and the pending save commits through ONE owner on every exit (Enter, the panel close, the group tap) with flushed TPLARM/TPLSAVE witnesses');
    }
  }

  // -- 60. P-DRAW-132 (2026-10-18): NAMED TEMPLATES PER TOOL, ONE RACK, ONE FILE ----
  // «میخوام تمپلت های مختلف رو سیو کنم و به راحیت هر کدوم خواستم فعال کنم بشه» — the
  // TradingView shape. What P-DRAW-02 shipped was a fixed six-slot rack: three
  // built-ins the user could never rename or remove, three anonymous user slots, and
  // a full rack that silently overwrote the oldest row. The rewrite is a NAMED rack
  // per kind (`DrawTpl`…, Toolbar_Tpl.mqh — split out of Toolbar_B by P-SIZE-1500),
  // persisted in ONE five-column file with rows 255/254 reserved (P-DRAW-09c /
  // P-DRAW-INK), reached from the strip through the paginated more popover and Look
  // tab. Six laws, each the walk of the report: put REPLACES by name (case-
  // insensitive) and REFUSES a full rack; delete COMPACTS; an apply is ONE file pass
  // (`s_dkTplHold`); an empty label gets "My N"; boot is seed-once-but-file-rules,
  // with P-DRAW-02's file migrated and retired exactly once; and the old architecture
  // does not linger — no old preset API name survives in either file's code.
  {
    const broken = [];
    const tplLines = linesOf(path.join(BIOTAK, 'Toolbar_Tpl.mqh')) || [];
    const tpl = codeOf(tplLines);
    const tbb = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || []);
    if (!tplLines.length) broken.push('Biotak/Toolbar_Tpl.mqh is gone — the rack has no owner file');
    if (!/define DRAW_TPL_MAX 12/.test(tpl) || !/define DRAW_TPL_PAGE 6/.test(tpl))
      broken.push('the rack\u2019s bounds left the file (DRAW_TPL_MAX 12 / DRAW_TPL_PAGE 6)');
    const put = bodyOf(tplLines, 'int DrawTplPut(');
    if (!put) broken.push('DrawTplPut() is gone — the rack has no writer');
    else {
      if (!/if\(DrawTplCount\(k\) >= DRAW_TPL_MAX\) return 0;/.test(put.text))
        broken.push('a full rack overwrites the oldest template again instead of refusing with 0');
      if (!/int at = DrawTplIndex\(k, nm\);/.test(put.text))
        broken.push('the put stopped asking by name — a re-save cannot replace');
    }
    const idx = bodyOf(tplLines, 'int DrawTplIndex(');
    if (!idx || !/StringCompare\(s_dkTpl\[k\]\[i\]\.name, nm, false\) == 0/.test(idx.text))
      broken.push('the name lookup is case-sensitive again — "My Box" and "my box" are one template to the user');
    const del = bodyOf(tplLines, 'bool DrawTplDelete(');
    if (!del) broken.push('DrawTplDelete() is gone — a template can never leave');
    else {
      if (!/for\(int i = slot; i < n - 1; i\+\+\)/.test(del.text))
        broken.push('the compaction walk is gone — the rows after a hole no longer move down');
      if (!/s_dkTpl\[k\]\[i\]\.used  = s_dkTpl\[k\]\[i \+ 1\]\.used;/.test(del.text))
        broken.push('the delete stopped compacting — a hole survives a removal and every row index past it lies');
      if (!/s_dkTpl\[k\]\[n - 1\]\.used  = false;/.test(del.text))
        broken.push('the delete stopped clearing the tail row');
      if (!/DrawTplSave\(\);/.test(del.text))
        broken.push('the delete never writes the file — the template comes back at the attach');
    }
    const app = bodyOf(tplLines, 'bool DrawTplApply(');
    if (!app) broken.push('DrawTplApply() is gone — a template cannot reach a drawing');
    else {
      if (!/s_dkTplHold\+\+;/.test(app.text) || !/s_dkTplHold--;/.test(app.text))
        broken.push('the apply\u2019s batch hold is gone — one template pays one full-file pass per slot');
      const iFc = app.text.indexOf('DRAW_SLOT_FILLCLR');
      const iF = app.text.indexOf('DRAW_SLOT_FILL,');
      if (iFc < 0 || iF < 0 || iFc > iF)
        broken.push('the interior colour is written AFTER the fill again — a fill routed to a child is born with the previous interior (P-DRAW-64)');
      if (!/if\(\(int\)L\.clr >= 0\)/.test(app.text))
        broken.push('the apply writes a colour the template never carried — clrNONE comes back as white');
    }
    if (!/if\(s_dkTplHold <= 0\) DrawTplSave\(\);/.test(tbb))
      broken.push('DrawSlotWrite forgot the hold — an apply pays a file write per slot again');
    const sa = bodyOf(tplLines, 'int DrawTplSaveAs(');
    if (!sa) broken.push('DrawTplSaveAs() is gone — the Save doors have no owner');
    else {
      if (!/if\(nm == ""\) nm = "My " \+ IntegerToString\(DrawTplCount\(k\) \+ 1\);/.test(sa.text))
        broken.push('an empty label survives as an unnamed template — a row the user cannot find');
      if (!/if\(res > 0\) DrawTplSave\(\);/.test(sa.text))
        broken.push('capture and persist stopped being one act — a saved template dies at the attach (P-DRAW-08b)');
    }
    const boot = bodyOf(tplLines, 'void DrawTplBoot()');
    if (!boot) broken.push('DrawTplBoot() is gone — nothing seeds or migrates the rack');
    else {
      if (!/if\(FileIsExist\(DRAW_TPL_FILE\)\)/.test(boot.text))
        broken.push('the boot no longer lets the FILE rule — a deleted seed comes back every attach');
      if (!/DrawTplSeed\(\);/.test(boot.text) || !/if\(FileIsExist\(DRAW_TPL_LEGACY\)\) DrawTplMigrate\(\);/.test(boot.text))
        broken.push('the first-run seed or the P-DRAW-02 migration left the boot');
      if (!/if\(FileIsExist\(DRAW_TPL_LEGACY\)\) FileDelete\(DRAW_TPL_LEGACY\);/.test(boot.text))
        broken.push('the legacy file is never retired — a later boot would migrate it again and fight the new file');
    }
    const legacyApi = /DrawPreset(Apply|CaptureAndSave|sSave|sLoad|Count|Name|IsBuiltin|Set|Clear|sInit|Path|Pack|Unpack)\s*\(/;
    if (legacyApi.test(tpl) || legacyApi.test(tbb))
      broken.push('an old preset API name is back in code — two racks, one question (the P-DRAW-132 rewrite deletes the old architecture)');
    const tap = codeOf(linesOf(STRIP_TAP) || []);
    if (!/if\(kind == DSTRIP_MK_PRESET\)[\s\S]{0,220}?DrawStripTplApplyGroup\(arg\)/.test(tap))
      broken.push('the more popover\u2019s template row stopped applying through the group owner');
    if (!/if\(kind == DSTRIP_MK_TPLNAV\)/.test(tap) ||
        (tap.match(/s_dsTplPage\[s_dsKind\] = \(s_dsTplPage\[s_dsKind\] \+ 1\) % pages;/g) || []).length < 2)
      broken.push('the paged list lost a door: the more popover\u2019s nav row or the Look tab\u2019s (both turn the page with a wrap)');
    if (!/if\(kind == DSTRIP_GRK_TPLNAV\)/.test(tap))
      broken.push('the Look tab\u2019s nav row (DSTRIP_GRK_TPLNAV) has no branch — the second page is unreachable');
    //--- P-DRAW-136 (2026-10-20): the nav row's kind must be its OWN. The group
    //--- header's branch is tested FIRST and swallows every row that shares the
    //--- header's number, so a nav row that wore kind 9 was painted, hit and
    //--- answered NOTHING (P-DRAW-84's law, one number over).
    {
      const headTxt = fs.readFileSync(STRIP_HEAD, 'utf8');
      const navDef = headTxt.match(/#define\s+DSTRIP_GRK_TPLNAV\s+(\d+)/);
      const grpDef = headTxt.match(/#define\s+DSTRIP_GRK_GROUP\s+(\d+)/);
      if (!navDef) broken.push('DSTRIP_GRK_TPLNAV is gone from DrawStrip_Head.mqh — the template page walk has no kind of its own');
      else if (grpDef && navDef[1] === grpDef[1])
        broken.push(`DSTRIP_GRK_TPLNAV (${navDef[1]}) shares the group header's number — the header's branch is tested first and swallows the page walk`);
      const gearA2 = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearA.mqh')) || []);
      if (!/DrawStripGearRow\(DSTRIP_GRK_TPLNAV, 0, y\)/.test(gearA2))
        broken.push('the Look tab\u2019s nav row is not built with DSTRIP_GRK_TPLNAV — a page the user cannot turn');
    }
    const gearA = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearA.mqh')) || []);
    if (!/string DrawStripTplNavText\(const EDrawKind k\)/.test(gearA) || !/DrawStripGearRow\(DSTRIP_GRK_TPLNAV, 0, y\);/.test(gearA))
      broken.push('the nav row\u2019s text or the TPL tab\u2019s own nav row left GearA — a page the user cannot turn');
    const paint = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || []);
    //--- P-DRAW-134: the delete door MOVED — the row's ✕ is its one door now and the
    //--- group owner is APPLY alone — so the assert follows the owner: the delete
    //--- body, its one DrawTplDelete call and the flushed TPLDEL witness all live
    //--- there (and the SHIFT read is asserted ABSENT by the P-DRAW-134 block below).
    if (!/bool DrawStripTplApplyGroup\(const int row\)/.test(paint) ||
        !/bool DrawStripTplRowDelete\(const int row\)/.test(paint) ||
        !/DrawTplDelete\(k, row\)/.test(paint) || !/\[drawstrip\] TPLDEL /.test(paint))
      broken.push('the group owner\u2019s apply door, the row-delete body or its TPLDEL witness left DrawStrip_Paint');
    if (broken.length) {
      failures.push('P-DRAW-132: ' + broken.join('; ') + ' (Biotak/Toolbar_Tpl.mqh + Toolbar_B.mqh + DrawStrip_Tap/GearA/Paint.mqh)');
    } else {
      console.log('[PASS] P-DRAW-132 named templates per tool: one rack per kind (12, six a page), replace-by-name, refuse-when-full, compact deletes, ONE file pass per apply, paged lists, and the one-time seed/migration');
    }
  }

  // -- 61. P-DRAW-133 (2026-10-18): NO DEAD RUNG IN THE GEAR ROUTER ----------------
  // MEASURED in the P-DRAW-132 walk: DrawStripGearRowTap carried a stray `return true;`
  // between its kind-4 and kind-5 rungs, so kinds 5/6/7/8 — the level-set rows, the
  // slot-visibility rows, the learn-current row and the glyph rows — compiled, painted
  // and hit-tested perfectly and answered nothing. A painted control is not a working
  // one (P-DRAW-84). The inverse is the exact line, back where it stood.
  {
    const broken = [];
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    if (!/}\s*if\(kind == 5\)/.test(tap))
      broken.push('a statement stands between the kind-4 and the kind-5 rung again — every rung below it is unreachable (P-DRAW-133)');
    for (const k of [6, 7, 8])
      if (!new RegExp('if\\(kind == ' + k + '\\)').test(tap))
        broken.push('the kind-' + k + ' rung is gone — a painted row answers nothing');
    if (broken.length) {
      failures.push('P-DRAW-133: ' + broken.join('; ') + ' (Biotak/DrawStrip_Tap.mqh DrawStripGearRowTap)');
    } else {
      console.log('[PASS] P-DRAW-133 every gear row kind reaches a live rung: no stray return between the level-set row and the slot-visibility, learn-current and glyph rungs');
    }
  }

  // -- 62. P-DRAW-134 (2026-10-18): DELETE IS A BUTTON, NOT A MODIFIER --------------
  // User order: «شیبف کلکی بردار بجاش یک دکمه حذف برای هر کدوم بزار» — the SHIFT+click
  // delete door on template rows is retired and every row carries its own ✕: a named
  // button + its gold glyph, painted on the row's own roster entry, answered by its
  // own router branch (BEFORE the row loop — the foot-glyph lesson, P-DRAW-83),
  // deleting through the ONE body `DrawStripTplRowDelete`. The inverse is each of
  // those facts undone: the modifier returns, the × is never painted, the branch or
  // the call is inert, the seat moves, the tooltip promises the dead door, or a
  // sweep forgets the family.
  {
    const broken = [];
    const paint = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Paint.mqh')) || []);
    const router = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    const gearA = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearA.mqh')) || []);
    const gearB = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_GearB.mqh')) || []);
    if (!/string DrawStripPickDelName\(const int r\)/.test(gearA) ||
        !/string DrawStripPickDelFaceName\(const int r\)/.test(gearA))
      broken.push('the row \u2715\u2019s two seat owners left GearA — the button or its glyph face has no name again');
    if (!/bool isTpl = \(s_dsPicker == DSTRIP_MORE && s_dsMoreKind\[r\] == DSTRIP_MK_PRESET\)/.test(paint))
      broken.push('the paint no longer asks the row roster before wearing a \u2715 — a control on a row that is not a template');
    if (!/int dx = px \+ contentW - DSTRIP_PICK_DEL_W;/.test(paint))
      broken.push('the \u2715\u2019s seat left the row\u2019s far end — the paint and the hit no longer share the roster\u2019s arithmetic');
    if (!/dirty \|= DrawStripBtnZ\(pd, dx, dy, DSTRIP_PICK_DEL_W, DSTRIP_PICK_DEL_W,/.test(paint) ||
        !/gl_x_gold\.bmp", tipd\)/.test(paint))
      broken.push('the \u2715 button or its gold glyph stopped being painted on the template rows');
    if (!/isTpl \? DSTRIP_PICK_DEL_W : 0/.test(paint))
      broken.push('the row label no longer reserves the \u2715\u2019s seat — text runs under the delete button again');
    if (!/sparam == DrawStripPickDelName\(rd\) \|\| sparam == DrawStripPickDelFaceName\(rd\)/.test(router) ||
        !/DrawStripPickTapDel\(rd\); return DrawStripClickFamily\(\);/.test(router))
      broken.push('the \u2715\u2019s own router branch is gone — the click the user aims at the \u2715 falls through to the row\u2019s apply');
    if (!/bool DrawStripPickTapDel\(const int row\)/.test(tap) ||
        !/DrawStripTplRowDelete\(s_dsMoreArg\[row\]\)/.test(tap))
      broken.push('the \u2715\u2019s tap door is gone or stopped calling the ONE delete body — a painted control that acts at nothing');
    if (/UIMagnetModifierDown\(\)/.test(paint))
      broken.push('the SHIFT delete returned to the template rows — the user ordered delete to be a visible BUTTON (the row\u2019s \u2715), never a modifier');
    if (/Shift\+click deletes it/.test(gearA))
      broken.push('the row tooltip promises the retired Shift+click again — a hint for a door that is not there');
    if (!/string pd = DrawStripPickDelName\(r\)/.test(paint) || !/ObjectDelete\(0, pd\)/.test(paint))
      broken.push('the open popover\u2019s row sweep forgot the \u2715 family — what the paint painted for a dead row stays on the plate');
    let sv = 0;
    for (const src of [paint, gearA, gearB])
      sv += (src.match(/ObjectDelete\(0, DrawStripPickDelName\(r\)\)/g) || []).length;
    if (sv < 3)
      broken.push('a purge site forgot the \u2715 family (' + sv + ' of 3 named sweeps left) — the button outlives the popover it served');
    if (broken.length) {
      failures.push('P-DRAW-134: ' + broken.join('; ') + ' (Biotak/DrawStrip_Paint/Router/Tap/GearA/GearB.mqh)');
    } else {
      console.log('[PASS] P-DRAW-134 every template row deletes through its own \u2715: named button + glyph, roster-gated, the seat shared with the hit, its own router branch, the ONE delete body, no SHIFT door, tooltips follow, and the family swept at all three purge sites');
    }
  }

  // -- 63. P-DRAW-135 (2026-10-18): THE TEMPLATE CARRIES THE LEVELS -----------------
  // User order: «وقتی تمپلت ذخیره میشه باید با همه چیزش ذخیره بشه دیگه ... با سایر
  // ارزها ... باید درست باشه». For the level family the LEVELS ARE THE DRAWING, and
  // the nine-value look never carried them — a saved fibo stamped a default fibo onto
  // every chart, on every pair. The level set now rides its own reserved row (index
  // 100+slot, the encoded string in the `name` column = `value:colour:width:style:text`
  // records joined by '|'), answered BEFORE the band guard, moved by a delete, written
  // by the ONE saver and restored by the ONE applier, with the toggle's own flushed
  // LVLTOG witness. The inverse is each of those facts undone.
  {
    const broken = [];
    const tplLines = linesOf(path.join(BIOTAK, 'Toolbar_Tpl.mqh')) || [];
    const tpl = codeOf(tplLines);
    if (!/define DRAW_TPL_LVL_ROW 100/.test(tpl))
      broken.push('the level row\u2019s reserved index left Toolbar_Tpl — the level set has no seat clear of the template band (0..11) and the 255/254 rows');
    if (!/string lvl;/.test(tpl))
      broken.push('struct DrawTpl lost its `lvl` member — a template can never carry a level set again');
    const put = bodyOf(tplLines, 'int DrawTplPut(');
    if (!put || !/int DrawTplPut\(const EDrawKind k, const string nm, const DrawLook &L, const string lvls = ""\)/.test(tpl))
      broken.push('DrawTplPut() no longer takes the encoded level set — the saver has nowhere to hand it');
    else if (!/s_dkTpl\[k\]\[at\]\.lvl   = lvls;/.test(put.text))
      broken.push('the put stopped recording the level set — a re-save cannot replace what it does not write');
    const sa = bodyOf(tplLines, 'int DrawTplSaveAs(');
    if (!sa || !/DrawTplLevelsOf\(name\)/.test(sa.text) || !/DrawTplPut\(k, nm, L, lv\)/.test(sa.text))
      broken.push('the save stopped capturing the level family\u2019s own truth — «با همه چیزش ذخیره بشه» regressed to the nine values alone');
    const app = bodyOf(tplLines, 'bool DrawTplApply(');
    if (!app || !/DrawTplLevelsTo\(name, s_dkTpl\[k\]\[slot\]\.lvl\)/.test(app.text))
      broken.push('the apply stopped restoring the level set — an applied fibo template comes back default-leveled');
    const sv = bodyOf(tplLines, 'void DrawTplSave()');
    if (!sv || !/FileWrite\(h, \(int\)k, DRAW_TPL_LVL_ROW \+ i, s_dkTpl\[k\]\[i\]\.lvl, "0", "0"\);/.test(sv.text))
      broken.push('the file writer dropped the level rows — the set dies at the next attach while the rack looks saved');
    const ld = bodyOf(tplLines, 'void DrawTplLoad()');
    if (!ld) broken.push('DrawTplLoad() is gone');
    else {
      const iLvl = ld.text.indexOf('DRAW_TPL_LVL_ROW');
      const iBand = ld.text.indexOf('i < 0 || i >= DRAW_TPL_MAX');
      if (iLvl < 0 || !/s_dkTpl\[k\]\[i - DRAW_TPL_LVL_ROW\]\.lvl = nm;/.test(ld.text))
        broken.push('the loader never reads the level rows — a saved level set comes back empty');
      else if (iBand >= 0 && iLvl > iBand)
        broken.push('the level-row read stands AFTER the template band guard — the guard eats the rows this feature writes (P-UI-133\u2019s lesson)');
    }
    const del = bodyOf(tplLines, 'bool DrawTplDelete(');
    if (!del || !/s_dkTpl\[k\]\[i\]\.lvl   = s_dkTpl\[k\]\[i \+ 1\]\.lvl;/.test(del.text))
      broken.push('a delete stopped moving the level set with its row — the wrong fibo wears the hole\u2019s levels');
    const boot = bodyOf(tplLines, 'void DrawTplBoot()');
    if (!boot || !/s_dkTpl\[k\]\[i\]\.lvl   = "";/.test(boot.text))
      broken.push('the boot wipe leaves the level set behind — a dead template\u2019s fibo can seed the next save');
    const enc = bodyOf(tplLines, 'string DrawTplLevelsOf(');
    if (!enc) broken.push('DrawTplLevelsOf() is gone — nothing captures a level set');
    else {
      if (!/StringReplace\(t, ";", ","\);/.test(enc.text))
        broken.push('the encoder stopped trading \u2018;\u2019 — one typed note splits the CSV line and corrupts the whole rack file');
      if (!/StringReplace\(t, "\\|", "\/"\);/.test(enc.text))
        broken.push('the encoder stopped trading \u2018|\u2019 — a note eats the record walk and the levels after it are lost');
    }
    const dec = bodyOf(tplLines, 'bool DrawTplLevelsTo(');
    if (!dec || !/ObjectSetInteger\(0, name, OBJPROP_LEVELS, n\);/.test(dec.text) ||
        !/FibPenTagDrop\(name\);/.test(dec.text) || !/FibPenSync\(name, false\);/.test(dec.text))
      broken.push('the decoder stopped writing the level rows or forgot the pen pair (P-DRAW-74b) — the restored fibo diverges from the truth');
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    if (!/\[drawstrip\] LVLTOG /.test(tap) || !/act=" \+ \(at >= 0 \? "del" : "add"\)/.test(tap) ||
        !/ok=" \+ \(lvlOk \? "1" : "0"\)/.test(tap))
      broken.push('the level toggle lost its LVLTOG witness — «کم و زیاد نمیشه» is unprovable again');
    if (broken.length) {
      failures.push('P-DRAW-135: ' + broken.join('; ') + ' (Biotak/Toolbar_Tpl.mqh + DrawStrip_Tap.mqh)');
    } else {
      console.log('[PASS] P-DRAW-135 the template carries the level set: reserved row, band-guard-safe load, put/save/delete/boot all move it, the encoder trades both separators, the apply restores through the pen pair, and the toggle witnesses on the flushed channel');
    }
  }

  // -- 64. P-UI-167 (2026-10-19): the seat family is born only while the ring is BUILT
  // Report: «گاهی اوقات چرا اینطوری میشه با اینکه منو اصلی بسته هستش … اینکون ایتم‌ها
  // دیده میشه بدون بک گراند ولی منو بسته هستش». MEASURED in the flushed frame
  // (biotak_diag_USDJPY_134362571361933145.txt, 230,095 bytes): three bursts of
  // `[P-UI-163] icon heal seat=0..11`, each right after a chart press — the drain ran
  // `UpdateCircularItemStates` while the menu was CLOSED, `CircUpdateItemState`
  // re-created all twelve GLYPHS, and the disc family (CircBg) — deleted by
  // DeleteRing/ToggleMenuVisibility — had no writer on that path at all. The ring's
  // every other builder reads the pair menuVisible+!g_ToolsOpen; this loop read only
  // the fan half (P-UI-163c's own fix), so the closed state grew a column of bare
  // icons beside the orb. The loop must read the same pair — one bool read, and it
  // replaces a 12-seat glyph burst per drain (cost: zero writes while the ring is
  // down). The inverse is the guard's menuVisible half removed.
  {
    const broken = [];
    const menuC67 = linesOf(MENU_C);
    if (!menuC67) broken.push('Biotak/BiotakMenu_C.mqh is gone — the ring has no painter');
    else {
      const states67 = bodyOf(menuC67, 'void UpdateCircularItemStates(');
      if (!states67) broken.push('UpdateCircularItemStates is gone — the sync pass has no owner');
      else if (!states67.text.includes('g_UI.menuVisible && !g_ToolsOpen'))
        broken.push('the sync pass rebuilds the ring while the menu is CLOSED again — CircUpdateItemState re-creates the twelve glyphs with no disc under them (the bare-icon column of the reported frame)');
    }
    if (broken.length) {
      failures.push('P-UI-167: ' + broken.join('; ') + ' (Biotak/BiotakMenu_C.mqh)');
    } else {
      console.log('[PASS] P-UI-167 the seat family is born only while the ring is BUILT: the state sync reads menuVisible AND the fan before it walks a seat, so a closed menu cannot grow bare icons (cost: one bool read, zero writes while the ring is down)');
    }
  }

  // -- 65. P-UI-168 (2026-10-19): THE RING'S VISIBILITY EDGE NAMES ITS WRITER
  // MEASURED in the flushed frame of 09:03 (biotak_diag_USDJPY_134362571361933145.txt,
  // 340,704 bytes): 4.5 whole-family sweeps — 108 `CircIcon` delete lines, icon+bg
  // together, ZERO `[P-UI-163] icon heal` (P-UI-167 held) — and nothing in the log
  // could name the writer: `ToggleMenuVisibility`'s close, `CircRelayoutIfNeeded`'s
  // rebuild and `CreateToolsMenu`'s fan open all delete the SAME twenty-four names.
  // While the bare-icon column was being chased, a reader could not tell "the ring
  // was closed" from "the ring was rebuilt" from "the fan merely opened" — the
  // object list is the same in all three. Each of the four owners now emits ONE
  // flushed line on its own edge, carrying the pair the relayout compares
  // (built vs live seats) or the restore flag; a still frame enters none of them.
  // The inverse is any one of the four emits removed.
  {
    const broken = [];
    const menuD68 = linesOf(MENU_D);
    const menuC68 = linesOf(MENU_C);
    if (!menuD68) broken.push('Biotak/BiotakMenu_D.mqh is gone — the ring has no visibility owner');
    if (!menuC68) broken.push('Biotak/BiotakMenu_C.mqh is gone — the ring has no painter');
    const flatOf = (lines68, needle) => {
      if (!lines68) return '';
      const fn = bodyOf(lines68, needle);
      return fn ? fn.text.replace(/\s+/g, ' ') : '';
    };
    const toggle68 = flatOf(menuD68, 'void ToggleMenuVisibility()');
    if (!toggle68)
      broken.push('ToggleMenuVisibility is gone — the orb\'s click has no owner');
    else {
      if (!toggle68.includes('"[P-UI-168] ring vis=%d tools=%d placed=%d built=%d"'))
        broken.push('the visibility edge lost its witness — a whole-family sweep in the frame can no longer be attributed to the close (P-UI-168)');
      if (!toggle68.includes('(g_UI.menuVisible ? 1 : 0)') || !toggle68.includes('(g_ToolsOpen ? 1 : 0)'))
        broken.push('the edge line no longer carries the pair the ring\'s every builder reads (menuVisible + the fan) — the reported state cannot be re-read from the frame');
      if (!toggle68.includes('CircPlacedCountLive(), s_circBuiltSeats)'))
        broken.push('the edge line dropped the relayout\'s own compare operands — a rebuild reads as a bare state change again');
    }
    const relayout68 = flatOf(menuC68, 'void CircRelayoutIfNeeded()');
    if (!relayout68)
      broken.push('CircRelayoutIfNeeded is gone — a seat-set flip has no rebuild owner');
    else if (!relayout68.includes('"[P-UI-168] ring relayout built=%d live=%d"'))
      broken.push('the rebuild edge lost its witness — the second writer of the same 24-name sweep is silent again (P-UI-168)');
    const fanOpen68 = flatOf(menuC68, 'void CreateToolsMenu()');
    if (!fanOpen68)
      broken.push('CreateToolsMenu is gone — the fan has no open edge');
    else if (!fanOpen68.includes('"[P-UI-168] fan open=1 cells=%d placed=%d"'))
      broken.push('the fan\'s open edge lost its witness — its own ring sweep reads as the ring being closed (P-UI-168)');
    const fanClose68 = flatOf(menuC68, 'void DeleteToolsMenu(');
    if (!fanClose68)
      broken.push('DeleteToolsMenu is gone — the fan has no close edge');
    else {
      if (!fanClose68.includes('"[P-UI-168] fan open=0 restore=%d placed=%d built=%d"'))
        broken.push('the fan\'s close edge lost its witness — a tear-down and a ring restore are the same delete burst again (P-UI-168)');
      if (!fanClose68.includes('(restoreRing ? 1 : 0)'))
        broken.push('the fan\'s close line no longer says whether the ring was meant to come back');
    }
    if (broken.length) {
      failures.push('P-UI-168: ' + broken.join('; ') + ' (Biotak/BiotakMenu_C.mqh + BiotakMenu_D.mqh)');
    } else {
      console.log('[PASS] P-UI-168 the seat sweep has four named owners: the visibility edge, the relayout rebuild and the fan\'s open/close each emit one flushed line with their own operands (cost: one line per user edge, zero on a still frame)');
    }
  }

  // -- 66. P-PERF-45e (2026-10-19): THE COOP WAIT IS MEASURED IN TIMER PERIODS
  // MEASURED: 325 `[W][PERF] coop job=` lines in two days, 319 of them one shape —
  // `waited=234..282ms ran=0ms stillOwed=0` (200 status-text + 125 label-expiry) —
  // against SIX whose `ran` was real. The arms sit right before `CoopPump()` in the
  // same tick, so a full-period wait is the pump's own deferral: the slice check at
  // its foot breaks on the ~15.6 ms GetTickCount granule (`COOP_BUDGET_MS 12`), and
  // the leftover job waits for the next 250 ms timer tick. 40 ms therefore warned
  // on the design and buried the six lines that mattered. The threshold must stay
  // ABOVE the timer period it is read against — this entry derives it, so retuning
  // the timer without retuning the warn fails here instead of in the journal.
  // The inverse is the wait half back on COOP_WARN_MS.
  {
    const broken = [];
    const init66 = linesOf(path.join(BIOTAK, 'EventHandlers_Init.mqh'));
    const tail66 = linesOf(path.join(BIOTAK, 'EventHandlers_Tail.mqh'));
    let periodMs = -1;
    if (!init66) broken.push('EventHandlers_Init.mqh is gone — the timer has no owner');
    else {
      for (const ln of init66) {
        const m = /EventSetMillisecondTimer\((\d+)\)/.exec(ln);
        if (m) { periodMs = Number(m[1]); break; }
      }
      if (periodMs < 0) broken.push('the millisecond timer is no longer started — OnTimer never runs and the coop pump is dead (P-PERF-45e)');
    }
    if (!tail66) broken.push('EventHandlers_Tail.mqh is gone — the coop pump has no owner');
    else {
      // The threshold is owned beside the slice it is read against (`COOP_BUDGET_MS`,
      // same constant block), so the pump's two numbers stay in one file (§7).
      let waitWarn = -1;
      for (const ln of tail66) {
        const m = /#define\s+COOP_WAIT_WARN_MS\s+(\d+)/.exec(ln);
        if (m) { waitWarn = Number(m[1]); break; }
      }
      if (waitWarn < 0)
        broken.push('COOP_WAIT_WARN_MS is gone — the wait half is back on the 40 ms frame threshold, so one normal deferral prints a warning again (319 of 325 measured lines)');
      else if (periodMs > 0 && waitWarn < 2 * periodMs)
        broken.push(`the wait threshold (${waitWarn} ms) is under two timer periods (2 x ${periodMs} ms) — a job skipped ONCE prints again, which is the noise this rule removes (P-PERF-45e)`);
      const cond = tail66.find((ln) => ln.includes('waited >=') && ln.includes('spent >='));
      if (!cond) broken.push('the coop ledger condition is gone — a starved job and a slow frame are no longer reported (P-PERF-45e)');
      else {
        if (!cond.includes('waited >= COOP_WAIT_WARN_MS'))
          broken.push('the wait half is not read against the timer-period threshold — one deferral warns again (P-PERF-45e)');
        if (!cond.includes('spent >= COOP_WARN_MS'))
          broken.push('the `spent` half was raised too — the six real lines (`heavy-frame ran=125ms`) are now silent (P-PERF-45e)');
      }
    }
    if (broken.length) {
      failures.push('P-PERF-45e: ' + broken.join('; ') + ' (Biotak/EventHandlers_Tail.mqh + EventHandlers_Init.mqh)');
    } else {
      console.log('[PASS] P-PERF-45e the coop wait warns in timer periods, not milliseconds: the threshold is at least two 250 ms ticks, so one deferral is silent and the `spent` half still names a real stall');
    }
  }

  // ── 67. P-DRAW-145 (2026-10-19) — A STRIP CELL EXISTS ONLY WHERE ITS WRITE CAN DRAW ──
  // The capability table is not decoration: a set bit IS a cell, and a cell is a promise
  // that the hand's tap changes a pixel. Three rows broke the promise at once.
  //   * A Gann was listed as a LEVEL kind, so its colour/width/style cells wrote
  //     `DrawLevelsSet*` — a loop over OBJPROP_LEVELS rows — while a Gann carries no
  //     line-levels at all. MetaQuotes' own object pages say it plainly: OBJ_PITCHFORK
  //     and OBJ_EXPANSION "can specify the number of line-levels, their values and
  //     color"; OBJ_GANNLINE offers angle, scale and ray and says nothing of levels.
  //     Zero rows means zero writes, and the READ (which already asks
  //     `DrawLevelCount(name) > 0`) answered the OBJECT — a cell showing a value it
  //     could not change. The pair that did work was the BODY's: two cells, one act.
  //   * A Text's width and style, and an Arrow's style, are the second face of the same
  //     defect. OBJ_TEXT's own page lists font, size, colour, angle, anchor, back —
  //     the terminal draws no line width and no dash for it, and none for an arrow.
  // Every read, every write and every live preview routes through `DrawKindHasLevels`,
  // so the whole family flips together here — that is why the gate sits on this table.
  {
    const tba145 = codeOf(linesOf(path.join(BIOTAK, 'Toolbar_A.mqh')) || []);
    const broken = [];
    const lvlFn = (() => { const m = tba145.match(/bool DrawKindHasLevels\(const EDrawKind k\)\s*\{[\s\S]*?\n\}/); return m ? m[0] : ''; })();
    if (!lvlFn) {
      broken.push('the level family has no owner — every level write is a guess again (P-DRAW-145)');
    } else {
      if (/\bDK_GANN\b/.test(lvlFn))
        broken.push('a Gann is a level kind again — its colour/width/style cells loop OBJPROP_LEVELS, a Gann sets it to 0, so the hand taps three cells that write nothing');
      for (const k of ['DK_FIBO', 'DK_FIBOFAN', 'DK_FIBOCHAN', 'DK_EXPANSION', 'DK_PITCHFORK'])
        if (!lvlFn.includes(k))
          broken.push(`${k} left the level family — its own levels and the pen that styles them are orphaned (P-DRAW-145)`);
    }
    const capsOf = (kind) => {
      const m = new RegExp(`case ${kind}:\\s*return ([^;]+);`).exec(tba145);
      return m ? m[1].trim() : '';
    };
    const gannCaps = capsOf('DK_GANN');
    if (!gannCaps) {
      broken.push('the Gann row left the capability table (P-DRAW-145)');
    } else {
      if (/DRAW_CAP_FILLCLR|DRAW_CAP_BODY/.test(gannCaps))
        broken.push('the Gann row offers a second colour or a body again — both are the same object property the colour/width/style cells already own, so one act wears two cells (P-DRAW-145)');
      if (!/DRAW_CAP_COMMON/.test(gannCaps))
        broken.push('the Gann row lost the common cells — a Gann does wear colour, width, style, lock, back and the terminal dialog (P-DRAW-145)');
    }
    const arrowCaps = capsOf('DK_ARROW');
    const textCaps = capsOf('DK_TEXT');
    if (!arrowCaps || !textCaps) {
      broken.push('the arrow or the text row left the capability table (P-DRAW-145)');
    } else {
      if (!/~DRAW_CAP_STYLE/.test(arrowCaps))
        broken.push('an arrow offers a line style again — the terminal draws an arrow code and a size, never a dash, so that cell paints nothing (P-DRAW-145)');
      if (!/~\(\s*DRAW_CAP_WIDTH\s*\|\s*DRAW_CAP_STYLE\s*\)/.test(textCaps))
        broken.push('a text offers a width or a style again — OBJ_TEXT wears a font and a size, and neither cell can change a pixel (P-DRAW-145)');
      if (!/DRAW_CAP_FONT/.test(textCaps) || !/DRAW_CAP_GLYPH/.test(arrowCaps))
        broken.push('the text\'s font or the arrow\'s glyph cell went with the dead ones — those two are the controls the kind really wears (P-DRAW-145)');
    }
    if (broken.length) {
      failures.push('P-DRAW-145: ' + broken.join('; ') + ' (Biotak/Toolbar_A.mqh)');
    } else {
      console.log('[PASS] P-DRAW-145 every strip cell answers a property its own object draws: the five level kinds carry levels, a Gann is a plain object strip, and neither a Text nor an Arrow offers a width or a dash the terminal cannot paint');
    }
  }

  // -- 68. P-UNIFY-3 (2026-10-19) -- THE PEN'S OWN FOUR, ONE OWNER, AND THE KIND'S OWN GEOMETRY --
  // MEASURED from the code: `FibPenSync` - the ONE function that builds the level pen (the
  // parallel copies) and the three looks (Neon core, Caps, Wash) - refused every kind but
  // DK_FIBO/DK_FIBOFAN on its own first line, while the STYLE slot's gate two files over
  // already asked `DrawKindHasLevels(k)` (Toolbar_B.mqh:291/302). One act, two owners, two
  // answers: the writer accepted a look for a Fibo Channel and the pen refused to draw it,
  // and the picker mirrored the refusal with 5 style rows instead of 8. Serving every level
  // kind blindly was not the answer either: the pen seated every child with ONE law
  // (`p2 + (p1 - p2) * v`) while MT4 draws a Channel's levels as PARALLELS of the base
  // through the third anchor, a Fan's as RAYS and an Expansion's as horizontals off the
  // THIRD - a child on a channel was a line the object never draws. One owner of the served
  // set now (`FibPenServesType`: exactly the four kinds whose level geometry is known;
  // pitchfork, arc and time zones refused until measured), asked by the pen, the drag
  // preview, the heal, the style fold, the pair coercion, the STYLE writer and the picker's
  // rows alike; and one owner of the geometry (`DrawLevelPriceAt`), asked by the sync rows,
  // the caps, the wash and both hit tests.
  {
    const brokenU3 = [];
    const srcU3 = (p) => linesOf(path.join(ROOT, p)) ? fs.readFileSync(path.join(ROOT, p), 'utf8') : '';
    const fp3 = srcU3('Biotak/FibPen.mqh');
    const tb3 = srcU3('Biotak/Toolbar_B.mqh');
    const pk3 = srcU3('Biotak/DrawStrip_Pick.mqh');
    const ta3 = srcU3('Biotak/Toolbar_A.mqh');
    const th3 = srcU3('Biotak/Toolbar_Hit.mqh');
    const pairRe = /k\s*(?:!=|==)\s*DK_FIBO\b/;
    //--- the served set, stated once — P-UNIFY-4 moved it to the profile's pen row;
    //--- the pen still asks it, and the four refusals stay in `DrawTypePenFamily`.
    const pr3 = srcU3('Biotak/DrawKindProfile.mqh');
    if (!/bool FibPenServesType\(const int ty\)[\s\S]{0,200}?return \(DrawTypePenFamily\(ty\) == DKPEN_LEVEL\);/.test(fp3) ||
        !/case DK_FIBO:[\s\S]{0,120}?case DK_FIBOFAN:[\s\S]{0,120}?case DK_FIBOCHAN:[\s\S]{0,120}?case DK_EXPANSION:[\s\S]{0,80}?p\.pen = DKPEN_LEVEL;/.test(pr3) ||
        !/if\(t == OBJ_FIBOTIMES \|\| t == OBJ_FIBOARC\) return DKPEN_NONE;/.test(pr3) ||
        !/if\(t == OBJ_STDDEVCHANNEL \|\| t == OBJ_REGRESSION\) return DKPEN_NONE;/.test(pr3))
      brokenU3.push('the served set is gone or widened - the pen may state only the four kinds whose level geometry is known (P-UNIFY-3)');
    if (!/bool FibPenServesName\(const string name\)[\s\S]{0,200}?return FibPenServesType\(DrawObjectType\(name\)\);/.test(fp3))
      brokenU3.push('the name oracle left the type oracle - two owners for one family again (P-UNIFY-3)');
    if ((fp3.match(/FibPenServesType\(/g) || []).length < 5)
      brokenU3.push('a pen seat stopped asking the served set - the name oracle, the preview, the sync and the heal share one question (P-UNIFY-3)');
    if (!fp3.includes('if(!FibPenServesType(DrawObjectType(name))) return;'))
      brokenU3.push('the drag preview is kind-guarded again - a dragged served kind keeps a pen the gesture cannot carry (P-UNIFY-3)');
    if (!fp3.includes('if(!FibPenServesType(DrawObjectType(fibo))) return false;'))
      brokenU3.push('the sync is kind-guarded again - the pen refuses a kind it can draw (P-UNIFY-3)');
    if (!fp3.includes('if(!FibPenServesType(ty)) return false;'))
      brokenU3.push('the heal is kind-guarded again (P-UNIFY-3)');
    if (!pk3.includes('if(FibPenServesType(ty)) FibPenHeal(nm);'))
      brokenU3.push('the 2 s net is kind-guarded again - a channel the terminal moves with no event keeps a stale pen (P-UNIFY-3)');
    //--- the look rows, the writer and the fold ask the same owner
    if (!/bool DrawStripPenLook\(const EDrawKind k\)[\s\S]{0,250}?DrawTypeLookMask\(DrawObjectType\(s_dsObj\)\) != 0/.test(pk3))
      brokenU3.push('the picker stopped asking the pen\'s own owner (P-UNIFY-3)');
    if (!pk3.includes('return ((int)STYLE_DASHDOTDOT + 1 + (DrawStripPenLook(k) ? DrawLookCount() : 0));'))
      brokenU3.push('the style list hides the looks for the served kinds again - the pen can draw them and the strip cannot ask (P-UNIFY-3)');
    if (!pk3.includes('string lkName = DrawLookName(DrawLookFromSlot(row));') ||
        !pk3.includes('if(lkName != "" && DrawStripPenLook(k)) return lkName;'))
      brokenU3.push('a look caption lost its gate - a row the writer accepts reads unnamed (P-UNIFY-3)');
    if (!tb3.includes('if(st > (int)STYLE_DASHDOTDOT && FibPenServesName(name))'))
      brokenU3.push('the STYLE writer accepts a look on a kind the pen refuses - an invisible tag again (P-UNIFY-3)');
    if (!tb3.includes('bool penKind = FibPenServesName(name) || PenStackServes(name);'))
      brokenU3.push('the style fold is kind-guarded again - a dash pick on a served kind erases the thickness one write before the pen reads it (P-UNIFY-3)');
    if (!tb3.includes('if(FibPenServesName(name)) return false;'))
      brokenU3.push('the pair coercion refuses the wrong family - a served kind\'s memory dies, or a pitchfork\'s dash never folds (P-UNIFY-3)');
    if (!tb3.includes('if(!FibPenServesName(nm)) continue;'))
      brokenU3.push('the drag arm scans a kind test again (P-UNIFY-3)');
    if (pairRe.test(fp3 + tb3 + pk3))
      brokenU3.push('a two-kind gate is back - the fibo pair spelled where the served set belongs (P-UNIFY-3)');
    //--- the geometry is the kind's own - one owner, asked at every seat
    if (!/double DrawLevelPriceAt\(/.test(ta3))
      brokenU3.push('the geometry owner is gone (P-UNIFY-3)');
    if (!/if\(k == DK_FIBOFAN\)/.test(ta3) || !/if\(k == DK_FIBOCHAN\)/.test(ta3) || !/if\(k == DK_EXPANSION\)/.test(ta3))
      brokenU3.push('a kind left the geometry owner - its levels would wear another kind\'s law (P-UNIFY-3)');
    if (!/return pb \+ \(pa - pb\) \* v;/.test(ta3))
      brokenU3.push('the geometry owner lost the terminal\'s horizontal law - 0 % at the second anchor (P-UNIFY-3)');
    if (!fp3.includes('lvA = DrawLevelPriceAt(k, v, ta, p1, tb, p2, t3, p3, ts0);') ||
        !fp3.includes('lvB = DrawLevelPriceAt(k, v, ta, p1, tb, p2, t3, p3, ts1);'))
      brokenU3.push('the sync rows no longer ask the kind\'s own geometry - a served kind\'s children sit on lines it never draws (P-UNIFY-3)');
    if (!fp3.includes('lpA = DrawLevelPriceAt(k, vv4, ta, p1, tb, p2, t3, p3, tc);') ||
        !fp3.includes('lpB = DrawLevelPriceAt(k, vv4, ta, p1, tb, p2, t3, p3, tb);'))
      brokenU3.push('the caps no longer follow the level\'s slope (P-UNIFY-3)');
    if (!fp3.includes('hpA = lva[l5] + 2.0 * px;') || !fp3.includes('hpB = lvb[l5] + 2.0 * px;'))
      brokenU3.push('the wash halo no longer rides the level\'s own ends (P-UNIFY-3)');
    if (!th3.includes('double la = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t1);') ||
        !th3.includes('double lb = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t2);'))
      brokenU3.push('the press naming measures another law again - a served kind\'s real lines cannot be named (P-UNIFY-3)');
    if (!tb3.includes('double la = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t1);'))
      brokenU3.push('the drag arm\'s full hit measures another law again (P-UNIFY-3)');
    if (!/FibPenNetWrite\(fibo, \(long\)ta, \(long\)tb, three \? \(long\)t3 : 0,/.test(fp3))
      brokenU3.push('the net forgot the third anchor - a moved channel keeps a stale pen (P-UNIFY-3)');
    if (brokenU3.length) {
      failures.push('P-UNIFY-3: ' + brokenU3.join('; ') + ' (Biotak/FibPen.mqh + Toolbar_A/B/Hit + DrawStrip_Pick.mqh)');
    } else {
      console.log('[PASS] P-UNIFY-3 the pen serves the four kinds whose level geometry it states: one owner of the served set (FibPenServesType/Name - pen, preview, heal, fold, coercion, STYLE writer, picker rows) and one owner of the geometry (DrawLevelPriceAt - sync, caps, wash, both hit tests)');
    }
  }

  // -- 69. P-UNIFY-4b (2026-10-19) -- THE KIND'S MEMORY KEEPS THE LOOK'S SLOT --
  // MEASURED: the STYLE writer translated 5/6/7 into the look's NATIVE half and saved
  // THAT in `s_dkStyle[k]`, so the next drawing of the kind was born with the right
  // dash and no `[LKn]` tag - Caps and Wash (native SOLID) came back a plain solid
  // line, Neon came back a dash with no thickness. The memory is a SLOT now: the
  // writer saves what the hand picked, and birth translates it ONCE (tag first,
  // native second), the same two writes the pick itself makes.
  {
    const brokenU4 = [];
    const srcU4 = (p) => linesOf(path.join(ROOT, p)) ? fs.readFileSync(path.join(ROOT, p), 'utf8') : '';
    const tb4 = srcU4('Biotak/Toolbar_B.mqh');
    const tpl4 = srcU4('Biotak/Toolbar_Tpl.mqh');
    if (!/int memSt = \(lk > 0 \? DrawLookToSlot\(lk\) : st\);/.test(tb4) ||
        !/if\(!DrawIsHRay\(name\) && !DrawIsPathSeg\(name\)\) s_dkStyle\[k\] = memSt;/.test(tb4))
      brokenU4.push('the writer saves the native half again - the next drawing of the kind loses Neon/Caps/Wash (P-UNIFY-4b)');
    if (!/int memSt = s_dkStyle\[k\];[\s\S]{0,160}?int mlk = \(memSt > \(int\)STYLE_DASHDOTDOT \? DrawLookFromSlot\(memSt\) : 0\);/.test(tb4) ||
        !/if\(mlk > 0 && FibPenServesName\(name\)\) \{ FibPenLookSet\(name, mlk\); FibPenSync\(name, false\); \}/.test(tb4))
      brokenU4.push('birth never re-applies the tag - a remembered look dies on the first new drawing (P-UNIFY-4b)');
    if (!/int native = \(mlk > 0 \? FibPenLookNative\(mlk\) : memSt\);/.test(tb4) ||
        !/ObjectSetInteger\(0, name, OBJPROP_STYLE, native\);/.test(tb4) ||
        !/if\(DrawKindHasLevels\(k\)\) DrawLevelsSetStyle\(name, native\);/.test(tb4))
      brokenU4.push('birth writes the slot itself to the terminal - OBJPROP_STYLE and a level set take 0..4, not 5..7 (P-UNIFY-4b)');
    if (!/\(s_dkStyle\[k\] & 0x7\) << 27/.test(tpl4) || !/s_dkStyle\[k\] = \(int\)\(\(a >> 27\) & 0x7\);/.test(tpl4))
      brokenU4.push('the last-look word lost its three style bits - a look cannot survive an attach (P-UNIFY-4b)');
    if (brokenU4.length) {
      failures.push('P-UNIFY-4b: ' + brokenU4.join('; ') + ' (Biotak/Toolbar_B.mqh + Toolbar_Tpl.mqh)');
    } else {
      console.log('[PASS] P-UNIFY-4b the kind memory keeps the look: the writer saves the SLOT, birth translates it once (tag first, native second) and the last-look word still carries all three bits');
    }
  }

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
