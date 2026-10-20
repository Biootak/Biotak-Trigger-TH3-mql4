#!/usr/bin/env node
// P-TP4-PROOF: re-derive the whole trade card from a terminal dump log, in node,
// with no MQL and no terminal. If the numbers this prints match the card on the
// chart, then the card is a pure function of the six raw ATR legs and nothing
// else is in play. Usage:
//   node log_verify.js <path-to-tradeplan-auto-SYM.log>
// The log is written by the indicator's own dump (key X) and carries the six
// iATR legs for every timeframe, so nothing here has to be guessed.

const fs = require('fs');

const ENG_DIV = 4.266666;
const W = [1, 1, 2, 3, 5, 8];
const P = [5, 10, 21, 66, 132, 264];
const RUNGS = [1, 5, 15, 30, 60, 240, 1440, 10080, 43200];
const NAME = { 1: 'M1', 5: 'M5', 15: 'M15', 30: 'M30', 60: 'H1', 240: 'H4', 1440: 'D1', 10080: 'W1', 43200: 'MN' };

const round = x => Math.round(x);              // TradePlanRound
const round1 = x => Math.round(x * 10) / 10;   // TradePlanRound1

const path = process.argv[2];
if (!path) { console.error('usage: node log_verify.js <log>'); process.exit(1); }
const raw = fs.readFileSync(path, 'utf8').replace(/\r/g, '');
const lines = raw.split('\n');

// ---- pip size and eng divisor come from the SNAP header -------------------
const snapHdr = lines.find(l => l.startsWith('[SNAP] ====='));
const pipSize = Number((snapHdr.match(/pipSize=([\d.]+)/) || [])[1]);

// ---- chart timeframe from the TRADEPLAN header ---------------------------
const tp = lines.find(l => l.startsWith('[TRADEPLAN] ') && /\d{4}\.\d\d\.\d\d/.test(l));
const tpTok = tp.split(/\s+/);
const symbol = tpTok[1];
const chartName = tpTok[2];
const chartMin = RUNGS.find(m => NAME[m] === chartName);

// ---- the six raw legs, per timeframe, in PIPS ----------------------------
const legs = {};
for (const l of lines) {
  const m = l.match(/^\[ATRLEGS\] TF=(\w+) bars=(\d+)(.*)$/);
  if (!m) continue;
  const tf = m[1];
  const body = m[3];
  const v = {};
  for (const k of P) {
    const g = body.match(new RegExp(' p' + k + '=([-\\d.]+)'));
    if (g) v[k] = Number(g[1]) / pipSize;
  }
  legs[tf] = v;
}

// ---- ATRWeightedComposite: weight over the legs that are non-zero --------
function composite(tf) {
  const v = legs[tf];
  if (!v) return null;
  let sum = 0, wsum = 0, used = [];
  for (let i = 0; i < 6; i++) {
    const a = v[P[i]];
    if (a && Math.abs(a) > 1e-12) { sum += a * W[i]; wsum += W[i]; used.push(P[i]); }
  }
  if (wsum === 0) return null;
  return { value: sum / wsum, used, legs: v };
}

// ---- the card, exactly as TradePlanFormulas.mqh builds it ----------------
function card(chartMin, rungsDown, rungsUp) {
  const idx = RUNGS.indexOf(chartMin);
  const trigMin = RUNGS[Math.max(0, idx - rungsDown)];
  const strMin = RUNGS[Math.min(RUNGS.length - 1, idx + rungsUp)];
  const own = composite(NAME[chartMin]);
  const str = composite(NAME[strMin]);
  if (!own || !str) return null;

  const engTrue = own.value / ENG_DIV;
  const slTrue = 1.20 * (str.value / ENG_DIV);

  return {
    trigMin, strMin,
    atrOwn: own.value, atrStr: str.value,
    engTrue, slTrue,
    eng: round1(engTrue),
    hunter: round1(8 * engTrue / 3),
    pricicle: round(5 * engTrue),
    classic: round(12 * engTrue),
    sl: round(slTrue),
    tp1: round(slTrue * 7 / 3),
    tp2: round(slTrue * 5),
    tp3: round(slTrue * 31 / 3),
    tp4: round(slTrue * 30),
  };
}

const f = (x, d = 4) => x.toFixed(d);
console.log('='.repeat(72));
console.log(`LOG     ${path}`);
console.log(`SYMBOL  ${symbol}   chart ${chartName} (${chartMin}m)   pip ${pipSize}`);
console.log('='.repeat(72));

console.log('\n-- ATR composite rebuilt from the six raw legs (pips) --');
for (const m of RUNGS) {
  const c = composite(NAME[m]);
  if (!c) continue;
  const shown = P.map(k => k + '=' + f(legs[NAME[m]][k], 2)).join('  ');
  console.log(`${NAME[m].padEnd(4)} ${shown}   -> composite ${f(c.value, 3)}`);
}

for (const [down, up] of [[2, 1], [1, 1], [2, 2]]) {
  const c = card(chartMin, down, up);
  if (!c) continue;
  console.log(`\n-- card: trigger ${NAME[c.trigMin]}, structure ${NAME[c.strMin]} (${down} down / ${up} up) --`);
  console.log(`ATR own ${f(c.atrOwn, 3)}   ATR struct ${f(c.atrStr, 3)}`);
  console.log(`engTrue ${f(c.engTrue, 4)}   slTrue ${f(c.slTrue, 4)}`);
  console.log(`TRex ${c.eng}   Trigger ${c.hunter}   Pricicle ${c.pricicle}   Classic ${c.classic}`);
  console.log(`SL ${c.sl}   TP1 ${c.tp1}   TP2 ${c.tp2}   TP3 ${c.tp3}   TP4 ${c.tp4}`);
}

// ---- optional: score against the professor's card -----------------------
// His card shows EIGHT cells: four legs and four targets. `sl` is engine state
// only - it is never drawn, so it is not in this table.
const HIS = {
  NZDUSD: { eng: 1.8, hunter: 4.9, pricicle: 9, classic: 22, tp1: 11, tp2: 25, tp3: 51, tp4: 148, atrOwn: 7.8, atrStr: 17.5 },
};
if (HIS[symbol]) {
  const h = HIS[symbol];
  const c = card(chartMin, 2, 1);
  const keys = ['eng', 'hunter', 'pricicle', 'classic', 'tp1', 'tp2', 'tp3', 'tp4'];
  console.log('\n-- vs the professor --');
  let ok = 0;
  for (const k of keys) {
    const hit = Math.abs(c[k] - h[k]) < 1e-9;
    if (hit) ok++;
    console.log(`  ${k.padEnd(9)} ours ${String(c[k]).padStart(4)}   his ${String(h[k]).padStart(4)}   ${hit ? 'EXACT' : 'DIFF'}`);
  }
  console.log(`  ATR H1   ours ${f(c.atrOwn, 3)}   his ${f(h.atrOwn, 1)}`);
  console.log(`  ATR H4   ours ${f(c.atrStr, 3)}   his ${f(h.atrStr, 1)}`);
  console.log(`\n  ${ok}/${keys.length} cells exact`);
}
console.log('');
