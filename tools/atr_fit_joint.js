// Two-sample JOINT ATR search (2026-09-10): one formula must clear BOTH
// EURUSD (13:43) and NZDUSD (14:10) professor strips. Live Wilder p-legs
// only (5/10/21/66/132/264) — exact-minute, no .hst. PIPS already applied.
const LEGS = [5, 10, 21, 66, 132, 264];
const EU = { // [p5,p10,p21,p66,p132,p264] pips + prof strip TR
  M1:  { legs: [1.3, 1.3, 1.3, 1.1, 1.0, 0.9], p: 1 },
  M5:  { legs: [3.2, 2.8, 2.6, 2.1, 1.9, 2.1], p: 2 },
  M15: { legs: [4.9, 4.4, 3.5, 3.0, 4.0, 3.6], p: 4 },
  H1:  { legs: [5.6, 5.7, 7.8, 7.3, 7.9, 7.9], p: 8 },
  H4:  { legs: [15.4, 15.2, 14.6, 15.9, 16.3, 18.2], p: 16 },
  D1:  { legs: [39.7, 42.9, 44.2, 52.6, 61.2, 63.1], p: 54 },
  W1:  { legs: [97.7, 105.3, 121.8, 150.0, 159.5, 170.6], p: 143 },
  MN:  { legs: [261.8, 281.1, 347.3, 367.9, 370.4, 475.9], p: 353 },
};
const NZ = {
  M1:  { legs: [1.2, 1.1, 1.2, 1.0, 0.9, 0.9], p: 1 },
  M5:  { legs: [2.9, 2.5, 2.2, 2.0, 2.0, 2.1], p: 2 },
  M15: { legs: [4.5, 4.1, 3.8, 3.5, 3.8, 3.8], p: 4 },
  H1:  { legs: [8.1, 7.8, 7.7, 7.7, 8.1, 8.2], p: 8 },
  H4:  { legs: [14.8, 16.0, 16.2, 18.1, 17.0, 17.4], p: 17 },
  D1:  { legs: [43.6, 45.5, 45.5, 45.5, 52.9, 50.6], p: 47 },
  W1:  { legs: [92.0, 104.4, 114.9, 114.7, 119.8, 136.1], p: 115 },
  MN:  { legs: [239.2, 233.0, 244.2, 295.9, 304.2, null], p: 280 }, // p264 missing (<266 bars)
};
const TFS = Object.keys(EU);
// band-aware excess: 0 when inside prof integer band
const exc = (v, p) => (v === null ? Infinity : Math.max(0, Math.abs(v - p) - 0.5));
function score(fn) {
  let worst = 0, worstAt = '';
  const per = [];
  for (const s of [EU, NZ]) for (const tf of TFS) {
    const v = fn(s[tf].legs), e = exc(v, s[tf].p);
    per.push(e);
    if (e > worst) { worst = e; worstAt = tf; }
  }
  return { worst, worstAt, per };
}
const show = (name, fn) => {
  const r = score(fn);
  console.log(`${name}: worstExcess=${r.worst.toFixed(2)} at ${r.worstAt} | ` +
    r.per.map(e => e.toFixed(1)).join(','));
};
const mean = sub => legs => {
  let s = 0, n = 0;
  for (const i of sub) if (legs[i] !== null) { s += legs[i]; n++; }
  return n ? s / n : null;
};
const wavg = w => legs => {
  let s = 0, t = 0;
  for (let i = 0; i < 6; i++) if (legs[i] !== null) { s += legs[i] * w[i]; t += w[i]; }
  return t ? s / t : null;
};
console.log('--- 63 subsets (mean), joint 16-number band-excess ---');
{
  const rows = [];
  for (let mask = 1; mask < 64; mask++) {
    const sub = [];
    for (let i = 0; i < 6; i++) if (mask & (1 << i)) sub.push(i);
    const r = score(mean(sub));
    rows.push({ sub: sub.map(i => LEGS[i]).join(','), ...r });
  }
  rows.sort((a, b) => a.worst - b.worst);
  for (const r of rows.slice(0, 10))
    console.log(` [${r.sub}] worst=${r.worst.toFixed(2)}@${r.worstAt} | ` + r.per.map(e => e.toFixed(1)).join(','));
}
console.log('--- named candidates ---');
show('curW112358 ', wavg([1, 1, 2, 3, 5, 8]));
show('mean6       ', mean([0, 1, 2, 3, 4, 5]));
show('short521    ', mean([0, 1, 2]));
show('long66132264', mean([3, 4, 5]));
console.log('--- joint LSQ weights (16 equations, 6 unknowns) ---');
{
  const A = [], b = [];
  for (const s of [EU, NZ]) for (const tf of TFS) {
    A.push(s[tf].legs.map(v => (v === null ? 0 : v)));
    b.push(s[tf].p);
  }
  // zero-out columns of missing legs per row is approximated by 0-fill (MN p264 only)
  const AtA = Array.from({ length: 6 }, (_, i) => Array.from({ length: 6 }, (_, j) =>
    A.reduce((x, row) => x + row[i] * row[j], 0)));
  const Atb = Array.from({ length: 6 }, (_, i) => A.reduce((x, row, k) => x + row[i] * b[k], 0));
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
  const w = Array.from({ length: 6 }, (_, i) => M[i][6] / M[i][i]);
  console.log('optimal weights:', w.map(x => x.toFixed(3)).join(','));
  const r = score(wavg(w));
  console.log(`LSQ fit: worstExcess=${r.worst.toFixed(2)}@${r.worstAt} | ` + r.per.map(e => e.toFixed(1)).join(','));
}
console.log('\n=== ENG: structure base — universal-divisor interval proof ===');
// IF SL = round(TR_MN/D) for one universal D, D must lie in EVERY symbol's
// implied interval (TR/(SL+0.5), TR/(SL-0.5)]. Same for Eng-ratio form
// SL = round(1.2*TR/k). Empty intersection = no such rule exists.
const SB = [
  { sym: 'EUR', tr: 353, sl: 103 },
  { sym: 'NZD', tr: 280, sl: 80 },
  { sym: 'AUD', tr: 294, sl: 84 },
  { sym: 'XAU', tr: 3144, sl: 1180 },
];
for (const p of SB) {
  const dLo = p.tr / (p.sl + 0.5), dHi = p.tr / (p.sl - 0.5);
  const kLo = 1.2 * p.tr / (p.sl + 0.5), kHi = 1.2 * p.tr / (p.sl - 0.5);
  console.log(`${p.sym}: SL-divisor D in (${dLo.toFixed(4)},${dHi.toFixed(4)}] Eng-ratio k in (${kLo.toFixed(4)},${kHi.toFixed(4)}]`);
}
console.log('sqrt12=3.4641 sits in the EUR|(NZD,AUD) gap: no universal divisor, no universal ratio. XAU (2.66) is a third regime.');
console.log('\n=== ENG: chart-level (AUD live corner; EUR undetermined; NZD stale) ===');
const CB = [
  { sym: 'AUD', tr: 48, eng: 10, hunter: 27, note: 'live' },
  { sym: 'EUR', tr: 54, eng: 11, hunter: 30, note: 'undetermined' },
  { sym: 'NZD', tr: 47, eng: 11, hunter: 30, note: 'STALE-corner' },
];
for (const c of [
  ['TR/4.8(user-exact)', (tr) => tr / 4.8],
  ['TR/4.3333(usercalc)', (tr) => tr / 4.3333],
  ['TR*15/64        ', (tr) => tr * 15 / 64],
]) {
  const line = CB.map(p => {
    const e = c[1](p.tr), de = Math.round(e), dh = Math.round(8 / 3 * e);
    const ok = (de === p.eng && dh === p.hunter) ? 'OK ' : 'miss';
    return `${p.sym}[${p.note}]:eng=${e.toFixed(2)}->${de}(vs${p.eng}) hunter->${dh}(vs${p.hunter}) ${ok}`;
  }).join(' ');
  console.log(`${c[0]}: ${line}`);
}
{
  const line = CB.map(p => {
    const h = p.tr / 1.66666, dh = Math.round(h);
    return `${p.sym}:TR/1.667=${h.toFixed(2)}->${dh}(vs${p.hunter})`;
  }).join(' ');
  console.log(`TR/1.6667(user-calc): ${line}`);
}
