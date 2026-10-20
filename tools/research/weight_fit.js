// WEIGHT FIT — solve for the composite weights that reproduce HIS ATR row.
//
// We have six legs per rung (SMA-of-TR at 5/10/21/66/132/264) and his printed
// row. The composite is a normalised weighted mean, so the weights are the only
// unknowns and the problem is linear once we pin sum(w) = 1. Six unknowns,
// sixteen equations (2 symbols x 8 rungs) — over-determined, so a clean integer
// set either falls out or it does not.
//
// If the fit returns 1/1/2/3/5/8, our composite is right and the gap is timing.
// If it returns 1/1/2/3/5/0, his build simply has no 264 leg.
//
// Run: node tools/research/weight_fit.js
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const ORDER = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const PERIODS = [5, 10, 21, 66, 132, 264];
const PIP = { XAUUSD: 0.1, EURUSD: 0.0001 };

const HIS = {
  XAUUSD: { M1: 11, M5: 32, M15: 62, H1: 133, H4: 288, D1: 991, W1: 1925, MN: 3139 },
  EURUSD: { M1: 2, M5: 4, M15: 8, H1: 16, H4: 31, D1: 75, W1: 198, MN: 411 },
};

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

function lastClosedIdx(bars, tf, t) {
  const dur = MIN[tf] * 60;
  let lo = 0, hi = bars.length - 1, best = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (bars[mid].time + dur <= t) { best = mid; lo = mid + 1; } else { hi = mid - 1; }
  }
  return best;
}

// Gaussian elimination on an n x n system
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

function fit(sym, anchorTime, tag) {
  const pip = PIP[sym];
  const rows = [];
  for (const tf of ORDER) {
    let bars;
    try { bars = parseHST(sym + MIN[tf] + '.hst'); } catch (e) { continue; }
    const anchor = lastClosedIdx(bars, tf, anchorTime);
    if (anchor < 300) continue;
    const legs = PERIODS.map((p) => smaLeg(bars, anchor, p) / pip);
    if (legs.some((v) => v === null || v <= 0)) continue;
    rows.push({ tf, legs, his: HIS[sym][tf] });
  }
  if (rows.length < 6) { console.log(`  ${sym}: not enough rungs`); return; }

  // normal equations for sum_i w_i * L_i = his, plus a heavy sum(w)=1 pin
  const n = 6;
  const A = Array.from({ length: n }, () => new Array(n).fill(0));
  const b = new Array(n).fill(0);
  const LAMBDA = 1e6;
  for (const r of rows) {
    for (let i = 0; i < n; i++) {
      for (let j = 0; j < n; j++) A[i][j] += r.legs[i] * r.legs[j];
      b[i] += r.legs[i] * r.his;
    }
  }
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) A[i][j] += LAMBDA;
  for (let i = 0; i < n; i++) b[i] += LAMBDA;

  const w = solve(A, b);
  const sum = w.reduce((a, v) => a + v, 0);
  const wn = w.map((v) => v / sum);
  const scale = 1 / Math.min(...wn.filter((v) => v > 1e-6));

  console.log(`\n  ${sym}  [${tag}]  ${rows.length} rungs`);
  console.log('    fitted weights  : ' + wn.map((v) => (v * scale).toFixed(2)).join('  ') +
    '   (normalised to the smallest = 1)');
  console.log('    shipped weights : 1.00  1.00  2.00  3.00  5.00  8.00');
  console.log('    rung |  his  | fitted | err   | 5-leg (no 264) | err');
  for (const r of rows) {
    const f = wn.reduce((a, v, i) => a + v * r.legs[i], 0);
    const l5 = [1, 1, 2, 3, 5].reduce((a, v, i) => a + v * r.legs[i], 0) / 12;
    console.log('    ' + r.tf.padEnd(4) + ' | ' + String(r.his).padStart(4) + ' | ' +
      String(Math.round(f)).padStart(6) + ' | ' + (((f - r.his) / r.his * 100).toFixed(0) + '%').padStart(5) + ' | ' +
      String(Math.round(l5)).padStart(14) + ' | ' + (((l5 - r.his) / r.his * 100).toFixed(0) + '%').padStart(5));
  }
  let e1 = 0, e2 = 0;
  for (const r of rows) {
    const f = wn.reduce((a, v, i) => a + v * r.legs[i], 0);
    const l5 = [1, 1, 2, 3, 5].reduce((a, v, i) => a + v * r.legs[i], 0) / 12;
    e1 += Math.abs(f - r.his) / r.his; e2 += Math.abs(l5 - r.his) / r.his;
  }
  console.log(`    mean |err|: fitted ${(e1 / rows.length * 100).toFixed(1)}%   5-leg ${(e2 / rows.length * 100).toFixed(1)}%`);
}

const T_GOLD = Math.floor(Date.parse('2026-10-13T07:00:00Z') / 1000);
const T_EUR = Math.floor(Date.parse('2026-10-19T18:00:00Z') / 1000);

console.log('Solving for HIS composite weights (sum pinned to 1).');
console.log('Anchors: gold 2026-10-13 07:00, EURUSD 2026-10-19 18:00 (our best row matches).');
fit('XAUUSD', T_GOLD, 'anchor where our row matches his M5..D1');
fit('EURUSD', T_EUR, 'same day as his card');
