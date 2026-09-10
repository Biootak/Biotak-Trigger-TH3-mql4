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

// ---------- leg caches (avoid O(bars) recompute) ----------
const wCache = {}, sCache = {}, hCache = {};
function WC(tf, p) {
  const k = tf + ':' + p;
  if (!(k in wCache)) wCache[k] = wilderAtShift1(data[tf].tr, p);
  return wCache[k];
}
function SC(tf, p) {
  const k = tf + ':' + p;
  if (!(k in sCache)) sCache[k] = smaAtShift1(data[tf].bars, data[tf].tr, p, false);
  return sCache[k];
}
function HC(tf, p) { // high-low-only mean over bars 1..p (shift=1)
  const k = tf + ':' + p;
  if (k in hCache) return hCache[k];
  const bars = data[tf].bars, n = bars.length, last = n - 2;
  if (last < p) return null;
  let s = 0;
  for (let kk = 1; kk <= p; kk++) s += bars[last - p + kk].high - bars[last - p + kk].low;
  hCache[k] = s / p;
  return hCache[k];
}
// generalized shift (0 = include forming bar)
function smaShift(tf, p, shift, quirk) {
  const bars = data[tf].bars, tr = data[tf].tr, n = bars.length;
  const last = n - 1 - shift;
  if (last < p || last < 1) return null;
  let s = 0;
  for (let kk = 1; kk <= p; kk++) {
    const i = last - p + kk;
    if (i < 1) return null;
    if (i === last && quirk) {
      const b = bars[i];
      s += Math.max(b.high - b.low, Math.abs(b.high - b.close), Math.abs(b.low - b.close));
    } else s += tr[i];
  }
  return s / p;
}
function wilderShift(tf, p, shift) {
  const tr = data[tf].tr, n = tr.length;
  const last = n - 1 - shift;
  if (last < p || last < 1) return null;
  let atr = 0;
  for (let i = 1; i <= p; i++) atr += tr[i];
  atr /= p;
  for (let i = p + 1; i <= last; i++) atr = (atr * (p - 1) + tr[i]) / p;
  return atr;
}
const rel = (v, tf) => (v === null ? Infinity : Math.abs(v * PIPS - prof[tf]) / prof[tf]);

console.log('\n=== S7: best single Wilder-N per TF (N=2..300) ===');
for (const tf of TFS) {
  let best = null;
  for (let nN = 2; nN <= 300; nN++) {
    const v = WC(tf, nN);
    if (v === null) break;
    const e = Math.abs(v * PIPS - prof[tf]);
    if (!best || e < best.e) best = { nN, e, v: v * PIPS };
  }
  console.log(`${tf}: WLD(${best.nN})=${best.v.toFixed(2)} d=${(best.v - prof[tf] >= 0 ? '+' : '') + (best.v - prof[tf]).toFixed(2)} (prof ${prof[tf]})`);
}
console.log('\n=== S8: best single HL-mean-N per TF (N=2..300) ===');
for (const tf of TFS) {
  let best = null;
  for (let nN = 2; nN <= 300; nN++) {
    const v = HC(tf, nN);
    if (v === null) break;
    const e = Math.abs(v * PIPS - prof[tf]);
    if (!best || e < best.e) best = { nN, e, v: v * PIPS };
  }
  console.log(`${tf}: HL(${best.nN})=${best.v.toFixed(2)} d=${(best.v - prof[tf] >= 0 ? '+' : '') + (best.v - prof[tf]).toFixed(2)} (prof ${prof[tf]})`);
}
console.log('\n=== S9: ALL 63 leg subsets x {Wilder,SMA} — JOINT minimax (worst TF err) ===');
{
  const rows = [];
  for (let mask = 1; mask < 64; mask++) {
    for (const fam of ['W', 'S']) {
      const errs = TFS.map(tf => {
        let ws = 0, tw = 0;
        for (let i = 0; i < 6; i++) if (mask & (1 << i)) {
          const v = fam === 'W' ? WC(tf, LEGS[i]) : SC(tf, LEGS[i]);
          if (v !== null && v > 0) { ws += v; tw++; }
        }
        const v = tw > 0 ? ws / tw : null;
        return rel(v, tf);
      });
      const worst = Math.max(...errs);
      const bits = LEGS.filter((_, i) => mask & (1 << i)).join(',');
      rows.push({ fam, bits, worst, errs });
    }
  }
  rows.sort((a, b) => a.worst - b.worst);
  console.log('top 8 subsets by worst-TF relative err:');
  for (const r of rows.slice(0, 8)) {
    console.log(` ${r.fam}[${r.bits}] worst=${(r.worst * 100).toFixed(1)}% err/M1..MN=` +
      r.errs.map(e => (e * 100).toFixed(1)).join(','));
  }
}
console.log('\n=== S10: joint least-squares weights over 6 legs (Wilder, then SMA) ===');
function lsq(famFn) {
  const A = TFS.map(tf => LEGS.map(p => (famFn(tf, p) || 0) * PIPS));
  const b = TFS.map(tf => prof[tf]);
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
  return Array.from({ length: 6 }, (_, i) => M[i][6] / M[i][i]);
}
for (const fam of [['Wilder', WC], ['SMA', SC]]) {
  const w = lsq(fam[1]);
  console.log(`${fam[0]} optimal weights:`, w.map(x => x.toFixed(2)).join(','));
  for (const tf of TFS) {
    const fit = LEGS.reduce((s, p, i) => s + (fam[1](tf, p) || 0) * PIPS * w[i], 0);
    console.log(`  ${tf}: fit=${fit.toFixed(2)} prof=${prof[tf]} err=${(((fit - prof[tf]) / prof[tf]) * 100).toFixed(1)}%`);
  }
}
console.log('\n=== S11: shift sweep 0/1/2 on SMA composite (1/1/2/3/5/8) ===');
for (const sh of [0, 1, 2]) {
  const line = TFS.map(tf => {
    let ws = 0, tw = 0;
    for (let i = 0; i < 6; i++) {
      const v = smaShift(tf, LEGS[i], sh, false);
      if (v !== null && v > 0) { ws += v * W[i]; tw += W[i]; }
    }
    const v = tw > 0 ? ws / tw * PIPS : null;
    return `${tf}=${v === null ? 'n/a' : v.toFixed(1)}`;
  }).join(' ');
  console.log(`shift=${sh}: ${line}`);
}
console.log('\n=== S12: global divisor sweep (composite/K, same K all TFs) — joint minimax ===');
for (const fam of [['Wcomp', t => composite(t, WF)], ['Scomp', t => composite(t, SF)],
                   ['meanW', t => LEGS.reduce((s, p) => s + WC(t, p), 0) / 6],
                   ['meanS', t => LEGS.reduce((s, p) => s + SC(t, p), 0) / 6]]) {
  let best = null;
  for (let K = 50; K <= 200; K++) {
    const k = K / 100;
    const worst = Math.max(...TFS.map(tf => rel(fam[1](tf) / k, tf)));
    if (!best || worst < best.worst) best = { k, worst };
  }
  console.log(`${fam[0]}: bestK=${best.k.toFixed(2)} worstTFerr=${(best.worst * 100).toFixed(1)}%`);
}
console.log('\n=== JOINT SCORECARD: TF-independent formulas, worst-TF err + in-band count ===');
{
  const cands = {
    'current(Trex+ovr)': null, // filled from live dump below (not .hst)
    'Wcomp': t => composite(t, WF),
    'Scomp': t => composite(t, SF),
    'meanW': t => LEGS.reduce((s, p) => s + WC(t, p), 0) / 6,
    'meanS': t => LEGS.reduce((s, p) => s + SC(t, p), 0) / 6,
    'SMA24-rule': t => SC(t, 24),
    'WLD24-rule': t => WC(t, 24),
    'SMA12-rule': t => SC(t, 12),
  };
  for (const name of Object.keys(cands)) {
    if (!cands[name]) continue;
    const errs = TFS.map(tf => rel(cands[name](tf), tf));
    const inband = TFS.map(tf => {
      const v = cands[name](tf);
      return v !== null && Math.abs(v * PIPS - prof[tf]) <= 0.5 ? 1 : 0;
    }).reduce((a, b) => a + b, 0);
    console.log(`${name}: worst=${(Math.max(...errs) * 100).toFixed(1)}% inband=${inband}/8 ` +
      errs.map(e => (e * 100).toFixed(1)).join(','));
  }
  // current engine values are LIVE (terminal), not .hst — pinned here from 13:43 dump
  const live = { M1: 1.04, M5: 2.19, M15: 3.71, H1: 7.58, H4: 16.73, D1: 56.98, W1: 140.70, MN: 338.26 };
  const errs = TFS.map(tf => Math.abs(live[tf] - prof[tf]) / prof[tf]);
  const inband = TFS.map(tf => Math.abs(live[tf] - prof[tf]) <= 0.5 ? 1 : 0).reduce((a, b) => a + b, 0);
  console.log(`current(Trex+ovr)LIVE: worst=${(Math.max(...errs) * 100).toFixed(1)}% inband=${inband}/8 ` +
    errs.map(e => (e * 100).toFixed(1)).join(','));
}
