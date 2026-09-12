// ENG window rig (2026-09-10 evening).
//
// PART 1 (rejected): a FIXED N on each chart's OWN timeframe. Dead — gold
//   ATR(own M1) never drops below ~16 pips while the professor's small-TF Eng
//   values are far lower, and ATR(own H4) is 350+ vs his 88.
// PART 2 (the finding): a fixed CALENDAR window on the TRIGGER tf, i.e.
//   N = windowDays * 1440 / trigMin. The two TFs whose trigger history is deep
//   enough to test without clamping pin it:
//     W1 <- ATR(H4, ~900)  = 150 days
//     MN <- ATR(D1, ~175)  = 175 days
//   Our current formula uses N = chartMin/trigMin = ONE chart bar of trigger
//   (= a 4h window for H4, a 1-day window for D1) and misses W1 by -39%.
//
// Prof Eng sources (SL-derived only, the observable ones):
//   XAUUSD ledger §3 back-solve (Sep-9-2026; window width ~0.02 pip)
//   EURUSD TRex M15/H4/D1 screenshots (Sep-10-2026) + SL-derived W1/MN
// NB: .hst is a boot snapshot (P-ATR-04). Ours ends 13:15 server today, so
// fast-TF rows (M1..H1) MISS the evening spike and will read low — flagged.
const fs = require('fs');
const path = require('path');

const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const LADDER = [
  { name: 'M1', min: 1, trig: 1 }, { name: 'M5', min: 5, trig: 1 },
  { name: 'M15', min: 15, trig: 1 }, { name: 'H1', min: 60, trig: 5 },
  { name: 'H4', min: 240, trig: 15 }, { name: 'D1', min: 1440, trig: 60 },
  { name: 'W1', min: 10080, trig: 240 }, { name: 'MN', min: 43200, trig: 1440 },
];
// only the observable (SL-derived) legs — Eng(M1)/Eng(M5) are not displayed anywhere
const SYMS = {
  XAUUSD: { pip: 10, eng: { M15: 16.515, H1: 39.854, H4: 87.766, D1: 252.338, W1: 600.0, MN: 982.978 } },
  EURUSD: { pip: 10000, eng: { M15: 1.9, H4: 4.4, D1: 11.2, W1: 32.0, MN: 85.6 } },
};
const CUR_PER = { M1: 1, M5: 5, M15: 15, H1: 12, H4: 16, D1: 24, W1: 42, MN: 30 }; // current formula
const DAYS = [21, 30, 45, 60, 75, 90, 120, 150, 175, 200, 250, 365, 550, 730];

function parseHST(file) {
  const buf = fs.readFileSync(file);
  const HDR = 148, REC = 60, n = Math.floor((buf.length - HDR) / REC);
  const bars = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    const b = { time: buf.readUInt32LE(o), open: buf.readDoubleLE(o + 8), high: buf.readDoubleLE(o + 16), low: buf.readDoubleLE(o + 24), close: buf.readDoubleLE(o + 32) };
    if (b.high < b.low) throw new Error(`corrupt H/L in ${file} bar ${i}`); // P-TOOL-04
    bars.push(b);
  }
  return bars;
}
function trueRanges(bars) {
  const tr = new Array(bars.length).fill(null);
  for (let i = 1; i < bars.length; i++)
    tr[i] = Math.max(bars[i].high - bars[i].low, Math.abs(bars[i].high - bars[i - 1].close), Math.abs(bars[i].low - bars[i - 1].close));
  return tr;
}
// MQL4 iATR(period, shift=1): seed = SMA of the OLDEST `period` TRs, Wilder to bar 1.
function atrShift1(tr, period) {
  const last = tr.length - 2;
  if (period < 1 || last < period) return null;
  let a = 0;
  for (let i = 1; i <= period; i++) a += tr[i];
  a /= period;
  for (let i = period + 1; i <= last; i++) a = (a * (period - 1) + tr[i]) / period;
  return a;
}
// cache by TRIGGER tf minutes, loaded from that very file (M1/M5/M15 all use M1)
const data = {};
for (const sym of Object.keys(SYMS)) {
  data[sym] = {};
  for (const l of LADDER) {
    if (data[sym][l.trig]) continue;
    const p = path.join(histDir, `${sym}${l.trig}.hst`);
    try { const bars = parseHST(p); data[sym][l.trig] = { tr: trueRanges(bars), bars: bars.length, last: bars[bars.length - 1].time }; }
    catch (e) { data[sym][l.trig] = null; }
  }
}
// search ladder for PART 3 (geometric-ish, capped at 20k)
const NLADDER = (() => {
  const out = [];
  for (let n = 5; n <= 60; n++) out.push(n);
  for (let n = 85; n <= 3000; n += 25) out.push(n);
  for (let n = 3250; n <= 20000; n += 250) out.push(n);
  return out;
})();

// window N is CLAMPED to available history (what the engine would have to do)
const atrWindow = (d, n) => {
  if (!d) return { v: null, clamped: true };
  const eff = Math.min(n, d.bars - 2);
  return { v: atrShift1(d.tr, eff), clamped: n > d.bars - 2 };
};

console.log('=== PART 1: fixed-N own-TF windows — rejected sample (XAUUSD) ===');
for (const tf of ['M1', 'M15', 'H4', 'D1']) {
  const d = data.XAUUSD[tf]; if (!d) continue;
  const vals = [10, 60, 264, 1000, 2000].map(n => { const v = atrShift1(d.tr, n); return v === null ? 'n/a' : (v * 10).toFixed(1); });
  console.log(` ATR(${tf}, [10,60,264,1000,2000]) = ${vals.join(' / ')}  (prof Eng for that TF is far below every value)`);
}

console.log('\n=== PART 3: per-target search — (series, window-days) that reproduces each prof Eng ===');
{
  for (const sym of Object.keys(SYMS)) {
    const cfg = SYMS[sym];
    console.log(`--- ${sym} ---`);
    for (const l of LADDER) {
      const prof = cfg.eng[l.name];
      if (prof === undefined) continue;
      const hits = [];
      for (const s of LADDER) {
        const d = data[sym][s.trig];
        if (!d) continue;
        let bestN = null, bestE = Infinity;
        const maxN = d.bars - 2;
        for (const n of NLADDER) { // ladder scan (atrShift1 is O(n); full sweep would be O(bars^2))
          if (n > maxN) break;
          const v = atrShift1(d.tr, n);
          if (v === null) continue;
          const e = Math.abs(v * cfg.pip - prof) / prof;
          if (e < bestE) { bestE = e; bestN = n; }
        }
        // refine +-1 ladder step around the winner
        if (bestN !== null) {
          const step = bestN < 60 ? 1 : (bestN < 3000 ? 25 : 250);
          for (let n = Math.max(5, bestN - step); n <= Math.min(maxN, bestN + step); n++) {
            const v = atrShift1(d.tr, n);
            if (v === null) continue;
            const e = Math.abs(v * cfg.pip - prof) / prof;
            if (e < bestE) { bestE = e; bestN = n; }
          }
        }
        if (bestN === null) continue;
        const days = bestN * s.trig / 1440;
        hits.push({ series: s.trig, n: bestN, days, err: bestE, hitMax: bestN >= d.bars - 3 });
      }
      hits.sort((a, b) => a.err - b.err);
      console.log(` ${l.name.padEnd(4)} prof=${String(prof).padStart(7)} trig=${l.trig}: ` +
        hits.slice(0, 3).map(h =>
          `${h.series}min N=${h.n}(${h.days.toFixed(0)}d,${(h.err * 100).toFixed(1)}%${h.hitMax ? ',MAX' : ''})`).join('  '));
    }
  }
}

console.log('\n=== PART 2: calendar-window scan on the trigger TF ===');
for (const sym of Object.keys(SYMS)) {
  const cfg = SYMS[sym];
  console.log(`\n--- ${sym} ---`);
  console.log('TF   trig  prof     cur(1barTrig) | ' + DAYS.map(d => String(d).padStart(5)).join(''));
  for (const l of LADDER) {
    const prof = cfg.eng[l.name];
    if (prof === undefined) continue;
    const d = data[sym][l.trig];
    if (!d) { console.log(`${l.name.padEnd(4)} ${l.trig}    ${prof}   (no ${l.trig} series)`); continue; }
    const cur = atrShift1(d.tr, CUR_PER[l.name]);
    let line = `${l.name.padEnd(4)} ${String(l.trig).padStart(4)}  ${String(prof).padStart(7)}  ${(cur === null ? 'n/a' : (cur * cfg.pip).toFixed(1)).padStart(8)}   |`;
    for (const days of DAYS) {
      const { v, clamped } = atrWindow(d, Math.round(days * 1440 / l.trig));
      line += (v === null ? '  n/a' : (v * cfg.pip).toFixed(1) + (clamped ? '*' : '')).padStart(7);
    }
    console.log(line);
  }
  // score each window: worst relative error, and which rows are clamped by history
  const rows = [];
  for (const days of DAYS) {
    let worst = 0, worstAt = '', errs = [];
    for (const l of LADDER) {
      const prof = cfg.eng[l.name];
      if (prof === undefined) continue;
      const d = data[sym][l.trig];
      if (!d) continue;
      const { v, clamped } = atrWindow(d, Math.round(days * 1440 / l.trig));
      if (v === null) { errs.push('n/a'); continue; }
      const e = Math.abs(v * cfg.pip - prof) / prof;
      errs.push((e * 100).toFixed(0) + (clamped ? '*' : ''));
      if (!clamped && e > worst) { worst = e; worstAt = l.name; }
    }
    rows.push({ days, worst, worstAt, errs });
  }
  rows.sort((a, b) => a.worst - b.worst);
  console.log('window score (worst rel err; *=N>available bars, clamped by history):');
  for (const r of rows.slice(0, 8))
    console.log(`  ${String(r.days).padStart(4)}d worst=${(r.worst * 100).toFixed(1)}%@${r.worstAt} | M15..MN: ${r.errs.join(',')}`);
}
