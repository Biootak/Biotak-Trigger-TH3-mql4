// gen-th3-icons.js — premium glassy 32-bit alpha BMP icons for Biotak Trigger TH3.
// Output: ./Files/Icons/*.bmp (embedded into the .ex4 via #resource at compile time).
// BMP format: 32bpp BI_RGB, BGRA (premultiplied alpha), bottom-up rows.
// Rendering engine (4x supersampling + glass skins) derived from the shared
// family project ../ichimoku/tools/gen-icons.js — the visual language of the
// circular menu is identical there. Glyph art below is the TH3 semantic set:
//   zone=trigger/zone levels, chk=visibility check, tl=(legacy) trend arrow,
//   atr=ATR range labels (vertical range bracket + double arrow),
//   dots=TH dotted levels, box=timeframe lock, custom=TH3 tool,
//   htf=HTF candles, pin=price pin, step=step-mode stairs,
//   factor=factor gauge, tools=tools menu.
// Run: node tools/gen-th3-icons.js   (regenerates every BMP in Files/Icons)
// Full deploy (regenerate + compile + sync to every MT4 terminal + verify):
//   powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1
'use strict';
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------- colors
// Warm Amber Professional Palette — high contrast on both dark & light charts.
// Ring buttons use the orb's dark-glass identity: near-opaque slate core,
// amber accent for ON. Icons stay legible on white AND black charts.
const OFF = [205, 214, 228];   // #cdd6e4 inactive icon (bright silver — on dark glass)
const ON  = [255, 200, 60];    // #ffc83c active icon (warm amber)
const ORB = [255, 225, 120];   // #ffe178 orb icon (pale amber)
const CYAN = [255, 171, 0];    // #ffab00 accent (amber — replaces cyan)
const BADGE_RING = [18, 22, 33];    // #121621 deep navy ring

// ---------------------------------------------------------------- shapes
// L    = line segment {x1,y1,x2,y2,w}
// CF   = filled circle {cx,cy,r}
// RF   = filled rect {x1,y1,x2,y2}
// RING = circle ring {cx,cy,r,w}

function seg(x1, y1, x2, y2, w) { return { t: 'L', x1, y1, x2, y2, w }; }
function cfill(cx, cy, r) { return { t: 'CF', cx, cy, r }; }
function rfill(x1, y1, x2, y2) { return { t: 'RF', x1, y1, x2, y2 }; }
function ring(cx, cy, r, w) { return { t: 'RING', cx, cy, r, w }; }
function rect(x1, y1, x2, y2, w) {
  return [seg(x1, y1, x2, y1, w), seg(x2, y1, x2, y2, w), seg(x2, y2, x1, y2, w), seg(x1, y2, x1, y1, w)];
}

function dashSegs(x1, y1, x2, y2, dash, gap, w) {
  const out = [];
  const dx = x2 - x1, dy = y2 - y1;
  const len = Math.hypot(dx, dy);
  if (len <= 0) return out;
  const ux = dx / len, uy = dy / len;
  let t = 0;
  while (t < len) {
    const t1 = Math.min(t + dash, len);
    out.push(seg(x1 + ux * t, y1 + uy * t, x1 + ux * t1, y1 + uy * t1, w));
    t += dash + gap;
  }
  return out;
}
function dashPoly(points, dash, gap, w) {
  const out = [];
  for (let i = 0; i < points.length - 1; i++)
    out.push(...dashSegs(points[i][0], points[i][1], points[i + 1][0], points[i + 1][1], dash, gap, w));
  return out;
}

// ---------------------------------------------------------------- icon art (32x32 space)
// Semantic icon set — each glyph IS the Ichimoku component it toggles:
//   tenkan : fast conversion wave + momentum arrow + pivot dots
//   kijun  : flat equilibrium base line + centered balance diamond
//   kumo   : two-bump cloud with flat base (the cloud itself)
//   chikou : lagging wave + back-arrow (close shifted back in time)
//   dots   : dotted line style toggle (bold dotted wave + baseline)
//   mtf    : stacked timeframe frames + ichimoku wave inside
//   box    : zone rectangle with selection corner handles
//   htf    : candlesticks with wicks (higher timeframe)
//   orb    : bow-medallion ingest — tools/orb-bow-master.bgra (built by
//            tools/make-orb-bow.ps1). No yy overlay anymore (retired).
const ART = {
  zone: [
    // zone — trigger/zone levels: two level lines joined by step ticks
    seg(5, 11, 27, 11, 2.0), seg(5, 21, 27, 21, 2.0),
    seg(9, 11, 9, 21, 1.5), seg(16, 11, 16, 21, 1.5), seg(23, 11, 23, 21, 1.5),
  ],
  zones: [
    // zones — MID-ZONE BAND: the translucent area between two step levels.
    // (dashed level lines + side brackets — the actual chart object it edits)
    ...dashSegs(6, 10, 26, 10, 3, 2, 1.8),
    ...dashSegs(6, 22, 26, 22, 3, 2, 1.8),
    seg(6, 10, 6, 22, 1.5), seg(26, 10, 26, 22, 1.5),
  ],
  ssls: [
    // ssls — SS/LS STEP LINES: short (SS) level over long (LS) level with ticks.
    seg(5, 10, 27, 10, 2.2),
    ...dashSegs(5, 22, 27, 22, 2.6, 2.2, 2.0),
    seg(11, 10, 11, 22, 1.4), seg(21, 10, 21, 22, 1.4),
  ],
  chk: [
    // chk — circle with check (visibility / enabled)
    ring(16, 16, 9.0, 2.0),
    seg(11.5, 16.3, 14.4, 19.2, 2.2), seg(14.4, 19.2, 20.6, 12.6, 2.2),
  ],
  tl: [
    // tl — LEGACY rising trend arrow (was the ATR glyph; kept generating so
    // the shipped tl_*.bmp files stay fresh — nothing references them now).
    seg(5, 25, 22, 8, 2.2),
    seg(22, 8, 17.6, 9.4, 1.8), seg(22, 8, 20.6, 12.4, 1.8),
  ],
  atr: [
    // atr — RANGE BRACKET: high/low ticks joined by a vertical double arrow.
    // Reads as "measure the range" = what the ATR labels card shows.
    seg(8, 7, 24, 7, 2.0),
    seg(8, 25, 24, 25, 2.0),
    seg(16, 8.5, 16, 23.5, 2.0),
    seg(16, 8.5, 12.6, 12.2, 1.8), seg(16, 8.5, 19.4, 12.2, 1.8),
    seg(16, 23.5, 12.6, 19.8, 1.8), seg(16, 23.5, 19.4, 19.8, 1.8),
  ],
  dots: [
    // dots — TH DOTTED LEVELS: three harmonic price levels measured from a
    // left axis, dotted exactly like the TH lines drawn on the chart.
    // (The old dashed-wave-over-baseline was ichimoku heritage — a wave
    // reads as "trend", not as horizontal harmonic levels.)
    seg(4.5, 8, 4.5, 24, 1.8),
    ...dashSegs(8, 9, 27, 9, 2.4, 2.8, 2.0),
    ...dashSegs(8, 16, 27, 16, 2.4, 2.8, 2.0),
    ...dashSegs(8, 23, 27, 23, 2.4, 2.8, 2.0),
  ],
  box: [
    // box — timeframe lock: rounded padlock body + shackle + keyhole
    ...rect(9.5, 14.5, 22.5, 25.5, 1.9),
    seg(12.5, 14.5, 12.5, 10.5, 1.9), seg(12.5, 10.5, 19.5, 10.5, 1.9), seg(19.5, 10.5, 19.5, 14.5, 1.9),
    cfill(16, 19.5, 1.7),
  ],
  custom: [
    // custom — TH3 tool: analysis trend with markers
    seg(4, 21, 10, 13, 2.2), seg(10, 13, 15, 17, 2.2), seg(15, 17, 22, 7, 2.2),
    seg(24, 20, 24, 28, 2.0), seg(20, 24, 28, 24, 2.0),
    cfill(10, 13, 1.5), cfill(22, 7, 1.5),
  ],
  htf: [
    // htf — three candles with wicks (higher timeframe)
    seg(8, 4, 8, 9, 1.6), rfill(5.5, 9, 10.5, 19), seg(8, 19, 8, 25, 1.6),
    seg(16, 6, 16, 11, 1.6), rfill(13.5, 11, 18.5, 23), seg(16, 23, 16, 28, 1.6),
    seg(24, 3, 24, 8, 1.6), rfill(21.5, 8, 26.5, 18), seg(24, 18, 24, 24, 1.6),
  ],
  pin: [
    // pin — map pin: halo head, tapered tip, anchor dot
    ring(16, 11.5, 7.5, 2.0),
    seg(10.6, 16.5, 16, 29, 2.4), seg(21.4, 16.5, 16, 29, 2.4),
    cfill(16, 11.5, 2.6),
  ],
  tools: [
    // tools — tools menu: three rows of sliders/knobs
    seg(4, 9, 28, 9, 1.8), cfill(10, 9, 2.2),
    seg(4, 16, 28, 16, 1.8), cfill(20, 16, 2.2),
    seg(4, 23, 28, 23, 1.8), cfill(14, 23, 2.2),
  ],
  step: [
    // step — step-mode override: ascending staircase
    seg(4.5, 22, 11, 22, 2.1), seg(11, 22, 11, 15.5, 2.1), seg(11, 15.5, 17, 15.5, 2.1),
    seg(17, 15.5, 17, 9, 2.1), seg(17, 9, 23.5, 9, 2.1),
    seg(23.5, 9, 19.4, 10.4, 1.8), seg(23.5, 9, 22.1, 13.1, 1.8),
  ],
  factor: [
    // factor — factor override: dial/gauge with needle
    ring(16, 16, 7.2, 2.0),
    seg(16, 16, 20.8, 11.2, 2.4),
    cfill(16, 16, 2.2),
  ],
};
// --- orb center art: bow-medallion ingest (NOT procedural) ---
// Single source of truth: tools/orb-bow-master.bgra — 72x72 premultiplied
// BGRA top-down bytes built by tools/make-orb-bow.ps1 from the artwork
// (circle-cropped, checkerboard removed, black-lifted for dark charts).
// P-ICONS-05: the retired yy overlay object is gone from the MQL side, so
// yy.bmp is no longer generated at all — the orb is ONE 72px image.
const ORB_MASTER_SIZE = 72;
function orbSkinFromMaster() {
  const master = path.join(__dirname, 'orb-bow-master.bgra');
  if (!fs.existsSync(master))
    throw new Error('missing ' + master + ' — run powershell -File tools/make-orb-bow.ps1 first');
  const m = fs.readFileSync(master);
  if (m.length !== ORB_MASTER_SIZE * ORB_MASTER_SIZE * 4)
    throw new Error('orb-bow-master.bgra bad size: ' + m.length + ' (want ' + (ORB_MASTER_SIZE * ORB_MASTER_SIZE * 4) + ')');
  return Buffer.from(m);
}

const BADGE_ART = [
  { ...cfill(16, 16, 15), color: CYAN },
  { ...ring(16, 16, 13.5, 3), color: BADGE_RING },
];

// ---------------------------------------------------------------- rasterizer
function distSeg(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1, dy = y2 - y1;
  const l2 = dx * dx + dy * dy;
  if (l2 <= 0) return Math.hypot(px - x1, py - y1);
  let t = ((px - x1) * dx + (py - y1) * dy) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
}

function contains(sh, x, y) {
  if (sh.t === 'L')  return distSeg(x, y, sh.x1, sh.y1, sh.x2, sh.y2) <= sh.w / 2;
  if (sh.t === 'CF') return Math.hypot(x - sh.cx, y - sh.cy) <= sh.r;
  if (sh.t === 'RF') return x >= sh.x1 && x <= sh.x2 && y >= sh.y1 && y <= sh.y2;
  if (sh.t === 'RING') return Math.abs(Math.hypot(x - sh.cx, y - sh.cy) - sh.r) <= sh.w / 2;
  return false;
}

function render(outSize, shapes, color) {
  const S = 32, SS = 4, N = SS * SS;
  const buf = Buffer.alloc(outSize * outSize * 4);
  for (let py = 0; py < outSize; py++) {
    for (let px = 0; px < outSize; px++) {
      let hits = 0, r = 0, g = 0, b = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const x = (px + (sx + 0.5) / SS) * S / outSize;
          const y = (py + (sy + 0.5) / SS) * S / outSize;
          let col = null;
          for (const sh of shapes) if (contains(sh, x, y)) col = sh.color || color;
          if (col) { hits++; r += col[0]; g += col[1]; b += col[2]; }
        }
      }
      const idx = (py * outSize + px) * 4;
      buf[idx]     = Math.round(b / N);          // B (premultiplied)
      buf[idx + 1] = Math.round(g / N);          // G
      buf[idx + 2] = Math.round(r / N);          // R
      buf[idx + 3] = Math.round(hits / N * 255); // A
    }
  }
  return buf;
}

// ---------------------------------------------------------------- fx rasterizer (skins)
// pixelFn(x, y) returns a PREMULTIPLIED [r,g,b,a] sample in output-pixel space.
function renderFx(outSize, pixelFn) {
  return renderFxWH(outSize, outSize, pixelFn);
}

function renderFxWH(w, h, pixelFn) {
  const SS = 4, N = SS * SS;
  const buf = Buffer.alloc(w * h * 4);
  for (let py = 0; py < h; py++) {
    for (let px = 0; px < w; px++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const c = pixelFn(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS);
          if (c) { r += c[0]; g += c[1]; b += c[2]; a += c[3]; }
        }
      }
      const idx = (py * w + px) * 4;
      buf[idx]     = Math.round(b / N);
      buf[idx + 1] = Math.round(g / N);
      buf[idx + 2] = Math.round(r / N);
      buf[idx + 3] = Math.round(a / N);
    }
  }
  return buf;
}

const clamp01 = v => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerp = (a, b, t) => a + (b - a) * t;

// premultiplied rgba helper
function pm(rgb, a) { return [rgb[0] * a / 255, rgb[1] * a / 255, rgb[2] * a / 255, a]; }
// "src over dst", premultiplied inputs
function over(dst, src) {
  const sa = src[3] / 255;
  const k = 1 - sa;
  return [src[0] + dst[0] * k, src[1] + dst[1] * k, src[2] + dst[2] * k, src[3] + dst[3] * k];
}

// Gaussian halo around a circle (glow for ON/orb, drop shadow for OFF)
function halo(x, y, cx, cy, r, sigma, peak, rgb, dy = 0) {
  const d = Math.hypot(x - cx, y - (cy + dy));
  const q = (d - r) / sigma;
  const a = peak * Math.exp(-q * q);
  if (a < 0.5) return null;
  return pm(rgb, a);
}

// Vertical gradient fill inside a circle
function gradCircle(x, y, cx, cy, r, top, bot) {
  const d = Math.hypot(x - cx, y - cy);
  if (d > r) return null;
  const t = clamp01((y - (cy - r)) / (2 * r));
  return pm(lerpColor(top, bot, t), Math.round(lerp(top[3], bot[3], t)));
}
function lerpColor(a, b, t) {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
}

// 1px circle border band
function circleBorder(x, y, cx, cy, r, rgb, a, w = 1.4) {
  const d = Math.hypot(x - cx, y - cy);
  if (Math.abs(d - r) > w / 2) return null;
  return pm(rgb, a);
}

// Rounded-rect SDF distance (negative inside)
function rrSdf(x, y, cx, cy, hw, hh, rad) {
  const qx = Math.abs(x - cx) - (hw - rad);
  const qy = Math.abs(y - cy) - (hh - rad);
  const ox = Math.max(qx, 0), oy = Math.max(qy, 0);
  return Math.hypot(ox, oy) + Math.min(Math.max(qx, qy), 0) - rad;
}

// --- circ_off.bmp / circ_on.bmp : 52x52, 44px item circle centered (4px margin)
// Dark-glass skin (matches the orb): near-opaque slate core reads on BOTH
// white and dark charts. off  = slate glass + light rim + top sheen + shadow
//                               on  = same base + amber tint + amber border/glow
function circSkin(on) {
  const S = 52, c = 26, r = 22;
  return renderFx(S, (x, y) => {
    let col = [0, 0, 0, 0];
    const s = halo(x, y, c, c, r, 3.5, 89, [0, 0, 0], 3);        // drop shadow
    if (s) col = over(col, s);
    if (on) {
      const g = halo(x, y, c, c, r, 3.2, 85, CYAN);               // amber glow
      if (g) col = over(col, g);
    }
    const f = gradCircle(x, y, c, c, r,
      on ? [74, 62, 36, 244] : [62, 72, 92, 244],                 // warm/slate top
      on ? [28, 23, 14, 250] : [17, 22, 33, 250]);                // dark bottom
    if (f) col = over(col, f);
    if (on) {
      const t = gradCircle(x, y, c, c, r,
        [CYAN[0], CYAN[1], CYAN[2], 92], [CYAN[0], CYAN[1], CYAN[2], 26]);
      if (t) col = over(col, t);                                  // amber tint
    }
    const sheen = gradCircle(x, y, c, c - 2, r - 1.8,
      [255, 255, 255, on ? 30 : 50], [255, 255, 255, 0]);         // top glass sheen
    if (sheen) col = over(col, sheen);
    const b = circleBorder(x, y, c, c, r,
      on ? CYAN : [235, 241, 250], on ? 245 : 88, on ? 2.0 : 1.4);
    if (b) col = over(col, b);
    return col[3] > 0 ? col : null;
  });
}

// --- orb_bg.bmp : 72x72 bow-medallion, embedded from tools/orb-bow-master.bgra
// (ingested artwork — see orbSkinFromMaster above, NOT a procedural skin)
function orbSkin() { return orbSkinFromMaster(); }

// --- badge.bmp : 12x12 GEAR icon (uniform settings affordance on every item)
// Amber cog with dark navy outline + hub — legible on white AND dark charts.
function badgeSkin() {
  const S = 12, c = 6, TEETH = 8;
  const Rbody = 3.3, H = 1.7, hole = 1.5;
  return renderFx(S, (x, y) => {
    const dx = x - c, dy = y - c;
    const d = Math.hypot(dx, dy);
    if (d > Rbody + H + 0.4) return null;
    const a = Math.atan2(dy, dx);
    const tooth = Math.pow(Math.abs(Math.cos(TEETH * a)), 1.4);
    const edge = Rbody + H * tooth;
    if (d <= hole) return pm(BADGE_RING, 255);              // dark center hub
    if (d <= edge) {
      if (d >= edge - 0.7) return over(pm(BADGE_RING, 235), pm(CYAN, 90)); // dark rim
      return pm(CYAN, 255);                                 // amber body
    }
    return null;
  });
}

// --- knob.bmp : 14x14 slider thumb, accent amber circle (preview range thumb)
function knobSkin() {
  const S = 14, c = 7, r = 6;
  return renderFx(S, (x, y) => {
    const d = Math.hypot(x - c, y - c);
    if (d > r) return null;
    let col = pm(CYAN, 255);
    if (Math.abs(d - 5.4) <= 0.7) col = over(col, pm([170, 110, 0], 255));
    return col;
  });
}

// --- chk_on.bmp / chk_off.bmp : 16x16 rounded checkbox (preview .prow checkbox)
function checkSkin(on) {
  const S = 16;
  return renderFx(S, (x, y) => {
    const d = rrSdf(x, y, 8, 8, 7, 7, 4);
    if (d > 0.7) return null;
    let col;
    if (on) {
      col = pm(CYAN, 255);
      const d1 = distSeg(x, y, 4.4, 8.4, 6.9, 10.9, 2.0);
      const d2 = distSeg(x, y, 6.9, 10.9, 11.6, 5.4, 2.0);
      if (Math.min(d1, d2) <= 1.0) col = over(col, pm(BADGE_RING, 255));
      if (d > -0.4) col = over(col, pm([255, 255, 255], 90)); // subtle edge
    } else {
      col = pm([42, 52, 66], 235);
      if (d > -0.8) col = over(col, pm([255, 255, 255], 64));
    }
    return col;
  });
}

// ---------------------------------------------------------------- settings-panel skins (v2)
// Fintech glass-card design language:
//   - Opaque matte body matching the on-chart palette card (C'17,23,34' /
//     #171722 family) so chart candles never bleed through the panel
//   - flat border like the palette card, thin hairline dividers, top amber accent
const PNL_W = 312;          // card width (content area)
const PNL_HEAD_H = 56;
const PNL_ROW_H = 50;
const PNL_FOOT_H = 48;
const PNL_MARGIN = 14;      // baked-in shadow margin around the card

// --- pnl_card3.bmp / pnl_card4.bmp : rounded glass card incl. shadow,
//     12px corners, top amber hairline, header + footer hairline dividers
function pnlCardSkin(rows) {
  const H = PNL_HEAD_H + rows * PNL_ROW_H + PNL_FOOT_H;
  const CW = PNL_W + 2 * PNL_MARGIN, CH = H + 2 * PNL_MARGIN;
  const buf = renderFxWH(CW, CH, (x, y) => {
    const cx = x - PNL_MARGIN, cy = y - PNL_MARGIN;
    let col = [0, 0, 0, 0];
    // drop shadow: soft band under/right of the card silhouette
    const sd = rrSdf(x, y, PNL_MARGIN + PNL_W / 2 + 2, PNL_MARGIN + H / 2 + 4,
                     PNL_W / 2 - 1, H / 2 - 1, 12);
    if (sd > 0 && sd < 10) col = over(col, pm([0, 0, 0], Math.round(95 * (1 - sd / 10))));
    const d = rrSdf(cx, cy, PNL_W / 2, H / 2, PNL_W / 2, H / 2, 12);
    if (d < 0.7) {
      if (d > -1.2) {
        col = over(col, pm([60, 70, 90], 255));              // flat border — matches palette card
      } else {
        col = over(col, pm([17, 23, 34], 255));              // opaque body — matches palette card
        if (cy >= 0 && cy <= 2.4 && cx > 14 && cx < PNL_W - 14)
          col = over(col, pm(CYAN, 205));                                    // amber accent hairline
        if (Math.abs(cy - PNL_HEAD_H) < 0.6) col = over(col, pm([235, 240, 248], 22));
        if (Math.abs(cy - (H - PNL_FOOT_H)) < 0.6) col = over(col, pm([235, 240, 248], 22));
      }
    }
    return col[3] > 0 ? col : null;
  });
  return { w: CW, h: CH, buf };
}

// --- pnl_knob.bmp : 18x18 slider thumb — glowing amber ring + bright core
function pnlKnobSkin() {
  const S = 18, c = 9;
  const buf = renderFxWH(S, S, (x, y) => {
    let col = [0, 0, 0, 0];
    const g = halo(x, y, c, c, 6, 2.2, 115, CYAN);
    if (g) col = over(col, g);
    const d = Math.hypot(x - c, y - c);
    if (d <= 6.4) {
      col = over(col, pm(CYAN, 255));
      if (d <= 4.4) col = over(col, pm([255, 248, 228], 255));
    }
    return col[3] > 0 ? col : null;
  });
  return { w: S, h: S, buf };
}

// --- pnl_sw_on.bmp / pnl_sw_off.bmp : 46x24 pill toggle body
function switchSkin(on) {
  const W = 46, H = 24;
  const buf = renderFxWH(W, H, (x, y) => {
    let col = [0, 0, 0, 0];
    if (on) {
      const g = halo(x, y, W / 2, H / 2, 11, 2.6, 65, CYAN);
      if (g) col = over(col, g);
    }
    const d = rrSdf(x, y, W / 2, H / 2, W / 2, H / 2, 12);
    if (d < 0.7) {
      if (d > -1.2) col = over(col, on ? pm([255, 216, 120], 190) : pm([235, 240, 248], 38));
      else col = over(col, on
        ? pm(lerpColor([255, 200, 60], [255, 138, 0], clamp01(x / W)), 255)
        : pm([34, 42, 56], 242));
    }
    return col[3] > 0 ? col : null;
  });
  return { w: W, h: H, buf };
}

// --- pnl_swknob.bmp : 18x18 white thumb with a soft drop shadow
function switchKnobSkin() {
  const S = 18, c = 9;
  const buf = renderFxWH(S, S, (x, y) => {
    let col = [0, 0, 0, 0];
    const sh = halo(x, y, c, c, 6.4, 2.0, 60, [0, 0, 0], 1.6);
    if (sh) col = over(col, sh);
    const d = Math.hypot(x - c, y - c);
    if (d <= 6.4) {
      col = over(col, pm([210, 218, 230], 255));       // bottom shade ring
      if (d <= 5.6) col = over(col, pm([246, 249, 253], 255));
    }
    return col[3] > 0 ? col : null;
  });
  return { w: S, h: S, buf };
}

// ---------------------------------------------------------------- BMP writer (32bpp, bottom-up)
function writeBmp(file, w, h, topDownBgra) {
  const rowSize = w * 4;
  const fileSize = 54 + rowSize * h;
  const buf = Buffer.alloc(fileSize);
  buf.write('BM', 0, 'ascii');
  buf.writeUInt32LE(fileSize, 2);
  buf.writeUInt32LE(54, 10);
  buf.writeUInt32LE(40, 14);
  buf.writeInt32LE(w, 18);
  buf.writeInt32LE(h, 22);
  buf.writeUInt16LE(1, 26);
  buf.writeUInt16LE(32, 28);
  buf.writeUInt32LE(0, 30);
  buf.writeUInt32LE(rowSize * h, 34);
  buf.writeInt32LE(2835, 38);
  buf.writeInt32LE(2835, 42);
  for (let y = 0; y < h; y++)
    topDownBgra.copy(buf, 54 + (h - 1 - y) * rowSize, y * rowSize, (y + 1) * rowSize);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, buf);
}

// ---------------------------------------------------------------- main
const outDirs = [path.join(__dirname, '..', 'Files', 'Icons')];

const files = [];
for (const [name, art] of Object.entries(ART)) {
  files.push([name + '_off.bmp', () => render(28, art, OFF)]);
  files.push([name + '_on.bmp',  () => render(28, art, ON)]);
}
files.push(['badge.bmp',    () => badgeSkin()]);
files.push(['circ_off.bmp', () => circSkin(false)]);
files.push(['circ_on.bmp',  () => circSkin(true)]);
files.push(['orb_bg.bmp',   () => orbSkin()]);
files.push(['knob.bmp',     () => knobSkin()]);

// settings-panel v2 skins (non-square capable) — تا 12 ردیف برای پنل باکس‌ها
const panelFiles = [
  { name: 'pnl_card3.bmp',   ...pnlCardSkin(3) },
  { name: 'pnl_card4.bmp',   ...pnlCardSkin(4) },
  { name: 'pnl_card5.bmp',   ...pnlCardSkin(5) },
  { name: 'pnl_card6.bmp',   ...pnlCardSkin(6) },
  { name: 'pnl_card7.bmp',   ...pnlCardSkin(7) },
  { name: 'pnl_card8.bmp',   ...pnlCardSkin(8) },
  { name: 'pnl_card9.bmp',   ...pnlCardSkin(9) },
  { name: 'pnl_card10.bmp',  ...pnlCardSkin(10) },
  { name: 'pnl_card11.bmp',  ...pnlCardSkin(11) },
  { name: 'pnl_card12.bmp',  ...pnlCardSkin(12) },
  { name: 'pnl_knob.bmp',    ...pnlKnobSkin() },
  { name: 'pnl_sw_on.bmp',   ...switchSkin(true) },
  { name: 'pnl_sw_off.bmp',  ...switchSkin(false) },
  { name: 'pnl_swknob.bmp',  ...switchKnobSkin() },
];

let count = 0;
for (const [fname, make] of files) {
  const bgra = make();
  const side = Math.round(Math.sqrt(bgra.length / 4));   // all skins are square
  for (const dir of outDirs) {
    writeBmp(path.join(dir, fname), side, side, bgra);
    count++;
  }
}
for (const pf of panelFiles) {
  for (const dir of outDirs) {
    writeBmp(path.join(dir, pf.name), pf.w, pf.h, pf.buf);
    count++;
  }
}
console.log('Generated ' + (files.length + panelFiles.length) + ' icons into:');
for (const dir of outDirs) console.log('  ' + dir);
