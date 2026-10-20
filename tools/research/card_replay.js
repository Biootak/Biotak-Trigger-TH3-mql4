// CARD REPLAY — find the minute his card was drawn, then read OUR card at that
// same minute.
//
// Every comparison so far mixed two clocks: his card was captured at some
// moment, ours at another, and the ATR composite moves between them. That
// makes a formula error and a timing difference look identical. This removes
// the timing: it sweeps the whole history, scores our 8-rung ATR row against
// HIS row at every anchor, and prints OUR card at the anchors where the two
// rows agree. If our card then equals his card, the chain is right and the
// gap was the clock. If it does not, the chain is wrong and we can see where.
//
// Run: node tools/research/card_replay.js [XAUUSD|EURUSD] [H1|H4|M15|M5]
'use strict';
const fs = require('fs');
const path = require('path');

const HIST = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const ORDER = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];
const DIV = 4.266666;
const TP_K = [7 / 3, 5, 31 / 3, 30];
const LEG_K = [1, 8 / 3, 5, 12];
const PIP = { XAUUSD: 0.1, EURUSD: 0.0001 };

const HIS = {
  XAUUSD: {
    row: { M1: 11, M5: 32, M15: 62, H1: 133, H4: 288, D1: 991, W1: 1925, MN: 3139 },
    card: { tf: 'H4', legs: [7, 19, 36, 87], tp: [31, 80, 190, 429] },
  },
  EURUSD: {
    row: { M1: 2, M5: 4, M15: 8, H1: 16, H4: 31, D1: 75, W1: 198, MN: 411 },
    card: { tf: 'H1', legs: [4, 10, 19, 45], tp: [20, 43, 90, 260] },
  },
};

const sym = (process.argv[2] || 'XAUUSD').toUpperCase();
const pip = PIP[sym];
const his = HIS[sym];

function parseHST(file) {
  const buf = fs.readFileSync(path.join(HIST, file));
  const HDR = 148, REC = 60;
  const n = Math.floor((buf.length - HDR) / REC);
  const bars = new Array(n);
  for (let i = 0; i < n; i++) {
    const o = i * REC + HDR;
    bars[i] = {
      time: buf.readUInt32LE(o),
      high: buf.readDoubleLE(o + 16),
      low: buf.readDoubleLE(o + 24),
      close: buf.readDoubleLE(o + 32),
    };
  }
  return bars;
}

const data = {};
for (const tf of ORDER) {
  try { data[tf] = parseHST(sym + MIN[tf] + '.hst'); } catch (e) { data[tf] = null; }
}

// index of the last bar that has CLOSED by wall-clock time `t`
function lastClosedIdx(bars, tf, t) {
  const dur = MIN[tf] * 60;
  let lo = 0, hi = bars.length - 1, best = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (bars[mid].time + dur <= t) { best = mid; lo = mid + 1; } else { hi = mid - 1; }
  }
  return best;
}

// one leg = mean TR over `period` bars ending at `anchor` (the indicator's
// TrexSMALeg at shift 1; the newest bar's TR uses its OWN close — the quirk)
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

function compositeAt(tf, t) {
  const bars = data[tf];
  if (!bars) return 0;
  const anchor = lastClosedIdx(bars, tf, t);
  if (anchor < 1) return 0;
  let s = 0, w = 0;
  for (let i = 0; i < 6; i++) {
    const v = smaLeg(bars, anchor, PERIODS[i]);
    if (v !== null && v > 0) { s += v * WEIGHTS[i]; w += WEIGHTS[i]; }
  }
  return w ? s / w : 0;
}

const R = Math.round, R1 = (x) => Math.round(x * 10) / 10;
const pad = (v, w) => String(v).padStart(w);

function rowAt(t) {
  const r = {};
  for (const tf of ORDER) r[tf] = compositeAt(tf, t) / pip;
  return r;
}

// relative error of our row against his row (rungs he prints, M1 excluded —
// it is one bar wide and pure noise on both sides)
function rowError(r) {
  let sum = 0, n = 0;
  for (const tf of ORDER) {
    if (tf === 'M1' || !(r[tf] > 0)) continue;
    sum += Math.abs(r[tf] - his.row[tf]) / his.row[tf];
    n++;
  }
  return n ? sum / n : 1;
}

function cardAt(t) {
  const r = rowAt(t);
  const i = ORDER.indexOf(his.card.tf);
  const eng = r[his.card.tf] / DIV;
  const sTf = ORDER[Math.min(i + 1, ORDER.length - 1)];
  const sl = 1.2 * (r[sTf] / DIV);
  return {
    t, r,
    legs: [R1(eng), R1(8 * eng / 3), R(5 * eng), R(12 * eng)],
    sl: R(sl),
    tp: TP_K.map((k) => R(sl * k)),
  };
}

// --- sweep: every H1 bar close, but only inside the window where EVERY rung
// has history. The fast .hst files are short (M1 ~46 days, M5 ~76), so an
// anchor older than that silently scores a row with rungs missing — which is
// how an April anchor once "won" while having no M5 at all.
const h1 = data.H1;
if (!h1) { console.log('no H1 history'); process.exit(1); }
const commonStart = Math.max(...ORDER.filter((tf) => data[tf]).map((tf) => data[tf][0].time));
const need = Math.max(...PERIODS) + 2;   // the 264 leg must fit
const scored = [];
let firstIdx = 0;
while (firstIdx < h1.length && h1[firstIdx].time < commonStart) firstIdx++;
firstIdx += need;
for (let i = firstIdx; i < h1.length; i++) {
  const t = h1[i].time + MIN.H1 * 60;      // just after that H1 bar closed
  const r = rowAt(t);
  if (!r.H4 || !r.M5 || !r.M15 || !r.D1) continue;   // every rung must exist
  scored.push({ t, err: rowError(r) });
}
scored.sort((a, b) => a.err - b.err);

console.log(`=== ${sym} — replay: our row vs his row, best of ${scored.length} anchors ===`);
console.log(`    common window starts ${new Date(commonStart * 1000).toISOString().slice(0, 10)} (shortest .hst wins)`);
console.log(`    his row: ${ORDER.map((tf) => tf + ' ' + his.row[tf]).join('  ')}`);
console.log(`    his card (${his.card.tf}): TRex ${his.card.legs[0]}  Trigger ${his.card.legs[1]}  Pricicle ${his.card.legs[2]}  Classic ${his.card.legs[3]}   TP ${his.card.tp.join(' / ')}`);
console.log('');
console.log('  rank |      when      | row err |    our row (M5..MN)                    | card legs            | SL  TP1..TP4');

const picks = [0, 1, 2, 3, 4];
for (const k of picks) {
  const s = scored[k];
  if (!s) continue;
  const c = cardAt(s.t);
  const when = new Date(s.t * 1000).toISOString().slice(0, 16).replace('T', ' ');
  const rowStr = ['M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'].map((tf) => pad(Math.round(c.r[tf]), 4)).join(' ');
  const legStr = c.legs.map((v) => pad(v, 5)).join(' ');
  console.log('  ' + pad(k + 1, 4) + ' | ' + when + ' | ' + pad((s.err * 100).toFixed(1) + '%', 7) + ' | ' + rowStr + ' | ' + legStr + ' | ' + pad(c.sl, 3) + ' ' + c.tp.map((v) => pad(v, 5)).join(' '));
}

// --- how close does the card get, per leg, at the single best anchor? -------
const best = cardAt(scored[0].t);
console.log('');
console.log(`=== card at the best-matching anchor (${new Date(scored[0].t * 1000).toISOString().slice(0, 16).replace('T', ' ')}) ===`);
const names = ['TRex', 'Trigger', 'Pricicle', 'Classic'];
for (let i = 0; i < 4; i++) {
  const o = best.legs[i], h = his.card.legs[i];
  console.log('  ' + names[i].padEnd(9) + ' ours ' + pad(o, 6) + '   his ' + pad(h, 4) + '   ' +
    pad(((h / o - 1) * 100).toFixed(1) + '%', 7));
}
for (let i = 0; i < 4; i++) {
  const o = best.tp[i], h = his.card.tp[i];
  console.log('  TP' + (i + 1) + '       ours ' + pad(o, 6) + '   his ' + pad(h, 4) + '   ' +
    pad(((h / o - 1) * 100).toFixed(1) + '%', 7));
}

// --- and: over the whole sweep, is there ANY anchor where the legs match? ---
console.log('');
console.log('=== does any anchor reproduce his four legs? (|err| < 5% on all four) ===');
let hits = 0, bestLeg = null, bestLegErr = 1e9;
for (let i = firstIdx; i < h1.length; i++) {
  const t = h1[i].time + MIN.H1 * 60;
  const c = cardAt(t);
  if (!c.r[his.card.tf]) continue;
  let worst = 0;
  for (let k = 0; k < 4; k++) {
    const h = his.card.legs[k], o = c.legs[k];
    if (!o) { worst = 1e9; break; }
    worst = Math.max(worst, Math.abs(h / o - 1));
  }
  if (worst < 0.05) hits++;
  if (worst < bestLegErr) { bestLegErr = worst; bestLeg = c; }
}
console.log(`  anchors with all four legs within 5%: ${hits}`);
if (bestLeg) {
  console.log(`  closest anchor: ${new Date(bestLeg.t * 1000).toISOString().slice(0, 16).replace('T', ' ')}  worst leg error ${(bestLegErr * 100).toFixed(1)}%`);
  console.log(`    ours ${bestLeg.legs.join(' / ')}   his ${his.card.legs.join(' / ')}`);
}
