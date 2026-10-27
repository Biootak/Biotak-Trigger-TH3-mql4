#!/usr/bin/env node
'use strict';
/*
 * bk-study.js - the BaseKnot evidence harness.
 *
 * WHY THIS EXISTS
 *   Every "entry should wait deeper / stop should be wider / TP should be closer"
 *   claim is a number. This reads the terminal's OWN history files, rebuilds the
 *   SHIPPED mathematics (TrexSMALeg composite ATR, Eng = TR/4.266666,
 *   Hunt = 5/8 x TR, the type rule of BaseKnotNodeKindOfLength (ratio edges, v7),
 *   the rung of BaseKnotLadderHopAt (55/64 of it must fit) and the one-ruler legs of
 *   BaseKnotLegPair) and then answers with counts:
 *
 *     --probe   do the journal's printed numbers come out of this pipeline?
 *     --study   where does the market actually react, and which placement
 *               (entry / stop / TP) pays per node type
 *
 * THE LESSON THE PROBE TAUGHT (2026-10-27)
 *   Aggregating M1 into H4 gave 294.2p where the terminal read 311.0p, because the
 *   terminal's H4 file carries 2,711 bars from 2025-01-27 and the M1 file only 54
 *   days - the 264-bar leg of the composite was MISSING from the aggregate. So a
 *   series is read from its OWN .hst when one exists; M1 aggregation is the
 *   fallback, not the source.
 *
 * USAGE
 *   node tools/bk-study.js --probe
 *   node tools/bk-study.js --study --tf 5,15,60,240 --out build-logs/bk-study.json
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

// - the terminal's history -
function terminalHistoryDirs() {
  const base = path.join(os.homedir(), 'AppData', 'Roaming', 'MetaQuotes', 'Terminal');
  if (!fs.existsSync(base)) return [];
  return fs.readdirSync(base)
    .map(id => path.join(base, id, 'history'))
    .filter(p => fs.existsSync(p));
}
function findHst(symbol, minutes) {
  const name = `${symbol}${minutes}.hst`;
  const hits = [];
  for (const h of terminalHistoryDirs()) {
    for (const srv of fs.readdirSync(h)) {
      const p = path.join(h, srv, name);
      if (fs.existsSync(p)) hits.push({ p, size: fs.statSync(p).size, mtime: fs.statSync(p).mtimeMs });
    }
  }
  hits.sort((a, b) => b.mtime - a.mtime || b.size - a.size);
  return hits[0] || null;
}
// MT4 HST: 148-byte header, then fixed records. v400 = 44 bytes (int32 time + 5
// doubles); v401 = 60 bytes (int64 time + 4 doubles + int64 volume + int32
// spread + int64 real volume). Both are read.
function readHst(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 148) throw new Error('HST too short: ' + file);
  const version = buf.readInt32LE(0);
  const rec = version === 400 ? 44 : version === 401 ? 60 : 0;
  if (!rec) throw new Error(`HST version ${version} (expected 400 or 401)`);
  const symbol = buf.toString('latin1', 68, 80).replace(/\0.*$/, '');
  const period = buf.readInt32LE(80);
  const digits = buf.readInt32LE(84);
  const n = Math.floor((buf.length - 148) / rec);
  const t = new Float64Array(n), o = new Float64Array(n), hi = new Float64Array(n),
        lo = new Float64Array(n), c = new Float64Array(n);
  let off = 148;
  for (let i = 0; i < n; i++, off += rec) {
    if (version === 400) {
      t[i] = buf.readUInt32LE(off);
      o[i] = buf.readDoubleLE(off + 4);
      lo[i] = buf.readDoubleLE(off + 12);
      hi[i] = buf.readDoubleLE(off + 20);
      c[i] = buf.readDoubleLE(off + 28);
    } else {
      t[i] = Number(buf.readBigInt64LE(off));
      o[i] = buf.readDoubleLE(off + 8);
      hi[i] = buf.readDoubleLE(off + 16);
      lo[i] = buf.readDoubleLE(off + 24);
      c[i] = buf.readDoubleLE(off + 32);
    }
  }
  return { file, symbol, period, digits, n, t, o, hi, lo, c };
}

// - timeframes -
const LADDER = [1, 5, 15, 60, 240, 1440, 10080, 43200];
function nextTF(min) {
  const i = LADDER.indexOf(min);
  if (i < 0) return 0;
  return i + 1 < LADDER.length ? LADDER[i + 1] : 0;
}
// Aggregation of M1 -> one TF (fallback only; MT4 buckets start on the period).
function aggregate(m1, minutes) {
  if (minutes === 1) return m1;
  const step = minutes * 60;
  const n = m1.n;
  const idx = [];
  let cur = -1;
  for (let i = 0; i < n; i++) {
    const b = Math.floor(m1.t[i] / step);
    if (b !== cur) { cur = b; idx.push(i); }
  }
  const m = idx.length;
  const t = new Float64Array(m), o = new Float64Array(m), hi = new Float64Array(m),
        lo = new Float64Array(m), c = new Float64Array(m);
  for (let k = 0; k < m; k++) {
    const s = idx[k], e = (k + 1 < m ? idx[k + 1] : n) - 1;
    t[k] = m1.t[s];
    o[k] = m1.o[s]; hi[k] = -Infinity; lo[k] = Infinity; c[k] = m1.c[e];
    for (let i = s; i <= e; i++) {
      if (m1.hi[i] > hi[k]) hi[k] = m1.hi[i];
      if (m1.lo[i] < lo[k]) lo[k] = m1.lo[i];
    }
  }
  return { symbol: m1.symbol, digits: m1.digits, n: m, t, o, hi, lo, c, minutes };
}

// - the shipped ATR (Biotak/ATR_A.mqh) -
// leg = SMA(TR, period) at shift; TR uses the PREVIOUS close (i == 0 uses its own
// close, exactly as TrexSMALeg does); composite = weighted 1/1/2/3/5/8 over
// periods {5,10,21,66,132,264}, divided by the weight of the non-zero legs.
const PERIODS = [5, 10, 21, 66, 132, 264];
const WEIGHTS = [1, 1, 2, 3, 5, 8];
function trSeries(s) {
  const tr = new Float64Array(s.n);
  for (let i = 0; i < s.n; i++) {
    const h = s.hi[i], l = s.lo[i];
    const pc = (i > 0 ? s.c[i - 1] : s.c[i]);
    tr[i] = Math.max(h - l, Math.abs(h - pc), Math.abs(l - pc));
  }
  return tr;
}
function prefix(tr) {
  const p = new Float64Array(tr.length + 1);
  for (let i = 0; i < tr.length; i++) p[i + 1] = p[i] + tr[i];
  return p;
}
function legAt(trP, i, period) {
  if (i + 1 < period) return 0;
  return (trP[i + 1] - trP[i + 1 - period]) / period;
}
function nz(x, digits) {
  const m = Math.pow(10, digits);
  return Math.round(x * m) / m;
}
function compositeAt(trP, i, digits) {
  let sum = 0, w = 0;
  for (let k = 0; k < PERIODS.length; k++) {
    const v = legAt(trP, i, PERIODS[k]);
    if (!(v > 0)) continue;
    const leg = nz(v, digits);
    if (!(leg > 0)) continue;
    sum += leg * WEIGHTS[k];
    w += WEIGHTS[k];
  }
  return w > 0 ? sum / w : 0;
}

// - series cache: native .hst first, M1 aggregate as fallback -
const H = { symbol: 'XAUUSD', m1: null, pip: 0.1, digits: 2, files: {}, cache: {} };
function m1() {
  if (H.m1) return H.m1;
  const f = findHst(H.symbol, 1);
  if (!f) throw new Error('no M1 history for ' + H.symbol);
  H.m1 = readHst(f.p);
  H.files[1] = f.p;
  H.digits = H.m1.digits;
  H.pip = Math.pow(10, 1 - H.digits);
  return H.m1;
}
function series(tf) {
  if (H.cache[tf]) return H.cache[tf];
  let s = null, src = '';
  if (tf !== 1) {
    const f = findHst(H.symbol, tf);
    if (f) { s = readHst(f.p); H.files[tf] = f.p; src = 'hst'; }
  }
  if (!s) { s = aggregate(m1(), tf); src = 'm1-agg'; }
  s.src = src;
  s.trP = prefix(trSeries(s));
  H.cache[tf] = s;
  return s;
}
// as-of index: the bar whose OPEN time is <= ts (last closed-at-ts bar).
function idxAsOf(s, ts) {
  let lo = 0, hi = s.n - 1, r = -1;
  while (lo <= hi) {
    const m = (lo + hi) >> 1;
    if (s.t[m] <= ts) { r = m; lo = m + 1; } else hi = m - 1;
  }
  return r;
}
// ATR in PIPS, as-of an anchor (P-BK-79 semantics: iBarShift(anchor), <=0 -> 1).
function atrPips(tf, ts) {
  const s = series(tf);
  let i = idxAsOf(s, ts);
  if (i < 0) return 0;
  return compositeAt(s.trP, i, s.digits) / H.pip;
}
function engPips(tf, ts) { return atrPips(tf, ts) / 4.266666; }

// - proof against the terminal's own journal -
// Every entry is a number the terminal PRINTED (20261024.log) and the series it
// must come out of. `box` names the line it was read from.
const PROBE = [
  { tf: 60,  at: '2026.10.22 17:00', atr: 149.3, box: '5_8851328 labelATR / L2247' },
  { tf: 240, at: '2026.10.22 17:00', atr: 311.0, box: '5_8851328 pattern -> stop 72.9 / L2247' },
  { tf: 1440, at: '2026.10.22 17:00', atr: 975.1, box: '5_8851328 structure / band CTR<975.1' },
  { tf: 5,   at: '2026.10.23 17:00', atr: 43.9,  box: '5_10454640 labelATR / L9634' },
  { tf: 15,  at: '2026.10.23 17:00', atr: 76.1,  box: '5_10454640 stop=17.8 / L9636' },
  { tf: 60,  at: '2026.10.23 17:00', atr: 145.5, box: '5_10454640 structure / L9634' },
];
function fmt(t) {
  const d = new Date(t * 1000);
  const p = x => String(x).padStart(2, '0');
  return `${d.getUTCFullYear()}.${p(d.getUTCMonth() + 1)}.${p(d.getUTCDate())} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`;
}
function uStamp(str) {
  const m = /^(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2})$/.exec(str);
  if (!m) throw new Error('stamp ' + str);
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) / 1000;
}
function probe() {
  m1();
  console.log(`HST  ${H.files[1]}`);
  console.log(`     ${H.m1.symbol} digits=${H.digits} bars=${H.m1.n} ${fmt(H.m1.t[0])} .. ${fmt(H.m1.t[H.m1.n - 1])} pip=${H.pip}`);
  let bad = 0;
  for (const p of PROBE) {
    const s = series(p.tf);
    const i = idxAsOf(s, uStamp(p.at));
    const atr = atrPips(p.tf, uStamp(p.at));
    const d = atr - p.atr;
    const ok = Math.abs(d) < 0.051;
    if (!ok) bad++;
    console.log(`${ok ? 'OK  ' : 'FAIL'} tf=${String(p.tf).padStart(4)}m ${p.at} bar=${fmt(s.t[i])} src=${s.src.padEnd(6)} ` +
                `atr=${atr.toFixed(1).padStart(7)}p log=${p.atr.toFixed(1).padStart(7)} d=${d >= 0 ? '+' : ''}${d.toFixed(2).padStart(5)}  ${p.box}`);
  }
  console.log(bad === 0 ? `PROBE PASS - ${PROBE.length}/${PROBE.length} journal numbers reproduced.`
                        : `PROBE FAIL - ${bad} of ${PROBE.length} disagree.`);
  return bad === 0 ? 0 : 2;
}

// - boxes -
// A node is a k-bar window of one TF: top = max high, bot = min low, h = top-bot.
// Its TYPE is the shipped rule (BaseKnot_Nodes.mqh:705-713) against the ATR
// ability triple at its LAST bar (trig = ATR(node TF), pat = ATR(+1 rung),
// str = ATR(+2 rungs)) - the same three numbers P-BK-107 prints.
const FTR = 0, ETR = 1, CTR = 2, OTR = 3;
const TYPE_NAME = ['FTR', 'ETR', 'CTR', 'OTR'];
const TYPE_HOPS = [0, 1, 2, 3];            // the NAME's hop - a cold-ladder fallback only
const DIV = 4.266666;                      // BK_NODE_POWER_DIV
const FIT = 55.0 / 64.0;                   // BK_AB_FIT_NUM / BK_AB_FIT_DEN (P-BK-128)
// P-BK-128: the boundaries are the ladder's RATIO midpoints, sqrt(a*b) - not (a+b)/2, which
// put the FTR/ETR edge 0.3 % from one real box and flipped it on 2 pips.
function typeOf(h, trig, pat, str) {
  if (!(h > 0) || !(trig > 0)) return -1;
  if (h <= Math.sqrt(trig * pat)) return FTR;
  if (h <= Math.sqrt(pat * str)) return ETR;
  if (h <= str) return CTR;
  return OTR;
}
// P-BK-128: the RUNG is the deepest one whose whole leg package (off 5/8 + risk 15/64 = 55/64
// of its ATR) still fits inside the box - BaseKnotLadderHopAt, same three rows, same anchor.
function hopOf(h, nodeTF, ts) {
  const up1 = nextTF(nodeTF), up2 = up1 > 0 ? nextTF(up1) : 0;
  if (!up1 || !up2) return -1;
  const a1 = atrPips(up1, ts), a2 = atrPips(up2, ts);
  if (!(a1 > 0) || !(a2 > a1)) return -1;
  let hop = 0;
  if (h >= FIT * a1) hop = 1;
  if (h >= FIT * a2) hop = 2;
  if (h > a2) {
    const up3 = nextTF(up2), a3 = up3 > 0 ? atrPips(up3, ts) : 0;
    if (!(a3 > a2)) return -1;
    if (h >= FIT * a3) hop = 3;
  }
  return hop;
}
function buildBoxes(nodeTF, kMax) {
  const s = series(nodeTF);
  const up1 = nextTF(nodeTF), up2 = up1 > 0 ? nextTF(up1) : 0;
  if (!up1 || !up2) return [];
  const out = [];
  const lastT = m1().t[m1().n - 1];
  for (let i = 40; i + 1 < s.n; i++) {
    const ts = s.t[i];
    if (ts + 6 * 86400 > lastT) break;       // no full hold window -> censored
    const trig = atrPips(nodeTF, ts), pat = atrPips(up1, ts), str = atrPips(up2, ts);
    if (!(trig > 0) || !(pat > 0) || !(str > 0)) continue;
    for (let k = 1; k <= kMax; k++) {
      if (i - k + 1 < 1) break;
      let top = -Infinity, bot = Infinity;
      for (let j = i - k + 1; j <= i; j++) {
        if (s.hi[j] > top) top = s.hi[j];
        if (s.lo[j] < bot) bot = s.lo[j];
      }
      const h = (top - bot) / H.pip;
      if (!(h > 0)) continue;
      const type = typeOf(h, trig, pat, str);
      if (type < 0) continue;
      // direction: the first of the next 6 node bars that CLOSES outside the box
      let dir = 0, brk = -1;
      for (let j = i + 1; j < Math.min(s.n, i + 7); j++) {
        if (s.c[j] > top) { dir = 1; brk = j; break; }
        if (s.c[j] < bot) { dir = -1; brk = j; break; }
      }
      if (!dir) continue;
      out.push({ nodeTF, ts, i, k, top, bot, h, type, dir, trig, pat, str,
                 up1, up2, per: nodeTF * 60, brkTs: s.t[brk] });
    }
  }
  return out;
}

// - M1 path -
function m1After(ts) {
  const s = m1();
  let i = idxAsOf(s, ts);
  return i < 0 ? 0 : i + 1;
}
// First touch of `level`, on/after `from`, before `untilTs`; -1 = never.
// `side` says which way price must travel to reach it: -1 = fall to it
// (test the LOW), +1 = rise to it (test the HIGH). A BUY limit is side -1,
// a BUY target is side +1 - the two are never the same test.
function touch(s, from, level, side, untilTs) {
  for (let i = from; i < s.n; i++) {
    if (s.t[i] > untilTs) break;
    if (side < 0 ? s.lo[i] <= level : s.hi[i] >= level) return i;
  }
  return -1;
}
// A trade: order `entry`, stop `sl`, targets `tps[]`, all in price.
// The setup DIES when the box' far edge breaks (that is the invalidation the
// product itself draws: the opposite side of the box), so a limit that is never
// reached before that is not a late entry, it is a dead setup.
function trade(box, entry, sl, tps, fillSide) {
  const s = m1();
  const buy = box.dir > 0;
  const far = buy ? box.bot : box.top;
  const t0 = box.brkTs + box.per;
  const from = m1After(t0);
  const dead = touch(s, from, far, -box.dir, t0 + 2 * 86400);
  const untilFill = dead >= 0 ? s.t[dead] : t0 + 2 * 86400;
  const fillIdx = touch(s, from, entry, fillSide, untilFill);
  if (fillIdx < 0) return { filled: false };
  const until = t0 + 6 * 86400;                    // 6 days to resolve
  const slIdx = touch(s, fillIdx, sl, -box.dir, until);
  const tpIdx = tps.map(lvl => touch(s, fillIdx, lvl, box.dir, until));
  const first = slIdx >= 0 ? slIdx : Infinity;
  const outcome = (tpIdx[0] >= 0 && tpIdx[0] < first) ? 'TP1' : (slIdx >= 0 ? 'SL' : 'OPEN');
  return { filled: true, fillIdx, slIdx, tpIdx, outcome,
           tp1: tpIdx[0] >= 0 && tpIdx[0] < first,
           tp2: tpIdx[1] >= 0 && tpIdx[1] < first,
           tp3: tpIdx[2] >= 0 && tpIdx[2] < first,
           mfe: mfeR(s, fillIdx, entry, sl, buy, until) };
}
// Max favourable excursion in R (how far the trade ever went before the stop).
function mfeR(s, from, entry, sl, buy, until) {
  const risk = Math.abs(entry - sl);
  if (!(risk > 0)) return 0;
  let best = 0;
  for (let i = from; i < s.n; i++) {
    if (s.t[i] > until) break;
    const p = buy ? s.hi[i] : s.lo[i];
    const r = (p - entry) * (buy ? 1 : -1) / risk;
    if (r > best) best = r;
    if (buy ? s.lo[i] <= sl : s.hi[i] >= sl) break;
  }
  return best;
}

// - the two studies -
// 1) REACTION MAP: price reaches level L = edge +- m*h (m<0 inside the box,
//    m>0 beyond it). Once it does, which barrier is taken first, one h away
//    (+1h with the trade / -1h against it) inside 4 hours?
//    reject = the against barrier first; follow = the with barrier first.
function reactionMap(boxes, step = 1) {
  const s = m1();
  const MS = [-1.0, -0.5, -0.25, 0, 0.25, 0.5, 1.0, 2.0];
  const agg = {};
  for (const m of MS) agg[m] = { n: 0, reach: 0, reject: 0, follow: 0, none: 0 };
  for (const b of boxes.filter((_, j) => j % step === 0)) {
    const buy = b.dir > 0;
    const edge = buy ? b.top : b.bot;
    const t0 = b.brkTs + b.per;                 // measured FROM the breakout
    const from = m1After(t0);
    for (const m of MS) {
      const L = buy ? edge - m * b.h * H.pip : edge + m * b.h * H.pip;
      const side = (m <= 0 ? -1 : 1) * b.dir;
      const at = touch(s, from, L, side, t0 + 86400);
      if (at < 0) continue;
      const a = agg[m];
      a.n++;
      const withL = buy ? L + b.h * H.pip : L - b.h * H.pip;
      const agL = buy ? L - b.h * H.pip : L + b.h * H.pip;
      const w = touch(s, at + 1, withL, b.dir, s.t[at] + 4 * 3600);
      const g = touch(s, at + 1, agL, -b.dir, s.t[at] + 4 * 3600);
      if (w >= 0 && (g < 0 || w < g)) a.follow++;
      else if (g >= 0) a.reject++;
      else a.none++;
    }
  }
  return { MS, agg };
}

// 2) PLACEMENT GRID: entry depth, stop width and TP distance, all in the box'
//    OWN unit (h) - because h is the only measure that belongs to the node
//    rather than to a timeframe the node happens to be viewed on. The shipped
//    ATR plan is rule `A shipped` and is the baseline every row is read against.
const DEPTHS = [-1.0, -0.5, -0.25, 0, 0.25, 0.5, 0.625, 0.75, 1.0];
const STOPS = [0.75, 1.0, 1.5, 2.0];
function ruleAt(b, d, s) {
  const buy = b.dir > 0;
  const edge = buy ? b.top : b.bot;
  // d > 0: the entry waits INSIDE the box (a limit) | d < 0: BEYOND the edge
  // (a stop order, the momentum side the reaction map says is the real one).
  const I = (base, x) => buy ? base - x * H.pip : base + x * H.pip;   // `x` pips AGAINST
  const L = (base, x) => buy ? base + x * H.pip : base - x * H.pip;   // `x` pips WITH
  const entry = I(edge, d * b.h);
  const risk = s * b.h;
  return { id: `d${d} s${s}`, entry, sl: I(entry, risk),
           tps: [1, 2, 3].map(m => L(entry, m * b.h)), risk, r: [1 / s, 2 / s, 3 / s],
           fillSide: (d >= 0 ? -b.dir : b.dir) };
}
function shippedRule(b) {
  const buy = b.dir > 0;
  const edge = buy ? b.top : b.bot;
  const I = (base, x) => buy ? base - x * H.pip : base + x * H.pip;
  const L = (base, x) => buy ? base + x * H.pip : base - x * H.pip;
  // P-BK-125/127/128: one rung for BOTH legs - the capacity one when the box was measured,
  // the name's only when the ladder could not answer (a cold row).
  const hop = hopOf(b.h, b.nodeTF, b.ts);
  let mtf = b.nodeTF;
  const steps = hop >= 0 ? hop : TYPE_HOPS[b.type];
  for (let i = 0; i < steps; i++) mtf = nextTF(mtf);
  const A = atrPips(mtf, b.ts);                 // that rung's ATR, the one the legs are sized on
  const risk = A / DIV;                         // EngSL: the stop, on the same rung
  const off = b.type === FTR ? risk : 0.625 * A; // FTR enters on EngSL, the rest on HuntSL (5/8)
  const entry = I(edge, off);
  return { id: 'A shipped', entry, sl: I(entry, risk),
           tps: [7 / 3, 5, 31 / 3].map(k => L(entry, risk * k)),
           risk, r: [7 / 3, 5, 31 / 3], fillSide: -b.dir };
}
function rulesFor(b) {
  const out = [];
  for (const d of DEPTHS) for (const s of STOPS) out.push(ruleAt(b, d, s));
  out.push(shippedRule(b));
  return out;
}
function scoreRule(list) {
  const a = { n: 0, fill: 0, sl: 0, tp1: 0, tp2: 0, tp3: 0, exp: 0, mfe: 0 };
  for (const t of list) {
    a.n++;
    if (!t.filled) continue;
    a.fill++;
    a.mfe += t.mfe;
    if (t.tp1) { a.tp1++; a.exp += t.r1; } else a.exp -= 1;
    if (t.tp2) a.tp2++;
    if (t.tp3) a.tp3++;
    if (t.outcome === 'SL') a.sl++;
  }
  return a;
}
function placementStudy(boxes, step = 1) {
  const sample = boxes.filter((_, j) => j % step === 0);
  const acc = {};                     // id -> {rule, trades[]}
  for (const b of sample) {
    for (const r of rulesFor(b)) {
      if (!acc[r.id]) acc[r.id] = { rule: r, trades: [] };
      const t = trade(b, r.entry, r.sl, r.tps, r.fillSide);
      t.r1 = r.r[0];
      acc[r.id].trades.push(t);
    }
  }
  const rows = [];
  for (const id of Object.keys(acc)) {
    const { rule, trades } = acc[id];
    rows.push({ id, risk: rule.risk, score: scoreRule(trades) });
  }
  return { rows, sample: sample.length };
}
// - reporting -
const pct = (a, b) => b > 0 ? (100 * a / b).toFixed(1).padStart(5) + '%' : '    -';
const num = (x, d = 2) => x.toFixed(d).padStart(6);

function table(rows, title, sub) {
  console.log(`\n   ${title}${sub ? '   ' + sub : ''}`);
  console.log('     rule          fill    SL    TP1    TP2    TP3   E[R]   MFE');
  for (const r of rows) {
    const a = r.score;
    console.log(`   ${r.id.padEnd(12)} ${pct(a.fill, a.n)} ${pct(a.sl, a.fill)} ${pct(a.tp1, a.fill)} ${pct(a.tp2, a.fill)} ${pct(a.tp3, a.fill)}  ${num(a.exp / Math.max(1, a.fill))}  ${num(a.mfe / Math.max(1, a.fill))}`);
  }
}
// one rule over an arbitrary subset of boxes (for the root-cause cuts)
function scoreSubset(boxes, pick, step = 1) {
  const sample = boxes.filter((_, j) => j % step === 0);
  const acc = { n: 0, fill: 0, sl: 0, tp1: 0, tp2: 0, tp3: 0, exp: 0, mfe: 0 };
  for (const b of sample) {
    const r = pick(b);
    const t = trade(b, r.entry, r.sl, r.tps, r.fillSide);
    acc.n++;
    if (!t.filled) continue;
    acc.fill++; acc.mfe += t.mfe;
    if (t.tp1) { acc.tp1++; acc.exp += r.r[0]; } else acc.exp -= 1;
    if (t.tp2) acc.tp2++;
    if (t.tp3) acc.tp3++;
    if (t.outcome === 'SL') acc.sl++;
  }
  return acc;
}

function main() {
  const argv = process.argv.slice(2);
  const arg = (name, dflt) => {
    const i = argv.indexOf(name);
    return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
  };
  const outFile = arg('--out', 'build-logs/bk-study.json');
  const tfs = arg('--tf', '5,15,60,240').split(',').map(Number);
  const kMax = +arg('--k', 3);
  const stride = +arg('--stride', 12);

  const rc = probe();
  if (rc !== 0) { console.log('\nSTUDY NOT RUN: the pipeline does not reproduce the journal.'); return rc; }

  const all = [];
  const perTF = {};
  for (const tf of tfs) {
    const bx = buildBoxes(tf, kMax);
    perTF[tf] = bx.length;
    for (const b of bx) all.push(b);
  }
  const byType = [0, 1, 2, 3].map(t => all.filter(b => b.type === t).length);
  console.log(`\nBOXES  ${all.length} total  ` + tfs.map(tf => `${tf}m:${perTF[tf]}`).join('  '));
  console.log(`       ` + TYPE_NAME.map((n, i) => `${n}:${byType[i]}`).join('  ') + `   (stride ${stride})`);

  console.log('\n- STUDY 1 - REACTION MAP: does the market come back to that level? -');
  console.log('   m<0 = inside the box from the broken edge, m>0 = beyond it (units of h)');
  console.log('   reach = of the sampled boxes; reject / follow = of the boxes that reached it');
  const mapOut = {};
  for (const type of [0, 1, 2, 3]) {
    const bx = all.filter(b => b.type === type);
    if (bx.length < 40) continue;
    const { MS, agg } = reactionMap(bx, stride);
    const nS = Math.ceil(bx.length / stride);
    mapOut[TYPE_NAME[type]] = { MS, agg, n: bx.length, nS };
    console.log(`\n   ${TYPE_NAME[type]}  sampled n=${nS}`);
    console.log('     m      reach   reject  follow   none');
    for (const m of MS) {
      const a = agg[m];
      console.log(`   ${String(m).padStart(5)}  ${pct(a.n, nS)}  ${pct(a.reject, a.n)}  ${pct(a.follow, a.n)}  ${pct(a.none, a.n)}`);
    }
  }

  console.log('\n- STUDY 2 - PLACEMENT GRID (entry depth / stop width in units of the box h; TP = 1h,2h,3h) -');
  const placeOut = {};
  for (const type of [0, 1, 2, 3]) {
    const bx = all.filter(b => b.type === type);
    if (bx.length < 40) continue;
    const { rows, sample } = placementStudy(bx, stride);
    const ranked = rows.slice().sort((x, y) => (y.score.exp / Math.max(1, y.score.fill)) - (x.score.exp / Math.max(1, x.score.fill)));
    placeOut[TYPE_NAME[type]] = { n: bx.length, sample, rows: ranked.map(r => ({ id: r.id, ...r.score })) };
    console.log(`\n   ${TYPE_NAME[type]}  sampled n=${sample}`);
    table(rows.filter(r => r.id === 'A shipped'), 'the shipped plan');
    table(ranked.filter(r => r.score.fill / Math.max(1, r.score.n) >= 0.25).slice(0, 6),
          'top 6 by E[R] (fill >= 25%)');
  }

  console.log('\n- STUDY 3 - ROOT CAUSE: is the TYPE the right split, and does the node TF matter? -');
  const FIX = b => ruleAt(b, 0.5, 1.0);          // one fixed rule, compared across cuts
  console.log('\n   (a) the SAME rule (entry -0.5h, stop 1h, TP 1/2/3h) per type');
  console.log('     type      n     fill    SL   TP1   E[R]');
  for (const type of [0, 1, 2, 3]) {
    const bx = all.filter(b => b.type === type);
    if (bx.length < 40) continue;
    const a = scoreSubset(bx, FIX, stride);
    console.log(`   ${TYPE_NAME[type].padEnd(6)} ${String(Math.ceil(bx.length / stride)).padStart(6)} ${pct(a.fill, a.n)} ${pct(a.sl, a.fill)} ${pct(a.tp1, a.fill)} ${num(a.exp / Math.max(1, a.fill))}`);
  }
  console.log('\n   (b) the SAME rule per box height in units of the node ATR (h / ATR(node))');
  const BUCK = [[0, 0.5], [0.5, 1], [1, 2], [2, 4], [4, 8], [8, 1e9]];
  console.log('     h/ATR        n     fill    SL   TP1   E[R]');
  for (const [lo, hi] of BUCK) {
    const bx = all.filter(b => b.h / b.trig >= lo && b.h / b.trig < hi);
    if (bx.length < 40) continue;
    const a = scoreSubset(bx, FIX, stride);
    console.log(`   ${(lo + '-' + (hi > 1e8 ? '+' : hi)).padEnd(10)} ${String(Math.ceil(bx.length / stride)).padStart(6)} ${pct(a.fill, a.n)} ${pct(a.sl, a.fill)} ${pct(a.tp1, a.fill)} ${num(a.exp / Math.max(1, a.fill))}`);
  }
  console.log('\n   (c) the SAME rule per node TF');
  console.log('     TF       n     fill    SL   TP1   E[R]');
  for (const tf of tfs) {
    const bx = all.filter(b => b.nodeTF === tf);
    if (bx.length < 40) continue;
    const a = scoreSubset(bx, FIX, stride);
    console.log(`   ${(tf + 'm').padEnd(7)} ${String(Math.ceil(bx.length / stride)).padStart(6)} ${pct(a.fill, a.n)} ${pct(a.sl, a.fill)} ${pct(a.tp1, a.fill)} ${num(a.exp / Math.max(1, a.fill))}`);
  }

  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, JSON.stringify({ at: new Date().toISOString(), files: H.files, perTF, byType, stride, map: mapOut, place: placeOut }, null, 1));
  console.log(`\nJSON  ${outFile}`);
  return 0;
}

module.exports = { readHst, aggregate, trSeries, prefix, compositeAt, findHst, nextTF, TF: LADDER, nz, series, atrPips, engPips };
if (require.main === module) {
  const argv = process.argv.slice(2);
  if (argv.includes('--probe') && !argv.includes('--study')) process.exit(probe());
  process.exit(main());
}
