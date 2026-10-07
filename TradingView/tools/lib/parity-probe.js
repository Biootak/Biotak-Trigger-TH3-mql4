// Generates the parity probe: a Pine script that calls the REAL src/30_math.pine
// functions once per bar, one bar per fixture row, and plots every intermediate so
// the harness can compare numbers instead of trusting a rewrite of the same sum.
//
// The probe is generated, never committed, and never edited: the Pine it runs is
// imported from the module chain, so a change to src/30_math.pine is exercised by
// the very next parity run - and a JS twin of the formula is impossible by
// construction, because there is no JS formula here to drift.

import { SRC, resolveChain, render } from './pine-build.js';

// `uni` and `derived` are INPUTS, deliberately not re-derived in the probe: the seed
// chain and the lock take a step as an argument and must be fed the case's own number,
// or the check measures the port's step twice and calls it a comparison.
const FLOAT_FIELDS = ['ratio', 'priorLeg', 'lastLeg', 'legCD', 'legAB', 'mother', 'rung', 'anchor', 'ladderStep', 'price1', 'pct', 'freqPct', 'lockBase', 'lockOk', 'uni', 'derived', 'retR', 'retRef', 'retTh', 'kDist', 'kRef', 'chartRung', 'pip'];
const INT_FIELDS = ['dir', 'tfMin', 'cdBars', 'ownerUp'];

// A Pine float literal needs a decimal point, or array.from() infers array<int>
// for a row whose values happen to be whole numbers and the probe stops type-checking.
const floatLit = (v) => {
  const s = String(Number(v));
  return /[.eE]/.test(s) ? s : `${s}.0`;
};
const intLit = (v) => String(Math.trunc(Number(v)));

const arrayLit = (values, kind) => `array.from(${values.map(kind === 'int' ? intLit : floatLit).join(', ')})`;

export const PLOTS = [
  'Ratio', 'RatioInput', 'K', 'KClosed', 'StepMother', 'StepPattern', 'Step', 'StepClosed',
  'R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7',
  'RungPct', 'RungFromClose', 'SeedStep', 'Locked', 'FreqPct', 'PipSize',
  'ChartTf', 'RungPctTF', 'OwnerTF', 'RetStep', 'RetQ', 'RetIdx', 'KpOk', 'KpK', 'KpStep', 'ShiftLocked', 'ShiftApplied',
];

// rows: objects carrying the FLOAT_FIELDS plus `dir` (int).
export function buildProbe(rows, { transform = null } = {}) {
  // resolveChain, not resolveEntry: the probe is assembled FROM a module, so the
  // module's own body has to be in the set. resolveEntry drops its argument.
  const { order: modules } = resolveChain('30_math.pine');

  const table = [];
  for (const field of FLOAT_FIELDS) {
    table.push(`th3Fx_${field} = ${arrayLit(rows.map((r) => r[field] ?? 0), 'float')}`);
  }
  for (const field of INT_FIELDS) {
    table.push(`th3Fx_${field} = ${arrayLit(rows.map((r) => r[field] ?? 0), 'int')}`);
  }
  table.push(`TH3FX_N = ${rows.length}`);

  const body = [
    '',
    '// ' + '-'.repeat(74),
    `// the fixture table - ${rows.length} row(s), one per bar. GENERATED, never edited.`,
    '// ' + '-'.repeat(74),
    ...table,
    '',
    'th3FxI = bar_index',
    'th3FxIn = th3FxI < TH3FX_N',
    '',
    'th3FxPick(array<float> a) =>',
    '    th3FxIn ? array.get(a, th3FxI) : 0.0',
    '',
    'th3FxPickI(array<int> a) =>',
    '    th3FxIn ? array.get(a, th3FxI) : 0',
    '',
    'th3FxRatioV = th3FxPick(th3Fx_ratio)',
    'th3FxRatioOut = th3Ratio(th3FxPick(th3Fx_priorLeg), th3FxPick(th3Fx_lastLeg))',
    'th3FxLegCDV = th3FxPick(th3Fx_legCD)',
    'th3FxMotherV = th3FxPick(th3Fx_mother)',
    'th3FxRungV = th3FxPick(th3Fx_rung)',
    '',
    'th3FxKOut = th3K(th3FxRatioV)',
    'th3FxClKOut = th3KClosed(th3FxRatioV)',
    'th3FxStepMotherOut = th3StepMother(th3FxMotherV, th3FxRungV)',
    'th3FxStepPatternOut = th3StepPattern(th3FxLegCDV, th3FxRatioV)',
    'th3FxStepOut = th3MasterStep(th3FxLegCDV, th3FxRatioV, th3FxMotherV, th3FxRungV)',
    'th3FxClStepOut = th3ClosedStep(th3FxLegCDV, th3FxRatioV)',
    '',
    'th3FxAnchorV = th3FxPick(th3Fx_anchor)',
    'th3FxLadderV = th3FxPick(th3Fx_ladderStep)',
    'th3FxDirV = th3FxPickI(th3Fx_dir)',
    '',
    '// the rung / seed / lock tail: the parts a fixture oracle can also gate',
    'th3FxLegABV = th3FxPick(th3Fx_legAB)',
    'th3FxPrice1V = th3FxPick(th3Fx_price1)',
    'th3FxPctV = th3FxPick(th3Fx_pct)',
    'th3FxFreqV = th3FxPick(th3Fx_freqPct)',
    'th3FxLockBaseV = th3FxPick(th3Fx_lockBase)',
    'th3FxLockOkV = th3FxPick(th3Fx_lockOk)',
    'th3FxUniV = th3FxPick(th3Fx_uni)',
    'th3FxDerivedV = th3FxPick(th3Fx_derived)',
    'th3FxRungFromCloseOut = th3RungFromClose(th3FxPrice1V, th3FxPctV)',
    '// the seed chain is fed the VALIDATED frequency, exactly as MQL4 passes GetCurrentTH3Frequency()',
    'th3FxFreqOut = th3FrequencyPct(th3FxFreqV)',
    'th3FxSeedOut = th3SeedStep(th3FxUniV, th3FxRungV, th3FxLegCDV, th3FxLegABV, th3FxFreqOut)',
    '[th3FxLockedOut, th3FxLockHowOut] = th3LockVerdict(th3FxDerivedV, th3FxLockBaseV, th3FxLockOkV)',
    'th3FxPctChartOut = th3RungPct()',
    '',
    'th3FxTfMinV = th3FxPickI(th3Fx_tfMin)',
    'th3FxCdBarsV = th3FxPickI(th3Fx_cdBars)',
    'th3FxOwnerUpV = th3FxPickI(th3Fx_ownerUp) != 0',
    'th3FxRetRV = th3FxPick(th3Fx_retR)',
    'th3FxRetRefV = th3FxPick(th3Fx_retRef)',
    'th3FxRetThV = th3FxPick(th3Fx_retTh)',
    'th3FxKDistV = th3FxPick(th3Fx_kDist)',
    'th3FxKRefV = th3FxPick(th3Fx_kRef)',
    'th3FxChartRungV = th3FxPick(th3Fx_chartRung)',
    'th3FxPipV = th3FxPick(th3Fx_pip)',
    '[th3FxRetStepOut, th3FxRetQOut, th3FxRetIdxOut] = th3RetraceBestStep(th3FxRetRV, th3FxRetRefV, th3FxRetThV)',
    '[th3FxKpOkOut, th3FxKpKOut, th3FxKpStepOut] = th3HitKPick(th3FxKDistV, th3FxKRefV)',
    '[th3FxShiftLockedOut, th3FxShiftHowOut] = th3LockShift(true, "x", th3FxDerivedV, th3FxLockBaseV, th3FxOwnerUpV, th3FxChartRungV, th3FxPipV, "H1")',
    '',
    'plot(th3FxRatioOut, "Ratio")',
    'plot(th3FxRatioV, "RatioInput")',
    'plot(th3FxKOut, "K")',
    'plot(th3FxClKOut, "KClosed")',
    'plot(th3FxStepMotherOut, "StepMother")',
    'plot(th3FxStepPatternOut, "StepPattern")',
    'plot(th3FxStepOut, "Step")',
    'plot(th3FxClStepOut, "StepClosed")',
    ...Array.from({ length: 7 }, (_, i) => `plot(th3RungPrice(th3FxAnchorV, th3FxLadderV, th3FxDirV, ${i + 1}), "R${i + 1}")`),
    'plot(th3FxPctChartOut, "RungPct")',
    'plot(th3FxRungFromCloseOut, "RungFromClose")',
    'plot(th3FxSeedOut, "SeedStep")',
    'plot(th3FxLockedOut ? 1.0 : 0.0, "Locked")',
    'plot(th3FxFreqOut, "FreqPct")',
    'plot(th3PipSize(), "PipSize")',
    'plot(th3ChartTfMin(), "ChartTf")',
    'plot(th3RungPctForTFMin(th3FxTfMinV), "RungPctTF")',
    'plot(th3OwnerTFMinutes(th3FxTfMinV, th3FxCdBarsV), "OwnerTF")',
    'plot(th3FxRetStepOut, "RetStep")',
    'plot(th3FxRetQOut, "RetQ")',
    'plot(th3FxRetIdxOut, "RetIdx")',
    'plot(th3FxKpOkOut ? 1.0 : 0.0, "KpOk")',
    'plot(th3FxKpKOut, "KpK")',
    'plot(th3FxKpStepOut, "KpStep")',
    'plot(th3FxShiftLockedOut ? 1.0 : 0.0, "ShiftLocked")',
    'plot(str.contains(th3FxShiftHowOut, "SHIFT") ? 1.0 : 0.0, "ShiftApplied")',
  ];

  const entry = {
    file: 'generated/parity-probe.pine',
    id: 'generated.parity',
    owner: 'generated by tools/lib/parity-probe.js - it holds no rule of its own',
    declare: ['//@version=6', 'indicator("Biotak TH3 parity probe", overlay=false)'],
    body: [],
    includes: [],
    header: [],
  };

  const built = render({ entry, modules, extraBody: body });
  if (transform) built.text = transform(built.text);
  return { ...built, modules: modules.map((m) => m.file), rows: rows.length, source: `${SRC}/30_math.pine` };
}
