// Full synthetic CARD for every rung of the ladder, straight off the .hst —
// the same arithmetic the indicator runs, with nothing frozen and nothing live.
//
// Why this exists: comparing a LIVE card to the master's card mixes two things —
// the formula and the moment. This prints the formula alone, so a mismatch is
// either a formula error (all rungs move together) or a timing difference (one
// rung is off). Run it before touching any constant.
//
// Chain (Biotak/TradePlanFormulas.mqh):
//   TR   = weighted SMA-of-TR, periods 5/10/21/66/132/264, weights 1/1/2/3/5/8, shift 1
//   Eng  = TR / 4.266666
//   legs = 1x, 8/3x, 5x, 12x  (TRex, Trigger, Pricicle, Classic)
//   SL   = 1.20 x Eng(structure = ONE rung up)      [P-TP4-RUNG]
//   TP   = SL x 7/3, 5, 31/3, 30
//
// Run: node tools/research/card_probe.js [XAUUSD|EURUSD]
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const ORDER = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];
const DIV = 4.266666;
const SL_COEFF = 1.20;
const TP_K = [7 / 3, 5, 31 / 3, 30];
const LEG_K = [1, 8 / 3, 5, 12];

const PIP = { XAUUSD: 0.1, EURUSD: 0.0001 };
const sym = (process.argv[2] || 'XAUUSD').toUpperCase();

function parseHST(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const bars = [];
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    bars.push({
      time: buf.readUInt32LE(o),          // MT4 .hst: time @0, open @8, high @16, low @24, close @32
      high: buf.readDoubleLE(o + 16),
      low: buf.readDoubleLE(o + 24),
      close: buf.readDoubleLE(o + 32),
    });
  }
  return bars;
}

// mean TR over `period` bars ending at shift 1 — the indicator's TrexSMALeg
function smaLeg(bars, period, shift) {
  const n = bars.length;
  let sum = 0;
  for (let i = 0; i < period; i++) {
    const idx = n - 1 - shift - i;
    if (idx < 1) return null;
    const h = bars[idx].high, l = bars[idx].low;
    const cPrev = (i === 0) ? bars[idx].close : bars[idx - 1].close;
    sum += Math.max(h - l, Math.abs(h - cPrev), Math.abs(l - cPrev));
  }
  return sum / period;
}

function composite(bars, shift) {
  let s = 0, w = 0;
  PERIODS.forEach((p, i) => {
    const v = smaLeg(bars, p, shift);
    if (v !== null && v > 0) { s += v * WEIGHTS[i]; w += WEIGHTS[i]; }
  });
  return w ? s / w : 0;
}

const R = Math.round;
const R1 = (x) => Math.round(x * 10) / 10;
const pad = (v, w) => String(v).padStart(w);

const pip = PIP[sym] || 0.0001;
const tr = {};
for (const tf of ORDER) {
  try {
    const bars = parseHST(sym + MIN[tf] + '.hst');
    tr[tf] = { bars, tr: composite(bars, 1) / pip, last: bars[bars.length - 1] };
  } catch (e) {
    tr[tf] = null;
  }
}

const head = tr[ORDER[0]] ? tr[ORDER[0]].last : null;
console.log(`=== ${sym} — synthetic card per rung (shift 1, nothing frozen) ===`);
if (head) console.log(`    last bar: ${new Date(head.time * 1000).toISOString().slice(0, 16).replace('T', ' ')}  close=${head.close}`);
console.log('  TF  |    TR   |  Eng   | TRex    Trigger  Pricicle  Classic |  SL   TP1   TP2   TP3   TP4 | struct');
console.log('  ' + '-'.repeat(96));

for (let i = 0; i < ORDER.length; i++) {
  const tf = ORDER[i];
  if (!tr[tf]) { console.log('  ' + tf.padEnd(4) + '|  no .hst'); continue; }
  const engTrue = tr[tf].tr / DIV;
  const sIdx = Math.min(i + 1, ORDER.length - 1);
  const sTf = ORDER[sIdx];
  const engStr = tr[sTf] ? tr[sTf].tr / DIV : 0;
  const slTrue = SL_COEFF * engStr;
  const legs = LEG_K.map((k) => R1(k * engTrue));
  const legsInt = [legs[0], legs[1], R(5 * engTrue), R(12 * engTrue)];
  const tps = TP_K.map((k) => R(slTrue * k));
  console.log(
    '  ' + tf.padEnd(4) + '| ' + pad(tr[tf].tr.toFixed(1), 7) + ' | ' + pad(engTrue.toFixed(2), 6) +
    ' | ' + pad(legs[0], 6) + ' ' + pad(legs[1], 8) + ' ' + pad(legsInt[2], 9) + ' ' + pad(legsInt[3], 8) +
    ' | ' + pad(R(slTrue), 4) + ' ' + tps.map((v) => pad(v, 5)).join(' ') +
    ' | ' + sTf
  );
}

// Side by side with the master's cards, when we have them for this symbol.
const HIS = {
  EURUSD: {
    M5: { legs: [1, 2, 4, 9], tp: [5, 10, 20, 52] },
    M15: { legs: [2, 4, 8, 19], tp: [10, 22, 45, 99] },
    H1: { legs: [4, 10, 19, 45], tp: [20, 43, 90, 260] },
    H4: { legs: [7, 19, 36, 87], tp: [31, 80, 190, 429] },
  },
  XAUUSD: {
    H4: { legs: [7, 19, 36, 87], tp: [31, 80, 190, 429] },
  },
}[sym];

if (HIS) {
  console.log(`\n=== ${sym} — his card vs ours (ratio > 1 means he is bigger) ===`);
  console.log('  TF  |        TRex        Trigger        Pricicle        Classic        |  Eng ratio');
  for (const tf of Object.keys(HIS)) {
    if (!tr[tf]) continue;
    const e = tr[tf].tr / DIV;
    const ours = [R1(e), R1(8 * e / 3), R(5 * e), R(12 * e)];
    const his = HIS[tf].legs;
    const cells = ours.map((v, k) => pad(v, 4) + ' vs ' + pad(his[k], 3) + ' ' +
      pad((his[k] / v).toFixed(2) + 'x', 6));
    console.log('  ' + tf.padEnd(4) + '| ' + cells.join(' | ') + ' | ' + (his[3] / 12 / e).toFixed(2) + 'x');
  }
}
