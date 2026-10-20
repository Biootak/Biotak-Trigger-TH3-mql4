// EURUSD: which ATR family reproduces HIS composite?
//
// His Eng is recoverable from the card legs (Pricicle/5, Classic/12, Trigger*3/8),
// and his Eng = ATR/4.266666, so his ATR = Eng * 4.266666.
// Our shipped composite is an SMA-of-TR blend; ATR_A.mqh:23-26 says a Wilder
// reweight was tried and retired because "the gap was Wilder-vs-SMA family".
// This measures both against his numbers from TODAY's cards (21:30).
//
// Run: node tools/research/atr_family_fit.js
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PIP = 0.0001;
const DIV = 4.266666;

// his cards, EURUSD, 19-Oct-2026 21:30  ->  ATR = Eng*4.266666
// Eng solved from Classic/12 (the widest leg = least rounding error)
const HIS = {
  M5:  { eng: 9 / 12,  atr: (9 / 12) * DIV },    // Classic 9
  M15: { eng: 19 / 12, atr: (19 / 12) * DIV },   // Classic 19
  H1:  { eng: 45 / 12, atr: (45 / 12) * DIV },   // Classic 45
  H4:  { eng: 87 / 12, atr: (87 / 12) * DIV },   // Classic 87
};
const FILE = { M5: 'EURUSD5.hst', M15: 'EURUSD15.hst', H1: 'EURUSD60.hst', H4: 'EURUSD240.hst' };
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];

function parseHST(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const bars = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    bars.push({
      high: buf.readDoubleLE(o + 16),
      low: buf.readDoubleLE(o + 24),
      close: buf.readDoubleLE(o + 32),
    });
  }
  return bars;
}

// bars[0] = oldest, bars[n-1] = forming bar (shift 0)
function trueRanges(bars) {
  const tr = new Array(bars.length).fill(0);
  for (let i = 1; i < bars.length; i++) {
    const h = bars[i].high, l = bars[i].low, c = bars[i - 1].close;
    tr[i] = Math.max(h - l, Math.abs(h - c), Math.abs(l - c));
  }
  return tr;
}

// our leg: plain mean of TR over `period` bars ending at shift 1, with the
// newest-bar quirk (bar 1's own close is its "previous" close) — mirrors
// tests/Biotak_TradePlan_Golden_Test.mq4 SmaLeg()
function smaLeg(bars, tr, period) {
  const n = bars.length;
  let sum = 0;
  for (let i = 0; i < period; i++) {
    const idx = n - 2 - i;              // shift 1 + i
    if (idx < 1) return null;
    const h = bars[idx].high, l = bars[idx].low;
    const cPrev = (i === 0) ? bars[idx].close : bars[idx - 1].close;
    sum += Math.max(h - l, Math.abs(h - cPrev), Math.abs(l - cPrev));
  }
  return sum / period;
}

// Wilder ATR at shift 1: seed = SMA of the oldest `period` TRs, then smooth
function wilderLeg(tr, period) {
  const n = tr.length;
  if (n < period + 3) return null;
  let atr = 0;
  for (let i = 1; i <= period; i++) atr += tr[i];
  atr /= period;
  for (let i = period + 1; i <= n - 2; i++) atr = (atr * (period - 1) + tr[i]) / period;
  return atr;
}

const composite = (legs) => {
  let s = 0, w = 0;
  legs.forEach((v, i) => { if (v !== null && v > 0) { s += v * WEIGHTS[i]; w += WEIGHTS[i]; } });
  return w ? s / w : 0;
};

console.log('EURUSD | his card 21:30  vs  the two families (pips)\n');
console.log('  TF   | his ATR | SMA (ours) | delta | Wilder | delta');
for (const tf of Object.keys(HIS)) {
  const bars = parseHST(FILE[tf]);
  const tr = trueRanges(bars);
  const sma = composite(PERIODS.map((p) => smaLeg(bars, tr, p))) / PIP;
  const wil = composite(PERIODS.map((p) => wilderLeg(tr, p))) / PIP;
  const his = HIS[tf].atr;
  const d = (x) => (((x - his) / his) * 100).toFixed(0) + '%';
  console.log('  ' + tf.padEnd(4) + ' | ' + his.toFixed(2).padStart(7) + ' | ' +
    sma.toFixed(2).padStart(10) + ' | ' + d(sma).padStart(5) + ' | ' +
    wil.toFixed(2).padStart(6) + ' | ' + d(wil).padStart(5));
}

// --- does a shorter horizon fit? his H1/H4 read HIGH, his M5 reads LOW, so the
// --- window length is the only knob that can move them in opposite directions.
const VARIANTS = [
  { name: 'ours 5..264 w=1/1/2/3/5/8', periods: PERIODS, weights: WEIGHTS },
  { name: '5..132   w=1/1/2/3/5',      periods: PERIODS.slice(0, 5), weights: WEIGHTS.slice(0, 5) },
  { name: '5..66    w=1/1/2/3',        periods: PERIODS.slice(0, 4), weights: WEIGHTS.slice(0, 4) },
  { name: '5..264   flat mean',        periods: PERIODS, weights: [1, 1, 1, 1, 1, 1] },
  { name: '5..132   flat mean',        periods: PERIODS.slice(0, 5), weights: [1, 1, 1, 1, 1] },
  { name: '5..66    flat mean',        periods: PERIODS.slice(0, 4), weights: [1, 1, 1, 1] },
  { name: '10..264  w=1/2/3/5/8',      periods: PERIODS.slice(1), weights: WEIGHTS.slice(1) },
  { name: '5..21    w=1/1/2',          periods: PERIODS.slice(0, 3), weights: WEIGHTS.slice(0, 3) },
  { name: '5..10    w=1/1',            periods: PERIODS.slice(0, 2), weights: WEIGHTS.slice(0, 2) },
  { name: '10..66   w=1/2/3',          periods: PERIODS.slice(1, 4), weights: WEIGHTS.slice(1, 4) },
  { name: '21..66   w=2/3',            periods: PERIODS.slice(2, 4), weights: WEIGHTS.slice(2, 4) },
];

console.log('\nvariants (SMA of TR at shift 1), delta vs his ATR:');
console.log('  ' + 'variant'.padEnd(26) + ['M5', 'M15', 'H1', 'H4'].map((t) => t.padStart(7)).join('') + '   max|d|');
for (const v of VARIANTS) {
  const cells = [];
  let worst = 0;
  for (const tf of Object.keys(HIS)) {
    const bars = parseHST(FILE[tf]);
    const tr = trueRanges(bars);
    const legs = v.periods.map((p) => smaLeg(bars, tr, p));
    let s = 0, w = 0;
    legs.forEach((x, i) => { if (x !== null && x > 0) { s += x * v.weights[i]; w += v.weights[i]; } });
    const val = (s / w) / PIP;
    const dd = (val - HIS[tf].atr) / HIS[tf].atr * 100;
    if (Math.abs(dd) > worst) worst = Math.abs(dd);
    cells.push(((dd >= 0 ? '+' : '') + dd.toFixed(0) + '%').padStart(7));
  }
  console.log('  ' + v.name.padEnd(26) + cells.join('') + '   ' + worst.toFixed(0) + '%');
}
