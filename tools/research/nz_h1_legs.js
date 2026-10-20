// NZDUSD H1 legs, rebuilt from the FRESH M15 file (the H1 .hst is stale to
// 2026-09-10, the M15 one runs to 2026-10-19 09:30). Four M15 bars make one H1
// bar exactly: high = max, low = min, close = last. That gives the six composite
// legs at H1 without the terminal, so we can see WHICH leg pushes our 8.45 away
// from his 7.8.
//
// Run: node tools/research/nz_h1_legs.js
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];
const PIP = 0.0001;
const HIS = 7.8;            // his ATR row, NZDUSD H1, 2026-10-19 21:43/22:12
const OURS = 8.45;          // our card's Eng 1.99 x 4.266666

function parseHST(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    out[i] = { time: buf.readUInt32LE(o), high: buf.readDoubleLE(o + 16), low: buf.readDoubleLE(o + 24), close: buf.readDoubleLE(o + 32) };
  }
  return out;
}

// aggregate M15 -> H1 on the hour boundary
function toH1(m15) {
  const out = [];
  for (let i = 0; i < m15.length; i += 4) {
    const g = m15.slice(i, i + 4);
    if (g.length === 0) break;
    out.push({
      time: g[0].time,
      high: Math.max(...g.map((b) => b.high)),
      low: Math.min(...g.map((b) => b.low)),
      close: g[g.length - 1].close,
    });
  }
  return out;
}

const h1 = toH1(parseHST('NZDUSD15.hst'));
console.log('NZDUSD H1 rebuilt from M15:', h1.length, 'bars, last', new Date(h1[h1.length - 1].time * 1000).toISOString().slice(0, 16).replace('T', ' '));

function smaLeg(bars, anchor, period) {
  let sum = 0;
  for (let i = 0; i < period; i++) {
    const j = anchor - i;
    if (j < 1) return null;
    const h = bars[j].high, l = bars[j].low;
    const cPrev = (i === 0) ? bars[j].close : bars[j - 1].close;
    sum += Math.max(h - l, Math.abs(h - cPrev), Math.abs(l - cPrev));
  }
  return sum / period;
}

const anchor = h1.length - 2;   // shift 1
const legs = PERIODS.map((p) => smaLeg(h1, anchor, p) / PIP);
console.log('anchor bar:', new Date(h1[anchor].time * 1000).toISOString().slice(0, 16).replace('T', ' '));
console.log('  leg  |   pips  | vs his 7.8 | weight');
PERIODS.forEach((p, i) => {
  console.log('  n' + String(p).padEnd(4) + '| ' + legs[i].toFixed(2).padStart(7) + ' | ' +
    (((legs[i] - HIS) / HIS * 100).toFixed(0) + '%').padStart(10) + ' | ' + WEIGHTS[i]);
});
const blend = (w) => { let s = 0, t = 0; w.forEach((k, i) => { s += legs[i] * k; t += k; }); return s / t; };
const show = (name, w) => {
  const v = blend(w);
  console.log('  ' + name.padEnd(26) + v.toFixed(2) + '   ' + (((v - HIS) / HIS * 100).toFixed(1) + '%').padStart(6));
};
console.log('');
show('6-leg 1/1/2/3/5/8 (shipped)', WEIGHTS);
show('5-leg 1/1/2/3/5', [1, 1, 2, 3, 5]);
show('4-leg 1/1/2/3', [1, 1, 2, 3]);
show('3-leg 1/1/2', [1, 1, 2]);
console.log('');
console.log('  our card implies ' + OURS.toFixed(2) + ' at 22:12; his row says ' + HIS + ';');
console.log('  this rebuild is anchored at the M15 file edge, so read the SHAPE, not the level.');
