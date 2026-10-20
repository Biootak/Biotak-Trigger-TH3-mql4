// NZDUSD same-minute fit — the first sample where HIS row, HIS card and OUR
// card all come from the same symbol, the same timeframe and the same minute.
//
// His ATR row (fractional, so no integer rounding to hide behind):
//   M1 0.7  M5 2.0  M15 3.9  H1 7.8  H4 17.5  D1 47.9  W1 111.9  MN 259.6
// His H1 card: TRex 1.8  Trigger 4.9  Pricicle 9  Classic 22
//              TP 11 / 25 / 51 / 148
// Our H1 card: TRex 2    Trigger 5    Pricicle 10 Classic 24
//              TP 12 / 25 / 51 / 152
//
// Run: node tools/research/nz_fit.js
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const ORDER = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];
const PIP = 0.0001;

const HIS = { M1: 0.7, M5: 2.0, M15: 3.9, H1: 7.8, H4: 17.5, D1: 47.9, W1: 111.9, MN: 259.6 };

function parseHST(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    out[i] = { time: buf.readUInt32LE(o), high: buf.readDoubleLE(o + 16), low: buf.readDoubleLE(o + 24), close: buf.readDoubleLE(o + 32) };
  }
  return out;
}

function smaLeg(bars, anchor, period) {
  let sum = 0;
  for (let i = 0; i < period; i++) {
    const j = anchor - i;
    if (j < 1) return null;
    const h = bars[j].high, l = bars[j].low;
    const cPrev = (i === 0) ? bars[j].close : bars[j - 1].close;
    sum += Math.max(h - l, Math.abs(h - cPrev), Math.abs(l - cPrev));
  }
  return sum / period;
}

const blend = (legs, ws) => {
  let s = 0, w = 0;
  ws.forEach((k, i) => { if (k && legs[i] > 0) { s += legs[i] * k; w += k; } });
  return w ? s / w : 0;
};

const rows = [];
console.log('=== NZDUSD — our six legs vs his ATR row (shift 1, latest bar) ===');
console.log('  TF  |  his  |    5     10     21     66    132    264  | 6-leg  5-leg  4-leg | best single');
for (const tf of ORDER) {
  const bars = parseHST('NZDUSD' + MIN[tf] + '.hst');
  const anchor = bars.length - 2;          // shift 1 = last closed bar
  const legs = PERIODS.map((p) => smaLeg(bars, anchor, p) / PIP);
  const c6 = blend(legs, WEIGHTS);
  const c5 = blend(legs, [1, 1, 2, 3, 5]);
  const c4 = blend(legs, [1, 1, 2, 3]);
  let bi = 0, bd = 1e9;
  legs.forEach((v, i) => { const d = Math.abs(v - HIS[tf]); if (d < bd) { bd = d; bi = i; } });
  rows.push({ tf, legs, his: HIS[tf], c6, c5, c4 });
  const p = (v) => ((v - HIS[tf]) / HIS[tf] * 100);
  console.log('  ' + tf.padEnd(4) + '| ' + String(HIS[tf]).padStart(5) + ' | ' +
    legs.map((v) => v.toFixed(1).padStart(6)).join(' ') + '  | ' +
    c6.toFixed(1).padStart(5) + (p(c6).toFixed(0) + '%').padStart(5) +
    c5.toFixed(1).padStart(6) + (p(c5).toFixed(0) + '%').padStart(5) +
    c4.toFixed(1).padStart(6) + (p(c4).toFixed(0) + '%').padStart(5) +
    ' | n' + PERIODS[bi] + ' (' + legs[bi].toFixed(1) + ')');
}
const last = parseHST('NZDUSD60.hst');
console.log('    last closed H1 bar: ' + new Date(last[last.length - 2].time * 1000).toISOString().slice(0, 16).replace('T', ' '));

// mean |error| of each composite shape
console.log('');
for (const [name, key] of [['6-leg 1/1/2/3/5/8 (shipped)', 'c6'], ['5-leg 1/1/2/3/5', 'c5'], ['4-leg 1/1/2/3', 'c4']]) {
  let e = 0;
  for (const r of rows) e += Math.abs(r[key] - r.his) / r.his;
  console.log('  ' + name.padEnd(30) + ' mean |err| ' + (e / rows.length * 100).toFixed(1) + '%');
}

// --- least squares for the weights (8 equations, 6 unknowns) ----------------
function solve(A, b) {
  const n = b.length;
  const M = A.map((row, i) => row.concat([b[i]]));
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    const d = M[c][c];
    if (Math.abs(d) < 1e-12) continue;
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      const f = M[r][c] / d;
      for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k];
    }
  }
  return M.map((row, i) => row[n] / (row[i] || 1));
}
const n = 6, A = Array.from({ length: n }, () => new Array(n).fill(0)), b = new Array(n).fill(0);
const LAM = 1e6;
for (const r of rows) {
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) A[i][j] += r.legs[i] * r.legs[j];
    b[i] += r.legs[i] * r.his;
  }
}
for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) A[i][j] += LAM;
for (let i = 0; i < n; i++) b[i] += LAM;
const w = solve(A, b);
const sum = w.reduce((a, v) => a + v, 0);
const wn = w.map((v) => v / sum);
const mn = Math.min(...wn.filter((v) => v > 1e-6));
console.log('\n  least-squares weights (smallest = 1): ' + wn.map((v) => (v / mn).toFixed(2)).join('  '));
console.log('  shipped                             : 1.00  1.00  2.00  3.00  5.00  8.00');
let e = 0;
for (const r of rows) e += Math.abs(blend(r.legs, wn) - r.his) / r.his;
console.log('  mean |err| of the fit: ' + (e / rows.length * 100).toFixed(1) + '%');
