#!/usr/bin/env node
// Master-card parity table (P-TP4 follow-up, 2026-10-19).
//
// Feeds the master's own cards through OUR chain and prints the delta per leg,
// so "our numbers are not close" becomes a number instead of a feeling.
//
// Inputs:
//   MASTER  — the four EURUSD cards he showed (M5 / M15 / H1 / H4, Oct-2026),
//             verbatim: TRex, Trigger, Pricicle, Classic, then TP1..TP4.
//   OUR_ATR — our own strip row for the same symbol (EURUSD), read off OUR
//             indicator's card (the M1..MN1 line it draws).
//
// Chain mirrored from Biotak/TradePlanFormulas.mqh:
//   Eng = ATR/4.266666 | TRex=Eng | Trigger=8/3 Eng | Pricicle=5 Eng |
//   Classic=12 Eng | SL=1.2×Eng(structure ONE rung up, P-TP4-RUNG) |
//   TP = SL × (7/3, 5, 31/3, 30)
//
// Run: node tools/research/master_card_parity.js
'use strict';

const DIV = 4.266666;
const R  = Math.round;
const R1 = (x) => Math.round(x * 10) / 10;

const ORDER = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];

// our indicator's own row (EURUSD)
const OUR_ATR = { M1: 1.5, M5: 3.8, M15: 7.0, H1: 13.7, H4: 25.3, D1: 61.2, W1: 136.0, MN: 342.6 };

// the master's cards, as printed
const MASTER = {
  M5:  { legs: [1, 2, 4, 9],     tp: [5, 10, 20, 52] },
  M15: { legs: [2, 4, 8, 19],    tp: [10, 22, 45, 99] },
  H1:  { legs: [4, 10, 19, 45],  tp: [20, 43, 90, 260] },
  H4:  { legs: [7, 19, 36, 87],  tp: [31, 80, 190, 429] },
};

const rungUp = (tf, n) => {
  const i = ORDER.indexOf(tf);
  return ORDER[Math.min(i + n, ORDER.length - 1)];
};

const pct = (a, b) => (b === 0 ? '  -  ' : (a >= b ? '+' : '') + Math.round((a - b) / b * 100) + '%');
const pad = (v, w) => String(v).padStart(w);

const engOf = (tf) => OUR_ATR[tf] / DIV;

function ours(tf, up) {
  const e  = engOf(tf);
  const sl = 1.2 * engOf(rungUp(tf, up));
  return {
    legs: [R1(e), R1(e * 8 / 3), R(5 * e), R(12 * e)],
    tp:   [7 / 3, 5, 31 / 3, 30].map((k) => R(sl * k)),
    sl,
  };
}

function table(up, title) {
  console.log('\n' + title + '  (SL = 1.2 x Eng(' + up + ' rung(s) up))');
  console.log('  TF   | TRex      | Trigger   | Pricicle  | Classic   | TP1        TP2        TP3         TP4');
  for (const tf of Object.keys(MASTER)) {
    const o = ours(tf, up), m = MASTER[tf];
    const row = (a, b) => a.map((v, i) => pad(v, 4) + '(' + pct(v, b[i]).padStart(4) + ')').join(' ');
    console.log('  ' + tf.padEnd(4) + ' | ' + row(o.legs, m.legs) + ' | ' + row(o.tp, m.tp));
  }
  console.log('  (value = ours, (...) = delta vs his card)');
}

console.log('master cards: EURUSD M5/M15/H1/H4 (Oct-2026)   our ATR: EURUSD strip row');
table(1, 'AS SHIPPED  (P-TP4-RUNG)');
table(2, 'OLD RULE');

console.log('\nimplied master Eng, solved from each leg (5x / 12x / 8-3x):');
for (const tf of Object.keys(MASTER)) {
  const m = MASTER[tf];
  console.log('  ' + tf.padEnd(4) +
    ' pricicle/5=' + (m.legs[2] / 5).toFixed(2) +
    '  classic/12=' + (m.legs[3] / 12).toFixed(2) +
    '  trigger*3/8=' + (m.legs[1] * 3 / 8).toFixed(2) +
    '   ours=' + engOf(tf).toFixed(2) +
    '   his/ours=' + ((m.legs[3] / 12) / engOf(tf)).toFixed(2));
}

console.log('\nH4 self-check (his four TPs need one base):');
for (const k of [7 / 3, 5, 31 / 3, 30]) {
  console.log('  TP/' + k.toFixed(3) + ' -> SL ' + (MASTER.H4.tp[[7 / 3, 5, 31 / 3, 30].indexOf(k)] / k).toFixed(2));
}
console.log('  (four different bases = that card is not one plan)');
