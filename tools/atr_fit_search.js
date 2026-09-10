// One-off fit search: which ATR definition reproduces the professor's strip TR?
// Candidates: Wilder single-leg, simple mean of TR(N), high-low-only mean,
// and a least-squares weight fit over our composite legs (5/10/21/66/132/264).
const fs = require('fs');
const path = require('path');

const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;

function parseHST(file) {
  const buf = fs.readFileSync(file);
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const bars = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    bars.push({
      time: buf.readUInt32LE(o),
      open: buf.readDoubleLE(o + 8),
      high: buf.readDoubleLE(o + 16),
      low: buf.readDoubleLE(o + 24),
      close: buf.readDoubleLE(o + 32),
    });
  }
  return bars;
}

function trueRanges(bars) {
  const tr = [];
  for (let i = 1; i < bars.length; i++) {
    tr.push(Math.max(
      bars[i].high - bars[i].low,
      Math.abs(bars[i].high - bars[i - 1].close),
      Math.abs(bars[i].low - bars[i - 1].close)
    ));
  }
  return tr;
}
function hlRanges(bars) { return bars.slice(-400).map(b => b.high - b.low); }

function wilderATR(tr, period) {
  if (tr.length < period) return null;
  let atr = 0;
  for (let i = 0; i < period; i++) atr += tr[i];
  atr /= period;
  for (let i = period; i < tr.length; i++) atr = (atr * (period - 1) + tr[i]) / period;
  return atr;
}
// Simple mean of the last N TRs (seed on the last N only)
function smaTR(tr, period) {
  if (tr.length < period) return null;
  let s = 0;
  for (let i = tr.length - period; i < tr.length; i++) s += tr[i];
  return s / period;
}
function weightedATR(tr, periods, weights) {
  let ws = 0, tw = 0;
  for (let i = 0; i < periods.length; i++) {
    const a = wilderATR(tr, periods[i]);
    if (a !== null) { ws += a * weights[i]; tw += weights[i]; }
  }
  return tw > 0 ? ws / tw : null;
}

const tfFiles = {
  M1: 'XAUUSD1.hst', M5: 'XAUUSD5.hst', M15: 'XAUUSD15.hst',
  H1: 'XAUUSD60.hst', H4: 'XAUUSD240.hst', D1: 'XAUUSD1440.hst',
  W1: 'XAUUSD10080.hst', MN: 'XAUUSD43200.hst',
};
const TFS = Object.keys(tfFiles);
const prof = { M1: 14, M5: 38, M15: 75, H1: 173, H4: 360, D1: 1066, W1: 2003, MN: 3144 };
const PIPS = 10; // XAUUSD price->pips on AMarkets (0.1 pip unit)

const data = {};
for (const tf of TFS) {
  const bars = parseHST(path.join(histDir, tfFiles[tf]));
  data[tf] = { tr: trueRanges(bars), hl: hlRanges(bars) };
}

function err(v, tf) { return v === null ? Infinity : Math.abs(v * PIPS - prof[tf]) / prof[tf]; }

console.log('=== 1. Simple mean of last N TRs — best N per TF ===');
for (const tf of TFS) {
  let best = null;
  for (let n = 3; n <= 300; n++) {
    const v = smaTR(data[tf].tr, n);
    if (v === null) break;
    const e = err(v, tf);
    if (!best || e < best.e) best = { n, e, v: v * PIPS };
  }
  console.log(`${tf}: best SMA-TR(N=${best.n}) = ${best.v.toFixed(0)} pips  (prof ${prof[tf]}, err ${(best.e * 100).toFixed(1)}%)`);
}

console.log('\n=== 2. High-Low-only mean (last 400 bars) vs prof ===');
for (const tf of TFS) {
  const hl = data[tf].hl.reduce((a, b) => a + b, 0) / data[tf].hl.length;
  console.log(`${tf}: meanHL=${(hl * PIPS).toFixed(0)}  prof=${prof[tf]}  ratio=${(prof[tf] / (hl * PIPS)).toFixed(2)}`);
}

console.log('\n=== 3. Least-squares weight fit over legs [5,10,21,66,132,264] (all 8 TFs jointly) ===');
const legs = [5, 10, 21, 66, 132, 264];
const A = TFS.map(tf => legs.map(p => (wilderATR(data[tf].tr, p) || 0) * PIPS));
const b = TFS.map(tf => prof[tf]);
// Normal equations: (AᵀA) w = Aᵀb, solve 6x6 by Gaussian elimination
const AtA = Array.from({ length: 6 }, (_, i) => Array.from({ length: 6 }, (_, j) =>
  A.reduce((s, row) => s + row[i] * row[j], 0)));
const Atb = Array.from({ length: 6 }, (_, i) => A.reduce((s, row, k) => s + row[i] * b[k], 0));
const M = AtA.map((r, i) => [...r, Atb[i]]);
for (let c = 0; c < 6; c++) {
  let piv = c;
  for (let r = c + 1; r < 6; r++) if (Math.abs(M[r][c]) > Math.abs(M[piv][c])) piv = r;
  [M[c], M[piv]] = [M[piv], M[c]];
  for (let r = 0; r < 6; r++) {
    if (r === c) continue;
    const f = M[r][c] / M[c][c];
    for (let k = c; k <= 6; k++) M[r][k] -= f * M[c][k];
  }
}
const wFit = Array.from({ length: 6 }, (_, i) => M[i][6] / M[i][i]);
console.log('fitted weights (can be negative — checks feasibility only):', wFit.map(x => x.toFixed(2)).join(', '));
for (const k of TFS) {
  const fit = legs.reduce((s, p, i) => s + (wilderATR(data[k].tr, p) || 0) * PIPS * wFit[i], 0);
  console.log(`${k}: fitted=${fit.toFixed(0)}  prof=${prof[k]}  err=${(((fit - prof[k]) / prof[k]) * 100).toFixed(1)}%`);
}

console.log('\n=== 4. Per-TF best single Wilder leg ===');
for (const tf of TFS) {
  let best = null;
  for (const p of [2, 3, 5, 8, 10, 14, 21, 34, 55, 66, 89, 132, 264]) {
    const v = wilderATR(data[tf].tr, p);
    if (v === null) continue;
    const e = err(v, tf);
    if (!best || e < best.e) best = { p, e, v: v * PIPS };
  }
  console.log(`${tf}: ATR(${best.p}) = ${best.v.toFixed(0)}  (prof ${prof[tf]}, err ${(best.e * 100).toFixed(1)}%)`);
}
