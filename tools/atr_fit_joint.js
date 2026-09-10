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
