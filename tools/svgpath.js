/* svgpath.js — minimal SVG path / element flattener for the TH3 icon set.
 *
 * The 57 glyphs in tools/glyphs.js are authored on a 24x24 grid with
 * stroke-width 1.7, round caps and joins, and use the M/L/H/V/C/S/A/Z
 * command family (plus <circle> and <rect> elements). MT4 can only draw
 * bitmaps, so every glyph is rasterised here at generation time.
 *
 * Output is a list of primitives in glyph space:
 *   { kind: 'stroke', pts: [[x,y],...] }          -> stroke a polyline
 *   { kind: 'fill',   pts: [[x,y],...] }          -> fill a polygon (even-odd)
 *
 * No dependency on the browser: this is a straight port of the SVG spec's
 * path grammar plus the endpoint->centre arc parameterisation.
 */
'use strict';

const NUM = /-?\d*\.?\d+(?:[eE][-+]?\d+)?/g;

function tokenize(d) {
  return d.match(/[MmLlHhVvCcSsAaZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?/g) || [];
}

// Sample a cubic bezier adaptively-ish: fixed subdivision is plenty at icon size.
function cubic(p0, p1, p2, p3, out, steps) {
  for (let i = 1; i <= steps; i++) {
    const t = i / steps, u = 1 - t;
    const a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t;
    out.push([
      a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0],
      a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1],
    ]);
  }
}

// SVG endpoint -> centre arc parameterisation, then sample.
function arcTo(px, py, rx, ry, phiDeg, largeArc, sweep, x, y, out) {
  if (rx === 0 || ry === 0) { out.push([x, y]); return; }
  const phi = (phiDeg * Math.PI) / 180;
  const cosP = Math.cos(phi), sinP = Math.sin(phi);
  const dx2 = (px - x) / 2, dy2 = (py - y) / 2;
  const x1p = cosP * dx2 + sinP * dy2;
  const y1p = -sinP * dx2 + cosP * dy2;
  rx = Math.abs(rx); ry = Math.abs(ry);
  // scale radii up if they are too small to span the chord
  const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lam > 1) { const s = Math.sqrt(lam); rx *= s; ry *= s; }
  const sign = largeArc !== sweep ? 1 : -1;
  const num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  const den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  const co = sign * Math.sqrt(Math.max(0, num / den));
  const cxp = (co * rx * y1p) / ry;
  const cyp = (-co * ry * x1p) / rx;
  const cx = cosP * cxp - sinP * cyp + (px + x) / 2;
  const cy = sinP * cxp + cosP * cyp + (py + y) / 2;
  const ang = (ux, uy, vx, vy) => {
    const d = (ux * vx + uy * vy) / (Math.hypot(ux, uy) * Math.hypot(vx, vy));
    let a = Math.acos(Math.max(-1, Math.min(1, d)));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  };
  const th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
  if (!sweep && dth > 0) dth -= 2 * Math.PI;
  else if (sweep && dth < 0) dth += 2 * Math.PI;
  const steps = Math.max(6, Math.ceil(Math.abs(dth) / (Math.PI / 16)));
  for (let i = 1; i <= steps; i++) {
    const t = th1 + (dth * i) / steps;
    out.push([cx + rx * Math.cos(t) * cosP - ry * Math.sin(t) * sinP,
              cy + rx * Math.cos(t) * sinP + ry * Math.sin(t) * cosP]);
  }
}

/* Flatten a `d` attribute into subpaths of points. */
function flattenPath(d) {
  const tk = tokenize(d);
  const subs = [];
  let cur = null;
  let x = 0, y = 0, sx = 0, sy = 0;
  let ctrlX = null, ctrlY = null;     // last cubic control point, for S/s
  let i = 0, cmd = '';

  const start = (nx, ny) => { cur = [[nx, ny]]; subs.push(cur); x = nx; y = ny; sx = nx; sy = ny; };
  const line = (nx, ny) => { if (!cur) start(nx, ny); else { cur.push([nx, ny]); x = nx; y = ny; } };
  const n = () => parseFloat(tk[i++]);

  while (i < tk.length) {
    if (/[MmLlHhVvCcSsAaZz]/.test(tk[i])) cmd = tk[i++];
    switch (cmd) {
      case 'M': start(n(), n()); cmd = 'L'; ctrlX = ctrlY = null; break;
      case 'm': start(x + n(), y + n()); cmd = 'l'; ctrlX = ctrlY = null; break;
      case 'L': line(n(), n()); ctrlX = ctrlY = null; break;
      case 'l': line(x + n(), y + n()); ctrlX = ctrlY = null; break;
      case 'H': line(n(), y); ctrlX = ctrlY = null; break;
      case 'h': line(x + n(), y); ctrlX = ctrlY = null; break;
      case 'V': line(x, n()); ctrlX = ctrlY = null; break;
      case 'v': line(x, y + n()); ctrlX = ctrlY = null; break;
      case 'C': {
        const a = [n(), n()], b = [n(), n()], c = [n(), n()];
        if (!cur) start(x, y);
        cubic([x, y], a, b, c, cur, 12);
        ctrlX = b[0]; ctrlY = b[1]; x = c[0]; y = c[1];
        break;
      }
      case 'c': {
        const a = [x + n(), y + n()], b = [x + n(), y + n()], c = [x + n(), y + n()];
        if (!cur) start(x, y);
        cubic([x, y], a, b, c, cur, 12);
        ctrlX = b[0]; ctrlY = b[1]; x = c[0]; y = c[1];
        break;
      }
      case 'S': case 's': {
        const rel = cmd === 's';
        const b = rel ? [x + n(), y + n()] : [n(), n()];
        const c = rel ? [x + n(), y + n()] : [n(), n()];
        const a = (ctrlX === null) ? [x, y] : [2 * x - ctrlX, 2 * y - ctrlY];
        if (!cur) start(x, y);
        cubic([x, y], a, b, c, cur, 12);
        ctrlX = b[0]; ctrlY = b[1]; x = c[0]; y = c[1];
        break;
      }
      case 'A': case 'a': {
        const rel = cmd === 'a';
        const rx = n(), ry = n(), rot = n(), la = n(), sw = n();
        const ex = rel ? x + n() : n(), ey = rel ? y + n() : n();
        if (!cur) start(x, y);
        arcTo(x, y, rx, ry, rot, la, sw, ex, ey, cur);
        x = ex; y = ey; ctrlX = ctrlY = null;
        break;
      }
      case 'Z': case 'z':
        if (cur) cur.push([sx, sy]);
        x = sx; y = sy; ctrlX = ctrlY = null;
        break;
      default:
        i++;   // unknown token — skip rather than loop forever
    }
  }
  return subs;
}

/* Cut a polyline into dashes (stroke-dasharray). */
function dashPolyline(pts, dash, gap) {
  const out = [];
  let carry = 0, on = true, run = null;
  for (let k = 1; k < pts.length; k++) {
    const [x1, y1] = pts[k - 1], [x2, y2] = pts[k];
    const len = Math.hypot(x2 - x1, y2 - y1);
    if (len === 0) continue;
    let t = 0;
    while (t < len) {
      const want = (on ? dash : gap) - carry;
      const take = Math.min(want, len - t);
      const ax = x1 + ((x2 - x1) * t) / len, ay = y1 + ((y2 - y1) * t) / len;
      const bx = x1 + ((x2 - x1) * (t + take)) / len, by = y1 + ((y2 - y1) * (t + take)) / len;
      if (on) {
        if (!run) { run = [[ax, ay], [bx, by]]; out.push(run); }
        else run.push([bx, by]);
      }
      t += take; carry += take;
      if (carry >= (on ? dash : gap) - 1e-9) { carry = 0; on = !on; run = null; }
    }
  }
  return out;
}

/* Rounded-rect outline as a polygon. */
function roundRectPts(x, y, w, h, r, segs) {
  r = Math.min(r, w / 2, h / 2);
  const pts = [];
  const corner = (cx, cy, a0) => {
    for (let i = 0; i <= segs; i++) {
      const a = a0 + (Math.PI / 2) * (i / segs);
      pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
  };
  corner(x + w - r, y + h - r, 0);
  corner(x + r, y + h - r, Math.PI / 2);
  corner(x + r, y + r, Math.PI);
  corner(x + w - r, y + r, -Math.PI / 2);
  return pts;
}

/* Parse one glyph's SVG fragment into stroke/fill primitives in glyph space. */
function parseGlyph(svg) {
  const out = [];
  const elems = svg.match(/<(path|circle|rect)\b[^>]*\/?>/g) || [];
  for (const el of elems) {
    const attr = (name) => {
      const m = el.match(new RegExp(name + '="([^"]*)"'));
      return m ? m[1] : null;
    };
    const filled = /fill="currentColor"/.test(el);
    const dashed = attr('stroke-dasharray');

    if (el.startsWith('<circle')) {
      const cx = parseFloat(attr('cx')), cy = parseFloat(attr('cy')), r = parseFloat(attr('r'));
      const pts = [];
      for (let i = 0; i <= 48; i++) {
        const a = (i / 48) * Math.PI * 2;
        pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
      }
      out.push({ kind: filled ? 'fill' : 'stroke', pts });
      continue;
    }
    if (el.startsWith('<rect')) {
      const x = parseFloat(attr('x')), y = parseFloat(attr('y'));
      const w = parseFloat(attr('width')), h = parseFloat(attr('height'));
      const r = parseFloat(attr('rx') || '0') || 0;
      const pts = roundRectPts(x, y, w, h, r, 6);
      pts.push(pts[0].slice());
      out.push({ kind: filled ? 'fill' : 'stroke', pts });
      continue;
    }
    // <path>
    const d = attr('d');
    if (!d) continue;
    for (const sub of flattenPath(d)) {
      if (sub.length < 2) continue;
      if (filled) { out.push({ kind: 'fill', pts: sub }); continue; }
      if (dashed) {
        const parts = dashed.trim().split(/[\s,]+/).map(Number);
        const dash = parts[0] || 3, gap = parts[1] || parts[0] || 3;
        for (const seg of dashPolyline(sub, dash, gap)) out.push({ kind: 'stroke', pts: seg });
      } else {
        out.push({ kind: 'stroke', pts: sub });
      }
    }
  }
  return out;
}

module.exports = { flattenPath, parseGlyph, roundRectPts, dashPolyline };
