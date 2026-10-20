// HISTORY DEPTH AUDIT — does each rung actually have the bars its composite
// needs?
//
// The composite silently DROPS a leg whose window does not fit the available
// history (`if(nb <= periods[i] + sh) continue;` in ATR_A.mqh). Dropping the
// 264 leg removes weight 8 of 20 — a 40% reweight — so on a short history the
// slow rungs quietly become a different average. This prints, per rung, how
// many bars we have against what each of the six legs needs.
//
// Run: node tools/research/hist_depth.js [XAUUSD|EURUSD]
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const ORDER = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];
const sym = (process.argv[2] || 'XAUUSD').toUpperCase();

function bars(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const out = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    out.push({ time: buf.readUInt32LE(o), high: buf.readDoubleLE(o + 16), low: buf.readDoubleLE(o + 24), close: buf.readDoubleLE(o + 32) });
  }
  return out;
}

console.log(`=== ${sym} — history depth vs the six composite legs (shift 1) ===`);
console.log('  TF  |  bars  | span (days) |  5  10  21  66 132 264 | legs live | weight used');
for (const tf of ORDER) {
  let b;
  try { b = bars(sym + MIN[tf] + '.hst'); } catch (e) { console.log('  ' + tf.padEnd(4) + '| no file'); continue; }
  const n = b.length;
  const days = ((b[n - 1].time - b[0].time) / 86400).toFixed(0);
  const ok = PERIODS.map((p) => n > p + 1);
  const used = PERIODS.reduce((a, p, i) => a + (ok[i] ? WEIGHTS[i] : 0), 0);
  const live = ok.filter(Boolean).length;
  console.log('  ' + tf.padEnd(4) + '| ' + String(n).padStart(6) + ' | ' + String(days).padStart(11) + ' | ' +
    ok.map((v) => (v ? ' ok' : ' --')).join('') + ' | ' + String(live).padStart(9) + ' | ' +
    String(used).padStart(3) + '/20' + (used < 20 ? '   <-- LEGS DROPPED' : ''));
}
