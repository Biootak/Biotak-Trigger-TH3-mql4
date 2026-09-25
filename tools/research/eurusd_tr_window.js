// Hypothesis: professor's strip TR (and Eng = TR/4.266666) uses a SHORTER
// window per TF than our long-weighted composite. Sweep ATR(TF, N) (Wilder
// and SMA) against the TR implied by his SAME-MOMENT Eng corners:
//   @2026-08-17 09:19 : Eng(M5) [0.5625,0.9375) -> TR [2.40, 4.00)
//                       Eng(M15) [1.3125,1.5)  -> TR [5.60, 6.40)
//                       Eng(H1) = 2.608        -> TR 11.13
//                       Eng(H4) = 4.558        -> TR 19.45
//   @2026-08-14 14:09 : Eng(M1) [0.1875,0.5)   -> TR [0.80, 2.13)
//                       Eng(M15) ~1.47-1.67    -> TR [6.27, 7.11)
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
// target TR in pips (from Eng * 4.266666)
const targets = [
  { tf: 'M1',  T: T14, lo: 0.80, hi: 2.13 },
  { tf: 'M5',  T: T17, lo: 2.40, hi: 4.00 },
  { tf: 'M15', T: T17, lo: 5.60, hi: 6.40 },
  { tf: 'H1',  T: T17, lo: 10.8, hi: 11.5 },
  { tf: 'H4',  T: T17, lo: 19.0, hi: 20.0 },
];

console.log('=== ATR(TF, N) windows that hit his implied TR ===');
for (const { tf, T, lo, hi } of targets) {
  const bars = asOf(data[tf], T);
  const tr = trueRanges(bars);
  const wr = [], sr = [];
  for (let N = 1; N <= 2000; N++) {
    const w = wilderAtShift1(tr, N), s = smaAtShift1(tr, N);
    if (w !== null) { const p = w * PIPS; if (p >= lo && p <= hi) wr.push(N); }
    if (s !== null) { const p = s * PIPS; if (p >= lo && p <= hi) sr.push(N); }
  }
  const fmt = (a) => a.length === 0 ? 'none' : (a.length < 8 ? a.join(',') : `${a[0]}..${a[a.length - 1]} (${a.length} vals)`);
  console.log(`${tf} @${new Date(T * 1000).toISOString().slice(0, 16)}Z target TR [${lo.toFixed(2)}, ${hi.toFixed(2)}]`);
  console.log(`   Wilder N: ${fmt(wr)}`);
  console.log(`   SMA    N: ${fmt(sr)}`);
}

console.log('\n=== Candidate windows vs his implied TR (check consistency of N across TFs) ===');
{
  const cand = { W: wilderAtShift1, S: smaAtShift1 };
  const names = { W: 'Wilder', S: 'SMA' };
  for (const fam of ['W', 'S']) {
    for (const N of [5, 7, 10, 12, 14, 16, 20, 24, 30, 40, 55, 100, 200, 400, 1000]) {
      const vals = targets.map(({ tf, T }) => {
        const bars = asOf(data[tf], T);
        const tr = trueRanges(bars);
        const v = cand[fam](tr, N);
        return v === null ? null : v * PIPS;
      });
      const row = targets.map((t, i) => {
        const v = vals[i];
        if (v === null) return 'n/a';
        const inT = v >= t.lo && v <= t.hi;
        return `${v.toFixed(2)}${inT ? '*' : ''}`;
      });
      console.log(`${names[fam]}(${N}): ` + row.join('  ') + `   (targets ${targets.map(t => `[${t.lo}-${t.hi}]`).join(' ')})`);
    }
  }
}

console.log('\n=== Ratio: his implied TR / our composite TR per TF (what our composite is missing) ===');
{
  const comp = { M1: 0.90, M5: 1.95, M15: 3.60, H1: 8.15, H4: 19.61 };
  for (const { tf, lo, hi } of targets) {
    console.log(`${tf}: his TR [${lo.toFixed(2)}-${hi.toFixed(2)}] vs our composite ${comp[tf].toFixed(2)}  ratio ${(lo / comp[tf]).toFixed(2)}-${(hi / comp[tf]).toFixed(2)}`);
  }
}