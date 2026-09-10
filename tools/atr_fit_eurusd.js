// EURUSD ATR scenario search (2026-09-10): which definition reproduces the
// professor's strip TR from the 13:44 screenshot, using terminal .hst data?
// MQL4-exact semantics: index 0 = forming bar; shift=1 evaluations end at
// bar 1; Wilder seed = SMA of the FIRST (oldest) `period` TRs.
const fs = require('fs');
const path = require('path');

const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PIPS = 10000; // EURUSD price->pips (0.0001)
// Professor strip TR, EURUSD, screenshot ~13:44 server (integers!)
const prof = { M1: 1, M5: 2, M15: 4, H1: 8, H4: 16, D1: 54, W1: 143, MN: 353 };
const tfFiles = {
  M1: 'EURUSD1.hst', M5: 'EURUSD5.hst', M15: 'EURUSD15.hst',
  H1: 'EURUSD60.hst', H4: 'EURUSD240.hst', D1: 'EURUSD1440.hst',
  W1: 'EURUSD10080.hst', MN: 'EURUSD43200.hst',
};
const TFS = Object.keys(tfFiles);

function parseHST(file) {
  const full = path.join(histDir, file);
  const st = fs.statSync(full);
  const buf = fs.readFileSync(full);
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
  return { bars, mtime: st.mtime, file };
}

// bars[0] = OLDEST, bars[n-1] = forming. TR[i] for i>=1 (needs prev close).
function trueRanges(bars) {
  const tr = new Array(bars.length).fill(null);
  for (let i = 1; i < bars.length; i++) {
    tr[i] = Math.max(
      bars[i].high - bars[i].low,
      Math.abs(bars[i].high - bars[i - 1].close),
      Math.abs(bars[i].low - bars[i - 1].close)
    );
  }
  return tr;
}
// MQL4 iATR(period, shift=1): seed = SMA of oldest `period` TRs, recurse to bar 1.
function wilderAtShift1(tr, period) {
  const n = tr.length;         // tr[n-1] = forming bar
  const end = n - 1;           // bar 1 == index end-1... compute series up to index end-1
  const last = end - 1;        // MQL4 bar 1
  if (last < period) return null; // need TR[1..period] at least
  let atr = 0;
  for (let i = 1; i <= period; i++) atr += tr[i];
  atr /= period;
  for (let i = period + 1; i <= last; i++) atr = (atr * (period - 1) + tr[i]) / period;
  return atr;
}
// Simple mean of TR over bars 1..period (shift=1). quirk: bar1 uses own close.
function smaAtShift1(bars, tr, period, quirk) {
  const n = bars.length;
  const last = n - 2; // bar 1
  if (last < period) return null;
  let s = 0;
  for (let k = 1; k <= period; k++) {
    const i = last - period + k; // window bars [last-period+1 .. last], i>=1
    if (i === last && quirk) {
      const b = bars[i];
      s += Math.max(b.high - b.low, Math.abs(b.high - b.close), Math.abs(b.low - b.close));
    } else s += tr[i];
  }
  return s / period;
}

const data = {};
for (const tf of TFS) {
  let { bars, mtime } = parseHST(tfFiles[tf]);
  // Torn tail from the wedged disk-writer: drop trailing H<L records only.
  let bad = [];
  for (let i = 0; i < bars.length; i++) if (!(bars[i].high >= bars[i].low)) bad.push(i);
  while (bars.length && !(bars[bars.length - 1].high >= bars[bars.length - 1].low)) bars.pop();
  const midBad = bad.filter(i => i < bars.length).length;
  console.log(`${tf}: bars=${bars.length} droppedTail=${bad.length - midBad} midBad=${midBad}`);
  if (midBad > 0) throw new Error('corrupt mid-file bars in ' + tf);
  if (bars.length < 10) throw new Error('too few bars in ' + tf);
  const tr = trueRanges(bars);
  data[tf] = { bars, tr, mtime, nbars: bars.length,
               lastBar: new Date(bars[bars.length - 1].time * 1000).toISOString() };
}
console.log('now =', new Date().toISOString());
for (const tf of TFS)
  console.log(`${tf}: bars=${data[tf].nbars} mtime=${data[tf].mtime.toISOString()} lastBar=${data[tf].lastBar}`);

// err in pips vs integer band: match = within +-0.5 pip of prof int
function band(v, tf) {
  if (v === null) return 'n/a';
  const p = v * PIPS, d = p - prof[tf];
  const mark = Math.abs(d) <= 0.5 ? 'IN ' : (Math.abs(d) / prof[tf] <= 0.01 ? '1% ' : 'OUT');
  return `${mark} v=${p.toFixed(2)} d=${d >= 0 ? '+' : ''}${d.toFixed(2)}`;
}

const LEGS = [5, 10, 21, 66, 132, 264], W = [1, 1, 2, 3, 5, 8];
function composite(tf, legFn) {
  let ws = 0, tw = 0;
  for (let i = 0; i < LEGS.length; i++) {
    const v = legFn(tf, LEGS[i]);
    if (v !== null && v > 0) { ws += v * W[i]; tw += W[i]; }
  }
  return tw > 0 ? ws / tw : null;
}
const WF = (tf, p) => wilderAtShift1(data[tf].tr, p);
const SF = (tf, p) => smaAtShift1(data[tf].bars, data[tf].tr, p, false);
const QF = (tf, p) => smaAtShift1(data[tf].bars, data[tf].tr, p, true);

console.log('\n=== S0 baseline: current engine (Wilder composite M1-D1, iATR W1/55, MN/30) ===');
for (const tf of TFS) {
  let v;
  if (tf === 'W1') v = WF(tf, 55);
  else if (tf === 'MN') v = WF(tf, 30);
  else v = composite(tf, WF);
  console.log(`${tf}: ${band(v, tf)}  (prof ${prof[tf]})`);
}
console.log('\n=== S1: same weights over SMA legs (no quirk) ===');
for (const tf of TFS) console.log(`${tf}: ${band(composite(tf, SF), tf)}  (prof ${prof[tf]})`);
console.log('\n=== S2: same weights over SMA legs WITH newest-bar quirk ===');
for (const tf of TFS) console.log(`${tf}: ${band(composite(tf, QF), tf)}  (prof ${prof[tf]})`);

console.log('\n=== S3: user hint — periods 12 and 24 (SMA and Wilder), all TFs ===');
for (const tf of TFS) {
  const r = [`SMA12=${(SF(tf,12)*PIPS).toFixed(2)}`, `WLD12=${(WF(tf,12)*PIPS).toFixed(2)}`,
             `SMA24=${(SF(tf,24)*PIPS).toFixed(2)}`, `WLD24=${(WF(tf,24)*PIPS).toFixed(2)}`].join(' ');
  console.log(`${tf}: ${r}  (prof ${prof[tf]})`);
}

console.log('\n=== S4: best single SMA-N per TF (N=2..300) ===');
for (const tf of TFS) {
  let best = null;
  for (let nN = 2; nN <= 300; nN++) {
    const v = SF(tf, nN);
    if (v === null) break;
    const e = Math.abs(v * PIPS - prof[tf]);
    if (!best || e < best.e) best = { nN, e, v: v * PIPS };
  }
  console.log(`${tf}: SMA(${best.nN})=${best.v.toFixed(2)} d=${(best.v-prof[tf]>=0?'+':'')+(best.v-prof[tf]).toFixed(2)} (prof ${prof[tf]})`);
}
console.log('\n=== S5: simple MEAN of leg sets (no weights) ===');
for (const tf of TFS) {
  const mw = LEGS.reduce((s, p) => s + WF(tf, p), 0) / LEGS.length;
  const ms = LEGS.reduce((s, p) => s + SF(tf, p), 0) / LEGS.length;
  console.log(`${tf}: meanWilder=${(mw*PIPS).toFixed(2)} meanSMA=${(ms*PIPS).toFixed(2)} (prof ${prof[tf]})`);
}
console.log('\n=== S6: quirk effect size per TF (composite with vs without) ===');
for (const tf of TFS) {
  const a = composite(tf, SF) * PIPS, b = composite(tf, QF) * PIPS;
  console.log(`${tf}: noQuirk=${a.toFixed(2)} quirk=${b.toFixed(2)} delta=${(b-a).toFixed(2)} (${(100*(b-a)/a).toFixed(1)}%)`);
}
