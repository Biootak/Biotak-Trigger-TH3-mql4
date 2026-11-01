'use strict';
// THE UI SCENARIO MATRIX — the list of questions every UI surface must answer,
// and the ONE function that answers each one for each surface.
//
// WHY THIS FILE EXISTS. The contract already says "Reattach · TF switch · terminal
// restart · template re-apply: every surface survives all four" (§4). It says it as
// PROSE, and prose is why P-UI-222 happened: the ring, the chip, the strip and the
// cards each learned to re-derive their place on a resize, and the two POPUPS that
// hang off them never did — the palette kept the x it was opened at, the gear panel
// kept the y its plate had. Both were invisible until a chart shrank under them, and
// both were found by reading the tree, not by a gate.
//
// The rule this file turns into a check: A SURFACE THAT IS NOT A ROW HERE IS NOT
// ALLOWED TO EXIST. `tools/ui_scenario_check.js` walks every .mqh that creates a UI
// control type and fails on a file no row claims — so the next surface is declared
// the day it is written, not the day it strands itself off-screen.
//
// WHAT A ROW OWNS. `answers[key]` names the function that answers that scenario, and
// `site` names the CALL that proves it is wired. The gate requires both: the
// function must exist, and the call must be in the file that runs on that event.
// A scenario answered `null` is OPEN — printed by the gate as a work item, never
// silently a pass (contract §6.13's "a stage that cannot see the symptom is a
// FINDING"). `na` is a deliberate "this scenario cannot happen to this surface".
//
// Adding a surface: add the row, name the answers, run the gate. Adding a scenario:
// add it to SCENARIOS, then answer it in every row or leave it OPEN on purpose.

const S = (fn, file, text, m5) => (m5 ? { fn, site: { file, text }, m5 } : { fn, site: { file, text } });
const NA = 'na';

// --- THE TWO TREES. MT4 is the split source (~150 modules); MT5 is the SAME code
// --- still in ~80 monoliths. `root` is relative to this repo, `dirs` are the module
// --- folders that platform's compiler sees, `entries` are its two products. The gate
// --- asks every scenario of BOTH, because a rule proved on one proves nothing about
// --- the other: MEASURED, the MT5 tree still carried both P-UI-222 defects after the
// --- MT4 fix shipped, and no gate had ever asked it.
const PLATFORMS = {
  mt4: {
    root: '.',
    dirs: ['Biotak'],
    entries: ['Biotak Trigger TH3.mq4', 'Biotak Trigger TH3 Lite.mq4'],
  },
  mt5: {
    root: '../Biotak-Trigger-TH3-mql5',
    dirs: ['Biotak', 'MT5Compat', 'Engine'],
    entries: ['Biotak Trigger TH3.mq5', 'Biotak Trigger TH3 Lite.mq5'],
  },
};

// --- the axes. One question each; the id is the name a report may cite.
const SCENARIOS = [
  { id: 'S01', key: 'attach',   q: 'a fresh attach builds it (or sweeps the last session first)' },
  { id: 'S02', key: 'reattach', q: 'a reload with nothing open leaves no orphan of it on the chart' },
  { id: 'S03', key: 'tfswitch', q: 'a timeframe switch / params change takes it down' },
  { id: 'S04', key: 'restart',  q: 'its place is a FRACTION of the window, never a stored pixel' },
  { id: 'S05', key: 'template', q: 'a template re-apply that ate its objects heals on the next pass' },
  { id: 'S06', key: 'resize',   q: 'a window resize re-derives its place (it never strands itself)' },
  { id: 'S07', key: 'dpi',      q: 'a DPI change rebuilds it from the new metrics' },
  { id: 'S08', key: 'mute',     q: 'the F mute closes it or masks it — never an invisible control' },
  { id: 'S09', key: 'delobj',   q: 'a user delete of what it serves takes it down in that event' },
  { id: 'S10', key: 'parent',   q: 'a popup dies with the surface that opened it' },
  { id: 'S11', key: 'hitpaint', q: 'its hit test reads the SAME seat the paint writes' },
  { id: 'S12', key: 'second',   q: 'a second unit on one chart refuses to load (P-ARCH-03)' },
  { id: 'S13', key: 'escape',   q: 'a window too small to hold it — is there an exit that does not need its own buttons' },
];

const SURFACES = [
  {
    id: 'ring',
    title: 'the orb, the circular menu, the pinned chip',
    files: ['BiotakMenu_A.mqh', 'BiotakMenu_B.mqh', 'BiotakMenu_C.mqh', 'BiotakMenu_D.mqh',
            'BiotakMenu_Ring.mqh', 'BiotakMenu_RingCensus.mqh', 'BiotakHomes.mqh'],
    close: 'DeleteMenu',
    filesM5: ['BiotakMenu.mqh', 'BiotakMenu_Ring.mqh', 'BiotakMenu_RingCensus.mqh', 'BiotakHomes.mqh'],
    answers: {
      S01: S('CreateMenu', 'Biotak/BiotakMenu_C.mqh', 'void CreateMenu()'),
      S02: S('BiotakMenuGhostSweep', 'Biotak/BiotakMenu_A.mqh', 'BiotakMenuGhostSweep();'),
      S03: S('DeleteMenu', 'Biotak Trigger TH3.mq4', 'DeleteMenu();'),
      S04: S('GVHomeSaveFrac', 'Biotak/BiotakHomes.mqh', 'GVHomeSaveFrac('),
      S05: S('CreateMenu', 'Biotak/BiotakPanels_Route.mqh', 'CreateMenu();'),
      S06: S('CircHomesRefresh', 'Biotak/BiotakPanels_Life.mqh', 'CircHomesRefresh();'),
      S07: S('UIRebuildForMetrics', 'Biotak/BiotakPanels_Life.mqh', 'UIRebuildForMetrics()'),
      S08: NA,
      S09: NA,
      S10: NA,
      S11: S(null, 'Biotak/BiotakPanels_Life.mqh', 'PnlClickFallback(cx, cy)'),
      S12: S('OnInitHandler', 'Biotak/EventHandlers_Init.mqh', 'P-ARCH-03'),
      S13: NA,
    },
  },
  {
    id: 'cards',
    title: 'the 14 settings cards (one at a time)',
    files: ['BiotakPanels.mqh', 'BiotakPanels_Apply.mqh', 'BiotakPanels_Build.mqh',
            'BiotakPanels_DynDef.mqh', 'BiotakPanels_Hit.mqh', 'BiotakPanels_Route.mqh',
            'BiotakPanels_Rows.mqh', 'BiotakPanels_State.mqh'],
    close: 'PnlCloseAll',
    filesM5: ['BiotakPanels.mqh'],
    answers: {
      S01: S('PnlOpen', 'Biotak/BiotakPanels_Hit.mqh', 'void PnlOpen(const int item)'),
      S02: S('PnlCloseAll', 'Biotak Trigger TH3.mq4', 'PnlCloseAll();'),
      S03: S('PnlCloseAll', 'Biotak Trigger TH3.mq4', 'PnlCloseAll();'),
      S04: S('PnlFracKey', 'Biotak/BiotakKit.mqh', 'PnlFracKey(i)'),
      S05: S('PnlOpen', 'Biotak/BiotakPanels_Hit.mqh', 'void PnlOpen(const int item)'),
      S06: S('PnlClampOpenPanel', 'Biotak/BiotakPanels_Life.mqh', 'if(PnlClampOpenPanel())'),
      S07: S('PnlRebuildKeepSpot', 'Biotak/BiotakPanels_Route.mqh', 'PnlRebuildKeepSpot(g_PnlOpen)'),
      S08: NA,
      S09: S('PnlCloseAll', 'Biotak Trigger TH3.mq4', 'PnlCloseAll();'),
      S10: S('PalClose', 'Biotak/BiotakPanels_Hit.mqh', 'PalClose();'),
      S11: S('PnlSeatRevert', 'Biotak/BiotakPanels_Life.mqh', 'PnlSeatRevert(sparam);'),
      S12: S('OnInitHandler', 'Biotak/EventHandlers_Init.mqh', 'P-ARCH-03'),
      S13: S('PnlCloseAll', 'Biotak/BiotakPanels_Life.mqh', 'if(g_PnlOpen >= 0) { PnlCloseAll(); return; }'),
    },
  },
  {
    id: 'palette',
    title: 'the colour popup (a POPUP of a card or of the strip)',
    files: ['BiotakPanels_PalA.mqh', 'BiotakPanels_PalB.mqh', 'BiotakPanels_PalSpec.mqh',
            'BiotakPanels_PalDiag.mqh'],
    close: 'PalClose',
    popup: true,
    filesM5: ['BiotakPanels.mqh'],
    answers: {
      S01: S('PalOpenKind', 'Biotak/BiotakPanels_PalA.mqh', 'void PalOpenKind('),
      S02: S('PalClose', 'Biotak Trigger TH3.mq4', 'PnlCloseAll();'),
      S03: S('PalClose', 'Biotak/BiotakPanels_Hit.mqh', 'PalClose();'),
      S04: S('PalComputePos', 'Biotak/BiotakPanels_PalA.mqh', 's_palManual'),
      S05: S('PalDraw', 'Biotak/BiotakPanels_PalB.mqh', 'ObjectsDeleteAll(0, g_UI.btnPrefix+"Pal_"'),
      S06: S('PalReclampOpen', 'Biotak/BiotakPanels_Life.mqh', 'if(PalReclampOpen())'),
      S07: S('PalOpenKind', 'Biotak/BiotakPanels_Route.mqh', 'PalOpenKind(g_PalAnchorItem, g_PalKind)'),
      S08: NA,
      S09: S('PalClose', 'Biotak Trigger TH3.mq4', 'if(!DrawStripPalParentLive()'),
      S10: S('PalClose', 'Biotak Trigger TH3.mq4', 'if(!DrawStripPalParentLive()'),
      S11: S('PalHoverCellAt', 'Biotak/BiotakPanels_PalB.mqh', 's_palRegionN'),
      S12: NA,
      S13: S('PalHandleKey', 'Biotak/BiotakPanels_Life.mqh', 'if(g_PalOpen) { PalHandleKey(PNL_KEY_ESC); return; }'),
    },
  },
  {
    id: 'strip',
    title: 'the quick strip that serves one drawing',
    files: ['DrawStrip.mqh', 'DrawStrip_Base.mqh', 'DrawStrip_Head.mqh', 'DrawStrip_Paint.mqh',
            'DrawStrip_Pick.mqh', 'DrawStrip_Router.mqh', 'DrawStrip_Skin.mqh', 'DrawStrip_Tap.mqh'],
    close: 'DrawStripClose',
    filesM5: ['DrawStrip.mqh'],
    answers: {
      S01: S('DrawStripSweepStale', 'Biotak Trigger TH3.mq4', 'DrawStripSweepStale();'),
      S02: S('DrawStripSweepStale', 'Biotak Trigger TH3.mq4', 'DrawStripSweepStale();'),
      S03: S('DrawStripClose', 'Biotak Trigger TH3.mq4', 'DrawStripClose();'),
      S04: S('GVHomeSaveFracHand', 'Biotak/DrawStrip_Paint.mqh', 'GVHomeSaveFracHand("STRIP"'),
      S05: S('DrawStripClose', 'Biotak/DrawStrip_Paint.mqh', 'paint found no object'),
      S06: S('DrawStripHomeClamp', 'Biotak/DrawStrip_Router.mqh', 'DrawStripHomeClamp();'),
      S07: S('UIRebuildForMetrics', 'Biotak/BiotakPanels_Life.mqh', 'UIRebuildForMetrics()'),
      S08: S('DrawStripClose', 'Biotak/DrawStrip_Paint.mqh', 'IsIndicatorHidden()) { DrawStripDiagEmit',
             { file: 'Biotak/DrawStrip.mqh', text: 'if(IsIndicatorHidden()) { Print("[drawstrip] close: indicator hidden (F)' }),
      S09: S('DrawStripClose', 'Biotak/DrawStrip_Router.mqh', 'OBJECT_DELETE of'),
      S10: S('DrawStripGearClose', 'Biotak/DrawStrip_GearB.mqh', 'DrawStripGearClose();'),
      S11: S('DrawStripPointInside', 'Biotak/DrawStrip_Base.mqh', 'bool DrawStripPointInside('),
      S12: S('OnInitHandler', 'Biotak/EventHandlers_Init.mqh', 'P-ARCH-03'),
      S13: S('DrawStripClose', 'Biotak/DrawStrip_Router.mqh', 'close: Esc key'),
    },
  },
  {
    id: 'gear',
    title: 'the Box Settings panel (a POPUP of the strip)',
    files: ['DrawStrip_GearA.mqh', 'DrawStrip_GearB.mqh'],
    close: 'DrawStripGearClose',
    popup: true,
    filesM5: ['DrawStrip.mqh'],
    answers: {
      S01: S('DrawStripGearPaint', 'Biotak/DrawStrip_Paint.mqh', 'DrawStripGearPaint();'),
      S02: S('DrawStripGearObjectsPurge', 'Biotak/DrawStrip_GearB.mqh', 'DrawStripGearObjectsPurge();'),
      S03: S('DrawStripGearClose', 'Biotak/DrawStrip_GearB.mqh', 'DrawStripGearClose();'),
      S04: S('DrawStripGearRestoreTab', 'Biotak/BiotakPanels_Life.mqh', 'DrawStripGearRestoreTab(g, col)'),
      S05: S('DrawStripGearPaint', 'Biotak/DrawStrip_Paint.mqh', 'DrawStripGearPaint();'),
      S06: S('DrawStripPlaceGear', 'Biotak/DrawStrip_Paint.mqh', 'const int gx0 = s_dsGEX, gy0 = s_dsGEY;'),
      S07: S('DrawStripGearLayout', 'Biotak/DrawStrip_GearA.mqh', 's_dsGearH = DrawStripGearLayout(0)'),
      S08: S('DrawStripGearClose', 'Biotak/DrawStrip_GearB.mqh', 'void DrawStripGearClose()'),
      S09: S('DrawStripGearClose', 'Biotak/DrawStrip_GearB.mqh', 'void DrawStripClose()'),
      S10: S('DrawStripGearClose', 'Biotak/DrawStrip_GearB.mqh', 'DrawStripGearClose();'),
      S11: S('DrawStripGearRowTap', 'Biotak/DrawStrip_Router.mqh', 'DrawStripGearRowTap(gr)'),
      S12: NA,
      S13: S('DrawStripGearClose', 'Biotak/DrawStrip_Router.mqh', 'if(s_dsGear != 0)'),
    },
  },
  {
    id: 'knot',
    title: 'the BaseKnot box, its badges, its note and plan cards',
    files: ['BaseKnot_Base.mqh', 'BaseKnot_Drag.mqh', 'BaseKnot_Measure.mqh', 'BaseKnot_Note.mqh',
            'BaseKnot_Plan.mqh', 'BaseKnot_Nodes.mqh', 'BaseKnot_Shot.mqh', 'BaseKnot_Ability.mqh',
            'BaseKnot_Direction.mqh', 'BaseKnot_Owner.mqh'],
    close: 'BaseKnotOnDeinit',
    filesM5: ['BaseKnotTool.mqh', 'BaseKnot_Base.mqh', 'BaseKnot_Drag.mqh', 'BaseKnot_Measure.mqh',
                'BaseKnot_Note.mqh', 'BaseKnot_Plan.mqh', 'BaseKnot_Nodes.mqh', 'BaseKnot_Shot.mqh',
                'BaseKnot_Ability.mqh', 'BaseKnot_Direction.mqh', 'BaseKnot_Owner.mqh'],
    answers: {
      S01: S('BaseKnotLazyInit', 'Biotak/BaseKnot_Drag.mqh', 'BaseKnotLazyInit();'),
      S02: S('BaseKnotOnDeinit', 'Biotak/EventHandlers_Deinit.mqh', 'BaseKnotOnDeinit(reason)'),
      S03: S('BaseKnotOnDeinit', 'Biotak/EventHandlers_Deinit.mqh', 'BaseKnotOnDeinit(reason)'),
      S04: S('BaseKnotNoteCornerRefresh', 'Biotak/BaseKnot_Drag.mqh', 'BaseKnotNoteCornerRefresh();'),
      S05: S('BaseKnotSyncBadges', 'Biotak/BaseKnot_Drag.mqh', 'void BaseKnotSyncBadges()'),
      S06: S('BaseKnotSyncBadges', 'Biotak/BaseKnot_Drag.mqh', 'if(id == CHARTEVENT_CHART_CHANGE)'),
      S07: S('BaseKnotSyncBadges', 'Biotak/BaseKnot_Drag.mqh', 'void BaseKnotSyncBadges()'),
      S08: S('BaseKnotOnDeinit', 'Biotak/EventHandlers_Deinit.mqh', 'BaseKnotOnDeinit(reason)'),
      S09: null,   // OPEN: a deleted box is the router's cascade; the knot has no delete door of its own
      S10: NA,
      S11: S('BaseKnotBoxAtPx', 'Biotak/BaseKnot_Drag.mqh', 'BaseKnotBoxAtPx('),
      S12: NA,
      S13: S('BaseKnotSessionActive', 'Biotak/BaseKnot_Drag.mqh', 'lparam == 27 && BaseKnotSessionActive()'),
    },
  },
  {
    id: 'htf',
    title: 'the HTF candle overlay and its card',
    files: ['HTFCandles.mqh', 'HTFCandles_Draw.mqh', 'HTFCandles_Geom.mqh', 'HTFCandles_Life.mqh'],
    close: 'DeleteHTFCandles',
    filesM5: ['HTFCandles.mqh'],
    answers: {
      S01: S('HTFEnsureDrawn', 'Biotak/HTFCandles_Draw.mqh', 'void HTFEnsureDrawn()'),
      S02: S('HTFEnsureDrawn', 'Biotak/BiotakKit.mqh', 'HTFEnsureDrawn();'),
      S03: S('HTFEnsureDrawn', 'Biotak/BiotakKit.mqh', 'HTFEnsureDrawn();'),
      S04: S('HTFCardCullRefresh', 'Biotak/HTFCandles_Draw.mqh', 'void HTFCardCullRefresh()'),
      S05: S('HTFEnsureDrawn', 'Biotak/BiotakPanels_Life.mqh', 'HTFEnsureDrawn();'),
      S06: S('HTFEnsureDrawn', 'Biotak/BiotakPanels_Life.mqh', 'if(g_UI.showHTF) HTFEnsureDrawn();'),
      S07: S('UIRebuildForMetrics', 'Biotak/BiotakPanels_Life.mqh', 'UIRebuildForMetrics()'),
      S08: S('HTFBoxMask', 'Biotak/HTFCandles_Draw.mqh', 'IsIndicatorHidden()'),
      S09: NA,
      S10: NA,
      S11: S('HTFCardCullRefresh', 'Biotak/HTFCandles_Draw.mqh', 'void HTFCardCullRefresh()'),
      S12: NA,
      S13: NA,
    },
  },
  {
    id: 'legmeasure',
    title: 'the leg-measure line, rings and its plate',
    files: ['TH3Tool_B.mqh', 'TH3Tool_C.mqh'],
    close: null,   // a chart-art family: swept by ObjectsDeleteAll(0, TH3_LEG_PREFIX) on REASON_REMOVE
    filesM5: ['TH3Tool.mqh'],
    answers: {
      S01: S('LegMeasureFollowAll', 'Biotak/TH3Tool_B.mqh', 'void LegMeasureFollowAll()'),
      S02: S(null, 'Biotak/EventHandlers_Deinit.mqh', 'ObjectsDeleteAll(0, "LM_prev_")'),
      S03: S(null, 'Biotak/EventHandlers_Deinit.mqh', 'ObjectsDeleteAll(0, "LM_prev_")'),
      S04: NA,
      S05: S('LegMeasureFollowAll', 'Biotak/EventHandlers_Router.mqh', 'LegMeasureFollowAll();'),
      S06: S('LegMeasureFollowAll', 'Biotak/EventHandlers_Router.mqh', 'LegMeasureFollowAll();'),
      S07: NA,
      S08: NA,
      S09: S('LegMeasureOnObjectDelete', 'Biotak/EventHandlers_Router.mqh', 'LegMeasureOnObjectDelete(sparam)'),
      S10: NA,
      S11: S('LegMeasureClickFinalize', 'Biotak/EventHandlers_Router.mqh', 'LegMeasureClickFinalize();'),
      S12: NA,
      S13: NA,
    },
  },
  {
    id: 'sessions',
    title: 'the session shading and its labels',
    files: ['Sessions_Draw.mqh', 'Sessions_Model.mqh', 'Sessions_Time.mqh'],
    close: null,   // a chart-art family: swept by the entry's prefix delete, not by a popup close
    filesM5: ['Sessions_Draw.mqh', 'Sessions_Model.mqh', 'Sessions_Time.mqh'],
    answers: {
      S01: S('SessPaintAll', 'Biotak/Sessions_Draw.mqh', 'bool SessPaintAll('),
      S02: S('SessSweepSurplus', 'Biotak/Sessions_Draw.mqh', 'int SessSweepSurplus()'),
      S03: S('SessWipe', 'Biotak/Sessions_Draw.mqh', 'void SessWipe()'),
      S04: NA,
      S05: S('SessPaintAll', 'Biotak/Sessions_Draw.mqh', 'bool SessPaintAll('),
      S06: S('SessPaintAll', 'Biotak/Sessions_Draw.mqh', 'bool SessPaintAll('),
      S07: NA,
      S08: S('SessFillVisible', 'Biotak/Sessions_Draw.mqh', 'bool SessFillVisible()'),
      S09: NA,
      S10: NA,
      S11: NA,
      S12: NA,
      S13: NA,
    },
  },
];

// --- THE WHITELIST, PER TREE. A file that creates a UI control type must belong to a
// --- row; `SHARED` is the only escape, so every entry is a hole in the gate by
// --- construction and has to earn its place. The gate therefore checks each key EXISTS
// --- and actually CREATES a control type (P-UI-223): a dead key is a free pass nobody
// --- is using, and a key for a file that paints no control is noise that makes the
// --- list look stronger than it is. The two trees do not share this list — MT5 keeps
// --- the router in a file MT4 has already split away, so each tree declares its own.
const SHARED = {
  mt4: {
    'GlobalVariables.mqh': "the handset handle raster (`HandsetHandleAtXY`) — the leg meter's plate, painted by the shared helper its surface calls",
  },
  mt5: {
    'GlobalVariables.mqh': "the handset handle raster (`HandsetHandleAtXY`) — the leg meter's plate, painted by the shared helper its surface calls",
    'EventHandlers.mqh': 'the event router — its control-type list is the MASK a hide-sweep walks (which object types to touch), not a painter',
    'RenderPlatform.mqh': 'the render-engine canvas — ONE bitmap label per chart (`BTRS_OBJ_<chart>_FG/BG/ZG`) that every surface draws into, so it has no open/close lifecycle of its own',
    'RenderBridge.mqh': 'the canvas teardown — it deletes the BTRS family and creates nothing',
  },
};

module.exports = { PLATFORMS, SCENARIOS, SURFACES, SHARED, NA };
