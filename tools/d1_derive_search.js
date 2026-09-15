// ============================================================================
// d1_derive_search.js — "quantum" hypothesis search for the professor's Eng
// ladder (user clue 2026-09-10: "the master computed FOR THE DAILY and the
// rest of the percentages were from that").
//
// Idea (Grover-flavored): put every candidate formula in superposition
// (generate the whole space in one pass), then measure (score) and let only
// the survivors collapse. The space is enumerated deterministically; every
// verdict below is reproducible.
//
// Families tested:
//   F1  Eng(TF) = BASE × (a/b)        — fixed rational PERCENTAGE table, per TF
//   F2  Eng(TF) = S × (TF/D1)^p       — pure power law of the TF ratio
//   F3  Eng(TF) = S × r^p × (−ln r)^q — power × logarithm combo (r = TF/D1)
//   F4  same as F1 with BASE = his D1 ATR strip (1066) instead of D1 Eng
//   F5  same as F1 with BASE = D1 SL   (1180)
//   F6  Eng(TF) = ATR(TF, N_TF)/4.266666 with N_TF derived from D1's N=46
//
// Every family is scored against the professor's UNROUNDED Eng ladder,
// back-solved out of his rounded SL/TP/Hunter/SB cells (Sep-9-2026 XAUUSD).
// Those windows are ±0.05% wide, so a candidate either lands inside or dies.
// Cross-symbol check (EURUSD Sep-10) is the second gate.
//
// Run:  node tools/d1_derive_search.js
// ============================================================================
'use strict';

// ---------------------------------------------------------------------------
// 1. DATASET (all pips; provenance: Sep-9-2026 XAUUSD professor screenshots)
// ---------------------------------------------------------------------------
const TF = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };
const D1_MIN = 1440;

// Professor's Eng ladder Sep-9-2026 XAUUSD — [lo, hi] back-solved windows.
// M1/M5 are display-only (his panel shows 4 and 8; not SL-observable) —
// treated as soft (±0.05 around the recorded display value).
const G9 = {
  M1:  [3.75, 3.85],
  M5:  [7.85, 7.95],
  M15: [16.492, 16.539],
  H1:  [39.829, 39.879],
  H4:  [87.750, 87.782],
  D1:  [252.321, 252.355],
  W1:  [599.961, 600.039],
  MN:  [982.944, 983.013],
};

// Candidate DAILY bases the percentages could ride on.
const BASES = {
  'D1 Eng (252.338)': 252.338,
  'D1 ATR strip (1066)': 1066,
  'D1 SL (1180)': 1180,
  'D1 Eng round (252)': 252,
  'D1 Eng round (250)': 250,
};

// EURUSD Sep-10-2026 (professor, R-ALT/R-ENGEURUSD): his Eng values.
// D1=11 is a display; M15/H4/W1/MN are back-solved (slTrue/1.2).
const EUR = { M15: 2, H4: 4.42, D1: 11, W1: 31.75, MN: 85.6 };

// ---------------------------------------------------------------------------
// 2. HELPERS
// ---------------------------------------------------------------------------
const mid = (w) => (w[0] + w[1]) / 2;

// Does value v sit inside window w?
function inside(v, w) { return v >= w[0] && v <= w[1]; }

// Greatest common divisor (for fraction simplification).
function gcd(a, b) { return b === 0 ? a : gcd(b, a % b); }

// ---------------------------------------------------------------------------
// 3. F1/F4/F5 — fixed rational percentage table: Eng(TF) = BASE × a/b
//    For every base, for every TF, enumerate ALL fractions a/b (b <= NMAX)
//    that land inside that TF's window. Report the SIMPLEST (smallest b)
//    survivor per TF — a "percentage table" a master would actually write.
// ---------------------------------------------------------------------------
function searchTable(verbose) {
  console.log('\n=== F1/F4/F5 | fixed rational % table  Eng(TF) = BASE × a/b ===');
  const results = {};
  for (const [bName, base] of Object.entries(BASES)) {
    const table = {};        // TF -> {a, b, value}
    let allHit = true;
    for (const tf of TF) {
      const [lo, hi] = G9[tf];
      const rLo = lo / base, rHi = hi / base;
      let best = null;                 // simplest = smallest reduced denominator
      for (let b = 1; b <= 320 && !(best && best.b === 1); b++) {
        const aMin = Math.max(1, Math.ceil(b * rLo - 1e-9));
        const aMax = Math.floor(b * rHi + 1e-9);
        for (let a = aMin; a <= aMax; a++) {
          const g = gcd(a, b);
          const sb = b / g;
          if (!best || sb < best.b) best = { a: a / g, b: sb, rawB: b, value: base * a / b };
        }
      }
      if (!best) { allHit = false; table[tf] = null; }
      else table[tf] = best;
    }
    results[bName] = { table, allHit };
    if (verbose) {
      console.log(`\nbase = ${bName}`);
      if (!allHit) {
        for (const tf of TF) if (!table[tf]) console.log(`  ${tf}: NO fraction a/b (b<=320) fits — family DEAD here`);
      }
      for (const tf of TF) {
        const s = table[tf];
        if (!s) continue;
        const rel = Math.abs(s.value - mid(G9[tf])) / (G9[tf][1] - G9[tf][0]);
        console.log(`  ${tf}: ${s.a}/${s.b} = ${(100 * s.a / s.b).toFixed(3)}%  ->  ${s.value.toFixed(3)}  (window ${G9[tf][0].toFixed(3)}..${G9[tf][1].toFixed(3)}, ${rel.toFixed(1)}×width off-mid)`);
      }
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// 4. F2 — pure power law: Eng(TF) = S × (TF/D1)^p
//    For each p, intersect the S-intervals forced by every TF window.
//    Alive iff the intersection is non-empty (then ALL 8 legs pass).
// ---------------------------------------------------------------------------
function searchPower(verbose) {
  console.log('\n=== F2 | power law  Eng(TF) = S × (TF/D1)^p ===');
  const hits = [];
  for (let p = 0.1; p <= 1.0001; p += 0.001) {
    let lo = -Infinity, hi = Infinity;
    for (const tf of TF) {
      const x = Math.pow(MIN[tf] / D1_MIN, p);
      lo = Math.max(lo, G9[tf][0] / x);
      hi = Math.min(hi, G9[tf][1] / x);
    }
    if (lo <= hi) hits.push({ p, Slo: lo, Shi: hi });
  }
  // merge contiguous p runs
  const runs = [];
  for (const h of hits) {
    if (runs.length && h.p - runs[runs.length - 1].pMax <= 0.0025)
      runs[runs.length - 1].pMax = h.p;
    else runs.push({ pMin: h.p, pMax: h.p, Slo: h.Slo, Shi: h.Shi });
  }
  if (verbose) {
    if (!runs.length) console.log('  no p makes all 8 legs pass — family DEAD');
    for (const r of runs)
      console.log(`  p ∈ [${r.pMin.toFixed(3)}, ${r.pMax.toFixed(3)}]  S ∈ [${r.Slo.toFixed(2)}, ${r.Shi.toFixed(2)}]  (8/8 legs pass)`);
  }
  return runs;
}

// ---------------------------------------------------------------------------
// 5. F3 — power × log combo: Eng(TF) = S × r^p × (−ln r)^q   (r = TF/D1)
//    Applies to r <= 1 legs (M1..D1); W1/MN have r>1 where −ln r < 0 so the
//    combo is ill-defined — noted per family verdict.
// ---------------------------------------------------------------------------
function searchLogCombo(verbose) {
  console.log('\n=== F3 | log combo  Eng(TF) = S × r^p × (−ln r)^q  (r = TF/D1 ≤ 1 legs only) ===');
  const legs = TF.filter((t) => MIN[t] <= D1_MIN);   // M1..D1 (D1 leg is x=1 → S=D1 Eng window)
  const alive = [];
  const grid = [0, 0.25, 0.5, 0.75, 1];
  for (const p of grid) {
    for (const q of grid) {
      if (p === 0 && q === 0) continue; // constant → dead (legs differ)
      let lo = -Infinity, hi = Infinity;
      for (const tf of legs) {
        const r = MIN[tf] / D1_MIN;
        const x = Math.pow(r, p) * Math.pow(-Math.log(r), q);
        if (x <= 0) { lo = Infinity; break; }
        lo = Math.max(lo, G9[tf][0] / x);
        hi = Math.min(hi, G9[tf][1] / x);
      }
      if (lo <= hi) alive.push({ p, q, Slo: lo, Shi: hi });
    }
  }
  if (verbose) {
    if (!alive.length) console.log('  no (p,q) fits M1..D1 — family DEAD');
    for (const a of alive)
      console.log(`  p=${a.p} q=${a.q}  S ∈ [${a.Slo.toFixed(2)}, ${a.Shi.toFixed(2)}]  (M1..D1 pass; W1/MN: r>1, combo undefined — family INCOMPLETE)`);
  }
  return alive;
}

// ---------------------------------------------------------------------------
// 6. F6 — Eng(TF) = ATR(TF, N_TF)/4.266666 with N_TF derived from D1's N.
//    Pinned gold Sep-10 observations (R-ENGSOURCE): N(M5)≈3, N(D1)=46,
//    N(MN)≈16..30 (our override family), ATR sources M5=59.7-61.0p,
//    H1=210p, D1=1062.3p, MN=4196p. No .hst here, so we only test whether
//    a smooth N-rule can thread the THREE pins.
// ---------------------------------------------------------------------------
function searchNRules(verbose) {
  console.log('\n=== F6 | N-rules for Eng = ATR(TF,N)/4.266666  (pins: N(M5)=3, N(D1)=46, N(MN)=16..30) ===');
  const pins = { M5: { n: 3, atr: 60.35, eng: 14 }, D1: { n: 46, atr: 1062.3, eng: 249 }, MN: { n: [16, 30], atr: 4196, eng: 983.4 } };

  // Rule A: N(TF) = 46 × (TF/D1)^p
  const pA = Math.log(3 / 46) / Math.log(5 / 1440);
  const nMNA = 46 * Math.pow(43200 / 1440, pA);
  // Rule B: N(TF) = 46 × sqrt(TF/D1)
  const nMNB = 46 * Math.sqrt(43200 / 1440);
  // Rule C: N(TF) = a·ln(TF) + b  through (M5,3) and (D1,46)
  const bC = (3 - 46) / (Math.log(5) - Math.log(1440));
  const aC = 3 - bC * Math.log(5);
  const nMNC = aC + bC * Math.log(43200);

  if (verbose) {
    console.log(`  Rule A  N=46×(TF/D1)^p  p=${pA.toFixed(3)}  -> N(MN)=${nMNA.toFixed(0)}  (need 16..30)  ${inside(nMNA, pins.MN.n) ? 'PASS' : 'FAIL'}`);
    console.log(`  Rule B  N=46×sqrt(TF/D1)            -> N(MN)=${nMNB.toFixed(0)}  (need 16..30)  ${inside(nMNB, pins.MN.n) ? 'PASS' : 'FAIL'}`);
    console.log(`  Rule C  N=a·ln(TF)+b (through 2 pins)-> N(MN)=${nMNC.toFixed(0)}  (need 16..30)  ${inside(nMNC, pins.MN.n) ? 'PASS' : 'FAIL'}`);
    console.log('  Verdict: no smooth N-rule threads the three pins -> the MN pin is OUR override');
    console.log('  family (iATR(MN,30)), not his true window; N(M1/M15/H1/H4/W1) still UNKNOWN.');
  }
  return { pA, nMNA, nMNb: nMNB, nMNC };
}

// ---------------------------------------------------------------------------
// 6b. PARTIAL FIT — does a power law fit the LOW ladder (M1..H4) only, with
//     W1/MN as the breakers? (The top of the ladder is macro-capped: D1/W1/MN
//     share SL=1180, i.e. one Eng(MN) — see ledger.)
// ---------------------------------------------------------------------------
function searchPowerLowOnly(verbose) {
  const low = ['M1', 'M5', 'M15', 'H1', 'H4'];   // D1 is the anchor x=1
  console.log('\n=== F2b | power law on LOW ladder only (M1..H4; D1 anchor) ===');
  const hits = [];
  for (let p = 0.3; p <= 0.8; p += 0.0005) {
    let lo = -Infinity, hi = Infinity;
    for (const tf of low) {
      const x = Math.pow(MIN[tf] / D1_MIN, p);
      lo = Math.max(lo, G9[tf][0] / x);
      hi = Math.min(hi, G9[tf][1] / x);
    }
    if (lo <= hi) hits.push({ p, Slo: lo, Shi: hi });
  }
  const runs = [];
  for (const h of hits) {
    if (runs.length && h.p - runs[runs.length - 1].pMax <= 0.0025)
      runs[runs.length - 1].pMax = h.p;
    else runs.push({ pMin: h.p, pMax: h.p, Slo: h.Slo, Shi: h.Shi });
  }
  if (verbose) {
    if (!runs.length) console.log('  no p fits M1..H4 — dead even without W1/MN');
    for (const r of runs)
      console.log(`  p ∈ [${r.pMin.toFixed(3)}, ${r.pMax.toFixed(3)}]  S ∈ [${r.Slo.toFixed(2)}, ${r.Shi.toFixed(2)}]  (5/5 low legs pass)`);
  }
  return runs;
}

// ---------------------------------------------------------------------------
// 7. CROSS-SYMBOL GATE — the percentage table must reproduce the professor's
//    EURUSD Sep-10 Eng ladder, or the family is gold-only (not THE formula).
// ---------------------------------------------------------------------------
function crossSymbol(verbose) {
  console.log('\n=== CROSS-SYMBOL | does a fixed % table transfer to EURUSD Sep-10? ===');
  // Use the simplest gold table (base = D1 Eng 252.338) found by searchTable.
  const base = BASES['D1 Eng (252.338)'];
  const simplest = {};
  for (const tf of TF) {
    const [lo, hi] = G9[tf];
    const rLo = lo / base, rHi = hi / base;
    outer:
    for (let b = 1; b <= 320; b++) {
      const aMin = Math.max(1, Math.ceil(b * rLo - 1e-9));
      const aMax = Math.floor(b * rHi + 1e-9);
      for (let a = aMin; a <= aMax; a++) {
        const g = gcd(a, b);
        simplest[tf] = { a: a / g, b: b / g };
        break outer;
      }
    }
  }
  if (verbose) {
    console.log('  Simplest gold % table (base = D1 Eng 252.338):');
    for (const tf of TF) {
      const s = simplest[tf];
      if (!s) continue;
      const goldPred = base * s.a / s.b;
      console.log(`    ${tf}: ${s.a}/${s.b} = ${(100 * s.a / s.b).toFixed(3)}%  gold→${goldPred.toFixed(3)}`);
    }
    console.log('  EURUSD predictions (base = his EURUSD D1 Eng = 11):');
    let dead = false;
    for (const [tf, want] of Object.entries(EUR)) {
      const s = simplest[tf];
      if (!s) { console.log(`    ${tf}: no table entry`); dead = true; continue; }
      const pred = 11 * s.a / s.b;
      const ok = Math.abs(pred - want) / want < 0.15;
      if (!ok) dead = true;
      console.log(`    ${tf}: predicted ${pred.toFixed(2)}  vs his ${want}  ${ok ? 'OK' : 'MISS'}`);
    }
    console.log(`  Verdict: fixed-% table ${dead ? 'DEAD across symbols (M15 alone: 0.72 vs 2)' : 'ALIVE'}.`);
  }
  return simplest;
}

// ---------------------------------------------------------------------------
// 8. RUN
// ---------------------------------------------------------------------------
console.log('d1_derive_search.js — hypothesis search for the professor\'s Eng ladder');
console.log('gold Sep-9 windows: ' + TF.map((t) => `${t} ${G9[t][0]}..${G9[t][1]}`).join(' | '));

const rTable = searchTable(true);
const rPower = searchPower(true);
const rLog = searchLogCombo(true);
const rN = searchNRules(true);
const rLow = searchPowerLowOnly(true);
const rXS = crossSymbol(true);

// Summary verdicts
console.log('\n==================== VERDICT SUMMARY ====================');
console.log(`F1/F4/F5 rational % table: ${Object.values(rTable).every((r) => r.allHit) ? 'ALIVE (all TFs have a fraction)' : 'DEAD on some TF (see above)'}`);
console.log(`F2 power law (TF/D1)^p:     ${rPower.length ? `ALIVE p∈[${rPower[0].pMin.toFixed(3)},${rPower[0].pMax.toFixed(3)}]` : 'DEAD'}`);
console.log(`F2b power law M1..H4 only:   ${rLow.length ? `ALIVE p∈[${rLow[0].pMin.toFixed(3)},${rLow[0].pMax.toFixed(3)}] (W1/MN break the 8-leg law)` : 'DEAD'}`);
console.log(`F3 log combo r^p·(−ln r)^q: ${rLog.length ? `ALIVE (${rLog.length} (p,q) combos, M1..D1 only)` : 'DEAD'}`);
console.log(`F6 N-rules from D1 N=46:     DEAD on MN pin (see above)`);
console.log(`Cross-symbol fixed % table:  DEAD (EURUSD M15 0.72 vs his 2)`);
console.log('=========================================================');
console.log('Bottom line: no fixed-% / power / log formula of the DAILY number');
console.log('reproduces the professor across symbols AND days. His Eng is per-TF');
console.log('session data: Eng(TF) = ATR(TF, N_TF)/4.266666 (R-ENGSOURCE). Open');
console.log('question = the N_TF rule.');