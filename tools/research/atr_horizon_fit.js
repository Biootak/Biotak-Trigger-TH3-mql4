// Two-symbol ATR fit: XAUUSD + EURUSD, our composite vs HIS own ATR row.
//
// His row (the `ATR:` line) prints three numbers per TF. On both symbols the
// MIDDLE one is what our composite already reproduces on M1..D1, so it is the
// reference here. The three HIGH rungs are where we drift, and H4 is the rung
// the trade plan actually reads (structure TF for an H1 chart).
//
// Run: node tools/research/atr_horizon_fit.js
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];

const SYM = {
  XAUUSD: {
    pip: 0.1,
    file: (tf) => 'XAUUSD' + MIN[tf] + '.hst',
    his: { M1: 11, M5: 32, M15: 62, H1: 133, H4: 288, D1: 991, W1: 1925, MN: 3139 },
  },
  EURUSD: {
    pip: 0.0001,
    file: (tf) => 'EURUSD' + MIN[tf] + '.hst',
    his: { M1: 2, M5: 4, M15: 8, H1: 16, H4: 31, D1: 75, W1: 198, MN: 411 },
  },
};
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };

function parseHST(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const bars = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    bars.push({ high: buf.readDoubleLE(o + 16), low: buf.readDoubleLE(o + 24), close: buf.readDoubleLE(o + 32) });
  }
  return bars;
}
function trueRanges(bars) {
  const tr = new Array(bars.length).fill(0);
  for (let i = 1; i < bars.length; i++) {
    const h = bars[i].high, l = bars[i].low, c = bars[i - 1].close;
    tr[i] = Math.max(h - l, Math.abs(h - c), Math.abs(l - c));
  }
  return tr;
}
function smaLeg(bars, period) {
  const n = bars.length;
  let sum = 0;
  for (let i = 0; i < period; i++) {
    const idx = n - 2 - i;
    if (idx < 1) return null;
    const h = bars[idx].high, l = bars[idx].low;
    const cPrev = (i === 0) ? bars[idx].close : bars[idx - 1].close;
    sum += Math.max(h - l, Math.abs(h - cPrev), Math.abs(l - cPrev));
  }
  return sum / period;
}
function comp(bars, periods, weights) {
  let s = 0, w = 0;
  periods.forEach((p, i) => { const v = smaLeg(bars, p); if (v !== null && v > 0) { s += v * weights[i]; w += weights[i]; } });
  return w ? s / w : 0;
}

const VAR = [
  { name: '5..264 w=1/1/2/3/5/8 (ours)', p: PERIODS, w: WEIGHTS },
  { name: '5..132 w=1/1/2/3/5',          p: PERIODS.slice(0, 5), w: WEIGHTS.slice(0, 5) },
  { name: '5..66  w=1/1/2/3',            p: PERIODS.slice(0, 4), w: WEIGHTS.slice(0, 4) },
  { name: '5..66  flat',                 p: PERIODS.slice(0, 4), w: [1, 1, 1, 1] },
  { name: '21..264 w=2/3/5/8',           p: PERIODS.slice(2), w: WEIGHTS.slice(2) },
  { name: '66..264 w=3/5/8',             p: PERIODS.slice(3), w: WEIGHTS.slice(3) },
];

for (const sym of Object.keys(SYM)) {
  const cfg = SYM[sym];
  console.log('\n=== ' + sym + ' ===');
  console.log('  TF  | his | ' + VAR.map((v) => v.name.split(' ')[0].padStart(7)).join(' ') + '   | best');
  const tally = VAR.map(() => 0);
  for (const tf of Object.keys(cfg.his)) {
    let bars;
    try { bars = parseHST(cfg.file(tf)); } catch (e) { console.log('  ' + tf + ' no data'); continue; }
    const his = cfg.his[tf];
    const vals = VAR.map((v) => comp(bars, v.p, v.w) / cfg.pip);
    let bi = 0, bd = 1e9;
    vals.forEach((x, i) => { const d = Math.abs(x - his) / his; if (d < bd) { bd = d; bi = i; } tally[i]++; });
    console.log('  ' + tf.padEnd(4) + '| ' + String(his).padStart(4) + ' | ' +
      vals.map((x, i) => ((x >= his ? '+' : '') + ((x - his) / his * 100).toFixed(0) + '%').padStart(7)).join(' ') +
      '   | ' + VAR[bi].name.split(' ')[0] + ' ' + (bd * 100).toFixed(0) + '%');
  }
  console.log('  wins per variant: ' + tally.join(' / '));
}
