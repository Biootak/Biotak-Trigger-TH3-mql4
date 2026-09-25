// Find the professor's REAL Eng formula using same-moment EURUSD corners:
//   @2026-08-17 09:19 (M5+M15 charts, same minute):
//     Eng(M5)  in [0.5625, 0.9375)   (Hunter=2, display=1)
//     Eng(M15) in [1.3125, 1.5)      (Hunter=4, display=1)
//     Eng(H1)  = 3.13/1.2 = 2.608    (from M5 chart SL=3 / StrBond 7--33)
//     Eng(H4)  = 5.47/1.2 = 4.558    (from M15 chart SL=5 / StrBond 12--58)
//   @2026-08-14 14:09 (M1 chart):
//     Eng(M15) = 1.76/1.2 = 1.467    (from SL(M1)=2 / StrBond 4--19)
//     Eng(M1)  in [0.1875, 0.5)      (Hunter=1, display=0)
const fs = require('fs');
const path = require('path');
const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PIPS = 10000;
const tfFiles = {
  M1: 'EURUSD1.hst', M5: 'EURUSD5.hst', M15: 'EURUSD15.hst',
  H1: 'EURUSD60.hst', H4: 'EURUSD240.hst', D1: 'EURUSD1440.hst',
};
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
    tr[i] = Math.max(bars[i].high - bars[i].low,
      Math.abs(bars[i].high - bars[i - 1].close), Math.abs(bars[i].low - bars[i - 1].close));
  }
  return tr;
}
function wilderAtShift1(tr, period) {
  const n = tr.length, last = n - 2;
  if (last < period) return null;
  let atr = 0;
  for (let i = 1; i <= period; i++) atr += tr[i];
  atr /= period;
  for (let i = period + 1; i <= last; i++) atr = (atr * (period - 1) + tr[i]) / period;
  return atr;
}
function smaAtShift1(tr, period) {
  const n = tr.length, last = n - 2;
  if (last < period) return null;
  let s = 0;
  for (let i = 0; i < period; i++) s += tr[last - i];
  return s / period;
}
function asOf(bars, T) {
  let i = bars.length - 1;
  while (i >= 0 && bars[i].time > T) i--;
  if (i < 1) throw new Error('history too short');
  return bars.slice(0, i + 1);
}
const data = {};
for (const tf of Object.keys(tfFiles)) {
  const bars = parseHST(tfFiles[tf]);
  while (bars.length && !(bars[bars.length - 1].high >= bars[bars.length - 1].low)) bars.pop();
  data[tf] = bars;
}

const T17 = Date.UTC(2026, 7, 17, 9, 19, 40) / 1000;
const T14 = Date.UTC(2026, 7, 14, 14, 9, 27) / 1000;
// target Eng values (midpoints for ranges)
const targets = {
  M1:  { T: T14, lo: 0.1875, hi: 0.5,   mid: 0.34 },
  M5:  { T: T17, lo: 0.5625, hi: 0.9375, mid: 0.75 },
  M15: { T: T17, lo: 1.3125, hi: 1.5,   mid: 1.41 },
  H1:  { T: T17, lo: 2.55,   hi: 2.65,  mid: 2.60 },
  H4:  { T: T17, lo: 4.45,   hi: 4.65,  mid: 4.55 },
};

console.log('=== ATR(TF, N) Wilder and SMA, N sweep — which N hits his Eng ===');
for (const tf of Object.keys(targets)) {
  const { T, lo, hi, mid } = targets[tf];
  const bars = asOf(data[tf], T);
  const tr = trueRanges(bars);
  let wBest = null, sBest = null;
  for (let N = 1; N <= 400; N++) {
    const w = wilderAtShift1(tr, N), s = smaAtShift1(tr, N);
    const wp = w === null ? null : w * PIPS, sp = s === null ? null : s * PIPS;
    if (wp !== null && wp >= lo && wp < hi && (!wBest || Math.abs(wp - mid) < Math.abs(wBest - mid))) wBest = wp;
    if (sp !== null && sp >= lo && sp < hi && (!sBest || Math.abs(sp - mid) < Math.abs(sBest - mid))) sBest = sp;
  }
  const wr = [], sr = [];
  for (let N = 1; N <= 400; N++) {
    const w = wilderAtShift1(tr, N);
    if (w !== null) { const p = w * PIPS; if (p >= lo && p < hi) wr.push(N); }
    const s = smaAtShift1(tr, N);
    if (s !== null) { const p = s * PIPS; if (p >= lo && p < hi) sr.push(N); }
  }
  const fmt = (a) => a.length === 0 ? 'none' : (a.length < 6 ? a.join(',') : a[0] + '..' + a[a.length - 1] + `(${a.length} vals, e.g. ${a.slice(0, 5).join(',')},...)`);
  console.log(`${tf}: target Eng [${lo.toFixed(3)}, ${hi.toFixed(3)}) -> Wilder N: ${fmt(wr)}  |  SMA N: ${fmt(sr)}`);
}

console.log('\n=== What if Eng = ATR(TRIGGER tf, N) ? (trigger per ladder: M1<-M1, M5<-M1, M15<-M1, H1<-M5, H4<-M15) ===');
{
  const trig = { M1: 'M1', M5: 'M1', M15: 'M1', H1: 'M5', H4: 'M15' };
  for (const tf of Object.keys(targets)) {
    const { T, lo, hi, mid } = targets[tf];
    const tg = trig[tf];
    const bars = asOf(data[tg], T);
    const tr = trueRanges(bars);
    const wr = [], sr = [];
    for (let N = 1; N <= 600; N++) {
      const w = wilderAtShift1(tr, N), s = smaAtShift1(tr, N);
      if (w !== null) { const p = w * PIPS; if (p >= lo && p < hi) wr.push(N); }
      if (s !== null) { const p = s * PIPS; if (p >= lo && p < hi) sr.push(N); }
    }
    const fmt = (a) => a.length === 0 ? 'none' : (a.length < 6 ? a.join(',') : a[0] + '..' + a[a.length - 1] + `(${a.length})`);
    console.log(`${tf} trig=${tg}: Wilder N: ${fmt(wr)}  |  SMA N: ${fmt(sr)}`);
  }
}

console.log('\n=== Calendar-window on trigger TF: Wilder with N = days*TFbars per TF (his long-window idea) ===');
{
  // e.g. Eng(H1) = ATR(M5, 12 * k) for k calendar days of M5 bars
  const days = [3, 5, 7, 10, 14, 21, 30, 45, 60, 90, 120, 150];
  const trig = { M1: 'M1', M5: 'M1', M15: 'M1', H1: 'M5', H4: 'M15' };
  const bpd = { M1: 1440, M5: 288, M15: 96, H1: 24 };
  for (const tf of Object.keys(targets)) {
    const { T, lo, hi } = targets[tf];
    const tg = trig[tf];
    const bars = asOf(data[tg], T);
    const tr = trueRanges(bars);
    const hits = [];
    for (const d of days) {
      const N = d * bpd[tg];
      const w = wilderAtShift1(tr, N);
      if (w === null) continue;
      const p = w * PIPS;
      if (p >= lo && p < hi) hits.push(`${d}d(${N})`);
    }
    console.log(`${tf} trig=${tg}: calendar-window Wilder hits: ${hits.length ? hits.join(' ') : 'none'}`);
  }
}