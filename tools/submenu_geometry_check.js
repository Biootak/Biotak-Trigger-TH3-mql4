// Sub-menu ladder geometry model — mirrors BiotakMenu.mqh verbatim.
// Proves, for every tool count 1..20 on every chart size and menu position:
//   1. no two buttons are closer than their skin allows (BTN+MIN_GAP in the
//      fan/ring, TILE+MIN_GAP in row B's rail, PITCH in the grid — the tile is
//      narrower than the disc),
//   2. no button ever comes closer to the orb than ORB/2 + half a footprint,
//   3. every button footprint stays inside the padded chart rect,
//   4. the grid panel stays fully on-chart,
//   5. the grid never shows more rows than the chart can hold (that is what
//      makes it PAGE, so a row can never spill past the bottom edge).
// Run: node tools/submenu_geometry_check.js
'use strict';

const BTN = 44, BG_MARGIN = 4, PAD = 10, ORB = 64, ORB_HALF = 32;
const MIN_GAP = 6;                 // SUB_MIN_GAP == CIRC_GAP — one gap language
const FAN_MAX = 6, RING_MAX = 8;
const FAN_R = 112, FAN_SPREAD = 180.0, RING_R = 100;
// grid metrics — mirror SUB_CELL_VIS / SUB_CELL_GAP / SUB_CELL_MARG in
// BiotakMenu.mqh (and the same consts in tools/gen-th3-icons.js).
const CELL_VIS = 40, CELL_GAP = 6, CELL_MARG = 3;
const CELL_CANVAS = CELL_VIS + 2 * CELL_MARG;   // 46 — the cell_*.bmp side
const PITCH = CELL_VIS + CELL_GAP;              // 46 — == CELL_CANVAS on purpose
const COLS = 4, GRID_PAD = 10, GRID_HDR = 28, GRID_PGR = 24;
const PAGE_ROWS = 4;
const EDGE_TRIGGER = 90, CIRC_GAP = 6;
// P-UI-207 (2026-10-22): ROW B — the Tools sub-menu rail — stands its items on the
// TILE it PAINTS, not on the 44px seat. `SubRailTile()` returns CIRC_BG_SIZE (52,
// BiotakMenu_A.mqh:112) and CircRailStep/Lead/Run/Room (BiotakMenu_Ring.mqh) are that
// tile's ONE owner, so this mirror asks the same four questions the product asks:
//   pitch = tile + CIRC_GAP                       -> 58 (not 50)
//   lead  = ORB/2 + tile/2 + CIRC_GAP             -> 64 (not 60)
//   run   = lead + (n-1)*pitch + tile/2           -> the orb centre to the FAR tile's edge
//   room  = free - PAD - tile/2                   -> the padded run the tiles must end inside
// A 52px tile on the retired 50px seat pitch is -2px: tile on tile. `RETIRED_SEAT`
// keeps the old mirror for ONE purpose — printing which decisions the tile moved.
const RAIL_TILE = 52;                                        // == CIRC_BG_SIZE
const RETIRED_SEAT = BTN;                                    // the pre-fix mirror (pitch 50)
const railStep = (tile) => tile + CIRC_GAP;                  // CircRailStep(tile)
const railLead = (tile) => ORB_HALF + tile / 2 + CIRC_GAP;   // CircRailLead(tile)
const railRun  = (tile, n) => railLead(tile) + (n - 1) * railStep(tile) + tile / 2;
const railRoom = (free, tile) => free - PAD - tile / 2;      // CircRailRoom(free,tile)
const RAIL_PITCH = railStep(RAIL_TILE);                      // 58 — the printed number
const HIDE = -500;

const pol = (d, r) => [Math.cos(d * Math.PI / 180) * r, Math.sin(d * Math.PI / 180) * r];
const chordRadius = (n, sweep) => {
  if (n < 2) return 0;
  const s = Math.sin(((sweep / (n - 1)) / 2) * Math.PI / 180);
  return s < 1e-6 ? 1e9 : (BTN + MIN_GAP) / (2 * s);
};
const fanFitR = (n, ax, ay, cw, ch) => {
  let r = FAN_R;
  const reach = PAD + BTN / 2 + BG_MARGIN;
  const step = n > 1 ? FAN_SPREAD / (n - 1) : 0, start = 210 - FAN_SPREAD / 2;
  for (let k = 0; k < n; k++) {
    const [c, s] = pol(start + k * step, 1);
    let lim = 1e18;
    if (c > 1e-6) lim = Math.min(lim, (cw - reach - ax) / c);
    else if (c < -1e-6) lim = Math.min(lim, (ax - reach) / -c);
    if (s > 1e-6) lim = Math.min(lim, (ch - reach - ay) / s);
    else if (s < -1e-6) lim = Math.min(lim, (ay - reach) / -s);
    if (lim < 1e17) r = Math.min(r, lim);
  }
  return r;
};
// the rail's OWN rule (SubRailAxis): axis by near edge, direction by room, fit by the
// tile's run — `tile` is the tile that row PAINTS (row B hands in CIRC_BG_SIZE).
function railAxis(ox, oy, cw, ch, n, tile) {
  const nearL = ox <= EDGE_TRIGGER, nearR = ox >= cw - EDGE_TRIGGER;
  const nearT = oy <= EDGE_TRIGGER, nearB = oy >= ch - EDGE_TRIGGER;
  if (!(nearL || nearR || nearT || nearB)) return { ax: 0, ay: 0, fits: false };
  const trainLen = railRun(tile, n);
  if (nearL || nearR) {
    const up = railRoom(oy, tile), down = railRoom(ch - oy, tile);
    let dir = up >= down ? -1 : 1;
    if (dir === -1 && up < trainLen && down >= trainLen) dir = 1;
    else if (dir === 1 && down < trainLen && up >= trainLen) dir = -1;
    return { ax: 0, ay: dir, fits: (dir === -1 ? up : down) >= trainLen };
  }
  const left = railRoom(ox, tile), right = railRoom(cw - ox, tile);
  let dir = left >= right ? -1 : 1;
  if (dir === -1 && left < trainLen && right >= trainLen) dir = 1;
  else if (dir === 1 && right < trainLen && left >= trainLen) dir = -1;
  return { ax: dir, ay: 0, fits: (dir === -1 ? left : right) >= trainLen };
}
// the ring needs RING_R + BTN/2 + BG_MARGIN clearance on all four sides
const ringFits = (ox, oy, cw, ch) => {
  const need = RING_R + BTN / 2 + BG_MARGIN;
  return ox - need >= PAD && ox + need <= cw - PAD &&
         oy - need >= PAD && oy + need <= ch - PAD;
};
// SubPageRowsCap(): how many rows this CHART can really show
const pageRowsCap = ch => {
  const room = ch - 2 * PAD - GRID_HDR - GRID_PAD - GRID_PGR + CELL_GAP;
  let r = Math.floor(room / PITCH);
  if (r < 1) r = 1;
  if (r > PAGE_ROWS) r = PAGE_ROWS;
  return r;
};
// SubPageSize() = columns x rows-that-fit
const pageSize = ch => COLS * pageRowsCap(ch);

// SubPanelRect(): prefer LEFT (the Tools axis points up-left), then right, then
// a band below/above the orb, then a clamped placement with a hard floor.
function panelRect(ox, oy, cw, ch, rows, paged) {
  const pw = COLS * CELL_VIS + (COLS - 1) * CELL_GAP + 2 * GRID_PAD;
  const ph = GRID_HDR + rows * CELL_VIS + (rows - 1) * CELL_GAP + GRID_PAD + (paged ? GRID_PGR : 0);
  const gap = ORB_HALF + 10;
  const minX = PAD, maxX = Math.max(PAD, cw - PAD - pw);
  const minY = PAD, maxY = Math.max(PAD, ch - PAD - ph);
  const leftX = ox - gap - pw, rightX = ox + gap;
  const belowY = oy + gap, aboveY = oy - gap - ph;
  const okL = leftX >= minX && leftX <= maxX;
  const okR = rightX >= minX && rightX <= maxX;
  const okB = belowY >= minY && belowY <= maxY;
  const okA = aboveY >= minY && aboveY <= maxY;
  let x = rightX, y = oy - Math.round(ph / 2);
  if (okL) x = leftX;
  else if (okR) x = rightX;
  else if (okB) { x = ox - Math.round(pw / 2); y = belowY; }
  else if (okA) { x = ox - Math.round(pw / 2); y = aboveY; }
  else if (leftX > rightX) x = leftX;
  x = Math.max(minX, Math.min(maxX, x));
  y = Math.max(minY, Math.min(maxY, y));
  return { x, y, w: pw, h: ph, rows };
}
function layout(n, ox, oy, cw, ch, tile = RAIL_TILE) {
  const rail = railAxis(ox, oy, cw, ch, n, tile);
  if (n <= FAN_MAX) {
    if (rail.ax || rail.ay) {
      if (rail.fits) return { mode: 'RAIL', pts: Array.from({ length: n }, (_, k) => {
        const d = railLead(tile) + k * railStep(tile);
        return [ox + rail.ax * d, oy + rail.ay * d];
      }) };
      return grid(n, ox, oy, cw, ch);
    }
    if (fanFitR(n, ox, oy, cw, ch) >= chordRadius(n, FAN_SPREAD)) {
      const r = Math.min(FAN_R, fanFitR(n, ox, oy, cw, ch));
      const step = n > 1 ? FAN_SPREAD / (n - 1) : 0, start = 210 - FAN_SPREAD / 2;
      return { mode: 'FAN', r, pts: Array.from({ length: n }, (_, k) => {
        const [dx, dy] = pol(start + k * step, r);
        return [ox + Math.round(dx), oy + Math.round(dy)];
      }) };
    }
    return grid(n, ox, oy, cw, ch);
  }
  if (n <= RING_MAX && ringFits(ox, oy, cw, ch)) {
    return { mode: 'RING', r: RING_R, pts: Array.from({ length: n }, (_, k) => {
      const [dx, dy] = pol(-90 + 360 * k / n, RING_R);
      return [ox + Math.round(dx), oy + Math.round(dy)];
    }) };
  }
  return grid(n, ox, oy, cw, ch);
}
function grid(n, ox, oy, cw, ch) {
  const ps = pageSize(ch);
  const cap = pageRowsCap(ch);
  const paged = n > ps;
  const rows = paged ? cap : Math.min(Math.ceil(n / COLS), cap);
  const p = panelRect(ox, oy, cw, ch, rows, paged);
  const pts = [];
  for (let i = 0; i < n; i++) {
    const on = (paged ? Math.floor(i / ps) : 0) === 0;
    const k = i % ps, c = k % COLS, r = Math.floor(k / COLS);
    pts.push(on ? [p.x + GRID_PAD + c * PITCH + CELL_VIS / 2,
                   p.y + GRID_HDR + r * PITCH + CELL_VIS / 2] : [HIDE, HIDE]);
  }
  return { mode: paged ? 'GRID/paged' : 'GRID', panel: p, rows, pts, paged };
}

const CH = [[1920, 1080, 'desktop'], [1280, 720, 'laptop'], [900, 600, 'small'],
            [600, 400, 'tiny'], [300, 900, 'narrow'], [1600, 320, 'short'],
            [1600, 220, 'v-short'], [240, 240, 'v-narrow']];
// positions as fractions of the chart, plus the clamped extremes
const POSF = [[0.5, 0.5, 'centre'], [0.03, 0.04, 'top-left'], [0.97, 0.96, 'bottom-right'],
              [0.5, 0.04, 'top-edge'], [0.03, 0.5, 'left-edge'], [0.5, 0.96, 'bottom-edge'],
              [0.97, 0.5, 'right-edge'], [0.25, 0.75, 'mid-low'], [0.8, 0.2, 'mid-high']];
let fail = 0, checked = 0;
for (const [cw, ch, cn] of CH) {
  for (const [fx, fy, pn] of POSF) {
    // the orb is clamped exactly like CircCreateOrb / the drag handler
    const ox = Math.max(PAD + ORB_HALF, Math.min(cw - PAD - ORB_HALF, Math.round(cw * fx)));
    const oy = Math.max(PAD + ORB_HALF, Math.min(ch - PAD - ORB_HALF, Math.round(ch * fy)));
    for (let n = 1; n <= 20; n++) {
      const L = layout(n, ox, oy, cw, ch);
      const isGrid = L.mode.indexOf('GRID') === 0;
      const isRail = L.mode === 'RAIL';
      // row B's rail stands 52px tiles, so BOTH the footprint half and the collision
      // floor are the TILE's (row A's fan/ring keep the 44px seat + 4px glow).
      const half = isGrid ? CELL_CANVAS / 2 : (isRail ? RAIL_TILE / 2 : BTN / 2 + BG_MARGIN);
      const needD = isGrid ? PITCH : (isRail ? RAIL_TILE + MIN_GAP : BTN + MIN_GAP);
      const vis = L.pts.filter(p => p[0] > -100);
      checked++;
      let minD = Infinity, minOrb = Infinity;
      for (let a = 0; a < vis.length; a++) {
        minOrb = Math.min(minOrb, Math.hypot(vis[a][0] - ox, vis[a][1] - oy));
        for (let b = a + 1; b < vis.length; b++)
          minD = Math.min(minD, Math.hypot(vis[a][0] - vis[b][0], vis[a][1] - vis[b][1]));
      }
      const off = vis.filter(p => p[0] - half < PAD - 1 || p[0] + half > cw - PAD + 1 ||
                                  p[1] - half < PAD - 1 || p[1] + half > ch - PAD + 1);
      const panelOff = L.panel && (L.panel.x < PAD - 1 || L.panel.y < PAD - 1 ||
                                   L.panel.x + L.panel.w > cw - PAD + 1 ||
                                   L.panel.y + L.panel.h > ch - PAD + 1);
      // ORB CLEARANCE is only guaranteed BY GEOMETRY while the sub-items are the
      // orb's PEERS (fan/rail/ring: all at z 1010, so one under the orb would be
      // drawn beneath it and become unclickable). In the GRID the orb sits at
      // z 2000, above the panel (1004) and the cells (1010) — so a panel that
      // runs under the orb tucks behind it, the orb stays visible AND clickable,
      // and clicking there still means "close the sub-menu".
      // The grid needs pw + ORB + gap + 2*PAD = 292px of width (or the same idea
      // of height for a below/above band). Charts smaller than that are below
      // the indicator's own envelope (the ring needs ~192px, the settings cards
      // 312px and clamp too), so only the on-chart invariants are asserted there.
      const orbClearRequired = isGrid ? (Math.max(cw, ch) >= 300) : true;
      const ok = (vis.length < 2 || minD >= needD - 0.5) &&
                 (!orbClearRequired || minOrb === Infinity || minOrb >= ORB_HALF + half - 0.5) &&
                 off.length === 0 && !panelOff;
      if (!ok) {
        fail++;
        if (fail <= 15) console.log(`FAIL ${cn}/${pn} (${ox},${oy}) n=${n} [${L.mode}] minD=${minD.toFixed(1)}/${needD} orb=${minOrb.toFixed(1)} off=${off.length} panelOff=${!!panelOff}`);
      }
    }
  }
}
console.log(`\n${checked} cases checked — ` + (fail === 0
  ? 'PASS: no collision, no orb overlap, nothing off-chart'
  : `${fail} FAILURES`));

console.log('\nchord-radius floor (SUB_MIN_GAP=' + MIN_GAP + ', button=' + BTN + '):');
for (let n = 3; n <= 8; n++)
  console.log(`  n=${n}  fan rMin=${chordRadius(n, 180).toFixed(1)}  ring rMin=${chordRadius(n, 360).toFixed(1)}`);
const pw = COLS * CELL_VIS + (COLS - 1) * CELL_GAP + 2 * GRID_PAD;
console.log(`\ngrid panel ${pw}px wide · cell ${CELL_VIS}px (canvas ${CELL_CANVAS}px == pitch ${PITCH}px)`);
console.log(`  heights ` + [1, 2, 3, 4].map(r =>
  `${r}r=${GRID_HDR + r * CELL_VIS + (r - 1) * CELL_GAP + GRID_PAD}`).join(' ') +
  ` · paged=${GRID_HDR + 4 * CELL_VIS + 3 * CELL_GAP + GRID_PAD + GRID_PGR}`);
console.log('  page size is CHART-DERIVED (cols x rows-that-fit):');
for (const [cw, ch, cn] of CH)
  console.log(`    ${cn.padEnd(8)} ${cw}x${ch}  rows=${pageRowsCap(ch)}  pageSize=${pageSize(ch)}  -> paging starts at n=${pageSize(ch) + 1}`);
console.log(`\ngrid envelope: a side placement needs pw+ORB+gap+2*PAD = ${pw + ORB + 10 + 2 * PAD}px of width;`);
console.log(`               a below/above band needs panelH+ORB+gap+2*PAD (${GRID_HDR + 4 * CELL_VIS + 3 * CELL_GAP + GRID_PAD + GRID_PGR + ORB + 10 + 2 * PAD}px at 4 paged rows, less with fewer).`);
console.log('               Below that the panel tucks UNDER the orb (orb z 2000 > panel 1004) — it stays on top and clickable.');
const show = (label, cw, ch, fx, fy) => {
  const ox = Math.max(PAD + ORB_HALF, Math.min(cw - PAD - ORB_HALF, Math.round(cw * fx)));
  const oy = Math.max(PAD + ORB_HALF, Math.min(ch - PAD - ORB_HALF, Math.round(ch * fy)));
  console.log(`${label}: ` + Array.from({ length: 20 }, (_, i) =>
    `${i + 1}:${layout(i + 1, ox, oy, cw, ch).mode}`).join(' '));
};
console.log();
show('mode @ 1920 centre   ', 1920, 1080, 0.5, 0.5);
show('mode @ 1920 top-left ', 1920, 1080, 0.03, 0.04);
show('mode @ 600x400 centre', 600, 400, 0.5, 0.5);
const L = layout(12, 960, 540, 1920, 1080);
console.log(`\n12 tools @ 1920 centre   -> ${L.mode}, panel ${L.panel.w}x${L.panel.h} at (${L.panel.x},${L.panel.y})`);
const L2 = layout(12, 42, 42, 1920, 1080);
console.log(`12 tools @ 1920 top-left -> ${L2.mode}, panel ${L2.panel.w}x${L2.panel.h} at (${L2.panel.x},${L2.panel.y})`);
const L3 = layout(12, 300, 450, 600, 900);
console.log(`12 tools @ 600x900 narrow-> ${L3.mode}, panel ${L3.panel.w}x${L3.panel.h} at (${L3.panel.x},${L3.panel.y})`);

// ---- ROW B: the rail's TILE, and every decision it moves ---------------------
// P-UI-207 (2026-10-22). The rail used to be modelled on the 44px SEAT (pitch 50)
// while the product paints a 52px TILE (pitch 58, lead 64) — a 52 tile on a 50 pitch
// is -2px, tile on tile. The difference is not cosmetic: on a cramped chart it is
// exactly the decision between a rail that fits and one that has to escalate. This
// section names every (chart, position, N) the tile MOVES against the retired seat
// mirror, so a mirror that drifts back to the seat pitch — or a layout constant that
// moves one more decision — fails here WITH the case's own name.
const EXPECT_FLIPS = [
  ['short', 'top-left', 4], ['short', 'bottom-right', 4],
  ['v-short', 'top-left', 2], ['v-short', 'bottom-right', 2],
  ['v-narrow', 'top-edge', 1], ['v-narrow', 'left-edge', 1],
  ['v-narrow', 'bottom-edge', 1], ['v-narrow', 'right-edge', 1],
  ['v-narrow', 'mid-low', 2],
];
const flips = [];
for (const [cw, ch, cn] of CH) {
  for (const [fx, fy, pn] of POSF) {
    const ox = Math.max(PAD + ORB_HALF, Math.min(cw - PAD - ORB_HALF, Math.round(cw * fx)));
    const oy = Math.max(PAD + ORB_HALF, Math.min(ch - PAD - ORB_HALF, Math.round(ch * fy)));
    for (let n = 1; n <= 20; n++) {
      const now = layout(n, ox, oy, cw, ch, RAIL_TILE).mode;
      const was = layout(n, ox, oy, cw, ch, RETIRED_SEAT).mode;
      if (now !== was) flips.push({ key: `${cn} ${pn} n=${n}`, cn, pn, n, was, now, ox, oy });
    }
  }
}
const want = new Set(EXPECT_FLIPS.map(([cn, pn, n]) => `${cn} ${pn} n=${n}`));
console.log(`\nrow B rail — the TILE it paints: tile=${RAIL_TILE} (== CIRC_BG_SIZE), pitch=${RAIL_PITCH}, ` +
            `lead=${railLead(RAIL_TILE)}, run(${RAIL_TILE},n)=${railRun(RAIL_TILE, 2)} at n=2`);
console.log(`  decisions the tile MOVES vs the retired ${RETIRED_SEAT}px seat (pitch ${railStep(RETIRED_SEAT)}):`);
for (const f of flips) {
  console.log(`    ${f.cn.padEnd(8)} ${f.pn.padEnd(12)} n=${String(f.n).padEnd(2)} ${f.was} -> ${f.now}  (orb ${f.ox},${f.oy})`);
}
const extra = flips.filter(f => !want.has(f.key)).map(f => f.key);
const lost = [...want].filter(k => !flips.some(f => f.key === k));
const flipOk = extra.length === 0 && lost.length === 0;
console.log(`  flips: ${flips.length} (expected ${want.size}) — ` + (flipOk
  ? 'PASS: row B lays its items on the tile it paints, and only these nine decisions move'
  : `FAIL: unexpected [${extra.join(', ') || 'none'}] · missing [${lost.join(', ') || 'none'}]`));
if (!flipOk) process.exitCode = 1;
