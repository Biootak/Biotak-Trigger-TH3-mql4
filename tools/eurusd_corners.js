// Full trade-plan block reproduction for EURUSD low-TF professor corners.
// The #SL/-TP row in his screenshots shows the LEVEL VALUES (pips), and the
// StrBond legs pin slTrue tightly, so his ENTIRE block is reconstructible:
//   M1  chart @2026-08-14 14:09:27 : Eng=0 Hunt=1 SL=2 TP1=4 TP2=9 TP3=18 SB=4--19
//   M5  chart @2026-08-17 09:19:34 : Eng=1 Hunt=2 SL=3 TP1=7 TP2=16 TP3=32 SB=7--33
//   M15 chart @2026-08-17 09:19:40 : Eng=1 Hunt=4 SL=5 TP1=13 TP2=27 TP3=57 SB=12--58
const fs = require('fs');
const path = require('path');

const histDir = String.raw`C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\history\AMarkets-Demo`;
const PIPS = 10000;
const tfFiles = {
  M1: 'EURUSD1.hst', M5: 'EURUSD5.hst', M15: 'EURUSD15.hst',
  H1: 'EURUSD60.hst', H4: 'EURUSD240.hst', D1: 'EURUSD1440.hst',
  W1: 'EURUSD10080.hst', MN: 'EURUSD43200.hst',
};
const LEGS = [5, 10, 21, 66, 132, 264], W = [1, 1, 2, 3, 5, 8];
const ENG_D = 4.266666;

function parseHST(file) {
  const full = path.join(histDir, file);
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
  return bars;
}
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
function wilderAtShift1(tr, period) {
  const n = tr.length, end = n - 1, last = end - 1;
  if (last < period) return null;
  let atr = 0;
  for (let i = 1; i <= period; i++) atr += tr[i];
  atr /= period;
  for (let i = period + 1; i <= last; i++) atr = (atr * (period - 1) + tr[i]) / period;
  return atr;
}
function asOf(bars, T) {
  let i = bars.length - 1;
  while (i >= 0 && bars[i].time > T) i--;
  if (i < 1) throw new Error('not enough history before ' + new Date(T * 1000).toISOString());
  return bars.slice(0, i + 1);
}
// our composite TR in pips for a TF at time T
function ourTR(tf, T) {
  const bars = asOf(data[tf], T);
  const tr = trueRanges(bars);
  const wf = (t, p) => wilderAtShift1(tr, p);
  let v;
  if (tf === 'W1') v = wilderAtShift1(tr, 55);
  else if (tf === 'MN') v = wilderAtShift1(tr, 30);
  else {
    let ws = 0, tw = 0;
    for (let i = 0; i < LEGS.length; i++) {
      const x = wf(tf, LEGS[i]);
      if (x !== null && x > 0) { ws += x * W[i]; tw += W[i]; }
    }
    v = tw > 0 ? ws / tw : null;
  }
  return v === null ? null : v * PIPS;
}

const data = {};
for (const tf of Object.keys(tfFiles)) {
  const bars = parseHST(tfFiles[tf]);
  while (bars.length && !(bars[bars.length - 1].high >= bars[bars.length - 1].low)) bars.pop();
  data[tf] = bars;
}

// corners: chart TF -> (moment, structure TF, his block)
const corners = {
  M1:  { T: Date.UTC(2026, 7, 14, 14, 9, 27) / 1000, str: 'M15', his: { eng: 0, hunt: 1, sl: 2, tp1: 4, tp2: 9, tp3: 18, sb1: 4, sb2: 19 } },
  M5:  { T: Date.UTC(2026, 7, 17, 9, 19, 34) / 1000, str: 'H1',  his: { eng: 1, hunt: 2, sl: 3, tp1: 7, tp2: 16, tp3: 32, sb1: 7, sb2: 33 } },
  M15: { T: Date.UTC(2026, 7, 17, 9, 19, 40) / 1000, str: 'H4',  his: { eng: 1, hunt: 4, sl: 5, tp1: 13, tp2: 27, tp3: 57, sb1: 12, sb2: 58 } },
};

console.log('=== OUR full block at professor corner moments (d=4.266666) ===');
for (const tf of Object.keys(corners)) {
  const { T, str, his } = corners[tf];
  const tStr = new Date(T * 1000).toISOString().replace('T', ' ').slice(0, 16) + 'Z';
  const trOwn = ourTR(tf, T);
  const trStr = ourTR(str, T);
  const engOwn = trOwn === null ? null : trOwn / ENG_D;
  const engStr = trStr === null ? null : trStr / ENG_D;
  const slTrue = engStr === null ? null : 1.2 * engStr;
  const r = Math.round;
  const out = {
    Eng: engOwn === null ? 'n/a' : r(engOwn),
    Hunter: engOwn === null ? 'n/a' : r(8 / 3 * engOwn),
    SL: slTrue === null ? 'n/a' : r(slTrue),
    TP1: slTrue === null ? 'n/a' : r(slTrue * 7 / 3),
    TP2: slTrue === null ? 'n/a' : r(slTrue * 5),
    TP3: slTrue === null ? 'n/a' : r(slTrue * 31 / 3),
    SB1: slTrue === null ? 'n/a' : r(slTrue * 20 / 9),
    SB2: slTrue === null ? 'n/a' : r(slTrue * 95 / 9),
  };
  const mk = (k) => out[k] === his[k] ? 'OK' : 'XX';
  console.log(`${tf} @${tStr}  TRown=${trOwn === null ? 'n/a' : trOwn.toFixed(2)} TR(${str})=${trStr === null ? 'n/a' : trStr.toFixed(2)}`);
  console.log(`  ours : Eng=${out.Eng}(${mk('Eng')}) Hunt=${out.Hunter}(${mk('Hunter')}) SL=${out.SL}(${mk('SL')}) TP1=${out.TP1} TP2=${out.TP2} TP3=${out.TP3} SB=${out.SB1}--${out.SB2}`);
  console.log(`  his  : Eng=${his.eng} Hunt=${his.hunt} SL=${his.sl} TP1=${his.tp1} TP2=${his.tp2} TP3=${his.tp3} SB=${his.sb1}--${his.sb2}`);
  // what divisor would his SL block imply for OUR composite?
  if (slTrue !== null && trStr !== null) {
    const engImpl = his.sl / 1.2;             // approx
    console.log(`  implied: his SL=${his.sl} -> Eng(${str})~${(slTrue / 1.2).toFixed(3)}; d(ourTR)=${(trStr / (slTrue / 1.2)).toFixed(3)}`);
  }
}

console.log('\n=== Our live strip (last .hst bar) vs professor LIVE panel TR (Sep 10 21:19) ===');
{
  const panelTR = { M1: 1, M5: 3, M15: 5, H1: 9, H4: 17, D1: 54, W1: 143, MN: 353 };
  for (const tf of Object.keys(tfFiles)) {
    const bars = data[tf];
    const last = new Date(bars[bars.length - 1].time * 1000).toISOString();
    const tr = trueRanges(bars);
    const wf = (t, p) => wilderAtShift1(tr, p);
    let v;
    if (tf === 'W1') v = wilderAtShift1(tr, 55);
    else if (tf === 'MN') v = wilderAtShift1(tr, 30);
    else {
      let ws = 0, tw = 0;
      for (let i = 0; i < LEGS.length; i++) {
        const x = wf(tf, LEGS[i]);
        if (x !== null && x > 0) { ws += x * W[i]; tw += W[i]; }
      }
      v = tw > 0 ? ws / tw : null;
    }
    const p = v === null ? null : v * PIPS;
    console.log(`${tf}: ourLive=${p === null ? 'n/a' : p.toFixed(2)} panel=${panelTR[tf]} d=${p === null ? 'n/a' : (p - panelTR[tf]).toFixed(2)}  lastBar=${last}`);
  }
}

console.log('\n=== What single divisor fits his structure chain (his own panel TR as proxy)? ===');
{
  // his Eng implied by SL block: Eng(str) = slTrue/1.2 ; his panel TR(str) live
  const rows = [
    { tf: 'M1',  str: 'M15', sl: 2,  tr: 5  },
    { tf: 'M5',  str: 'H1',  sl: 3,  tr: 9  },
    { tf: 'M15', str: 'H4',  sl: 5,  tr: 17 },
  ];
  for (const r of rows) {
    const slTrue = r.sl / 1.0; // displayed SL ≈ slTrue
    const engStr = slTrue / 1.2;
    console.log(`${r.tf}: Eng(${r.str})=${engStr.toFixed(3)}  TRpanel=${r.tr} -> d=${(r.tr / engStr).toFixed(3)}`);
  }
}