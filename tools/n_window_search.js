// ============================================================================
// n_window_search.js — pin N in Eng(TF) = ATR(TF, N)/4.266666 for EVERY TF,
// using the professor's Sep-9-2026 12:18 golden ladder (the ONLY moment fully
// covered by the XAUUSD .hst files) + user confirmation 2026-09-10 23:49 that
// Panel B (Th-TR-Live, long window) is the REAL trade plan.
//
// Targets: Eng_source(TF) = Eng_golden(TF) × 4.266666
//   M1 3.8*  M5 7.9*  M15 16.515  H1 39.854  H4 87.766  D1 252.338
//   W1 600.000  MN 982.978   (* display-only, soft)
// For each TF, find N minimizing |ATR(TF,N)@shift1 − source| at the bar
// closed just before 2026-09-09 12:18 local (the screenshot moment), for
// Wilder and SMA variants. Then look for an N(TF) RULE.
//
// Run: node tools/n_window_search.js
// ============================================================================
'use strict';
const fs = require('fs');
const path = require('path');
const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PIPS = 10; // XAUUSD price->pips (0.1)
const D = 4.266666;
// screenshot moment (local) — the bar in progress then is <moment>
const MOMENT = new Date(2026, 8, 9, 12, 18, 0); // Sep-9 12:18 local
const FILES = { M1: 'XAUUSD1.hst', M5: 'XAUUSD5.hst', M15: 'XAUUSD15.hst', H1: 'XAUUSD60.hst', H4: 'XAUUSD240.hst', D1: 'XAUUSD1440.hst', W1: 'XAUUSD10080.hst', MN: 'XAUUSD43200.hst' };
// golden Eng × divisor → ATR source targets (pips)
const TARGET = {
  M1: 3.8 * D, M5: 7.9 * D, M15: 16.515 * D, H1: 39.854 * D,
  H4: 87.766 * D, D1: 252.338 * D, W1: 600.0 * D, MN: 982.978 * D,
};
const SOFT = ['M1', 'M5']; // display-only windows

function parseHST(file) {
  const buf = fs.readFileSync(path.join(histDir, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const bars = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    bars.push({ time: buf.readUInt32LE(o), high: buf.readDoubleLE(o + 16), low: buf.readDoubleLE(o + 24), close: buf.readDoubleLE(o + 32) });
  }
  return bars;
}
function trueRanges(bars) {
  const tr = new Array(bars.length).fill(null);
  for (let i = 1; i < bars.length; i++) {
    tr[i] = Math.max(bars[i].high - bars[i].low, Math.abs(bars[i].high - bars[i - 1].close), Math.abs(bars[i].low - bars[i - 1].close));
  }
  return tr;
}
// SMA of TR over `period` bars ENDING at endIdx (inclusive).
function smaEnd(tr, period, endIdx) {
  if (endIdx - period + 1 < 1) return null;
  let s = 0;
  for (let i = 0; i < period; i++) s += tr[endIdx - i];
  return s / period;
}
// Wilder ATR over `period` bars ending at endIdx.
function wilderEnd(tr, period, endIdx) {
  if (endIdx - period + 1 < 1) return null;
  let a = 0;
  for (let i = 0; i < period; i++) a += tr[endIdx - i];
  a /= period;
  for (let i = endIdx - period; i >= 1; i--) a = (a * (period - 1) + tr[i]) / period;
  return a;
}
// index of the bar IN PROGRESS at `mom` (bar open time <= mom); last closed = k-1
function barIdxAt(bars, mom) {
  const t = Math.floor(mom.getTime() / 1000);
  for (let i = bars.length - 1; i >= 0; i--) if (bars[i].time <= t) return i;
  return 0;
}

console.log('n_window_search.js — pin N(TF) from the Sep-9-2026 12:18 golden ladder');
console.log('moment: ' + MOMENT.toLocaleString() + ' | pip = 0.1 | divisor = ' + D);
console.log('targets (ATR source pips = Eng×4.266666): ' + Object.entries(TARGET).map(([t, v]) => `${t} ${v.toFixed(1)}${SOFT.includes(t) ? '*' : ''}`).join('  '));

const results = {};
for (const tf of Object.keys(FILES)) {
  const bars = parseHST(FILES[tf]);
  while (bars.length && !(bars[bars.length - 1].high >= bars[bars.length - 1].low)) bars.pop();
  const tr = trueRanges(bars);
  const k = barIdxAt(bars, MOMENT);          // in-progress bar at screenshot
  const end = k - 1;                          // last CLOSED bar
  const lastTime = new Date(bars[bars.length - 1].time * 1000).toISOString();
  let bestS = null, bestW = null, bestEs = Infinity, bestEw = Infinity;
  const maxN = Math.min(400, end - 1);
  for (let N = 1; N <= maxN; N++) {
    const s = smaEnd(tr, N, end), w = wilderEnd(tr, N, end);
    if (s !== null) { const p = s * PIPS; const e = Math.abs(p - TARGET[tf]) / TARGET[tf]; if (e < bestEs) { bestEs = e; bestS = N; } }
    if (w !== null) { const p = w * PIPS; const e = Math.abs(p - TARGET[tf]) / TARGET[tf]; if (e < bestEw) { bestEw = e; bestW = N; } }
  }
  results[tf] = { bestS, bestEs, bestW, bestEw, bars: bars.length, lastTime, endIdx: end, k };
  console.log(`\n${tf}: bars=${bars.length} last=${lastTime} inProgress=${new Date(bars[k].time * 1000).toISOString()}`);
  const fmt = (N, e) => N === null ? 'n/a' : `N=${N} (${e < 0.005 ? 'EXACT' : (e * 100).toFixed(1) + '% off'})`;
  console.log(`  target ${TARGET[tf].toFixed(1)}p  | SMA ${fmt(bestS, bestEs)}  | Wilder ${fmt(bestW, bestEw)}`);
}

console.log('\n=== candidate N(TF) table (best SMA N; Wilder in parens) ===');
for (const tf of Object.keys(FILES)) {
  const r = results[tf];
  const n = r.bestS !== null ? r.bestS : r.bestW;
  console.log(`  ${tf}: N=${n} (SMA ${r.bestS}, Wilder ${r.bestW})  err ${(Math.min(r.bestEs, r.bestEw) * 100).toFixed(2)}%`);
}

// --- N(TF) rule hunt: is N a clean function of TF minutes? ---
console.log('\n=== N rule hunt ===');
const mins = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const nList = {};
for (const tf of Object.keys(FILES)) nList[tf] = results[tf].bestS !== null ? results[tf].bestS : results[tf].bestW;
console.log('  N(TF): ' + Object.entries(nList).map(([t, n]) => `${t}:${n}`).join('  '));
for (const tf of Object.keys(FILES)) {
  if (tf === 'M1') continue;
  const r = Math.log(nList[tf]) / Math.log(mins[tf]);
  console.log(`  ln(N)/ln(min) ${tf}: ${r.toFixed(3)}  (N = min^${r.toFixed(3)}; sqrt-law would be 0.5)`);
}
console.log('  note: N(D1)=46 pinned earlier (R-ENGSOURCE); MN 16..30 from our override — compare with the MN hit above.');