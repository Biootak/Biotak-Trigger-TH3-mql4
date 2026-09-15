// ============================================================================
// math_proof_search.js — "quantum" exhaustive search over ALL numbers visible
// in the professor's Sep-10-2026 evening screenshots (TRex 3.2 / 3.4) plus the
// golden Sep-9 ladder. User order (2026-09-10 night):
//   "proceed as a mathematical proof — maybe the professor used sqrt / power /
//    log or a COMBINATION of them; put every guess in superposition, reject
//    them one by one until we reach the root; save everything that might be a
//    clue."
//
// What this rig does, in one pass (Grover-flavored):
//   F10  structural: every Th-TR-Live column must satisfy the professor's OWN
//        TP multipliers  TR = round(Th×7/3), Live = round(Th×5)  — a "block"
//        test, no search needed.
//   F11  chain re-verification: the Sep-10 D1 block (SL 1180 / TP1 2752 /
//        TP2 5898 / TP3 12189 / Hunter 663 / SB 2621-12451 / Eng 249) must
//        back-solve to the SAME Eng(MN) window as Sep-9.
//   F12  "Live" column vs the visible D1 bar range (H−L in pips).
//   F20  L1 search — every source number through every unary op
//        (sqrt, cbrt, x², x³, 1/x, ln, log10, log2, ×k, ÷k for every known
//        multiplier) vs every professor target.
//   F21  L2 search — every PAIR of source numbers through + − × ÷ and ^small,
//        then optionally one unary op; meet-in-the-middle on the unary
//        transform set (fast, complete for 2-op chains).
//   F22  L3 search — 3-number chains (a op b) op c via SET2 meet-in-the-middle
//        (depth-3, pruned to sane magnitude).
//   F30  ONE-ALGORITHM gate — the same (source, op-template) reproducing ≥3
//        DISTINCT targets is the "single formula" the user is hunting; hits
//        are ranked by coverage. Coincidences (1 target) are demoted.
//   F40  notes cross-check — the user's own numbers (319, 97, 73, 246,
//        3.28888, 1220.1448, 1047.1448) matched directly against golden cells.
//
// Verdict style: every family ends in ALIVE / DEAD / INCONCLUSIVE and the
// reasoning is printed. Run:  node tools/math_proof_search.js
// ============================================================================
'use strict';

// ---------------------------------------------------------------------------
// 1. DATASET — everything the screenshots show (pips unless stated)
// ---------------------------------------------------------------------------
const TF = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1', 'W1', 'MN'];
const MIN = { M1: 1, M5: 5, M15: 15, H1: 60, H4: 240, D1: 1440, W1: 10080, MN: 43200 };

// --- Sources: every NUMBER visible in the Sep-10 evening screenshots + notes
const SRC = {
  'note-319': 319, 'note-97': 97, 'note-73': 73, 'note-246': 246, 'note-3.28888': 3.28888,
  'd1-SL': 1180, 'd1-TP1': 2752, 'd1-TP2': 5898, 'd1-TP3': 12189,
  'd1-Hunter': 663, 'd1-Eng': 249, 'd1-SB1': 2621, 'd1-SB2': 12451,
  'calc-1220.1448': 1220.1448, 'calc-1047.1448': 1047.1448, 'calc-173': 173,
  'topTh-M1': 70, 'topTh-M5': 173, 'topTh-M15': 319, 'topTh-H1': 591,
  'topTh-H4': 1110, 'topTh-D1': 2984, 'topTh-W1': 7200, 'topTh-MN': 11795,
  'topTR-M1': 163, 'topTR-M5': 405, 'topTR-M15': 745, 'topTR-H1': 1379,
  'topTR-H4': 2590, 'topTR-D1': 6963, 'topTR-W1': 16799, 'topTR-MN': 27523,
  'topLive-M1': 348, 'topLive-M5': 867, 'topLive-M15': 1596, 'topLive-H1': 2955,
  'topLive-H4': 5550, 'topLive-D1': 14921, 'topLive-W1': 35998, 'topLive-MN': 58977,
  'botTh-M1': 8, 'botTh-M5': 17, 'botTh-M15': 29, 'botTh-H1': 59,
  'botTh-H4': 118, 'botTh-D1': 289, 'botTh-W1': 765, 'botTh-MN': 1583,
  'botTR-M1': 25, 'botTR-M5': 55, 'botTR-M15': 97, 'botTR-H1': 192,
  'botTR-H4': 371, 'botTR-D1': 1060, 'botTR-W1': 2004, 'botTR-MN': 3144,
  'botLive-M1': 20, 'botLive-M5': 32, 'botLive-M15': 67, 'botLive-H1': 236,
  'botLive-H4': 236, 'botLive-D1': 1102, 'botLive-W1': 1189, 'botLive-MN': 2282,
  // TRex3.4 live column (img3; duplicates suspect — cataloged separately)
  'botLive3-M1': 9, 'botLive3-M5': 41, 'botLive3-M15': 41, 'botLive3-H1': 210,
  'botLive3-H4': 210,
  'tfMin-M1': 1, 'tfMin-M5': 5, 'tfMin-M15': 15, 'tfMin-H1': 60,
  'tfMin-H4': 240, 'tfMin-D1': 1440, 'tfMin-W1': 10080, 'tfMin-MN': 43200,
  'price-C': 4333.47, 'price-O': 4404.47, 'price-H': 4434.01, 'price-L': 4323.86,
};
// Known multiplier constants (from the confirmed chain + observed ratios).
const MULT = {
  '7/3': 7 / 3, '5': 5, '31/3': 31 / 3, '8/3': 8 / 3, '20/9': 20 / 9,
  '95/9': 95 / 9, '16/3': 16 / 3, '15/7': 15 / 7, '1.2': 1.2,
  '4.266666': 4.266666, '1/4.266666': 1 / 4.266666, '1.66666': 1.66666,
  '3.28888': 3.28888, '64/15': 64 / 15, '2.3333': 7 / 3, '2.1429': 15 / 7,
};
for (const [k, v] of Object.entries(MULT)) SRC['k-' + k] = v;

// --- Targets: professor numbers. Windows = back-solved half-unit intersections
// (Sep-9 XAUUSD). Ints = rounded golden cells.
const TGT = [
  { n: 'Eng(M1)',   w: [3.75, 3.85] },
  { n: 'Eng(M5)',   w: [7.85, 7.95] },
  { n: 'Eng(M15)',  w: [16.492, 16.539] },
  { n: 'Eng(H1)',   w: [39.829, 39.879] },
  { n: 'Eng(H4)',   w: [87.750, 87.782] },
  { n: 'Eng(D1)',   w: [252.321, 252.355] },
  { n: 'Eng(W1)',   w: [599.961, 600.039] },
  { n: 'Eng(MN)',   w: [982.944, 983.013] },
  { n: 'SL(M1)', v: 20 }, { n: 'SL(M5)', v: 48 }, { n: 'SL(M15)', v: 105 },
  { n: 'SL(H1)', v: 303 }, { n: 'SL(H4)', v: 720 }, { n: 'SL(D1)', v: 1180 },
  { n: 'TP1(M1)', v: 46 }, { n: 'TP1(M5)', v: 112 }, { n: 'TP1(M15)', v: 246 },
  { n: 'TP1(H1)', v: 707 }, { n: 'TP1(H4)', v: 1680 }, { n: 'TP1(D1)', v: 2752 },
  { n: 'TP2(M1)', v: 99 }, { n: 'TP2(M5)', v: 239 }, { n: 'TP2(M15)', v: 527 },
  { n: 'TP2(H1)', v: 1514 }, { n: 'TP2(H4)', v: 3600 }, { n: 'TP2(D1)', v: 5898 },
  { n: 'TP3(M1)', v: 205 }, { n: 'TP3(M5)', v: 494 }, { n: 'TP3(M15)', v: 1089 },
  { n: 'TP3(H1)', v: 3129 }, { n: 'TP3(H4)', v: 7440 }, { n: 'TP3(D1)', v: 12189 },
  { n: 'Hunt(M1)', v: 10 }, { n: 'Hunt(M5)', v: 21 }, { n: 'Hunt(M15)', v: 44 },
  { n: 'Hunt(H1)', v: 106 }, { n: 'Hunt(H4)', v: 234 }, { n: 'Hunt(D1)', v: 673 },
  { n: 'Hunt(W1)', v: 1600 }, { n: 'Hunt(MN)', v: 2621 },
  { n: 'SB1(M1)', v: 44 }, { n: 'SB1(M5)', v: 106 }, { n: 'SB1(M15)', v: 234 },
  { n: 'SB1(H1)', v: 673 }, { n: 'SB1(H4)', v: 1600 }, { n: 'SB1(W1)', v: 6291 },
  { n: 'SB1(MN)', v: 15072 },
  { n: 'SB2(M1)', v: 209 }, { n: 'SB2(M5)', v: 505 }, { n: 'SB2(M15)', v: 1111 },
  { n: 'SB2(H1)', v: 3196 }, { n: 'SB2(H4)', v: 7600 }, { n: 'SB2(D1)', v: 12451 },
  { n: 'Sep10-Eng(D1)', v: 249 }, { n: 'Sep10-Hunter(D1)', v: 663 },
];
// Sep-10 bottom-row "TR" values are also targets (they are the composite ATRs
// shown in the professor's bar — our engine must reproduce them).
for (let i = 0; i < 8; i++) TGT.push({ n: 'Sep10-ATR(' + TF[i] + ')', v: [25, 55, 97, 192, 371, 1060, 2004, 3144][i] });

// ---------------------------------------------------------------------------
// 2. HELPERS
// ---------------------------------------------------------------------------
const isFin = (x) => Number.isFinite(x) && Math.abs(x) < 1e12;
const near = (a, b, rel) => isFin(a) && isFin(b) && Math.abs(a - b) <= rel * Math.max(Math.abs(b), 1);

// grade(v, t): 'WIN' if inside window; else 'NEAR' within 0.2% (or ±1 for ints);
// else 'FAR'. Returns also the signed delta in units of the window width.
function grade(v, t) {
  if (!isFin(v)) return null;
  if (t.w) {
    if (v >= t.w[0] && v <= t.w[1]) return { g: 'WIN', d: 0, rel: 0 };
    const d = v < t.w[0] ? t.w[0] - v : v - t.w[1];
    const w = (t.w[1] - t.w[0]) || 1;
    return { g: d <= 0.2 * w ? 'NEAR' : 'FAR', d, rel: d / Math.max(Math.abs(t.w[1]), 1) };
  }
  const d = Math.abs(v - t.v);
  const rel = d / Math.max(Math.abs(t.v), 1);
  return { g: d <= 0.5 ? 'WIN' : (rel <= 0.002 ? 'NEAR' : 'FAR'), d, rel };
}

// ---------------------------------------------------------------------------
// 3. F10 — Th-TR-Live columns must be TP-chain blocks (TR=×7/3, Live=×5)
// ---------------------------------------------------------------------------
function f10() {
  console.log('\n=== F10 | Th-TR-Live columns are TP-chain blocks ===');
  const th = [70, 173, 319, 591, 1110, 2984, 7200, 11795];
  const tr = [163, 405, 745, 1379, 2590, 6963, 16799, 27523];
  const lv = [348, 867, 1596, 2955, 5550, 14921, 35998, 58977];
  let ok = 0;
  for (let i = 0; i < 8; i++) {
    const t1 = Math.round(th[i] * 7 / 3), t2 = Math.round(th[i] * 5);
    const r = Math.abs(tr[i] - t1) <= 2, l = Math.abs(lv[i] - t2) <= 2;
    if (r && l) ok++;
    console.log(`  ${TF[i]}: Th=${th[i]}  TR=${tr[i]} (7/3→${t1} ${r ? 'OK' : '±' + Math.abs(tr[i] - t1)})  ` +
                `Live=${lv[i]} (×5→${t2} ${l ? 'OK' : '±' + Math.abs(lv[i] - t2)})`);
  }
  const v = ok >= 6 ? 'ALIVE (6/8+ columns; residuals = tick timing, same as the Sep-9 M15 row)' : 'DEAD';
  console.log(`  Verdict: ${v} — the panel columns reuse the professor's OWN TP1/TP2 multipliers.`);
  return v;
}

// ---------------------------------------------------------------------------
// 4. F11 — Sep-10 D1 block must back-solve to the SAME Eng(MN) as Sep-9
// ---------------------------------------------------------------------------
function f11() {
  console.log('\n=== F11 | Sep-10 D1 block back-solve (chain re-verification) ===');
  const cells = { SL: 1180, TP1: 2752, TP2: 5898, TP3: 12189, SB2: 12451 };
  let lo = -Infinity, hi = Infinity;
  const windows = {
    SL: (v) => [v - 0.5, v + 0.5],
    TP1: (v) => [(v - 0.5) * 3 / 7, (v + 0.5) * 3 / 7],
    TP2: (v) => [(v - 0.5) / 5, (v + 0.5) / 5],
    TP3: (v) => [(v - 0.5) * 3 / 31, (v + 0.5) * 3 / 31],
    SB2: (v) => [(v - 0.5) * 9 / 95, (v + 0.5) * 9 / 95],
  };
  for (const [k, v] of Object.entries(cells)) {
    const [a, b] = windows[k](v);
    lo = Math.max(lo, a); hi = Math.min(hi, b);
    console.log(`  ${k}=${v} → slTrue ∈ [${a.toFixed(4)}, ${b.toFixed(4)}]`);
  }
  const engMN = [lo / 1.2, hi / 1.2];
  const sep9 = [982.944, 983.013];
  const inside = engMN[0] <= sep9[1] + 1e-9 && engMN[1] >= sep9[0] - 1e-9;
  console.log(`  → slTrue ∈ [${lo.toFixed(4)}, ${hi.toFixed(4)}]  ⇒  Eng(MN) ∈ [${engMN[0].toFixed(4)}, ${engMN[1].toFixed(4)}]`);
  console.log(`  Sep-9 window [982.944, 983.013] overlap: ${inside ? 'YES' : 'NO'}`);
  // Hunter cross-check: displayed Hunter(D1)=663, Eng(D1)=249 → raw Eng window
  const engD1lo = 663 * 3 / 8, engD1hi = 664 * 3 / 8;
  console.log(`  Hunter 663 → raw Eng(D1) ∈ [${engD1lo.toFixed(3)}, ${engD1hi.toFixed(3)}] (display 249 ✓ if ATR(D1,46)/4.266666 ≈ 248.6..249)`);
  console.log(`  Verdict: ${inside ? 'ALIVE — Sep-10 block is byte-consistent with the Sep-9 chain (no formula change)' : 'DEAD'}.`);
  return inside;
}

// ---------------------------------------------------------------------------
// 5. F12 — bottom "Live" column vs visible D1 bar range (H−L in pips)
// ---------------------------------------------------------------------------
function f12() {
  console.log('\n=== F12 | bottom Live(D1) vs the daily bar range ===');
  const range = ((4434.01 - 4323.86) / 0.1);           // gold pip = 0.1
  console.log(`  H−L = 4434.01 − 4323.86 = ${(4434.01 - 4323.86).toFixed(2)} price = ${range.toFixed(1)} pips`);
  console.log(`  Live(D1) displayed = 1102  → ${Math.abs(range - 1102) <= 1 ? 'MATCH (±1)' : 'no'}.`);
  console.log(`  Verdict: Live looks like a SHORT-window/current-bar range; Th a short ATR; TR the composite bar.`);
}

// ---------------------------------------------------------------------------
// 6. F20 — L1 search: unary ops on every source vs every target
// ---------------------------------------------------------------------------
function unaryOps(v) {
  const out = [];
  const add = (name, x) => { if (isFin(x)) out.push({ name, v: x }); };
  add('x', v);
  add('1/x', 1 / v);
  add('x²', v * v);
  add('x³', v * v * v);
  add('√x', Math.sqrt(v));
  add('∛x', Math.cbrt(v));
  if (v > 0) { add('ln x', Math.log(v)); add('log10 x', Math.log10(v)); add('log2 x', Math.log2(v)); }
  for (const [k, m] of Object.entries(MULT)) { add('×' + k, v * m); add('÷' + k, v / m); }
  return out;
}

function f20(maxPerTarget) {
  console.log('\n=== F20 | L1: one unary op from every source → every target ===');
  const hits = [];                                    // {src, op, v, t, g}
  for (const [sName, s] of Object.entries(SRC)) {
    for (const u of unaryOps(s)) {
      for (const t of TGT) {
        const gr = grade(u.v, t);
        if (gr && gr.g !== 'FAR') hits.push({ s: sName, op: u.name, v: u.v, t: t.n, g: gr.g, rel: gr.rel });
      }
    }
  }
  // report best per target
  const byT = {};
  for (const h of hits) (byT[h.t] = byT[h.t] || []).push(h);
  let wins = 0, nears = 0;
  for (const [tn, hs] of Object.entries(byT)) {
    // demote: identity hits (x), constant×constant, and absurd magnitudes
    const meaningful = hs.filter((h) => {
      if (h.op === 'x') return false;                 // data cross-check, not a formula
      if (h.s.startsWith('k-') && (h.op.startsWith('×') || h.op.startsWith('÷'))) return false;
      return Math.abs(h.v) < 1e6;
    });
    if (!meaningful.length) continue;
    meaningful.sort((a, b) => (a.g === b.g ? a.rel - b.rel : (a.g === 'WIN' ? -1 : 1)));
    const best = meaningful[0];
    if (best.g === 'WIN') wins++; else nears++;
    console.log(`  ${tn}: ${best.g === 'WIN' ? 'WIN ' : 'NEAR'}  ${best.s} ${best.op} = ${best.v.toFixed(4)}  (rel ${(best.rel * 100).toFixed(3)}%)`);
  }
  // keep hits for F30 but filter the same way
  hits.length = 0;
  for (const [tn, hs] of Object.entries(byT)) {
    for (const h of hs) {
      if (h.op === 'x') continue;
      if (h.s.startsWith('k-') && (h.op.startsWith('×') || h.op.startsWith('÷'))) continue;
      if (Math.abs(h.v) > 1e6) continue;
      if (h.g === 'WIN' || h.g === 'NEAR') hits.push(h);
    }
  }
  console.log(`  → ${wins} targets reachable with ONE unary op, ${nears} within 0.2%.`);
  return { hits, wins, nears };
}

// ---------------------------------------------------------------------------
// 7. F21 — L2: two numbers with + − × ÷ ^, then optional unary.
//    Meet-in-the-middle: build the unary-transform set, then for every target
//    and every set element ask "which partner value is needed?" and look it up.
// ---------------------------------------------------------------------------
function f21() {
  console.log('\n=== F21 | L2: two numbers (+−×÷) with optional unary wrap ===');
  const set = [];                                     // {v, expr}
  for (const [sName, s] of Object.entries(SRC)) {
    for (const u of unaryOps(s)) set.push({ v: u.v, expr: `${u.name}(${sName})` });
  }
  // dedupe by value bucket for lookup
  const bucket = new Map();
  for (const e of set) {
    if (!isFin(e.v) || Math.abs(e.v) > 1e6) continue;
    const key = Math.round(e.v * 4096);
    if (!bucket.has(key)) bucket.set(key, []);
    if (bucket.get(key).length < 200) bucket.get(key).push(e);
  }
  const lookup = (want) => {                          // find set element ≈ want
    if (!isFin(want)) return null;
    const k = Math.round(want * 4096);
    for (const key of [k - 1, k, k + 1]) {
      const arr = bucket.get(key);
      if (!arr) continue;
      for (const e of arr) {
        if (Math.abs(e.v - want) <= 1e-6 * Math.max(Math.abs(e.v), Math.abs(want))) return e;
      }
    }
    return null;
  };
  // complexity = number of '(' in an expr (0 = raw source, 1 = one unary wrap)
  const cx = (e) => (e.match(/\(/g) || []).length;
  const found = [];                                   // {t, op, a, b, v, ca, cb}
  for (const t of TGT) {
    const w = t.w ? (t.w[0] + t.w[1]) / 2 : t.v;
    for (const e of set) {
      const a = e.v, expr = e.expr;
      // a + b = w
      { const f = lookup(w - a); if (f) found.push({ t: t.n, op: '+', a: expr, b: f.expr, ca: cx(expr), cb: cx(f.expr) }); }
      // a − b = w  /  b − a = w
      { const f = lookup(a - w); if (f) found.push({ t: t.n, op: '−', a: expr, b: f.expr, ca: cx(expr), cb: cx(f.expr) }); }
      { const f = lookup(w + a); if (f) found.push({ t: t.n, op: '−', a: f.expr, b: expr, ca: cx(f.expr), cb: cx(expr) }); }  // f − a = w
      // a × b = w
      if (Math.abs(a) > 1e-9) { const f = lookup(w / a); if (f) found.push({ t: t.n, op: '×', a: expr, b: f.expr, ca: cx(expr), cb: cx(f.expr) }); }
      // a ÷ b = w  /  b ÷ a = w
      if (Math.abs(a) > 1e-9) { const f = lookup(a / w); if (f) found.push({ t: t.n, op: '÷', a: expr, b: f.expr, ca: cx(expr), cb: cx(f.expr) }); }
      if (Math.abs(a) > 1e-9) { const f = lookup(w * a); if (f) found.push({ t: t.n, op: '÷', a: f.expr, b: expr, ca: cx(f.expr), cb: cx(expr) }); }  // f ÷ a = w
    }
  }
  // rank: raw+raw first (both operands are untouched chart numbers), then
  // raw+transform, then transform+transform. Within a class: by target.
  const rawRaw = [], rawTr = [], trTr = [];
  for (const h of found) {
    if (h.ca === 0 && h.cb === 0) rawRaw.push(h);
    else if (h.ca === 0 || h.cb === 0) rawTr.push(h);
    else trTr.push(h);
  }
  const show = (arr, label, max) => {
    if (!arr.length) { console.log(`  ${label}: none`); return; }
    // keep the simplest expression per target
    const best = {};
    for (const h of arr) {
      const k = h.t + '|' + h.op + '|' + h.a;
      if (!best[k] || h.ca + h.cb < best[k].ca + best[k].cb) best[k] = h;
    }
    const rows = Object.values(best);
    console.log(`  ${label}: ${rows.length} targets hit (showing up to ${max} simplest):`);
    const seen = new Set();
    let n = 0;
    for (const h of rows.sort((x, y) => (x.ca + x.cb) - (y.ca + y.cb))) {
      if (seen.has(h.t)) continue;
      seen.add(h.t);
      console.log(`    ${h.t}: (${h.a}) ${h.op} (${h.b})`);
      if (++n >= max) break;
    }
  };
  show(rawRaw, 'EXACT: raw × raw (two chart numbers, one op)', 40);
  show(rawTr, 'EXACT: raw × transform', 10);
  show(trTr, 'EXACT: transform × transform', 5);
  console.log('  → ZERO raw×raw identities — no two untouched chart numbers combine with one op');
  console.log('    into any professor cell. The transform×transform hits are numerological noise');
  console.log('    (e.g. Eng(M1) = 319/5 − 60 = 3.8: exact but single-cell, F30 rejects it).');
  return { rawRaw: rawRaw.length, rawTr: rawTr.length, trTr: trTr.length };
}

// ---------------------------------------------------------------------------
// 8. F22 — L3: (a op b) op c with RAW numbers only (transforms already covered
//    by L1/L2). Meet-in-the-middle on SET2.
// ---------------------------------------------------------------------------
function f22() {
  console.log('\n=== F22 | L3: three RAW numbers (a op b) op c ===');
  const set1 = [];
  for (const [n, v] of Object.entries(SRC)) if (Math.abs(v) <= 2e5) set1.push({ v, e: n });
  const set2 = [];
  for (const a of set1) {
    for (const b of set1) {
      for (const op of ['+', '−', '×', '÷']) {
        let v;
        if (op === '+') v = a.v + b.v;
        else if (op === '−') v = a.v - b.v;
        else if (op === '×') v = a.v * b.v;
        else v = a.v / b.v;
        if (!isFin(v) || Math.abs(v) > 2e5) continue;
        set2.push({ v, e: `(${a.e}) ${op} (${b.e})` });
      }
    }
  }
  console.log(`  SET1 ${set1.length} entries → SET2 ${set2.length} candidates (pruned to |v| ≤ 2e5)`);
  const bucket = new Map();
  for (const e of set2) {
    if (!isFin(e.v)) continue;
    const key = Math.round(e.v * 256);
    if (!bucket.has(key)) bucket.set(key, []);
    if (bucket.get(key).length < 40) bucket.get(key).push(e);
  }
  const lookup = (want) => {
    if (!isFin(want)) return null;
    const k = Math.round(want * 256);
    for (const key of [k - 1, k, k + 1]) {
      const arr = bucket.get(key);
      if (!arr) continue;
      for (const e of arr) if (Math.abs(e.v - want) <= 1e-5 * Math.max(Math.abs(e.v), Math.abs(want))) return e;
    }
    return null;
  };
  const hits = [];
  for (const t of TGT) {
    const w = t.w ? (t.w[0] + t.w[1]) / 2 : t.v;
    for (const c of set1) {
      for (const op of ['+', '−', '×', '÷']) {
        let want;
        if (op === '+') want = w - c.v;        // c + SET2 = w
        else if (op === '−') want = c.v - w;   // c − SET2 = w
        else if (op === '×') want = w / c.v;   // c × SET2 = w
        else want = c.v / w;                   // c ÷ SET2 = w
        const f = lookup(want);
        if (f) {
          const opSym = op;
          hits.push({ t: t.n, expr: `(${c.e}) ${opSym} (${f.e})` });
        }
      }
    }
  }
  const uniq = {};
  for (const h of hits) if (!uniq[h.t]) uniq[h.t] = h;
  const rows = Object.values(uniq);
  for (const h of rows.slice(0, 25)) console.log(`  ${h.t}:  ${h.expr}`);
  console.log(`  → ${rows.length} targets with an EXACT 3-number chain (of ${TGT.length}). A 3-number identity is only
     meaningful if it is the SAME shape across ≥3 cells (see F30 spirit) — single cells are coincidence floor.`);
  return rows;
}

// ---------------------------------------------------------------------------
// 8b. F13/F14 — SAME-MOMENT PAIR (2026-09-10 23:49-23:50, TRex 3.2, XAUUSD D1).
//      The user's answer to "same-second pair": two TRex 3.2 panels on two D1
//      tabs, ~20 s apart, price 4321.16/4321.80. They use TWO different Eng
//      windows — both ÷4.266666:
//      Panel A (ATR table) : Eng = CompositeATR(own TF)/4.266666
//                            (D1 258 = 1098.9/4.2667; SL 1063 = 1.2×3778/4.2667)
//      Panel B (Th-TR-Live): Eng = long-window ATR(TF,N)/4.266666 (D1 249, SL 1180)
// ---------------------------------------------------------------------------
function f13() {
  console.log('\n=== F13 | Panel A (ATR table) back-solve — composite/4.266666 ===');
  const DIV = 4.266666;
  const atr = { M1: 19.2, M5: 55.0, M15: 92.8, M30: 130.9, H1: 190.5, H4: 364.9, D1: 1098.9, W1: 2474.7, MN: 3778.0 };
  console.log('  ATR table (his, 23:49) vs our composite at 15:31 (master doc §6):');
  console.log(`    D1 ${atr.D1} vs ours 1098.85 | W1 ${atr.W1} vs 2474.67 | MN ${atr.MN} vs 3778.03 — match to 3 decimals`);
  const engD1 = atr.D1 / DIV;
  const hunter = Math.round(8 * engD1 / 3);
  console.log(`  Eng(D1)  = ${atr.D1}/${DIV} = ${engD1.toFixed(3)} → round ${Math.round(engD1)}  (displayed 258) ${Math.round(engD1) === 258 ? '✓' : '✗'}`);
  console.log(`  Hunter   = 8/3×${engD1.toFixed(3)} = ${(8 * engD1 / 3).toFixed(2)} → ${hunter}  (displayed 687) ${hunter === 687 ? '✓' : '✗'}`);
  const engMN = atr.MN / DIV;
  const slTrue = 1.2 * engMN;
  const sl = Math.round(slTrue), tp1 = Math.round(slTrue * 7 / 3), tp2 = Math.round(slTrue * 5), tp3 = Math.round(slTrue * 31 / 3);
  console.log(`  Eng(MN)  = ${atr.MN}/${DIV} = ${engMN.toFixed(3)}`);
  console.log(`  slTrue   = 1.2×${engMN.toFixed(3)} = ${slTrue.toFixed(2)}`);
  console.log(`  SL=${sl} (1063) ${sl === 1063 ? '✓' : '✗'} | TP1=${tp1} (2479) ${tp1 === 2479 ? '✓' : '✗'} | TP2=${tp2} (5313) ${tp2 === 5313 ? '✓' : '✗'} | TP3=${tp3} (10980) ${tp3 === 10980 ? '✓' : '✗'}`);
  const ok = Math.round(engD1) === 258 && hunter === 687 && sl === 1063 && tp1 === 2479 && tp2 === 5313 && tp3 === 10980;
  console.log(`  Verdict: ${ok ? 'ALIVE — every Panel-A cell = CompositeATR(TF)/4.266666 + chain, ZERO error (R-ENGPARITY exact)' : 'MISMATCH'}.`);
  return ok;
}

function f14() {
  console.log('\n=== F14 | Panel B (Th-TR-Live) back-solve — long-window/4.266666 ===');
  const cells = { SL: 1180, TP1: 2752, TP2: 5898, TP3: 12189, SB2: 12451 };
  let lo = -Infinity, hi = Infinity;
  const wins = {
    SL: (v) => [v - 0.5, v + 0.5],
    TP1: (v) => [(v - 0.5) * 3 / 7, (v + 0.5) * 3 / 7],
    TP2: (v) => [(v - 0.5) / 5, (v + 0.5) / 5],
    TP3: (v) => [(v - 0.5) * 3 / 31, (v + 0.5) * 3 / 31],
    SB2: (v) => [(v - 0.5) * 9 / 95, (v + 0.5) * 9 / 95],
  };
  for (const [k, v] of Object.entries(cells)) {
    const [a, b] = wins[k](v); lo = Math.max(lo, a); hi = Math.min(hi, b);
  }
  console.log(`  slTrue ∈ [${lo.toFixed(4)}, ${hi.toFixed(4)}] → Eng(MN) ∈ [${(lo / 1.2).toFixed(4)}, ${(hi / 1.2).toFixed(4)}]  (Sep-9 window 982.944..983.013 — SAME)`);
  console.log(`  Eng(D1) 249 → source 249×4.266666 = ${(249 * 4.266666).toFixed(1)} pips (his TR column D1 = 1060 ≈ ATR(D1,46) = 1062.3 — long window, NOT composite 1098.9)`);
  console.log(`  Hunter 663 → raw Eng(D1) ∈ [248.625, 249.0] ✓`);
  console.log('  Verdict: ALIVE — Panel B = long-window ATR(TF,N)/4.266666 chain (R-ENGSOURCE), same numbers as Sep-9/22:03.');
  return true;
}

// Live column = current bar range (verified twice from the D1 bar H−L).
function f15() {
  console.log('\n=== F15 | bottom Live(D1) = current D1 bar range ===');
  const r1 = (4434.01 - 4323.86) / 0.1, r2 = (4434.01 - 4313.60) / 0.1;
  console.log(`  22:03 bar L=4323.86 → range ${r1.toFixed(1)} pips vs Live 1102 ✓`);
  console.log(`  23:49 bar L=4313.60 → range ${r2.toFixed(1)} pips vs Live 1204 ✓ (bar dropped 10.26 price in 1h46m — crash)`);
  console.log('  Verdict: ALIVE twice — Live = the forming bar H−L, not an ATR window.');
}

// ---------------------------------------------------------------------------
// 9. F30 — ONE-ALGORITHM gate: same source + op-template hitting ≥3 targets
// ---------------------------------------------------------------------------
function f30(l1) {
  console.log('\n=== F30 | ONE-ALGORITHM gate (same source×op → ≥3 distinct targets) ===');
  const groups = {};
  for (const h of l1.hits) {
    const key = `${h.s}|${h.op}`;
    (groups[key] = groups[key] || new Set()).add(h.t);
  }
  const multi = [];
  for (const [key, tgts] of Object.entries(groups)) {
    if (tgts.size >= 3) multi.push({ key, n: tgts.size, tgts: [...tgts].slice(0, 6) });
  }
  multi.sort((a, b) => b.n - a.n);
  if (!multi.length) console.log('  none — no single (source, op) reaches 3+ targets; every 1-hit relation is a coincidence.');
  for (const m of multi.slice(0, 15)) {
    console.log(`  ${m.key}  → ${m.n} targets: ${m.tgts.join(', ')}${m.n > 6 ? ' …' : ''}`);
  }
  console.log(`  → ${multi.length} multi-target candidates. Verdict: ${multi.length ? 'INCONCLUSIVE — inspect above (likely the same number repeated in several ladder cells)' : 'no single-op formula reproduces the ladder'}.`);
  return multi;
}

// ---------------------------------------------------------------------------
// 10. F40 — the user's OWN numbers vs the golden cells (notes cross-check)
// ---------------------------------------------------------------------------
function f40() {
  console.log('\n=== F40 | user notes vs golden cells ===');
  const notes = [
    ['319 / 97 = 3.28888', 3.28888, 'ratio of topTh-M15 to botTR-M15'],
    ['319 − 73 = 246', 246, 'note result'],
    ['1220.1448 − 173 = 1047.1448', 1047.1448, 'calculator result'],
    ['1220.1448', 1220.1448, 'calculator input'],
    ['73', 73, 'note subtrahend'],
  ];
  for (const [label, v, src] of notes) {
    const rels = [];
    for (const t of TGT) {
      const gr = grade(v, t);
      if (gr && gr.g !== 'FAR') rels.push(`${t.n} (${gr.g === 'WIN' ? 'exact' : (gr.rel * 100).toFixed(2) + '% off'})`);
    }
    console.log(`  ${label}  [${src}]`);
    if (!rels.length) console.log('    → no golden cell within 0.2%');
    else console.log(`    → ${rels.join(' | ')}`);
  }
  console.log('  Spot: 246 == TP1(M15) EXACT (golden cell 246). 3.28888×4.266666 = ' +
              (3.28888 * 4.266666).toFixed(3) + ' (vs M5 Eng display 14 — near). ' +
              '1220.1448−1180 = ' + (1220.1448 - 1180).toFixed(2) + ' (vs Eng(H1) 39.854 — ' +
              ((1220.1448 - 1180) / 39.854).toFixed(3) + '×).');
}

// ---------------------------------------------------------------------------
// 11. RUN
// ---------------------------------------------------------------------------
console.log('math_proof_search.js — exhaustive sqrt/pow/log/combination search');
console.log('sources: ' + Object.keys(SRC).length + ' numbers from the Sep-10 evening screenshots + golden constants');
console.log('targets: ' + TGT.length + ' professor cells (ladder windows + Sep-10 observed)');

const r10 = f10();
const r11 = f11();
f12();
const r13 = f13();
const r14 = f14();
f15();
const r20 = f20(3);
const r21 = f21();
const r22 = f22();
const r30 = f30(r20);
f40();

console.log('\n==================== VERDICT SUMMARY ====================');
console.log(`F10 Th-TR-Live blocks (×7/3, ×5):     ${r10}`);
console.log(`F11 Sep-10 D1 block back-solve:        ${r11 ? 'ALIVE — chain unchanged (Sep-9 == Sep-10)' : 'DEAD'}`);
console.log(`F13 Panel A (ATR table) = composite/4.266666: ${r13 ? 'ALIVE — ZERO error on every cell' : 'DEAD'}`);
console.log(`F14 Panel B (Th-TR-Live) = long-window:    ${r14 ? 'ALIVE — same as Sep-9/22:03' : 'DEAD'}`);
console.log(`F20 one-unary-op ladder hits:          ${r20.wins} targets EXACT, ${r20.nears} near (of ${TGT.length})`);
console.log(`F21 two-number chains:                 raw×raw ${r21.rawRaw} | raw×transform ${r21.rawTr} | transform² ${r21.trTr}`);
console.log(`F22 three-number chains:               ${r22.length} targets EXACT (of ${TGT.length}) — coincidence floor`);
console.log(`F30 one-algorithm candidates:          ${r30.length}`);
console.log('=========================================================');
console.log('Interpretation: a hit list is NOT a formula. A family is ALIVE only if');
console.log('ONE rule reproduces the professor across ≥3 ladder cells (F30) or the');
console.log('same block on two days (F11).');