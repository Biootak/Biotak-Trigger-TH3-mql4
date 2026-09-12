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

// ---------------------------------------------------------------- Base Box MINI strip icons
// R-BKSTRIP 2026-09-07 — TradingView-style icon set for the floating strip
// (item 13), modeled on TV's floating drawing toolbar: WHITE rounded strip
// (bk_strip.bmp) with dark outlined glyphs (bk_*). Files:
//   bk_bucket       : paint-bucket fill-color button (opens the color popover)
//   bk_style0..4    : border line-style glyphs (button + dropdown rows)
//   bk_w1..5        : border width glyphs (line + end ticks, thickness 1..5)
//   bk_lock_off     : OPEN padlock (unlocked)
//   bk_lock_on      : closed padlock, amber-filled body (locked)
//   bk_del          : outlined trash can
//   bk_more         : three horizontal dots (full-settings menu)
//   bk_chev         : small down-chevron (STYLE/WIDTH ▾ selectors — a text
//                     "▼" label renders as "?" in MT4/Wine fonts, so the
//                     chevron is a bitmap like every other strip glyph)
//   bk_dds          : WIDE obsidian dropdown popover (STYLE menu — fits
//                     "Dash-Dot-Dot" with headroom, content 216x192)
//   bk_ddw          : NARROW obsidian dropdown popover (WIDTH menu —
//                     short "Npx" rows only, content 120x192)
// Obsidian 2026-09-11 — the strip left the white TV family with the cards:
// light icon ink on the dark glass (was near-black on white).
const BK_DARK = [203, 212, 226];        // light icon ink for the obsidian strip
const BK_AMBER = [255, 171, 0];      // locked padlock body / selected accents
const BK_STYLES = [
  // Solid — strong full line
  [ seg(4, 16, 28, 16, 3.4) ],
  // Dash — evenly spaced dashes
  [ ...dashSegs(4, 16, 28, 16, 4.0, 3.0, 2.8) ],
  // Dot — round dots
  [ cfill(8, 16, 1.9), cfill(14, 16, 1.9), cfill(20, 16, 1.9), cfill(26, 16, 1.9) ],
  // Dash-Dot — dash then a dot
  [ ...dashSegs(4, 16, 18, 16, 3.6, 2.6, 2.6), cfill(24.5, 16, 2.0) ],
  // Dash-Dot-Dot — dash then two dots
  [ ...dashSegs(4, 16, 14, 16, 3.6, 2.6, 2.6), cfill(20.5, 16, 1.9), cfill(26.5, 16, 1.9) ],
];
function bkWidthArt(n) {
  return [
    seg(6.5, 16, 25.5, 16, 1.4 + (n - 1) * 0.9),   // the line itself, thickness 1..5
    seg(6.5, 11.5, 6.5, 20.5, 1.5), seg(25.5, 11.5, 25.5, 20.5, 1.5),   // ruler end ticks
  ];
}
const BK_BUCKET = [
  seg(7.5, 9.5, 24.5, 9.5, 1.9),                  // rim
  seg(9.5, 9.5, 12.5, 18.5, 1.9),                 // left wall
  seg(12.5, 18.5, 19.5, 18.5, 1.9),               // bottom
  seg(19.5, 18.5, 22.5, 9.5, 1.9),                // right wall
  cfill(20.8, 21.2, 1.7),                         // falling droplet
];
// TV-parity 2026-09-07 — pencil = BORDER color button (TV's border-color tool
// is the pencil with a color underline; the dynamic underline bar itself is a
// PnlSetRect drawn under this glyph, recolored live in BkMiniRefresh).
const BK_PENCIL = [
  seg(7.5, 24.5, 10.5, 21.5, 2.4),                // tip point
  seg(10.5, 21.5, 21.0, 11.0, 3.4),               // wooden shaft
  seg(21.0, 11.0, 24.5, 7.5, 3.0),                // eraser cap
  seg(19.2, 12.8, 22.8, 9.2, 1.2),                // ferrule band
];
// TV-parity 2026-09-07 — "T" = TEXT button (TV's text-color tool). Bold serif
// T; the dynamic text-color underline is a live PnlSetRect like the pencil.
const BK_TEXT = [
  seg(8.5, 8.0, 23.5, 8.0, 3.2),                  // top bar
  seg(16.0, 8.0, 16.0, 24.0, 3.2),                // stem
];
const BK_LOCK_OFF = [   // OPEN padlock — shackle floats above the body (gap)
  ...rect(9.5, 15.5, 22.5, 24.5, 2.2),
  seg(11.5, 14.5, 11.5, 9.5, 2.2), seg(11.5, 9.5, 20.5, 9.5, 2.2), seg(20.5, 9.5, 20.5, 14.5, 2.2),
  cfill(16, 19.5, 1.9),
];
const BK_LOCK_ON = [   // CLOSED padlock, shackle meets the body; amber body
  { ...rfill(10.5, 16.5, 21.5, 23.5), color: BK_AMBER },
  ...rect(9.5, 15.5, 22.5, 24.5, 2.2),
  seg(12.5, 15.5, 12.5, 10.5, 2.2), seg(12.5, 10.5, 19.5, 10.5, 2.2), seg(19.5, 10.5, 19.5, 15.5, 2.2),
];
const BK_DEL = [   // outlined trash can (TV style)
  seg(8, 10.5, 24, 10.5, 2.4),
  ...rect(13.5, 7.5, 18.5, 10.5, 2.0),
  ...rect(10.5, 13.5, 21.5, 24.5, 2.2),
  seg(13, 16.5, 13, 21.5, 1.7), seg(16, 16.5, 16, 21.5, 1.7), seg(19, 16.5, 19, 21.5, 1.7),
];
const BK_MORE = [   // three horizontal dots (TV "more")
  cfill(8.5, 16, 2.1), cfill(16, 16, 2.1), cfill(23.5, 16, 2.1),
];
const BK_CHEV = [   // down-chevron for the STYLE/WIDTH ▾ selector buttons
  seg(8.0, 12.5, 16.0, 20.0, 4.2),
  seg(16.0, 20.0, 24.0, 12.5, 4.2),
];

// --- orb center art: bow-medallion ingest (NOT procedural) ---
// Single source of truth: tools/orb-bow-master.bgra — 72x72 premultiplied
// BGRA top-down bytes built by tools/make-orb-bow.ps1 from the artwork
// (circle-cropped, checkerboard removed, black-lifted for dark charts).
// P-ICONS-05: the retired yy overlay object is gone from the MQL side, so
// yy.bmp is no longer generated at all — the orb is ONE 72px image.
const ORB_MASTER_SIZE = 72;
// Shared ingest for the TWO orb states (the preview's .orb / .orbtext split):
//   closed -> orb_bg.bmp   (the bow medallion)      make-orb-bow.ps1
//   open   -> orb_word.bmp (the same disc + "TRex") make-orb-word.ps1
// Both masters are the same 72x72 premultiplied top-down BGRA, built by
// ingesting the bow artwork, so the two states share one chrome and the orb
// only changes in the middle (P-ICONS-04/05).
function orbMasterFrom(file, script) {
  const master = path.join(__dirname, file);
  if (!fs.existsSync(master))
    throw new Error('missing ' + master + ' — run powershell -File tools/' + script + ' first');
  const m = fs.readFileSync(master);
  if (m.length !== ORB_MASTER_SIZE * ORB_MASTER_SIZE * 4)
    throw new Error(file + ' bad size: ' + m.length + ' (want ' + (ORB_MASTER_SIZE * ORB_MASTER_SIZE * 4) + ')');
  return Buffer.from(m);
}
function orbSkinFromMaster() {
  return orbMasterFrom('orb-bow-master.bgra', 'make-orb-bow.ps1');
}
function orbWordFromMaster() {
  return orbMasterFrom('orb-word-master.bgra', 'make-orb-word.ps1');
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
  // R-PANELCHIP: flattened SVG glyph geometry (tools/svgpath.js)
  if (sh.t === 'PL') {
    const p = sh.pts;
    for (let i = 1; i < p.length; i++)
      if (distSeg(x, y, p[i - 1][0], p[i - 1][1], p[i][0], p[i][1]) <= sh.w / 2) return true;
    return false;
  }
  if (sh.t === 'POLY') {
    let inside = false;
    const p = sh.pts;
    for (let a = 0, b = p.length - 1; a < p.length; b = a++) {
      const xi = p[a][0], yi = p[a][1], xj = p[b][0], yj = p[b][1];
      if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }
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

// ---------------------------------------------------------------- settings-panel skins (v3)
// Obsidian Gold — the panel_all_redesign_preview.html card language (2026-09-11).
// The settings cards left the TV-white family: dark body, 14px corners, hairline
// row dividers, deep drop shadow. Geometry is UNCHANGED
// (PNL_W/HEAD/ROW/FOOT/MARGIN) so no .mqh coordinate moves — only paint.
//   .card { width:312px; border-radius:14px;
//           background:linear-gradient(180deg,#1E242F,#171C25 52%,#12161D);
//           border:1px solid #2C3444;
//           box-shadow:0 28px 62px rgba(0,0,0,.70), inset 0 1px 0 rgba(255,255,255,.075) }
//   .row { border-top:1px solid rgba(255,255,255,.055) }
const PNL_W = 312;          // card width (content area)
// WIDE-CARDS contract (2026-09-11): PNL_WIDE_WEL = PNL_WIDE_WEL in
// Biotak/BiotakPanels.mqh (624 = two full 312 slots: 16+280+16|16+280+16).
// Change together — the MQL blits cardW+2*MARGIN and a wrong canvas leaves
// bare background. P-UI-25: 608 let right-column glow pads bleed past the
// card edge, so the card is two whole slots, not 608.
const PNL_WIDE_WEL = 624;
const PNL_HEAD_H = 56;
const PNL_ROW_H = 42;       // TV-dense single-line rows (matches BiotakPanels.mqh)
const PNL_FOOT_H = 48;
const PNL_MARGIN = 14;      // baked-in shadow margin around the card
const PNL_RAD = 14;         // .card border-radius

const CARD_TOP = [0x1E, 0x24, 0x2F];   // #1E242F
const CARD_MID = [0x17, 0x1C, 0x25];   // #171C25  (at 52%)
const CARD_BOT = [0x12, 0x16, 0x1D];   // #12161D
const CARD_BD  = [0x2C, 0x34, 0x44];   // #2C3444
const HAIR_A   = 14;                   // rgba(255,255,255,.055) * 255
const CARD_SHADOW = [6, 9, 14];        // near-black shadow tint

// 3-stop vertical gradient, exactly the preview's stops.
function cardGrad(t) {
  if (t <= 0.52) {
    const u = t / 0.52;
    return [lerp(CARD_TOP[0], CARD_MID[0], u), lerp(CARD_TOP[1], CARD_MID[1], u), lerp(CARD_TOP[2], CARD_MID[2], u)];
  }
  const u = (t - 0.52) / 0.48;
  return [lerp(CARD_MID[0], CARD_BOT[0], u), lerp(CARD_MID[1], CARD_BOT[1], u), lerp(CARD_MID[2], CARD_BOT[2], u)];
}

// --- pnl_cardN.bmp / pnl_cardW{N}.bmp : Obsidian-Gold card incl. shadow,
//     14px corners and the hairline row/footer dividers the preview draws
//     with border-top. wide=true bakes the 608px two-column card.
function pnlCardSkin(rows, fade, wide) {
  const W = wide ? PNL_WIDE_WEL : PNL_W;
  const H = PNL_HEAD_H + rows * PNL_ROW_H + PNL_FOOT_H;
  const CW = W + 2 * PNL_MARGIN, CH = H + 2 * PNL_MARGIN;

  // .fade — 26px band hugging the footer, transparent -> rgba(18,22,29,.92).
  // Only the preview's scrollable cards carry it (CARDS[].fade), so it is a
  // per-skin OPTION: PnlCardFade() picks pnl_card<N>f.bmp for those cards.
  const fadeTop = H - PNL_FOOT_H - 26, fadeBot = H - PNL_FOOT_H;

  // hairline y positions (card-local): header/rows + each row seam + rows/footer
  const seams = [PNL_HEAD_H];
  for (let k = 1; k < rows; k++) seams.push(PNL_HEAD_H + k * PNL_ROW_H);
  seams.push(H - PNL_FOOT_H);

  const buf = renderFxWH(CW, CH, (x, y) => {
    const cx = x - PNL_MARGIN, cy = y - PNL_MARGIN;
    let col = [0, 0, 0, 0];

    // drop shadow: silhouette nudged down, blurred. The baked margin is only
    // PNL_MARGIN wide, so the blur is tightened from the CSS 62px to fit —
    // a wider margin would move every .mqh coordinate.
    const sd = rrSdf(x, y, PNL_MARGIN + W / 2 + 1, PNL_MARGIN + H / 2 + 5,
                     W / 2 - 1, H / 2 - 1, PNL_RAD);
    if (sd > 0 && sd < 13) {
      const k = 1 - sd / 13;
      col = over(col, pm(CARD_SHADOW, Math.round(175 * k * k)));
    }

    const d = rrSdf(cx, cy, W / 2, H / 2, W / 2, H / 2, PNL_RAD);
    if (d < 0.7) {
      if (d > -1.2) {
        col = over(col, pm(CARD_BD, 255));                     // 1px #2C3444 border
      } else {
        const g = cardGrad(cy / H);
        col = over(col, pm(g, 255));                           // obsidian body
        // inset 0 1px 0 rgba(255,255,255,.075) — light catching the top edge
        if (cy > -1.2 && cy < 0.2) col = over(col, pm([255, 255, 255], 19));
        // hairline dividers
        for (const s of seams) {
          if (Math.abs(cy - s) < 0.6) { col = over(col, pm([255, 255, 255], HAIR_A)); break; }
        }
        // .fade wash over the last row, just above the footer
        if (fade && cy >= fadeTop && cy <= fadeBot) {
          const u = (cy - fadeTop) / (fadeBot - fadeTop);
          col = over(col, pm([18, 22, 29], Math.round(235 * u)));
        }
      }
    }
    return col[3] > 0 ? col : null;
  });
  return { w: CW, h: CH, buf };
}

// ---------------------------------------------------------------- sub-menu skins (R-SUBLADDER)
// The Tools grid panel + its cells — Obsidian Gold, mirroring
// panel_all_redesign_preview.html (.tgrid / .tcell / .pgbar) 1:1.
// These live in the RING-MENU family (dark glass), NOT the TV-white settings
// cards: the sub-menu hangs off the ring, so it must read as ring chrome.
// Geometry mirrors BiotakMenu.mqh SUB_* defines exactly — if one side moves,
// the other must move with it or the objects stop lining up with the art.
const SUB_CELL_VIS  = 40;    // visible rounded square (the .tcell)
const SUB_CELL_GAP  = 6;     // .cells gap
// The canvas is EXACTLY the pitch (40+6): adjacent canvases abut with zero
// overlap, so an ON cell's glow can never wash onto its neighbour — with a
// larger canvas the winner depended on object Z-order, i.e. it flickered.
const SUB_CELL_MARG  = 3;    // baked margin around a cell (glow + shadow room)
const SUB_GRID_COLS = 4;
const SUB_GRID_ROWS_MAX = 4; // panel BMPs are generated for 1..4 visible rows
const SUB_GRID_PAD  = 10;    // panel padding around the cell block
const SUB_GRID_HDR  = 28;    // header strip (dot + TOOLS + count)
const SUB_GRID_PGR  = 24;    // pager strip (paged panels only)
const SUB_PANEL_MARG = 12;   // baked shadow margin around the panel
const SUB_PANEL_W = SUB_GRID_COLS * SUB_CELL_VIS + (SUB_GRID_COLS - 1) * SUB_CELL_GAP
                    + 2 * SUB_GRID_PAD;

// --- cell_off.bmp / cell_on.bmp : 48x48 (40px tile + 4px glow margin)
// Rounded-square glass tile: radial sheen at 34%/28%, off = slate, on = amber
// tint + amber border + outer glow (the .tcell.on). The ring's circular
// circ_*.bmp is deliberately NOT reused: a grid of discs reads as scattered
// debris, a grid of tiles reads as one control block.
function cellSkin(on) {
  const S = SUB_CELL_VIS + 2 * SUB_CELL_MARG, V = SUB_CELL_VIS, r = 10;
  const buf = renderFxWH(S, S, (x, y) => {
    const cx = x - SUB_CELL_MARG, cy = y - SUB_CELL_MARG;
    let col = [0, 0, 0, 0];
    const sd = rrSdf(x, y, SUB_CELL_MARG + V / 2 + 1, SUB_CELL_MARG + V / 2 + 1.6,
                     V / 2 - 1, V / 2 - 1, r);
    if (sd > 0 && sd < 3.2) col = over(col, pm([0, 0, 0], Math.round(120 * (1 - sd / 3.2))));
    if (on) {   // outer amber glow (box-shadow 0 0 14px), clipped to the canvas
      const g = rrSdf(x, y, SUB_CELL_MARG + V / 2, SUB_CELL_MARG + V / 2, V / 2 + 0.8, V / 2 + 0.8, r + 0.8);
      if (g < 0 && g > -2.6) col = over(col, pm(CYAN, Math.round(120 * (1 + g / 2.6))));
    }
    const d = rrSdf(cx, cy, V / 2, V / 2, V / 2, V / 2, r);
    if (d < 0.6) {
      if (d > -1.0) {                                        // 1px border
        col = over(col, pm(on ? CYAN : [255, 255, 255], on ? 140 : 26));
      } else {
        // radial-gradient(circle at 34% 28%, top, bottom) over a 40px tile.
        // The base tile is IDENTICAL for on/off — .on only adds the amber
        // overlay + border + glow, exactly like the preview's .tcell.on.
        const t = clamp01(Math.hypot(cx - V * 0.34, cy - V * 0.28) / (V * 0.98));
        col = over(col, pm(lerpColor([42, 50, 66], [22, 27, 36], t), 250));
        if (on) col = over(col, pm(CYAN, Math.round(255 * lerp(0.30, 0.12, t))));
        if (d > -2.2 && d < -1.0 && cy < 3) col = over(col, pm([255, 255, 255], 26));  // top sheen
      }
    }
    return col[3] > 0 ? col : null;
  });
  return { w: S, h: S, buf };
}

// --- sub_panel_r<N>[p].bmp : the grid panel backdrop.
// ONE BMP PER VISIBLE ROW COUNT (1..4, +24px when paged) because the height
// varies: stretching a single rounded panel would turn its 13px corners into
// ellipses and blur its 1px border — the "blur by scaling" trap. Width is
// fixed (4 columns), so only the height multiplies.
function subPanelSkin(rows, paged) {
  const H = SUB_GRID_HDR + rows * SUB_CELL_VIS + (rows - 1) * SUB_CELL_GAP
            + SUB_GRID_PAD + (paged ? SUB_GRID_PGR : 0);
  const M = SUB_PANEL_MARG, W = SUB_PANEL_W, CW = W + 2 * M, CH = H + 2 * M;
  const buf = renderFxWH(CW, CH, (x, y) => {
    const cx = x - M, cy = y - M;
    let col = [0, 0, 0, 0];
    // baked drop shadow (box-shadow 0 22px 48px rgba(0,0,0,.72))
    const sd = rrSdf(x, y, M + W / 2 + 1, M + H / 2 + 5, W / 2 - 2, H / 2 - 2, 13);
    if (sd > 0 && sd < 15) col = over(col, pm([5, 8, 14], Math.round(165 * (1 - sd / 15))));
    const d = rrSdf(cx, cy, W / 2, H / 2, W / 2, H / 2, 13);
    if (d < 0.6) {
      if (d > -1.1) {
        col = over(col, pm([44, 52, 68], 255));              // #2C3444 border
      } else {
        // linear-gradient(180deg,#1E242F,#141922)
        col = over(col, pm(lerpColor([30, 36, 47], [20, 25, 34], clamp01(cy / H)), 249));
        if (cy < 1.6) col = over(col, pm([255, 255, 255], 20));   // inset 0 1px 0 highlight
        // faint divider above the pager strip so the strip reads as its own band
        if (paged && Math.abs(cy - (H - SUB_GRID_PGR)) < 0.6)
          col = over(col, pm([255, 255, 255], 22));
      }
    }
    return col[3] > 0 ? col : null;
  });
  return { w: CW, h: CH, buf };
}


//     the backdrop of the Base Box MINI floating toolbar — obsidian glass
//     (dark body #1E242F->#141922, #2C3444 border, deep drop shadow, light
//     outlined icons). Geometry untouched (380px, 8 slots); only paint left
//     the white TV family with the cards. R-BKSTRIP 2026-09-07.
function bkStripSkin() {
  const W = 380, H = 58, M = 14, CW = W + 2 * M, CH = H + 2 * M;
  const buf = renderFxWH(CW, CH, (x, y) => {
    const cx = x - M, cy = y - M;
    let col = [0, 0, 0, 0];
    const sd = rrSdf(x, y, M + W / 2 + 2, M + H / 2 + 4, W / 2 - 1, H / 2 - 1, 12);
    if (sd > 0 && sd < 15) col = over(col, pm([5, 8, 14], Math.round(165 * (1 - sd / 15))));
    const d = rrSdf(cx, cy, W / 2, H / 2, W / 2, H / 2, 10);
    if (d < 0.7) {
      if (d > -1.2) col = over(col, pm([44, 52, 68], 255));                // #2C3444 border
      else {
        col = over(col, pm(lerpColor([30, 36, 47], [20, 25, 34], clamp01(cy / H)), 249));
        if (d > -2.4 && d < -1.2) col = over(col, pm([255, 255, 255], 20));
      }
    }
    return col[3] > 0 ? col : null;
  });
  return { w: CW, h: CH, buf };
}

// --- bk_dds.bmp / bk_ddw.bmp : OBSIDIAN dropdown popovers (baked shadow) —
//     the STYLE (wide, fits "Dash-Dot-Dot") and WIDTH (narrow, short "Npx"
//     rows) selector menus of the strip. Content-fitted pair so no label
//     ever truncates; R-BKSTRIP.
function bkDdSkin(W, H) {
  const M = 8, CW = W + 2 * M, CH = H + 2 * M;
  const buf = renderFxWH(CW, CH, (x, y) => {
    const cx = x - M, cy = y - M;
    let col = [0, 0, 0, 0];
    const sd = rrSdf(x, y, M + W / 2 + 2, M + H / 2 + 3, W / 2 - 1, H / 2 - 1, 10);
    if (sd > 0 && sd < 15) col = over(col, pm([5, 8, 14], Math.round(165 * (1 - sd / 15))));
    const d = rrSdf(cx, cy, W / 2, H / 2, W / 2, H / 2, 10);
    if (d < 0.7) {
      if (d > -1.2) col = over(col, pm([44, 52, 68], 255));
      else col = over(col, pm(lerpColor([30, 36, 47], [20, 25, 34], clamp01(cy / H)), 249));
    }
    return col[3] > 0 ? col : null;
  });
  return { w: CW, h: CH, buf };
}

// --- pnl_knob.bmp : 18x18 slider thumb — the preview's .knob: white face
//     lit from 35%/28%, dark hairline rim, soft drop shadow + the faint 3px
//     outer halo (rgba(255,255,255,.04)) that lifts it off the track
function pnlKnobSkin() {
  const S = 18, c = 9;
  const buf = renderFxWH(S, S, (x, y) => {
    let col = [0, 0, 0, 0];
    const sh = halo(x, y, c, c + 1.2, 6.4, 2.0, 55, [15, 20, 30]);
    if (sh) col = over(col, sh);
    const d = Math.hypot(x - c, y - c);
    if (d > 6.4 && d < 9.0) col = over(col, pm([255, 255, 255], 10));  // faint halo
    if (d <= 6.4) {
      // RICH-MT4 (2026-09-11): the old gray ring #BEC6D4 exists nowhere in the
      // preview (its rim is rgba(0,0,0,.38)) and read as a blurry outline —
      // bake the spec's dark rim instead so the knob sits crisp on the track.
      col = over(col, pm([0, 0, 0], 97));                 // spec rim .38*255
      if (d <= 5.6) {
        const t = clamp01(Math.hypot(x - c * 0.7, y - c * 0.56) / 9.5);  // lit 35%/28%
        col = over(col, pm(lerpColor([255, 255, 255], [221, 227, 236], t), 255));
      }
      if (d > 4.6 && d <= 5.6 && y < c - 1) col = over(col, pm([255, 255, 255], 70));  // top catchlight
    }
    return col[3] > 0 ? col : null;
  });
  return { w: S, h: S, buf };
}

// --- pnl_cb_on.bmp / pnl_cb_off.bmp : 20px TV-style checkboxes (panel
//     kind=1 rows) — white/gray off, navy + white check on. Two-color art via
//     per-shape color (render() honors sh.color).
function rrFill(x1, y1, x2, y2, r) {
  return [
    rfill(x1 + r, y1, x2 - r, y2),
    rfill(x1, y1 + r, x2, y2 - r),
    cfill(x1 + r, y1 + r, r), cfill(x2 - r, y1 + r, r),
    cfill(x1 + r, y2 - r, r), cfill(x2 - r, y2 - r, r),
  ];
}
const tint = (arr, c) => arr.map(s => Object.assign({ color: c }, s));
const CB_NAVY = [38, 44, 56];
function cbArt(on) {
  if (on) return [
    ...tint(rrFill(6, 6, 26, 26, 5), CB_NAVY),
    { ...seg(11, 16.5, 14.2, 19.7, 2.6), color: [255, 255, 255] },
    { ...seg(14.2, 19.7, 21, 12, 2.6), color: [255, 255, 255] },
  ];
  return [
    ...tint(rrFill(6, 6, 26, 26, 5), [178, 186, 200]),
    ...tint(rrFill(8.4, 8.4, 23.6, 23.6, 3), [255, 255, 255]),
  ];
}

// (pill-switch skins retired with the dark-glass panels — kind=1 rows are TV
// checkboxes now: pnl_cb_on/off.bmp above. R-PANELS 2026-09-07.)

// ---------------------------------------------------------------- panel row chips (R-PANELCHIP)
// The 13 redesign cards put a 22px icon chip on every row (preview CSS .gl):
//   off -> background rgba(255,255,255,.045), border rgba(255,255,255,.08),
//          glyph var(--muted)  #8C96A6
//   on  -> background var(--aSoft) rgba(accent,.12), border var(--aBd)
//          rgba(accent,.38..42), glyph var(--a1) (the accent's light stop)
// Chip and glyph are SEPARATE objects so one chip skin serves every glyph.
const GLYPHS = require('./glyphs');
const { parseGlyph } = require('./svgpath');

const ACCENTS = {
  gold:   { a1: [0xFF, 0xC2, 0x47], soft: [255, 171, 0],  softA: 31, bdA: 97  },
  jade:   { a1: [0x63, 0xEC, 0xBD], soft: [18, 184, 134], softA: 31, bdA: 102 },
  cyan:   { a1: [0x79, 0xDC, 0xFF], soft: [31, 168, 224], softA: 31, bdA: 102 },
  violet: { a1: [0xBC, 0xA6, 0xFF], soft: [124, 92, 255], softA: 36, bdA: 107 },
  ember:  { a1: [0xFF, 0xC0, 0x8C], soft: [255, 106, 43], softA: 33, bdA: 107 },
  rose:   { a1: [0xFF, 0xA7, 0xB6], soft: [240, 69, 95],  softA: 33, bdA: 107 },
};
const ACCENT_NAMES = Object.keys(ACCENTS);
const GLYPH_MUTED = [0x8C, 0x96, 0xA6];

const CHIP_VIS = 22;                       // .gl width/height
const CHIP_PAD = 2;                        // antialias room baked into the BMP
const CHIP_CANVAS = CHIP_VIS + 2 * CHIP_PAD;
const GLYPH_VIS = 13;                      // .gl svg { width:13px }
const GLYPH_PAD = 1;
const GLYPH_CANVAS = GLYPH_VIS + 2 * GLYPH_PAD;

const _glyphCache = {};
function glyphPrims(name) {
  if (!_glyphCache[name]) _glyphCache[name] = parseGlyph(GLYPHS[name] || '');
  return _glyphCache[name];
}

// Flattened glyph geometry (24-grid) -> render() shapes on a `target` grid.
function glyphShapes(name, target, strokeW, color) {
  const k = target / 24;
  const out = [];
  for (const p of glyphPrims(name)) {
    const pts = p.pts.map(([x, y]) => [x * k, y * k]);
    out.push(p.kind === 'fill' ? { t: 'POLY', pts, color } : { t: 'PL', pts, w: strokeW * k, color });
  }
  return out;
}

// 22px chip. acc = null -> the neutral (row off) chip.
function chipSkin(acc) {
  const S = CHIP_CANVAS;
  const c = (S - 1) / 2;
  const hw = (CHIP_VIS - 1) / 2;           // half-extent of the visible square
  const rad = 7;                           // .gl border-radius
  const rgb = acc ? acc.soft : [255, 255, 255];
  // RICH-MT4 (2026-09-11): the spec's .045/.08 whites sink below visibility
  // after the MT4 blit — the neutral bake runs one step brighter. Accent
  // chips keep their exact softA/bdA (their colour carries them).
  const bgA = acc ? acc.softA : 14;        // spec rgba(255,255,255,.045) * 255
  const bdA = acc ? acc.bdA : 26;          // spec rgba(255,255,255,.08) * 255

  const sdf = (x, y) => {
    const qx = Math.abs(x - c) - (hw - rad);
    const qy = Math.abs(y - c) - (hw - rad);
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - rad;
  };

  const buf = renderFxWH(S, S, (x, y) => {
    const d = sdf(x, y);
    if (d > 0.5) return null;
    const cov = clamp01(0.5 - d);
    let col = pm(rgb, bgA);
    const bw = clamp01(0.5 - Math.abs(d + 0.5));   // 1px border hugging the edge
    if (bw > 0) col = over(col, pm(rgb, bdA * bw));
    return [col[0] * cov, col[1] * cov, col[2] * cov, col[3] * cov];
  });
  return { w: S, h: S, buf };
}

// 13px glyph, transparent background, single flat colour.
// RICH-MT4 (2026-09-11): stroke 2.3 on the 32-grid (≈0.93px at 13px). The
// preview's SVG keeps 1.7 — but its browser AA holds a 0.69px stem while the
// MT4 blit + chart backdrop eats it, so the MT4 bake runs one weight heavier.
function glyphSkin(name, color) {
  const buf = render(GLYPH_VIS, glyphShapes(name, 32, 2.3, color), color);
  if (GLYPH_PAD === 0) return { w: GLYPH_VIS, h: GLYPH_VIS, buf };
  // pad with a transparent frame so the glyph never touches the bitmap edge
  const S = GLYPH_CANVAS;
  const out = Buffer.alloc(S * S * 4);
  for (let y = 0; y < GLYPH_VIS; y++)
    buf.copy(out, ((y + GLYPH_PAD) * S + GLYPH_PAD) * 4, y * GLYPH_VIS * 4, (y + 1) * GLYPH_VIS * 4);
  return { w: S, h: S, buf: out };
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

// ---------------------------------------------------------------- R-PANELUI2
// Chrome the redesign needs BEYOND the 22px chip (preview CSS author is the
// source of every colour here — do not re-derive):
//   .mark 30px accent chip (header)      .sw   40x22 pill switch
//   .val.chip 46x22 accent pill           .row.sec 6px accent dot
//   .row.sec .cnt neutral count pill      .key  18x18 keycap
//   .x 26x26 ghost close button           .card::before 3px accent top bar
//   .hd::after accent hairline            .row.sec band wash
//   .row.act accent wash                  .rail 2px active-row rail
// Every skin keeps a 2px antialias pad (PAD), so the MQL side must offset the
// object by -PAD: OBJ_BITMAP_LABEL always renders at native canvas size.
const PAD2 = 2;
const A2 = {
  gold:   [0xFF, 0x8A, 0x00], jade:   [0x12, 0xB8, 0x86], cyan:   [0x1F, 0xA8, 0xE0],
  violet: [0x7C, 0x5C, 0xFF], ember:  [0xFF, 0x6A, 0x2B], rose:   [0xF0, 0x45, 0x5F],
};
const A_INK = {
  gold:   [0x1A, 0x12, 0x06], jade:   [0x04, 0x14, 0x0F], cyan:   [0x04, 0x12, 0x1A],
  violet: [0x0C, 0x07, 0x22], ember:  [0x1A, 0x0A, 0x03], rose:   [0x1C, 0x04, 0x09],
};
const A_NAME = ['gold', 'jade', 'cyan', 'violet', 'ember', 'rose'];

// --aGlow — the coloured halo behind .mark / .sw.on / .btn.primary. Taken from
// the preview's .ac-* rules (rgba). Only the RGB is baked; the alpha is applied
// per-use by halo()'s `peak`.
const A_GLOW = {
  gold:   [255, 159, 10], jade:   [18, 184, 134], cyan:   [31, 168, 224],
  violet: [124, 92, 255], ember:  [255, 106, 43], rose:   [240, 69, 95],
};

// Glyphs that can sit ON an accent-filled surface (.mark, .btn.primary) — the
// preview gives them `color: var(--aInk)`, i.e. a DARK ink on the bright ramp.
// Emitted as gl_<name>_i_<accent>.bmp. Only these are needed; emitting an ink
// variant for all 57 glyphs would add 342 files for nothing.
const INK_GLYPHS = [
  'crosshair', 'layers', 'gauge', 'wave', 'candle', 'line', 'pin', 'steps',
  'sigma', 'box', 'type', 'target', 'bolt', 'check',
];

// Rounded box with optional vertical fill gradient, 1px border and a glow.
// visW/visH = the CSS element size; the canvas adds o.pad (default PAD2) on
// every side. Skins WITH a glow need a pad that holds ~2 sigma of it or the
// halo clips at the canvas edge and the control reads flat next to the
// preview (mark sigma 3.4 -> pad 7, switch 2.6 -> pad 6, secdot 1.8 -> pad 4;
// the MQL PNL_*_PAD twin must equal it — MT4 blits at native size).
function uiBox(o) {
  const P = (o.pad === undefined) ? PAD2 : o.pad;
  const W = o.w + 2 * P, H = o.h + 2 * P;
  const cx = W / 2, cy = H / 2;
  const hw = (o.w - 1) / 2, hh = (o.h - 1) / 2;
  const buf = renderFxWH(W, H, (x, y) => {
    const d = rrSdf(x, y, cx, cy, hw, hh, o.rad);
    if (d > 0.5 && !o.glow) return null;
    let col = [0, 0, 0, 0];
    if (o.glow) {
      const g = halo(x, y, cx, cy, Math.max(hw, hh), o.glow[1], o.glow[2], o.glow[0]);
      if (g) col = over(col, g);
    }
    if (d > 0.5) return col[3] > 0 ? col : null;
    const cov = clamp01(0.5 - d);
    if (o.top) {
      const t = clamp01((y - (cy - hh)) / (2 * hh));
      col = over(col, pm(lerpColor(o.top, o.bot, t), 255));
    }
    if (o.flat) col = over(col, pm(o.flat, o.flatA === undefined ? 255 : o.flatA));
    if (o.bd) {
      const bw = clamp01(0.5 - Math.abs(d + 0.5));
      if (bw > 0) col = over(col, pm(o.bd, o.bdA * bw));
    }
    return [col[0] * cov, col[1] * cov, col[2] * cov, col[3] * cov];
  });
  return { w: W, h: H, buf };
}

// --- .mark — 30px header chip: accent gradient, glow, inset top highlight
function markSkin(name) {
  const a1 = ACCENTS[name].a1, a2 = A2[name];
  const s = uiBox({ w: 30, h: 30, rad: 10, top: a1, bot: a2, pad: 7,
                    glow: [a2, 3.4, 90] });
  // inset 0 1px 0 rgba(255,255,255,.35) — a 1px light line hugging the top edge
  const buf = s.buf;
  const W = s.w, cx = W / 2, hw = (30 - 1) / 2, hh = (30 - 1) / 2, cy = W / 2;
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < W; y++) {
      const d = rrSdf(x, y, cx, cy, hw, hh, 10);
      if (d > -1.4 && d < -0.2) {   // just inside the top border
        const i = (y * W + x) * 4;
        const bev = pm([255, 255, 255], 90);
        // premultiplied "over" on the already-rendered pixel
        const sa = bev[3] / 255;
        buf[i]     = bev[0] + buf[i]     * (1 - sa);
        buf[i + 1] = bev[1] + buf[i + 1] * (1 - sa);
        buf[i + 2] = bev[2] + buf[i + 2] * (1 - sa);
        buf[i + 3] = bev[3] + buf[i + 3] * (1 - sa);
      }
    }
  }
  return s;
}

// --- .sw — 40x22 pill switch. on = accent gradient + aInk knob at x=28,
//     off = #232A37 face + #3A4353 border + #8D97A8 knob at x=10.
function swSkin(name, on) {
  const P = 6;   // holds the ON glow (~2 sigma); OFF shares the canvas so the
                 // MQL can place both states with one PNL_SW_PAD
  const s = uiBox(on
    ? { w: 40, h: 22, rad: 11, top: ACCENTS[name].a1, bot: A2[name], bd: A2[name], bdA: 255, pad: P,
        glow: [A2[name], 2.6, 70] }
    : { w: 40, h: 22, rad: 11, flat: [0x23, 0x2A, 0x37], bd: [0x3A, 0x43, 0x53], bdA: 255, pad: P });
  const buf = s.buf, W = s.w, H = s.h;
  const kc = on ? 28 : 10;
  const kcol = on ? A_INK[name] : [0x8D, 0x97, 0xA8];
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < H; y++) {
      const d = Math.hypot(x - (kc + P), y - (H / 2));
      if (d > 8.6) continue;
      const i = (y * W + x) * 4;
      const a = clamp01(8.0 - d + 0.5) * 255;
      const src = pm(kcol, a);
      const sa = src[3] / 255;
      buf[i]     = src[0] + buf[i]     * (1 - sa);
      buf[i + 1] = src[1] + buf[i + 1] * (1 - sa);
      buf[i + 2] = src[2] + buf[i + 2] * (1 - sa);
      buf[i + 3] = src[3] + buf[i + 3] * (1 - sa);
    }
  }
  return s;
}

// --- .val.chip — 46x22 accent-soft pill behind the slider value
function vchipSkin(name) {
  const ac = ACCENTS[name];
  return uiBox({ w: 46, h: 22, rad: 6, flat: ac.soft, flatA: ac.softA, bd: ac.soft, bdA: ac.bdA });
}

// --- .rail — 2px active-row accent rail (gradient a1 -> a2 over the row height)
function railSkin(name) {
  const W = 2 + PAD2, H = 42;
  const buf = renderFxWH(W, H, (x, y) => {
    if (x < 0.5 || x > 2.5) return null;
    const cov = Math.min(clamp01(x - 0.5 + 0.5), clamp01(2.5 - x + 0.5));
    const t = clamp01(y / (H - 1));
    return pm(lerpColor(ACCENTS[name].a1, A2[name], t), 255 * cov);
  });
  return { w: W, h: H, buf };
}

// --- .row.sec .sl i — 6px accent square dot (radius 2) with its glow.
// pad 4 holds the glow; the MQL PNL_SECDOT_PAD twin must equal it.
function secDotSkin(name) {
  const s = uiBox({ w: 6, h: 6, rad: 2, top: ACCENTS[name].a1, bot: A2[name], pad: 4,
                    glow: [A2[name], 1.8, 120] });
  return s;
}

// --- .subttl i — the 4px round dot the preview puts before EVERY subtitle
//     segment, alternating amber/jade (odd children get .j). Two fixed
//     colours, no accent ramp: the preview hard-codes #FFAB00 / #12B886 here,
//     unlike every other row which rides the card accent. The 4px dot sits
//     centred in an 8px canvas (PAD2=2), so the MQL places it at dot-2.
function subDotSkin(col) {
  return uiBox({ w: 4, h: 4, rad: 2, flat: col, flatA: 255 });
}

// --- .row.sec .cnt — neutral count pill (white .05 face, white .09 border)
function cntChipSkin() {
  return uiBox({ w: 24, h: 16, rad: 5, flat: [255, 255, 255], flatA: 13,
                 bd: [255, 255, 255], bdA: 23 });
}

// --- .key — 18x18 keycap (#242B38 face, #39424F border, 2px bottom edge)
function keycapSkin() {
  const s = uiBox({ w: 18, h: 18, rad: 5, flat: [0x24, 0x2B, 0x38],
                    bd: [0x39, 0x42, 0x4F], bdA: 255 });
  const W = s.w, H = s.h, buf = s.buf;
  const cx = W / 2, cy = H / 2, hw = (18 - 1) / 2, hh = (18 - 1) / 2;
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < H; y++) {
      // border-bottom-width:2px — the lower edge reads as a physical key
      if (y - PAD2 < 18 - 2.5) continue;
      const d = rrSdf(x, y, cx, cy, hw, hh, 5);
      if (d > 0) continue;
      const i = (y * W + x) * 4;
      const src = pm([0x39, 0x42, 0x4F], 255);
      const sa = src[3] / 255;
      buf[i]     = src[0] + buf[i]     * (1 - sa);
      buf[i + 1] = src[1] + buf[i + 1] * (1 - sa);
      buf[i + 2] = src[2] + buf[i + 2] * (1 - sa);
      buf[i + 3] = src[3] + buf[i + 3] * (1 - sa);
    }
  }
  return s;
}

// --- .x — 26x26 ghost close button (#1C222C face, #313A4A border)
function xBtnSkin() {
  return uiBox({ w: 26, h: 26, rad: 8, flat: [0x1C, 0x22, 0x2C], bd: [0x31, 0x3A, 0x4A], bdA: 255 });
}

// --- .card::before — 3px accent top bar (a2 -> a1 42% -> transparent)
function topBarSkin(name, wide) {
  // .card::before is inset 0 0 auto 0 — it spans the FULL 312px card, not the
  // 280px content box. OBJ_BITMAP_LABEL renders at native size, so a 300px
  // canvas would leave the right 12px of the card without its accent bar.
  const W = wide ? PNL_WIDE_WEL : PNL_W, H = 3 + 2 * PAD2;
  const a2 = A2[name], a1 = ACCENTS[name].a1;
  // NB: renderFxWH samples at sub-pixel centres, so a 1px/3px band must be
  // written in continuous coordinates — never as integer y equality.
  const buf = renderFxWH(W, H, (x, y) => {
    const yy = y - PAD2;                       // 0..3 across the visible bar
    if (yy < 0 || yy >= 3) return null;
    const t = clamp01((x - PAD2) / (W - 2 * PAD2));
    const col = t < 0.42 ? lerpColor(a2, a1, t / 0.42) : a1;
    const a = t < 0.42 ? 255 : 255 * clamp01(1 - (t - 0.42) / 0.58);
    return pm(col, a);
  });
  return { w: W, h: H, buf };
}

// --- .hd::after — header hairline (accent border -> white .02 at 70% -> gone)
function hairSkin(name, wide) {
  const W = wide ? PNL_WIDE_WEL - 32 : 280, H = 1 + 2 * PAD2;
  const bd = ACCENTS[name].soft, bdA = ACCENTS[name].bdA;
  const buf = renderFxWH(W, H, (x, y) => {
    const yy = y - PAD2;                       // 0..1 across the visible hairline
    if (yy < 0 || yy >= 1) return null;
    const t = clamp01((x - PAD2) / (W - 2 * PAD2));
    if (t < 0.70) return pm([bd[0], bd[1], bd[2]], bdA);
    const a = bdA * clamp01(1 - (t - 0.70) / 0.30);
    return a < 0.5 ? null : pm([255, 255, 255], a * 0.08);
  });
  return { w: W, h: H, buf };
}

// --- .row.sec band wash — white .028 -> transparent at 62% (over the card).
//     The W twin spans both columns of a wide card (608-32).
function secBandSkin(wide) {
  const W = wide ? PNL_WIDE_WEL - 32 : 280, H = 42;
  const buf = renderFxWH(W, H, (x, y) => {
    const t = clamp01(x / (W - 1));
    // RICH-MT4 (2026-09-11): spec white .028 (a=7) vanishes on the blit —
    // the MT4 bake runs at 11, still a whisper next to the preview.
    const a = 11 * clamp01(1 - t / 0.62);
    return a < 0.5 ? null : pm([255, 255, 255], a);
  });
  return { w: W, h: H, buf };
}

// --- .row.act wash — accent .12 -> transparent at 70%
function actWashSkin(name) {
  const W = 280, H = 42;
  const ac = ACCENTS[name];
  const buf = renderFxWH(W, H, (x, y) => {
    const t = clamp01(x / (W - 1));
    const a = ac.softA * clamp01(1 - t / 0.70);
    return a < 0.5 ? null : pm(ac.soft, a);
  });
  return { w: W, h: H, buf };
}

// --- .cset / .q.add / .dd .chev — the small pieces the row engine needs
//     34x19 dual switch (.dual .sw), 22x22 dashed "+" cell (.q.add),
//     6x6 accent chevron (.dd .chev).
// RICH-MT4 (2026-09-11): pad 6, NOT PAD2 — BiotakPanels.mqh lays the dual
// switch out at 34+12 x 19+12 (same PAD 6 twin as the full switch), so a
// PAD2 canvas (38x23) blitted into a 46x31 slot. Canvas MUST stay 46x31.
const DUAL_PAD = 6;
function dualSwSkin(name, on) {
  const s = uiBox(on
    ? { w: 34, h: 19, rad: 9, pad: DUAL_PAD, top: ACCENTS[name].a1, bot: A2[name], bd: A2[name], bdA: 255 }
    : { w: 34, h: 19, rad: 9, pad: DUAL_PAD, flat: [0x23, 0x2A, 0x37], bd: [0x3A, 0x43, 0x53], bdA: 255 });
  const W = s.w, H = s.h, buf = s.buf;
  const kc = on ? 23.5 : 8.5;
  const kcol = on ? A_INK[name] : [0x8D, 0x97, 0xA8];
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < H; y++) {
      const d = Math.hypot(x - (kc + DUAL_PAD), y - H / 2);
      if (d > 7.1) continue;
      const i = (y * W + x) * 4;
      const src = pm(kcol, clamp01(6.5 - d + 0.5) * 255);
      const sa = src[3] / 255;
      buf[i]     = src[0] + buf[i]     * (1 - sa);
      buf[i + 1] = src[1] + buf[i + 1] * (1 - sa);
      buf[i + 2] = src[2] + buf[i + 2] * (1 - sa);
      buf[i + 3] = src[3] + buf[i + 3] * (1 - sa);
    }
  }
  return s;
}
function addCellSkin(name) {
  const ac = ACCENTS[name];
  // .q.add: accent-soft face. The CSS dash border cannot be baked into a
  // raster without looking like noise, so the border is the SOLID aBd.
  return uiBox({ w: 22, h: 22, rad: 6, flat: ac.soft, flatA: ac.softA, bd: ac.soft, bdA: ac.bdA });
}
function chevSkin(name) {
  const W = 6 + 2 * PAD2, H = 6 + 2 * PAD2;
  const c = ACCENTS[name].a1;
  const buf = renderFxWH(W, H, (x, y) => {
    const px = x - PAD2, py = y - PAD2;
    const d = Math.min(distSeg(px, py, 0.5, 1.4, 3, 3.9), distSeg(px, py, 3, 3.9, 5.5, 1.4));
    if (d > 1.6) return null;
    return pm(c, clamp01(1.6 - d + 0.5) * 255);
  });
  return { w: W, h: H, buf };
}
// --- collapsed-band chevron (preview .acc.collapsed .cv): the same 6px
// --- accent chevron rotated to point right. Same canvas, same twin rule.
function chevRSkin(name) {
  const W = 6 + 2 * PAD2, H = 6 + 2 * PAD2;
  const c = ACCENTS[name].a1;
  const buf = renderFxWH(W, H, (x, y) => {
    const px = x - PAD2, py = y - PAD2;
    const d = Math.min(distSeg(px, py, 1.4, 0.5, 3.9, 3), distSeg(px, py, 3.9, 3, 1.4, 5.5));
    if (d > 1.6) return null;
    return pm(c, clamp01(1.6 - d + 0.5) * 255);
  });
  return { w: W, h: H, buf };
}

// --- .ft .btn — the footer button face. 92x28, radius 8, and a pad wide enough
//     for the primary's box-shadow glow (the preview's card has overflow:hidden,
//     so the glow is clipped to the card anyway — 8px is plenty).
//     ghost   = flat #1C222C + #313A4A border  (--ghostBg / --ghostBd)
//     primary = vertical a1->a2 ramp + a2 border + inset top highlight + aGlow
//     The MQL side puts an OBJ_BUTTON *under* this skin purely as a click
//     target, so the corners outside the radius must be transparent and the
//     button's own bg must be the card's footer colour (PNL_CLR_FOOTBG).
//     FT_BTN_W MUST equal the MQL's PNL_BTN_W (Biotak/BiotakPanels.mqh).
//     MT4 renders an OBJ_BITMAP_LABEL at its NATIVE size (XSIZE/YSIZE are
//     read-only), so a skin baked wider than the button's declared width
//     overhangs the card and leaves the overhang outside the click target.
//     It was 92 while PNL_BTN_W had already moved to 72 — the Done face ran
//     4px past the card's content edge and 20px of each face was dead.
const FT_BTN_W = 72, FT_BTN_H = 28, FT_BTN_PAD = 8;
function ftBtnSkin(accent, primary) {
  const W = FT_BTN_W + 2 * FT_BTN_PAD, H = FT_BTN_H + 2 * FT_BTN_PAD;
  const a1 = primary ? ACCENTS[accent].a1 : null;
  const a2 = primary ? A2[accent] : null;
  const glow = primary ? A_GLOW[accent] : null;
  const cx = FT_BTN_W / 2, cy = FT_BTN_H / 2;
  const hw = (FT_BTN_W - 1) / 2, hh = (FT_BTN_H - 1) / 2;
  const buf = renderFxWH(W, H, (x, y) => {
    const px = x - FT_BTN_PAD, py = y - FT_BTN_PAD;
    let col = [0, 0, 0, 0];
    if (primary) {
      // box-shadow: 0 7px 20px var(--aGlow) — nudged down, tightened to fit
      const gd = rrSdf(px, py - 5, cx, cy, hw, hh, 8);
      if (gd > 0 && gd < 13) {
        const k = 1 - gd / 13;
        col = over(col, pm(glow, Math.round(112 * k * k)));
      }
    }
    const d = rrSdf(px, py, cx, cy, hw, hh, 8);
    if (d > 0.5) return col[3] > 0 ? col : null;
    const cov = clamp01(0.5 - d);
    if (primary) {
      const t = clamp01((py - (cy - hh)) / (2 * hh));
      col = over(col, pm(lerpColor(a1, a2, t), 255));
      // inset 0 1px 0 rgba(255,255,255,.32) — only along the TOP edge
      if (py < 1.6 && d > -1.7 && d < -0.3) col = over(col, pm([255, 255, 255], 82));
      const bw = clamp01(0.5 - Math.abs(d + 0.5));
      if (bw > 0) col = over(col, pm(a2, 255 * bw));           // border 1px a2
    } else {
      col = over(col, pm([0x1C, 0x22, 0x2C], 255));            // --ghostBg
      const bw = clamp01(0.5 - Math.abs(d + 0.5));
      if (bw > 0) col = over(col, pm([0x31, 0x3A, 0x4A], 255 * bw));   // --ghostBd
    }
    return [col[0] * cov, col[1] * cov, col[2] * cov, col[3] * cov];
  });
  return { w: W, h: H, buf };
}

// ---------------------------------------------------------------- RICH-MT4 skins (2026-09-11)
// MT4 buttons/rects are flat squares — no gradient, no radius, no glow. The
// trick for FIXED-geometry controls is a baked overlay with a TRANSPARENT
// middle: the live colour (fill level, swatch colour) shows through while
// the baked light/shadow gives the preview's gloss. Accent-independent
// (white/black alpha only), so one file serves all six accents.
// Contract (R-SUBLADDER pattern — change all three together):
//   PAL_W/H        = PalW()/PalH() in Biotak/BiotakPanels.mqh
//   TRACK_GLOSS    = PNL_TRACK_W-2 x PNL_TRK_H
//   NAV_W/H        = the NAV pill geometry in PnlCreateRow (118x26)
//   GLASS sizes    = PNL_QSW_W / PNL_QSW_PREV / PNL_CSET_W x row heights
const PAL_W = 293, PAL_H = 309;
const TRACK_GLOSS_W = 278, TRACK_GLOSS_H = 7;
const NAV_W = 118, NAV_H = 26;

// --- pnl_trackgloss.bmp : gloss laid OVER the flat track+fill rects (Z between
//     the rects and the knob). Top-light + bottom-shade faux-gradient —
//     square, because the rects underneath are square.
function trackGlossSkin() {
  const W = TRACK_GLOSS_W, H = TRACK_GLOSS_H;
  const buf = renderFxWH(W, H, (x, y) => {
    let col = [0, 0, 0, 0];
    const top = clamp01(1 - y / 3.4);          // white 40 -> 0 over rows 0..3
    if (top > 0) col = over(col, pm([255, 255, 255], 40 * top));
    const bot = clamp01((y - 4.2) / 1.8);      // black 0 -> 38 over rows 4..6
    if (bot > 0) col = over(col, pm([0, 0, 0], 38 * bot));
    return col[3] < 0.5 ? null : col;
  });
  return { w: W, h: H, buf };
}

// --- pnl_glass{22,46,38}.bmp : rounded glass frame over a flat colour button.
//     Transparent middle (the colour shows through), light top edge, dark
//     bottom edge — the preview's inset highlight on a control MT4 draws flat.
function glassSkin(w, h) {
  const rad = 5, cx = w / 2, cy = h / 2;
  const hw = (w - 1) / 2, hh = (h - 1) / 2;
  const buf = renderFxWH(w, h, (x, y) => {
    const d = rrSdf(x, y, cx, cy, hw, hh, rad);
    if (d > 0.6 || d < -2.0) return null;
    const cov = clamp01(0.6 - d);
    const edge = clamp01(1 - Math.abs(d + 0.7) / 1.3);   // 1px band just inside
    let col = [0, 0, 0, 0];
    if (edge > 0) col = over(col, y < cy ? pm([255, 255, 255], 46 * edge)
                                         : pm([0, 0, 0], 58 * edge));
    return [col[0] * cov, col[1] * cov, col[2] * cov, col[3] * cov];
  });
  return { w, h, buf };
}

// --- pnl_nav.bmp : the 118x26 NAV pill (preview .nav). Dark gradient + rim +
//     top inset — the MQL button stays underneath purely as the click target
//     (footer-button pattern), caption + chevron ride on top.
function navSkin() {
  const W = NAV_W, H = NAV_H, rad = 7;
  const cx = W / 2, cy = H / 2;
  const hw = (W - 1) / 2, hh = (H - 1) / 2;
  const buf = renderFxWH(W, H, (x, y) => {
    const d = rrSdf(x, y, cx, cy, hw, hh, rad);
    if (d > 0.5) return null;
    const cov = clamp01(0.5 - d);
    const t = clamp01((y - (cy - hh)) / (2 * hh));
    let col = over([0, 0, 0, 0], pm(lerpColor([0x24, 0x2C, 0x39], [0x17, 0x1C, 0x26], t), 255));
    if (y < 1.6 && d > -1.7 && d < -0.3) col = over(col, pm([255, 255, 255], 24));
    const bw = clamp01(0.5 - Math.abs(d + 0.5));
    if (bw > 0) col = over(col, pm([0x33, 0x3C, 0x4C], 255 * bw));   // --fieldBd
    return [col[0] * cov, col[1] * cov, col[2] * cov, col[3] * cov];
  });
  return { w: W, h: H, buf };
}

// --- pal_card.bmp : the palette popup face (preview .pal gradient + radius).
//     Replaces the flat CARD rect — same object name, same Z, prefix-wiped.
function palCardSkin() {
  const W = PAL_W, H = PAL_H, rad = 13;
  const cx = W / 2, cy = H / 2;
  const hw = (W - 1) / 2, hh = (H - 1) / 2;
  const buf = renderFxWH(W, H, (x, y) => {
    const d = rrSdf(x, y, cx, cy, hw, hh, rad);
    if (d > 0.5) return null;
    const cov = clamp01(0.5 - d);
    const t = clamp01((y - (cy - hh)) / (2 * hh));
    let col = over([0, 0, 0, 0], pm(lerpColor([0x1E, 0x24, 0x2F], [0x14, 0x19, 0x22], t), 255));
    if (y < 1.6 && d > -1.7 && d < -0.3) col = over(col, pm([255, 255, 255], 19));
    const bw = clamp01(0.5 - Math.abs(d + 0.5));
    if (bw > 0) col = over(col, pm([0x2C, 0x34, 0x44], 255 * bw));
    return [col[0] * cov, col[1] * cov, col[2] * cov, col[3] * cov];
  });
  return { w: W, h: H, buf };
}

// ---------------------------------------------------------------- main
const outDirs = [path.join(__dirname, '..', 'Files', 'Icons')];

// ---------------------------------------------------------------- ICON-DIET (2026-09-12)
// Only emit what a runtime path can load — every other file is dead bytes
// in the repo AND link time in the compiler (each #resource is embedded).
// Audit 2026-09-12 (P-UI-28): ~485 of 727 files unreachable — retired accent
// families (R-GOLDALL forces gold everywhere), retired menu tools
// (TH3TOOL/FACTORBTN/NOBADGES), 14 unused glyph stems, card rows 17-20.
// Flip EMIT_RETIRED_ACCENTS + regen to restore all families. gl_nav_* stays:
// NAVC falls back to "nav" for forward nav rows (BiotakPanels.mqh:5078).
const EMIT_RETIRED_ACCENTS = false;
const ACCENT_EMIT = EMIT_RETIRED_ACCENTS ? ACCENT_NAMES : ['gold'];
const DEAD_GLYPHS = new Set(['alignL','alignR','bolt','down','grid','hand',
  'italic','lock','more','palette','search','trash','up','warn']);
const DEAD_ART = new Set(['custom','ssls','chk','tl','factor']);

const files = [];
for (const [name, art] of Object.entries(ART)) {
  if (DEAD_ART.has(name)) continue;   // retired tools/glyphs, zero builders
  files.push([name + '_off.bmp', () => render(28, art, OFF)]);
  files.push([name + '_on.bmp',  () => render(28, art, ON)]);
}
// Base Box MINI floating strip (item 13) — obsidian glass: light outlined
// glyphs on the dark strip, amber only for the locked padlock.
// R-BKSTRIP 2026-09-07.
files.push(['bk_bucket.bmp',   () => render(24, BK_BUCKET,   BK_DARK)]);
files.push(['bk_pencil.bmp',   () => render(24, BK_PENCIL,   BK_DARK)]);
files.push(['bk_text.bmp',     () => render(24, BK_TEXT,     BK_DARK)]);
for (let i = 0; i < 5; i++) files.push(['bk_style' + i + '.bmp', () => render(16, BK_STYLES[i], BK_DARK)]);
for (let i = 1; i <= 5; i++) files.push(['bk_w' + i + '.bmp', () => render(16, bkWidthArt(i), BK_DARK)]);
files.push(['bk_lock_off.bmp', () => render(24, BK_LOCK_OFF, BK_DARK)]);
files.push(['bk_lock_on.bmp',  () => render(24, BK_LOCK_ON,  BK_DARK)]);
files.push(['bk_del.bmp',      () => render(24, BK_DEL,      BK_DARK)]);
files.push(['bk_more.bmp',     () => render(24, BK_MORE,     BK_DARK)]);
files.push(['bk_chev.bmp',     () => render(16, BK_CHEV,     BK_DARK)]);
// ICON-DIET: badge.bmp (NOBADGES gates every create/show — purges use
// ObjectDelete and need no file) and knob.bmp (superseded by pnl_knob.bmp)
// have zero runtime paths, so they are not emitted.
files.push(['circ_off.bmp', () => circSkin(false)]);
files.push(['circ_on.bmp',  () => circSkin(true)]);
files.push(['orb_bg.bmp',   () => orbSkin()]);
files.push(['orb_word.bmp', () => orbWordFromMaster()]);

// settings-panel v2 skins (non-square capable) — تا 12 ردیف برای پنل باکس‌ها
const panelFiles = [
  { name: 'bk_strip.bmp',    ...bkStripSkin() },
  { name: 'bk_dds.bmp',      ...bkDdSkin(216, 192) },   // STYLE menu (wide)
  { name: 'bk_ddw.bmp',      ...bkDdSkin(120, 192) },   // WIDTH menu (narrow)
  { name: 'pnl_knob.bmp',    ...pnlKnobSkin() },
  // RICH-MT4 (2026-09-11): baked gloss/glass/nav/palette skins — see the
  // RICH-MT4 block above for the contract. One accent-independent file each
  // (transparent middles), except the palette card which is one gradient.
  { name: 'pnl_trackgloss.bmp', ...trackGlossSkin() },
  { name: 'pnl_glass22.bmp',    ...glassSkin(22, 22) },
  { name: 'pnl_glass46.bmp',    ...glassSkin(46, 22) },
  { name: 'pnl_glass38.bmp',    ...glassSkin(38, 20) },
  { name: 'pnl_nav.bmp',        ...navSkin() },
  { name: 'pal_card.bmp',       ...palCardSkin() },
  { name: 'pnl_cb_on.bmp',   w: 20, h: 20, buf: render(20, cbArt(true), CB_NAVY) },
  { name: 'pnl_cb_off.bmp',  w: 20, h: 20, buf: render(20, cbArt(false), [255, 255, 255]) },
  // R-SUBLADDER (2026-09-11): Tools sub-menu grid — cells + one panel per
  // visible row count (1..4), plus a paged variant (+SUB_GRID_PGR) per row count.
  { name: 'cell_off.bmp',    ...cellSkin(false) },
  { name: 'cell_on.bmp',     ...cellSkin(true)  },
];

// One card skin per ROW COUNT: BiotakPanels.mqh resolves
// "::Files\Icons\pnl_card" + cardRows + ".bmp", so the file name IS the row
// count. Never stretch one skin across counts — the 14px corners and the 1px
// border distort. Clamp is 3..16 BOTH sides (PNL_CARD_ROWS_MAX): tallest live
// card is 14-15 display rows, so 16 keeps headroom — 1, 2 (clamp min is 3)
// and 17..20 (the 8 largest files, zero runtime path) are not emitted
// (ICON-DIET 2026-09-12). 20 also covers the section BANDS the redesign
// inserts (a band is itself a 42px row, so a 11-setting card becomes
// 15 display rows).
const PNL_CARD_ROWS_MAX = 16;
for (let r = 3; r <= PNL_CARD_ROWS_MAX; r++) {
  panelFiles.push({ name: 'pnl_card' + r + '.bmp',  ...pnlCardSkin(r, false) });
  // the .fade variant — PnlCardFade() picks it for the scrollable cards
  panelFiles.push({ name: 'pnl_card' + r + 'f.bmp', ...pnlCardSkin(r, true)  });
}
// WIDE-CARDS (2026-09-11): two-column skins. PNL_WIDE_ROWS_MAX must equal the
// MQL's PNL_WIDE_ROWS_MAX (Biotak/BiotakPanels.mqh) — the MQL clamps pairN to
// it, so a missing file would draw bare rows.
const PNL_WIDE_ROWS_MAX = 12;
for (let r = 1; r <= PNL_WIDE_ROWS_MAX; r++) {
  panelFiles.push({ name: 'pnl_cardW' + r + '.bmp',  ...pnlCardSkin(r, false, true) });
  panelFiles.push({ name: 'pnl_cardW' + r + 'f.bmp', ...pnlCardSkin(r, true, true)  });
}
for (let r = 1; r <= SUB_GRID_ROWS_MAX; r++) {
  panelFiles.push({ name: 'sub_panel_r' + r + '.bmp',  ...subPanelSkin(r, false) });
  panelFiles.push({ name: 'sub_panel_r' + r + 'p.bmp', ...subPanelSkin(r, true)  });
}

// R-PANELCHIP (2026-09-11): per-row icon chips for the 13 redesign cards.
//   1 neutral chip + 6 accent chips, then 57 glyphs in muted + 6 accent inks.
//   Chip and glyph are separate objects so one chip serves every glyph; the
//   accent travels in the glyph ink (preview .gl.on { color: var(--a1) }).
const chipFiles = [
  { name: 'pnl_chip.bmp', ...chipSkin(null) },
];
for (const a of ACCENT_EMIT) chipFiles.push({ name: 'pnl_chip_' + a + '.bmp', ...chipSkin(ACCENTS[a]) });

const glyphFiles = [];
const glyphNames = Object.keys(GLYPHS);
for (const g of glyphNames) {
  if (DEAD_GLYPHS.has(g)) continue;
  glyphFiles.push({ name: 'gl_' + g + '_m.bmp', ...glyphSkin(g, GLYPH_MUTED) });
  for (const a of ACCENT_EMIT) glyphFiles.push({ name: 'gl_' + g + '_' + a + '.bmp', ...glyphSkin(g, ACCENTS[a].a1) });
}
// --aInk inks for the glyphs that sit ON an accent ramp (.mark, .btn.primary)
for (const g of INK_GLYPHS) {
  if (glyphNames.indexOf(g) < 0 || DEAD_GLYPHS.has(g)) continue;
  for (const a of ACCENT_EMIT) glyphFiles.push({ name: 'gl_' + g + '_i_' + a + '.bmp', ...glyphSkin(g, A_INK[a]) });
}
panelFiles.push(...chipFiles, ...glyphFiles);

// R-PANELUI2: per-accent chrome (mark · switch · value chip · rail · dot ·
// washes) plus the neutral pieces (count pill, keycap, close button).
const uiFiles = [
  { name: 'pnl_cntchip.bmp', ...cntChipSkin() },
  { name: 'pnl_keycap.bmp',  ...keycapSkin()  },
  { name: 'pnl_xbtn.bmp',    ...xBtnSkin()    },
  { name: 'pnl_secband.bmp', ...secBandSkin(false) },
  { name: 'pnl_secbandW.bmp', ...secBandSkin(true) },
  { name: 'pnl_subdot_amber.bmp', ...subDotSkin([0xFF, 0xAB, 0x00]) },
  { name: 'pnl_subdot_jade.bmp',  ...subDotSkin([0x12, 0xB8, 0x86]) },
];
for (const a of ACCENT_EMIT) {
  uiFiles.push({ name: 'pnl_mark_' + a + '.bmp',    ...markSkin(a)     });
  uiFiles.push({ name: 'pnl_sw_on_' + a + '.bmp',   ...swSkin(a, true)  });
  uiFiles.push({ name: 'pnl_vchip_' + a + '.bmp',   ...vchipSkin(a)     });
  uiFiles.push({ name: 'pnl_rail_' + a + '.bmp',    ...railSkin(a)      });
  uiFiles.push({ name: 'pnl_secdot_' + a + '.bmp',  ...secDotSkin(a)    });
  uiFiles.push({ name: 'pnl_topbar_' + a + '.bmp',  ...topBarSkin(a, false)    });
  uiFiles.push({ name: 'pnl_hair_' + a + '.bmp',    ...hairSkin(a, false)      });
  uiFiles.push({ name: 'pnl_topbarW_' + a + '.bmp', ...topBarSkin(a, true)     });
  uiFiles.push({ name: 'pnl_hairW_' + a + '.bmp',   ...hairSkin(a, true)       });
  uiFiles.push({ name: 'pnl_actbg_' + a + '.bmp',   ...actWashSkin(a)   });
  uiFiles.push({ name: 'pnl_dsw_on_' + a + '.bmp',  ...dualSwSkin(a, true) });
  uiFiles.push({ name: 'pnl_add_' + a + '.bmp',     ...addCellSkin(a)      });
  uiFiles.push({ name: 'pnl_chev_' + a + '.bmp',    ...chevSkin(a)         });
  uiFiles.push({ name: 'pnl_chevr_' + a + '.bmp',   ...chevRSkin(a)        });
}
uiFiles.push({ name: 'pnl_sw_off.bmp',  ...swSkin('gold', false) });
uiFiles.push({ name: 'pnl_dsw_off.bmp', ...dualSwSkin('gold', false) });
// footer buttons — .btn.ghost (Reset) + .btn.primary (Done, per accent)
uiFiles.push({ name: 'pnl_btn_ghost.bmp', ...ftBtnSkin(null, false) });
for (const a of ACCENT_EMIT)
  uiFiles.push({ name: 'pnl_btn_prim_' + a + '.bmp', ...ftBtnSkin(a, true) });
panelFiles.push(...uiFiles);

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
// Emit manifest: the EXACT runtime-reachable set. Purge scripts and the
// #resource preflight derive from it — a disk BMP outside this list is dead
// weight, a #resource outside it embeds a ghost.
const manifest = [...files.map(f => f[0]), ...panelFiles.map(f => f.name)].sort();
fs.writeFileSync(path.join(__dirname, 'icon-manifest.txt'),
                 manifest.join('\n') + '\n');
console.log('Manifest: ' + manifest.length + ' files -> tools/icon-manifest.txt');
console.log('Generated ' + (files.length + panelFiles.length) + ' icons into:');
for (const dir of outDirs) console.log('  ' + dir);
