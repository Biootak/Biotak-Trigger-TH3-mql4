// Replicate the weighted-ATR engine from HST data and fit the professor's strip TR.
// Output: build-logs/atr_fit_result.json
const fs = require('fs');
const path = require('path');

const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const outPath = path.join(__dirname, '..', 'build-logs', 'atr_fit_result.json');

// AMarkets build: 148-byte header, 60-byte record (time u32, pad u32, O/L/H/C f64 @8/16/24/32, vol f64 @40, spread+ctm u32 @48/52)
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
      low: buf.readDoubleLE(o + 16),
      high: buf.readDoubleLE(o + 24),
      close: buf.readDoubleLE(o + 32),
    });
  }
  return bars;
}

// TR series, oldest-first: tr[k] belongs to bar k+1 (uses prev close)
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

// Wilder ATR over the FULL series ending at the last bar (≈ iATR(..., shift=1))
function wilderATR(tr, period) {
  if (tr.length < period) return null;
  let atr = 0;
  for (let i = 0; i < period; i++) atr += tr[i];
  atr /= period;
  for (let i = period; i < tr.length; i++) atr = (atr * (period - 1) + tr[i]) / period;
  return atr;
}

function weightedATR(tr, periods, weights) {
  let ws = 0, tw = 0, used = [];
  for (let i = 0; i < periods.length; i++) {
    const a = wilderATR(tr, periods[i]);
    if (a !== null) { ws += a * weights[i]; tw += weights[i]; used.push(periods[i]); }
  }
  return { value: tw > 0 ? ws / tw : null, used };
}

const tfFiles = {
  M1: 'XAUUSD1.hst', M5: 'XAUUSD5.hst', M15: 'XAUUSD15.hst',
  H1: 'XAUUSD60.hst', H4: 'XAUUSD240.hst', D1: 'XAUUSD1440.hst',
  W1: 'XAUUSD10080.hst', MN: 'XAUUSD43200.hst',
};

const data = {};
for (const [tf, f] of Object.entries(tfFiles)) {
  const p = path.join(histDir, f);
  const bars = parseHST(p);
  const tr = trueRanges(bars);
  data[tf] = { bars: bars.length, tr, last: new Date(bars[bars.length - 1].time * 1000).toISOString().slice(0, 10) };
}
console.log('history depth:', Object.fromEntries(Object.entries(data).map(([k, v]) => [k, `${v.bars} bars to ${v.last}`])));

// Our engine + logged live values (13:48 log) + professor strip (14:15 screenshot)
const curPeriods = [5, 10, 21, 66, 132, 264];
const curWeights = [1, 1, 2, 3, 5, 8];
const logged = { M1: 13.02, M5: 38.33, M15: 75.13, H1: 177.02, H4: 352.71, D1: 1100.82, W1: 1629.70, MN: 2282.13 };
const prof = { M1: 13, M5: 38, M15: 72, H1: 170, H4: 358, D1: 1066, W1: 2003, MN: 3144 };

console.log('\n=== Engine replication check (pips, price*10) ===');
const replica = {};
for (const tf of Object.keys(prof)) {
  const { value, used } = weightedATR(data[tf].tr, curPeriods, curWeights);
  replica[tf] = value * 10;
  console.log(`${tf}: replicated=${replica[tf].toFixed(1)}  logged=${logged[tf]}  prof=${prof[tf]}  legs=[${used}]`);
}

console.log('\n=== Single-leg Wilder ATR sweep on W1 / MN (pips) ===');
for (const tf of ['W1', 'MN', 'D1']) {
  const row = [];
  for (const p of [3, 5, 6, 8, 10, 14, 21, 34, 55, 66, 89, 132, 264]) {
    const a = wilderATR(data[tf].tr, p);
    if (a !== null) row.push(`ATR(${p})=${(a * 10).toFixed(0)}`);
  }
  console.log(`${tf}: ${row.join(' ')}`);
}

console.log('\n=== Leg-drop scenarios (what MT4 would do with shallow history) ===');
const scenarios = [
  ['all 6 legs', curPeriods, curWeights],
  ['no 264 (5/10/21/66/132)', [5, 10, 21, 66, 132], [1, 1, 2, 3, 5]],
  ['no 132/264', [5, 10, 21, 66], [1, 1, 2, 3]],
  ['no 66/132/264', [5, 10, 21], [1, 1, 2]],
  ['5/10 only', [5, 10], [1, 1]],
];
for (const [name, ps, ws] of scenarios) {
  const vals = [];
  for (const tf of ['D1', 'W1', 'MN']) {
    const { value } = weightedATR(data[tf].tr, ps, ws);
    vals.push(`${tf}=${(value * 10).toFixed(0)}`);
  }
  console.log(`${name.padEnd(26)} -> ${vals.join('  ')}   (prof: D1=1066 W1=2003 MN=3144)`);
}

fs.writeFileSync(outPath, JSON.stringify({
  depth: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, v.bars])),
  replica, prof, logged,
}, null, 2));
console.log('\nwrote', outPath);
