// Find N in Eng(TF) = ATR(TF, N)/4.266666 from LIVE gold screenshots:
//   M5 chart (Sep-10 19:55): Eng(M5)=14 -> ATR(M5,N)=59.7p ; Eng(H1)=49.25 (from SL(M5)=59 -> slTrue 59.1/1.2) -> ATR(H1,N)=210p
//   D1 chart (Sep-10 21:20): Eng(D1)=249 -> ATR(D1,N)=1062p ; Eng(MN)=983.3 (from SL(D1)=1180) -> ATR(MN,N)=4196p
// His panel TR (composite display) at ~19:55: M5 54, H1 192, D1 1060, MN 3144.
// Caveat: our .hst is a boot snapshot ending ~13:15 UTC (pre-US-session), so
// short-TF ATRs will read below his 19:55 values; D1 should be close.
const fs = require('fs');
const path = require('path');
const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PIPS = 10; // XAUUSD price->pips (0.1)
const files = { M1: 'XAUUSD1.hst', M5: 'XAUUSD5.hst', M15: 'XAUUSD15.hst', H1: 'XAUUSD60.hst', H4: 'XAUUSD240.hst', D1: 'XAUUSD1440.hst', W1: 'XAUUSD10080.hst', MN: 'XAUUSD43200.hst' };
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
function wilderAtShift1(tr, period) {
  const n = tr.length, last = n - 2;
  if (last < period) return null;
  let a = 0;
  for (let i = 1; i <= period; i++) a += tr[i];
  a /= period;
  for (let i = period + 1; i <= last; i++) a = (a * (period - 1) + tr[i]) / period;
  return a;
}
function smaAtShift1(tr, period) {
  const n = tr.length, last = n - 2;
  if (last < period) return null;
  let s = 0;
  for (let i = 0; i < period; i++) s += tr[last - i];
  return s / period;
}
const data = {};
for (const tf of Object.keys(files)) {
  const bars = parseHST(files[tf]);
  while (bars.length && !(bars[bars.length - 1].high >= bars[bars.length - 1].low)) bars.pop();
  data[tf] = { bars, tr: trueRanges(bars), last: new Date(bars[bars.length - 1].time * 1000).toISOString() };
  console.log(`${tf}: bars=${bars.length} last=${data[tf].last}`);
}
const D = 4.266666;
// his Eng-source ATR targets in pips (Eng * 4.266666)
const targets = {
  M5:  { tgt: 59.7, panel: 54,  note: 'Eng(M5)=14 (M5 chart 19:55)' },
  H1:  { tgt: 210.1, panel: 192, note: 'Eng(H1)=49.25 from SL(M5)=59' },
  D1:  { tgt: 1062.2, panel: 1060, note: 'Eng(D1)=249 (D1 chart 21:20)' },
  MN:  { tgt: 4195.8, panel: 3144, note: 'Eng(MN)=983.3 from SL(D1)=1180' },
};
console.log('\n=== ATR(TF, N) in pips at last .hst bar — where does ATR/D hit his Eng? ===');
for (const tf of ['M5', 'H1', 'D1', 'MN']) {
  const t = targets[tf];
  const tr = data[tf].tr;
  let bestW = null, bestS = null, bestEw = Infinity, bestEs = Infinity;
  for (let N = 1; N <= 400; N++) {
    const w = wilderAtShift1(tr, N), s = smaAtShift1(tr, N);
    if (w !== null) { const p = w * PIPS; const e = Math.abs(p - t.tgt) / t.tgt; if (e < bestEw) { bestEw = e; bestW = N; } }
    if (s !== null) { const p = s * PIPS; const e = Math.abs(p - t.tgt) / t.tgt; if (e < bestEs) { bestEs = e; bestS = N; } }
  }
  const fmtN = (N, e) => {
    const v = N === null ? null : (N === 1 ? wilderAtShift1(tr, 1) : wilderAtShift1(tr, N));
    return N === null ? 'n/a' : `N=${N} (${(v * PIPS).toFixed(1)}p, ${(e * 100).toFixed(0)}%)`;
  };
  console.log(`${tf}: target ATR=${t.tgt}p (panel ${t.panel}p) | best Wilder ${fmtN(bestW, bestEw)} | best SMA ${fmtN(bestS, bestEs)}`);
}
console.log('\n=== ATR/D vs his Eng for candidate N (Wilder) — at stale 13:15 (session: read LOW on M5/H1) ===');
for (const N of [5, 10, 14, 21, 30, 55]) {
  const row = [];
  for (const tf of ['M5', 'H1', 'D1']) {
    const v = wilderAtShift1(data[tf].tr, N);
    row.push(`${tf}: ${v === null ? 'n/a' : (v * PIPS / D).toFixed(1)} (his ${tf === 'M5' ? 14 : tf === 'H1' ? 49.25 : 249})`);
  }
  console.log(`Wilder(${N}): ` + row.join('  '));
}
console.log('\n=== SMA variant ===');
for (const N of [5, 10, 14, 21, 30, 55]) {
  const row = [];
  for (const tf of ['M5', 'H1', 'D1']) {
    const v = smaAtShift1(data[tf].tr, N);
    row.push(`${tf}: ${v === null ? 'n/a' : (v * PIPS / D).toFixed(1)}`);
  }
  console.log(`SMA(${N}): ` + row.join('  '));
}
console.log('\n=== Our composite (engine TR) at last bar vs his panel ===');
{
  const LEGS = [5, 10, 21, 66, 132, 264], W = [1, 1, 2, 3, 5, 8];
  for (const tf of ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN']) {
    let v;
    const wf = (p) => wilderAtShift1(data[tf].tr, p);
    if (tf === 'W1') v = wilderAtShift1(data[tf].tr, 55);
    else if (tf === 'MN') v = wilderAtShift1(data[tf].tr, 30);
    else { let ws = 0, tw = 0; for (let i = 0; i < LEGS.length; i++) { const x = wf(LEGS[i]); if (x !== null && x > 0) { ws += x * W[i]; tw += W[i]; } } v = tw > 0 ? ws / tw : null; }
    console.log(`${tf}: our composite=${v === null ? 'n/a' : (v * PIPS).toFixed(1)}p  his panel=${tf === 'M1' ? 24 : tf === 'M5' ? 54 : tf === 'M15' ? 97 : tf === 'H1' ? 192 : tf === 'H4' ? 371 : tf === 'D1' ? 1060 : tf === 'W1' ? 2004 : 3144}`);
  }
}