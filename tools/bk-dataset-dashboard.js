#!/usr/bin/env node
/*
 * bk-dataset-dashboard.js — the Base Knot dataset as one reviewable page.
 *
 * THE SHAPE. One card per sample, the way the TH3 dataset page reads: the shot first, then
 * the numbers the capture measured, then the ladder position, then the discussion. A sample
 * is a FOLDER (shot.png + sample.txt + notes.md), so the card is a view of that folder and
 * the page never holds data the folder does not.
 *
 * THE TWO NUMBERS THAT MATTER ON EVERY CARD
 *   margin  — how far the box' height sits from the nearest type edge, in pips
 *   u       — the same distance in RUNGS of the ability ladder (0 at ATR(node rung), 1 at +1,
 *             2 at +2, 3 at +3). `u` is the coordinate the four type names are bands of:
 *             FTR u<=0.5 · ETR <=1.5 · CTR <=2.0 · OTR above. Measured on the first five
 *             samples: BK-0004 sits 0.003 rung past the CTR edge and pays a stop 2.28x wider.
 *             A `~` on the bar means the fourth rung was not recorded, so `u` is extrapolated.
 *
 * COMMANDS (each one rewrites the page)
 *   node tools/bk-dataset-dashboard.js                      build, no browser
 *   node tools/bk-dataset-dashboard.js --open               build and open
 *   node tools/bk-dataset-dashboard.js note    <id> "…"     append a timestamped note
 *   node tools/bk-dataset-dashboard.js attach  <id> <f…>    copy files into the sample folder
 *   node tools/bk-dataset-dashboard.js review  <id> real|invented|unclear "…"
 *   node tools/bk-dataset-dashboard.js journal "…"
 *
 * Captures are filed by `tools/bk-shot-sync.js`; this page only renders what is filed.
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DIR = path.join(ROOT, "Samples", "BK_Dataset");
const CSV = path.join(DIR, "Dataset.csv");
const REV = path.join(DIR, "Reviews.csv");
const JRN = path.join(DIR, "journal.md");
const OUT = path.join(DIR, "dashboard.html");

//--- dark, one ramp per type: the four names are an ORDER along the ladder, so the hues run
//--- green -> blue -> amber -> red, the same order the bands sit on the axis.
const TYPE_COLOR = { FTR: "#97C459", ETR: "#85B7EB", CTR: "#EF9F27", OTR: "#F09595" };
const TYPE_DIM = { FTR: "#1d2a13", ETR: "#132030", CTR: "#2e2312", OTR: "#331a1a" };
const IMG_EXT = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp"]);

// ---------------------------------------------------------------- csv (quotes, BOM)
function parseCsv(text) {
  const rows = [];
  let row = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { row.push(cell); cell = ""; }
    else if (ch === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (ch === "\r") { /* skip */ }
    else cell += ch;
  }
  if (cell.length || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.length > 1 || (r[0] || "").trim() !== "");
}

function toObjects(text) {
  const table = parseCsv(text.replace(/^\uFEFF/, ""));
  if (!table.length) return [];
  const head = table.shift().map((h) => h.trim());
  return table.map((cells) => {
    const o = {};
    head.forEach((h, i) => (o[h] = (cells[i] || "").trim()));
    return o;
  });
}

const readRows = () => toObjects(fs.readFileSync(CSV, "utf8"));

function readReviews() {
  const map = new Map();
  if (!fs.existsSync(REV)) return map;
  for (const o of toObjects(fs.readFileSync(REV, "utf8"))) if (o.Sample_ID) map.set(o.Sample_ID, o);
  return map;
}

const sampleDir = (id) => path.join(DIR, "Samples", id);
const readImages = (id) => {
  const dir = sampleDir(id);
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => IMG_EXT.has(path.extname(f).toLowerCase())).sort();
};
const readNotes = (id) => {
  const f = path.join(sampleDir(id), "notes.md");
  return fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "";
};

// ---------------------------------------------------------------- the inbox
// The captures MT4 has written but the CSV does not know about yet. This is the ONE number the
// page can show that changes what you do next, so it is read from the same tree the sync tool
// reads - not from a counter anyone has to keep correct.
function pendingCaptures() {
  const base = path.join(process.env.APPDATA || "", "MetaQuotes", "Terminal");
  let filed = [];
  try { filed = JSON.parse(fs.readFileSync(path.join(DIR, ".filed.json"), "utf8")).filed || []; } catch {}
  const seen = new Set(filed);
  const out = [];
  let terms = [];
  try { terms = fs.readdirSync(base); } catch { return out; }
  for (const t of terms) {
    const dir = path.join(base, t, "MQL4", "Files", "BK_Dataset", "Samples");
    let leaves = [];
    try { leaves = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    for (const l of leaves) {
      if (!l.isDirectory() || seen.has(l.name)) continue;
      if (fs.existsSync(path.join(dir, l.name, "sample.txt"))) out.push(l.name);
    }
  }
  return out;
}

// A note counts only when there is a sentence under `## روایت`; the heading alone is the
// skeleton the sync writes, and counting it would make every fresh sample look explained.
function noteFilled(md) {
  if (!md) return false;
  const m = /##\s*روایت\s*\n([\s\S]*?)(?=\n##\s|$)/.exec(md);
  return !!(m && m[1].trim().length > 0);
}

// ---------------------------------------------------------------- numbers
const n = (v) => {
  const x = parseFloat(v);
  return Number.isFinite(x) ? x : NaN;
};
const f1 = (v) => (Number.isFinite(v) ? v.toFixed(1) : "—");
const esc = (s) =>
  String(s == null ? "" : s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function median(list) {
  const a = list.filter(Number.isFinite).sort((x, y) => x - y);
  if (!a.length) return NaN;
  const m = Math.floor(a.length / 2);
  return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
}

function perType(rows) {
  const out = {};
  for (const r of rows) {
    const t = r.Type || "?";
    out[t] = out[t] || { n: 0, margins: [], offStop: [], stop: [] };
    out[t].n++;
    out[t].margins.push(n(r.Edge_Margin_Pips));
    const off = n(r.Entry_Off_Pips), stop = n(r.Stop_Pips);
    if (off > 0 && stop > 0) out[t].offStop.push(off / stop);
    out[t].stop.push(stop);
  }
  return out;
}

//--- THE LADDER COORDINATE. Same piecewise-LOG map the indicator prints (BaseKnot_Shot.mqh,
//--- BaseKnotLadderU): 0 at ATR(node), 1 at +1, 2 at +2, 3 at +3, interpolated in ln(h) — so
//--- u = 0.5 IS the printed FTR/ETR boundary, √(a0·a1) (P-BK-128; v6 interpolated linearly, which
//--- put the boundary at (a0+a1)/2 and flipped one 217-pip box between FTR and ETR on 2 pips).
//--- `exact` is false when the fourth rung is missing, in which case it is extrapolated from the
//--- last step and the card marks it with a `~`. Never silently: an estimated coordinate that
//--- looks measured is the exact failure this page exists to make visible.
function uOf(r) {
  const h = n(r.Box_Pips), a0 = n(r.ATR_Trig), a1 = n(r.ATR_Pat), a2 = n(r.ATR_Str);
  let a3 = n(r.ATR_Fourth), exact = Number.isFinite(a3) && a3 > a2;
  if (!(h > 0 && a0 > 0 && a1 > a0)) return { u: NaN, exact: false };
  if (h <= a1) return { u: Math.log(h / a0) / Math.log(a1 / a0), exact: true };
  if (h <= a2) return { u: 1 + Math.log(h / a1) / Math.log(a2 / a1), exact: true };
  if (!exact) { a3 = a2 * (a2 / a1); exact = false; }
  if (!(a3 > a2)) return { u: NaN, exact: false };
  return { u: 2 + Math.log(h / a2) / Math.log(a3 / a2), exact };
}

// ---------------------------------------------------------------- notes (markdown-lite)
function mdLite(text) {
  const lines = String(text || "").split(/\r?\n/);
  let out = "", list = false, table = false;
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) { if (list) { out += "</ul>"; list = false; } if (table) { out += "</table>"; table = false; } continue; }
    if (/^\|[\s|:-]+\|$/.test(line)) continue;   // the |---|---| rule
    if (line.startsWith("|")) {
      if (list) { out += "</ul>"; list = false; }
      const cells = line.replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
      if (!table) { out += '<table class="kv">'; table = true; }
      out += "<tr>" + cells.map((c, i) => (i === 0 ? `<th>${esc(c)}</th>` : `<td>${esc(c)}</td>`)).join("") + "</tr>";
      continue;
    }
    if (table) { out += "</table>"; table = false; }
    if (line.startsWith("### ")) { if (list) { out += "</ul>"; list = false; } out += `<h6>${esc(line.slice(4))}</h6>`; }
    else if (line.startsWith("## ")) { if (list) { out += "</ul>"; list = false; } out += `<h5>${esc(line.slice(3))}</h5>`; }
    else if (line.startsWith("# ")) { if (list) { out += "</ul>"; list = false; } out += `<h4>${esc(line.slice(2))}</h4>`; }
    else if (line.startsWith("- ")) { if (!list) { out += "<ul>"; list = true; } out += `<li>${esc(line.slice(2))}</li>`; }
    else {
      if (list) { out += "</ul>"; list = false; }
      out += `<p>${esc(line)}</p>`;
    }
  }
  if (list) out += "</ul>";
  if (table) out += "</table>";
  return out;
}

// ---------------------------------------------------------------- the ladder bar
//--- 0..3 rungs across 240 px. The four bands are fixed in rung units (that is the whole
//--- point of the coordinate), so every card's bar has the same bands and only the dot moves.
function uBar(r) {
  const { u, exact } = uOf(r);
  const X = (v) => Math.max(3, Math.min(237, v * 80));
  const band = (a, b, t) =>
    `<rect x="${a * 80}" y="7" width="${(b - a) * 80}" height="10" fill="${TYPE_COLOR[t]}" fill-opacity="0.22"/>`;
  let s = `<svg viewBox="0 0 240 24" width="100%" height="24" role="img" aria-label="ladder position">`;
  s += band(0, 0.5, "FTR") + band(0.5, 1.5, "ETR") + band(1.5, 2, "CTR") + band(2, 3, "OTR");
  s += `<line x1="40" y1="5" x2="40" y2="19" stroke="#8b95a5" stroke-width="0.5" stroke-opacity="0.6"/>`;
  s += `<line x1="120" y1="5" x2="120" y2="19" stroke="#8b95a5" stroke-width="0.5" stroke-opacity="0.6"/>`;
  s += `<line x1="160" y1="4" x2="160" y2="20" stroke="#F09595" stroke-width="1" stroke-opacity="0.8"/>`;
  if (Number.isFinite(u)) {
    const x = X(u);
    s += exact
      ? `<circle cx="${x.toFixed(1)}" cy="12" r="4" fill="#e6edf3"/>`
      : `<circle cx="${x.toFixed(1)}" cy="12" r="4" fill="none" stroke="#e6edf3" stroke-width="1.5"/>`;
  }
  s += `</svg>`;
  return s;
}

// ---------------------------------------------------------------- one card
function card(r, rev, imgs, notes) {
  const t = r.Type || "?";
  const col = TYPE_COLOR[t] || "#8b95a5";
  const { u, exact } = uOf(r);
  const v = rev ? rev.Verdict : "";
  const thumb = imgs.length
    ? `<img class="thumb" src="Samples/${esc(r.Sample_ID)}/${esc(imgs[0])}" alt="${esc(r.Sample_ID)}" loading="lazy" data-id="${esc(r.Sample_ID)}">`
    : `<div class="thumb none" style="--c:${col}"><span>${esc(t)}</span><small>بدون عکس</small></div>`;
  const extra = imgs.length > 1 ? `<span class="shots">${imgs.length} عکس</span>` : "";
  return `<article class="card" id="${esc(r.Sample_ID)}" data-type="${esc(t)}" data-verdict="${esc(v || "")}">
  ${thumb}
  <header>
    <b class="mono">${esc(r.Sample_ID)}</b>
    <span class="badge" style="color:${col};border-color:${col};background:${TYPE_DIM[t] || "#1a1f27"}">${esc(t)}</span>
    <span class="badge ${v ? "v-" + esc(v) : "v-none"}">${esc(v || "بازبینی نشده")}</span>
    ${extra}
  </header>
  <div class="meta">
    <div><span>نماد</span>${esc(r.Symbol)} ${esc(r.Chart_TF)}</div>
    <div><span>گره</span>${esc(r.Node_TF || "—")}</div>
    <div><span>h</span>${f1(n(r.Box_Pips))}p</div>
    <div><span>فاصله از مرز</span>${f1(n(r.Edge_Margin_Pips))}p</div>
    <div><span>u</span>${Number.isFinite(u) ? (exact ? "" : "~") + u.toFixed(3) : "—"}</div>
    <div><span>ورود</span>${f1(n(r.Entry_Off_Pips))}p</div>
    <div><span>استاپ</span>${f1(n(r.Stop_Pips))}p</div>
    <div><span>لات</span>${Number.isFinite(n(r.Lot)) ? n(r.Lot).toFixed(2) : "—"}</div>
    <div><span>ریسک</span>$${f1(n(r.Risk_USD))}</div>
  </div>
  <div class="ladder" title="0 = ATR گره · 1 = +1 · 2 = +2 · 3 = +3">${uBar(r)}</div>
  <div class="anchor"><span>داستان</span>${esc(r.Story_Anchor || "—")} <span>لبه</span>${esc(r.Edge_Anchor || "—")}</div>
  <div class="note">${notes ? mdLite(notes) : '<p class="dim">بدون یادداشت — از دکمهٔ دستور پایین اضافه کن.</p>'}</div>
  <footer>
    <code>note ${esc(r.Sample_ID)} "…"</code>
    <button data-copy="note ${esc(r.Sample_ID)} &quot;…&quot;">کپی</button>
  </footer>
</article>`;
}

// ---------------------------------------------------------------- the page
function build(rows) {
  const rev = readReviews();
  const withShot = rows.filter((r) => readImages(r.Sample_ID).length > 0).length;
  const margins = rows.map((r) => n(r.Edge_Margin_Pips)).filter(Number.isFinite);
  const close = margins.filter((m) => m < 1).length;
  const us = rows.map((r) => uOf(r).u).filter(Number.isFinite);
  const nearEdge = rows.filter((r) => { const o = uOf(r); return Number.isFinite(o.u) && Math.abs(o.u - Math.round(o.u * 2) / 2) < 0.1; }).length;
  const verdicts = { real: 0, invented: 0, unclear: 0, none: 0 };
  for (const r of rows) {
    const v = rev.get(r.Sample_ID);
    if (v && verdicts[v.Verdict] !== undefined) verdicts[v.Verdict]++; else verdicts.none++;
  }
  const versions = [...new Set(rows.map((r) => r.Formula_Version || "?"))].join(" · ");
  const byType = perType(rows);

  // --- what to do next. One line, decided by the state of the tree, not by the reader's memory
  // of the routine. Priority is the order the routine runs in: file > capture > talk > review.
  const pend = pendingCaptures();
  const noPic = rows.filter((r) => readImages(r.Sample_ID).length === 0).length;
  const noNote = rows.filter((r) => !noteFilled(readNotes(r.Sample_ID))).length;
  const unreviewed = rows.filter((r) => !rev.get(r.Sample_ID)).length;
  const firstId = (rows[0] || {}).Sample_ID || "BK-0001";
  // The user's own plan: option 1 (the formula) NOW, option 2 (the verdict) at 20 samples.
  // The checkpoint is a number in the page, not a promise in a chat: until 20 rows exist a
  // version comparison would only add another version nobody can call better.
  const RESCORE_AT = 20;
  const moved = rows.filter((r) => {
    const a = n(r.Stop_Pips), b = n(r.Stop_V1_Pips);
    return Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) > 0.05;
  }).length;
  const next = (() => {
    if (pend.length) return { k: "file", h: `<b>${pend.length} نمونه در صف ثبت است</b>
      <span>عکس و اعداد روی دیسک‌اند، هنوز در CSV نیستند — با یک دستور ثبت و صفحه بازسازی می‌شوند</span>
      <code>node tools/bk-shot-sync.js</code>` };
    if (!rows.length) return { k: "zero", h: `<b>هنوز نمونه‌ای نیست</b>
      <span>روی چارت، مستطیل نود را کلیک کن و <kbd>K</kbd> را بزن</span><code>K</code>` };
    if (rows.length >= RESCORE_AT) return { k: "review", h: `<b>${rows.length} نمونه — وقتِ بازبینی نسخه است</b>
      <span>v1 و v2 روی همین سطرها سنجیده می‌شوند (${moved} سطر استاپش با v2 عوض شده). ستون «استاپ v1» را با «استاپ» در جدول مقایسه بگذار کنار هم؛ هر کدام روی کلِ نمونه‌ها برد، می‌ماند</span>
      <code>node tools/bk-dataset-dashboard.js --open</code>` };
    if (noNote) return { k: "talk", h: `<b>${noNote} نمونه بدون روایت است${noPic ? ` · ${noPic} بدون عکس` : ""}</b>
      <span>عددی که دلیلش نوشته نشده، سه هفته بعد قابل بازخوانی نیست — ${rows.length}/${RESCORE_AT} تا بازبینی نسخه</span>
      <code>node tools/bk-dataset-dashboard.js note ${firstId} "…"</code>` };
    if (unreviewed) return { k: "review", h: `<b>${unreviewed} نمونه بازبینی‌نشده</b>
      <span>واقعی / ساختگی / نامعلوم — یکی را انتخاب کن · ${rows.length}/${RESCORE_AT} تا بازبینی نسخه</span>
      <code>node tools/bk-dataset-dashboard.js review ${firstId} real "…"</code>` };
    return { k: "ok", h: `<b>همه‌چیز ثبت شده</b>
      <span>نمونهٔ بعدی: نود را انتخاب کن و <kbd>K</kbd> را بزن · ${rows.length}/${RESCORE_AT} تا بازبینی نسخه</span><code>K</code>` };
  })();

  const DATA = rows.map((r) => {
    const o = uOf(r);
    const imgs = readImages(r.Sample_ID).map((f) => `Samples/${r.Sample_ID}/${f}`);
    return {
      id: r.Sample_ID, type: r.Type || "?", symbol: r.Symbol, tf: r.Chart_TF,
      h: n(r.Box_Pips), margin: n(r.Edge_Margin_Pips), u: Number.isFinite(o.u) ? +o.u.toFixed(3) : null,
      exact: o.exact, off: n(r.Entry_Off_Pips), stop: n(r.Stop_Pips), stopv1: n(r.Stop_V1_Pips),
      tp1: n(r.TP1_Pips), tp2: n(r.TP2_Pips), tp3: n(r.TP3_Pips),
      lot: n(r.Lot), risk: n(r.Risk_USD), dir: r.Direction, ver: r.Formula_Version,
      verdict: (rev.get(r.Sample_ID) || {}).Verdict || "", imgs
    };
  });

  const cards = rows.map((r) => card(r, rev.get(r.Sample_ID), readImages(r.Sample_ID), readNotes(r.Sample_ID))).join("\n");

  const typeRow = Object.keys(byType).sort().map((t) => {
    const d = byType[t];
    return `<div class="tchip"><b style="color:${TYPE_COLOR[t] || "#8b95a5"}">${t}</b>
      <span>${d.n}</span>
      <small>میانهٔ حاشیه ${f1(median(d.margins))}p · میانهٔ استاپ ${f1(median(d.stop))}p</small></div>`;
  }).join("");

  return `<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>دیتاست بیس‌نات</title>
<style>
:root{--bg:#0e1116;--card:#161b22;--line:#2b3240;--txt:#d7dde6;--dim:#8b95a5;
      --real:#3fb950;--inv:#f85149;--unclear:#d29922;--none:#6e7681;--accent:#58a6ff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--txt);font:14px/1.6 "Segoe UI",Tahoma,sans-serif}
header.top{padding:18px 24px 10px;border-bottom:1px solid var(--line);position:sticky;top:0;
      background:#0e1116f2;backdrop-filter:blur(6px);z-index:5}
h1{margin:0;font-size:19px} h1 small{color:var(--dim);font-weight:400;margin-right:8px;font-size:13px}
.kpis{display:flex;flex-wrap:wrap;gap:10px;padding:14px 24px 6px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px 12px;min-width:104px}
.kpi b{display:block;font-size:18px} .kpi span{color:var(--dim);font-size:12px}
.next{margin:12px 24px 0;display:flex;flex-wrap:wrap;align-items:baseline;gap:6px 14px;
      border:1px solid var(--line);border-right:3px solid var(--accent);border-radius:8px;
      background:#11161d;padding:9px 14px;font-size:13px}
.next b{font-size:13px} .next span{color:var(--dim);font-size:12px}
.next code{font:12px/1.4 Consolas,monospace;background:#0d1117;border:1px solid var(--line);
      border-radius:5px;padding:2px 8px;margin-right:auto;direction:ltr;unicode-bidi:embed;color:#9ecbff}
.next kbd{font:11px/1 Consolas,monospace;background:#0d1117;border:1px solid var(--line);
      border-bottom-width:2px;border-radius:4px;padding:2px 5px;color:#fff}
.next.file{border-right-color:var(--unclear)} .next.ok{border-right-color:var(--real)}
.steps{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px;margin:10px 0 4px}
.step{background:#11161d;border:1px solid var(--line);border-radius:8px;padding:9px 12px}
.step b{display:block;font-size:12px;color:var(--accent);margin-bottom:3px}
.step p{margin:0 0 6px;font-size:12px;color:#b9c2cf}
.step code{display:block;font:11px/1.5 Consolas,monospace;color:#9ecbff;direction:ltr;
      unicode-bidi:embed;text-align:left;overflow-x:auto;white-space:pre}
.step kbd{font:11px/1 Consolas,monospace;background:#0d1117;border:1px solid var(--line);
      border-bottom-width:2px;border-radius:4px;padding:1px 5px;color:#fff}
.tchips{display:flex;flex-wrap:wrap;gap:8px;padding:6px 24px 12px}
.tchip{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 10px;font-size:12px}
.tchip b{font-size:14px;margin-left:6px} .tchip small{display:block;color:var(--dim)}
.filters{display:flex;flex-wrap:wrap;gap:8px;padding:0 24px 10px;align-items:center}
select,input,button{background:#0d1117;color:var(--txt);border:1px solid var(--line);
      border-radius:6px;padding:6px 8px;font:inherit;font-size:13px}
button{cursor:pointer} button:hover{border-color:var(--accent);color:#fff}
main{padding:0 24px 40px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(360px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden;scroll-margin-top:120px}
.card:hover{border-color:#3d4757}
.thumb{width:100%;display:block;background:#0a0d12;cursor:zoom-in;border-bottom:1px solid var(--line);aspect-ratio:16/9;object-fit:cover}
.thumb.none{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;
      color:var(--c);background:linear-gradient(0deg,#0a0d12,#0f141b);cursor:default}
.thumb.none span{font-size:26px;font-weight:600;opacity:.5} .thumb.none small{color:var(--dim);font-size:12px}
.card>header{display:flex;align-items:center;gap:8px;padding:9px 12px;background:#11161d;border-bottom:1px solid var(--line)}
.card>header b{font-size:13px}
.badge{font-size:11px;padding:1px 8px;border-radius:999px;border:1px solid;white-space:nowrap}
.v-real{color:var(--real);border-color:var(--real)} .v-invented{color:var(--inv);border-color:var(--inv)}
.v-unclear{color:var(--unclear);border-color:var(--unclear)} .v-none{color:var(--none);border-color:var(--none)}
.shots{margin-right:auto;color:var(--dim);font-size:11px}
.meta{padding:8px 12px;display:grid;grid-template-columns:repeat(3,1fr);gap:3px 10px;font-size:12px}
.meta div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meta span{color:var(--dim);margin-left:4px}
.ladder{padding:0 12px 4px}
.anchor{padding:0 12px 6px;color:var(--dim);font-size:11px}
.anchor span{color:#5f6b7a;margin-left:6px} .anchor span:first-child{margin-left:0}
.note{padding:2px 12px 8px;font-size:12px;max-height:190px;overflow:auto;border-top:1px dashed var(--line)}
.note h4,.note h5,.note h6{margin:8px 0 4px;font-size:12px;color:var(--accent);font-weight:500}
.note p{margin:2px 0;color:#b9c2cf} .note ul{margin:2px 0;padding-inline-start:18px}
.note table.kv{width:100%;border-collapse:collapse;font-size:11px}
.note table.kv th,.note table.kv td{padding:2px 4px;border-bottom:1px solid #20262f;text-align:right}
.note table.kv th{color:var(--dim);font-weight:400;width:38%}
.dim{color:var(--dim)}
.card>footer{display:flex;gap:6px;padding:7px 12px;border-top:1px solid var(--line);align-items:center}
.card>footer code{font:11px/1.4 Consolas,monospace;color:var(--dim);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.card>footer button{font-size:11px;padding:3px 8px}
section.panel{margin:22px 0;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 16px}
section.panel h2{margin:0 0 8px;font-size:15px}
table.cmp{width:100%;border-collapse:collapse;font-size:12px}
table.cmp th,table.cmp td{text-align:right;padding:4px 8px;border-bottom:1px solid var(--line)}
table.cmp th{color:var(--dim);font-weight:600}
.empty{color:var(--dim);font-size:12px;margin:0}
.lb{position:fixed;inset:0;background:#000e;display:none;align-items:center;justify-content:center;z-index:9}
.lb.on{display:flex}
.lb img{max-width:94vw;max-height:88vh;border:1px solid var(--line);cursor:grab;
       transform-origin:center center;user-select:none;-webkit-user-drag:none}
.lb img.drag{cursor:grabbing}
.lbbar{position:absolute;top:12px;left:50%;transform:translateX(-50%);display:flex;gap:6px;
       align-items:center;background:#161b22ee;border:1px solid var(--line);border-radius:8px;padding:6px 10px}
.lbbar .z{color:var(--dim);min-width:52px;text-align:center;font-size:12px}
.lbhint{position:absolute;bottom:12px;left:50%;transform:translateX(-50%);color:var(--dim);font-size:12px;
        background:#161b22dd;border:1px solid var(--line);border-radius:8px;padding:4px 10px}
@media (max-width:520px){.grid{grid-template-columns:1fr}.meta{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<header class="top">
  <h1>دیتاست بیس‌نات <small>هر نمونه یک پوشه: عکس + اعداد + یادداشت</small></h1>
</header>
<div class="next ${next.k}">${next.h}</div>
<div class="kpis">
  <div class="kpi"><b>${rows.length}</b><span>نمونه</span></div>
  <div class="kpi"><b>${withShot}</b><span>با عکس</span></div>
  <div class="kpi"><b>${close}</b><span>زیر ۱ پیپ از مرز</span></div>
  <div class="kpi"><b>${f1(median(margins))}p</b><span>میانهٔ حاشیه</span></div>
  <div class="kpi"><b>${nearEdge}</b><span>زیر ۰.۱ رنگ از مرز</span></div>
  <div class="kpi"><b>${verdicts.real}/${verdicts.invented}/${verdicts.unclear}</b><span>واقعی / ساختگی / نامعلوم</span></div>
  <div class="kpi"><b>${esc(versions)}</b><span>نسخهٔ فرمول</span></div>
  <div class="kpi"><b>${moved}</b><span>استاپِ عوض‌شده با v2</span></div>
  <div class="kpi"><b>${rows.length}/${RESCORE_AT}</b><span>تا بازبینی نسخه</span></div>
</div>
<div class="tchips">${typeRow}</div>
<div class="filters">
  <input id="q" placeholder="جست‌وجو: شناسه، نماد، یادداشت…" style="min-width:220px">
  <select id="ft"><option value="">همهٔ نوع‌ها</option>${["FTR", "ETR", "CTR", "OTR"].map((t) => `<option>${t}</option>`).join("")}</select>
  <select id="fv"><option value="">همهٔ داوری‌ها</option><option value="real">واقعی</option><option value="invented">ساختگی</option><option value="unclear">نامعلوم</option><option value="__none">بازبینی‌نشده</option></select>
  <select id="sort"><option value="id">شناسه ↑</option><option value="margin">حاشیه ↑</option><option value="u">u ↑</option><option value="stop">استاپ ↑</option><option value="h">h ↑</option></select>
  <span id="count" class="dim" style="font-size:12px"></span>
</div>
<main>
  <div id="grid" class="grid">
${cards}
  </div>
  <section class="panel">
    <h2>مقایسه <small class="dim" style="font-weight:400">— دو تا چهار نمونه را از دکمهٔ تیک هر کارت انتخاب کن</small></h2>
    <div id="cmp"></div>
  </section>
  <section class="panel">
    <h2>روال کار <small class="dim" style="font-weight:400">— چهار قدم، هر قدم یک دستور، هر دست‌آورد یک فایل</small></h2>
    <div class="steps">
      <div class="step"><b>۱ · گرفتن</b>
        <p>مستطیل نود را کلیک کن، <kbd>K</kbd> را بزن. یک پوشه با عکس و ۳۷ عدد ساخته می‌شود.</p>
        <code>K  →  MQL4\Files\BK_Dataset\Samples\</code></div>
      <div class="step"><b>۲ · ثبت</b>
        <p>صف را در CSV بنویس، پوشهٔ نمونه بساز، صفحه را بازسازی کن.</p>
        <code>node tools/bk-shot-sync.js --watch</code></div>
      <div class="step"><b>۳ · گفتن</b>
        <p>عکس دوم، جملهٔ دلیل، داوری. یادداشت به نمونه می‌چسبد نه به روز.</p>
        <code>node tools/bk-dataset-dashboard.js note BK-0005 "…"</code></div>
      <div class="step"><b>۴ · تصمیم</b>
        <p>فرمول فقط وقتی عوض می‌شود که یک نسخه روی همین سطرها ببرد. امروز v2 رفت (hop = round(u)) و تصمیمِ نهایی به <b>۲۰ نمونه</b> موکول شد: هر سطر «استاپ v1» را هم نگه می‌دارد، پس مقایسه بدون سفرِ دوم به چارت انجام می‌شود.</p>
        <code>Formula_Version: v1 → v2  (next: 20)</code></div>
    </div>
    <p class="empty">عددها از خودِ چارت خوانده می‌شوند (مستطیل و برچسب‌های ENTRY/SL/TP)، پس یک سطر نمی‌تواند استاپی را توصیف کند که چارت نمی‌کشد. متن کامل روال: <code>docs/bk-dataset.md</code> بند ۸.</p>
  </section>
</main>
<div class="lb" id="lb">
  <div class="lbbar"><button id="prev">‹</button><span class="z" id="zi">100%</span><button id="next">›</button><button id="close">بستن</button></div>
  <img id="lbimg" alt="">
  <div class="lbhint">چرخ ماوس = زوم · کشیدن = جابه‌جایی · Esc = بستن</div>
</div>
<script>
var DATA = ${JSON.stringify(DATA)};
var picked = [];
var sortKey = "id";

function esc2(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];}); }
function fmt(v,d){ return (v===null||v===undefined||isNaN(v))?"—":Number(v).toFixed(d); }
function pill(t){
  var col={FTR:"#97C459",ETR:"#85B7EB",CTR:"#EF9F27",OTR:"#F09595"}[t]||"#8b95a5";
  return '<span class="badge" style="color:'+col+';border-color:'+col+'">'+esc2(t)+'</span>';
}
function verdictCell(v){
  if(!v) return '<span class="badge v-none">—</span>';
  return '<span class="badge v-'+esc2(v)+'">'+esc2(v)+'</span>';
}
function rowsNow(){
  var q=(document.getElementById("q").value||"").toLowerCase();
  var ft=document.getElementById("ft").value;
  var fv=document.getElementById("fv").value;
  var out=DATA.filter(function(r){
    if(ft && r.type!==ft) return false;
    if(fv==="__none"){ if(r.verdict) return false; }
    else if(fv && r.verdict!==fv) return false;
    if(!q) return true;
    return (r.id+" "+r.symbol+" "+r.type+" "+r.verdict).toLowerCase().indexOf(q)>=0;
  });
  out.sort(function(a,b){
    var x=a[sortKey], y=b[sortKey];
    if(sortKey==="id"){ x=String(x); y=String(y); return x<y?-1:x>y?1:0; }
    x=(x===null?Infinity:x); y=(y===null?Infinity:y);
    return x-y;
  });
  return out;
}
function render(){
  var keep=rowsNow();
  var ids={}; keep.forEach(function(r){ ids[r.id]=1; });
  var cards=document.querySelectorAll("#grid .card");
  for(var i=0;i<cards.length;i++) cards[i].style.display = ids[cards[i].id]?"":"none";
  document.getElementById("count").textContent = keep.length+" / "+DATA.length+" نمونه";
  renderCompare();
}
function renderCompare(){
  var rows=DATA.filter(function(r){ return picked.indexOf(r.id)>=0; });
  var box=document.getElementById("cmp");
  if(rows.length<2){ box.innerHTML = rows.length ? '<p class="empty">یک نمونه انتخاب شده — یکی دیگر هم تیک بزن.</p>' : '<p class="empty">چیزی انتخاب نشده.</p>'; return; }
  var head="<tr><th></th>"+rows.map(function(r){return "<th>"+esc2(r.id)+"</th>";}).join("")+"</tr>";
  var defs=[["نوع",function(r){return pill(r.type);}],
    ["h",function(r){return fmt(r.h,1)+"p";}],
    ["حاشیه",function(r){return fmt(r.margin,1)+"p";}],
    ["u",function(r){return (r.u===null)?"—":((r.exact?"":"~")+r.u.toFixed(3));}],
    ["ورود",function(r){return fmt(r.off,1)+"p";}],
    ["استاپ",function(r){return fmt(r.stop,1)+"p";}],
    ["استاپ v1",function(r){return fmt(r.stopv1,1)+"p"+(r.stopv1!==null&&r.stop!==null&&Math.abs(r.stopv1-r.stop)>0.05?' <span class="dim">Δ</span>':'');}],
    ["TP",function(r){return fmt(r.tp1,0)+" / "+fmt(r.tp2,0)+" / "+fmt(r.tp3,0);}],
    ["لات",function(r){return fmt(r.lot,2);}],
    ["ریسک $",function(r){return fmt(r.risk,1);}],
    ["داوری",function(r){return verdictCell(r.verdict);}],
    ["عکس",function(r){return r.imgs.length;}],
    ["",function(r){return '<button data-pick="'+esc2(r.id)+'">حذف</button>';}]];
  var body=defs.map(function(d){
    return "<tr><td class=\\"dim\\">"+d[0]+"</td>"+rows.map(function(r){return "<td>"+d[1](r)+"</td>";}).join("")+"</tr>";
  }).join("");
  box.innerHTML='<table class="cmp"><thead>'+head+'</thead><tbody>'+body+'</tbody></table>';
}
document.addEventListener("change",function(e){
  if(e.target && e.target.dataset && e.target.dataset.pick!==undefined){
    var id=e.target.dataset.pick, i=picked.indexOf(id);
    if(i>=0) picked.splice(i,1); else { picked.push(id); if(picked.length>4) picked.shift(); }
    renderCompare();
  }
});
document.addEventListener("click",function(e){
  var b=e.target.closest?e.target.closest("[data-pick]"):null;
  if(b){ var id=b.dataset.pick, i=picked.indexOf(id); if(i>=0) picked.splice(i,1); renderCompare(); return; }
  var c=e.target.closest?e.target.closest("[data-copy]"):null;
  if(c){ if(navigator.clipboard) navigator.clipboard.writeText("node tools/bk-dataset-dashboard.js "+c.dataset.copy); c.textContent="کپی شد"; setTimeout(function(){c.textContent="کپی";},1200); return; }
});
document.addEventListener("input",function(e){
  if(e.target && (e.target.id==="q")) render();
});
document.addEventListener("change",function(e){
  if(e.target && (e.target.id==="ft"||e.target.id==="fv"||e.target.id==="sort")){
    if(e.target.id==="sort") sortKey=e.target.value;
    render();
  }
});

var ALL=[];
DATA.forEach(function(r){ r.imgs.forEach(function(src){ ALL.push({src:src,id:r.id}); }); });
var cur=-1, zoom=1, ox=0, oy=0;
var lb=document.getElementById("lb"), img=document.getElementById("lbimg"), zi=document.getElementById("zi");
function show(i){
  if(i<0||i>=ALL.length) return;
  cur=i; zoom=1; ox=0; oy=0;
  img.src=ALL[i].src; img.alt=ALL[i].id; img.style.transform="translate(0,0) scale(1)";
  zi.textContent="100%"; lb.classList.add("on");
}
document.addEventListener("click",function(e){
  var t=e.target;
  if(t && t.classList && t.classList.contains("thumb") && t.dataset.id){
    var i=ALL.findIndex(function(a){return a.src===t.getAttribute("src");});
    if(i>=0) show(i);
  }
});
document.getElementById("close").onclick=function(){ lb.classList.remove("on"); };
document.getElementById("prev").onclick=function(){ show(cur-1); };
document.getElementById("next").onclick=function(){ show(cur+1); };
lb.addEventListener("click",function(e){ if(e.target===lb) lb.classList.remove("on"); });
document.addEventListener("keydown",function(e){
  if(!lb.classList.contains("on")) return;
  if(e.key==="Escape") lb.classList.remove("on");
  if(e.key==="ArrowLeft") show(cur+1);
  if(e.key==="ArrowRight") show(cur-1);
});
lb.addEventListener("wheel",function(e){
  e.preventDefault();
  zoom=Math.max(0.4,Math.min(8,zoom*(e.deltaY<0?1.15:1/1.15)));
  img.style.transform="translate("+ox+"px,"+oy+"px) scale("+zoom+")";
  zi.textContent=Math.round(zoom*100)+"%";
},{passive:false});
var drag=false, sx=0, sy=0;
img.addEventListener("mousedown",function(e){ drag=true; sx=e.clientX-ox; sy=e.clientY-oy; img.classList.add("drag"); });
window.addEventListener("mousemove",function(e){ if(!drag) return; ox=e.clientX-sx; oy=e.clientY-sy; img.style.transform="translate("+ox+"px,"+oy+"px) scale("+zoom+")"; });
window.addEventListener("mouseup",function(){ drag=false; img.classList.remove("drag"); });
render();
</script>
</body>
</html>`;
}

// ---------------------------------------------------------------- review / note / attach / journal
function stamp() {
  const d = new Date();
  const p = (x) => String(x).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function requireSample(id) {
  if (!id || !readRows().some((r) => r.Sample_ID === id)) {
    console.error(`no sample ${id || "?"} in Dataset.csv`);
    process.exit(1);
  }
}

function review(id, verdict, note) {
  if (!["real", "invented", "unclear"].includes(verdict)) {
    console.error("verdict must be real | invented | unclear");
    process.exit(1);
  }
  requireSample(id);
  const map = readReviews();
  map.set(id, { Sample_ID: id, Verdict: verdict, Note: note || "", Reviewer: "user", Reviewed_At: stamp() });
  const head = ["Sample_ID", "Verdict", "Note", "Reviewer", "Reviewed_At"];
  const body = [...map.values()].map((r) =>
    head.map((h) => {
      const v = String(r[h] || "");
      return /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
    }).join(",")
  );
  fs.writeFileSync(REV, [head.join(","), ...body].join("\n") + "\n", "utf8");
  fs.appendFileSync(JRN, `- ${stamp()} · ${id} → ${verdict}${note ? ` — ${note}` : ""}\n`, "utf8");
  console.log(`  ${id} → ${verdict}`);
}

function note(id, text) {
  requireSample(id);
  const dir = sampleDir(id);
  fs.mkdirSync(dir, { recursive: true });
  fs.appendFileSync(path.join(dir, "notes.md"), `\n## ${stamp()}\n${text}\n`, "utf8");
  console.log(`  ${id}: note appended`);
}

function attach(id, files) {
  requireSample(id);
  if (!files.length) {
    console.error("attach needs at least one file");
    process.exit(1);
  }
  const dir = sampleDir(id);
  fs.mkdirSync(dir, { recursive: true });
  for (const src of files) {
    if (!fs.existsSync(src)) { console.error(`  missing ${src}`); continue; }
    const base = path.basename(src);
    fs.copyFileSync(src, path.join(dir, base));
    console.log(`  ${id}: ${base}`);
  }
}

function journal(text) {
  fs.appendFileSync(JRN, `- ${stamp()} · ${text}\n`, "utf8");
  console.log("  journal: " + text);
}

// ---------------------------------------------------------------- main
function mainBuild(open) {
  if (!fs.existsSync(CSV)) { console.error(`missing ${CSV}`); return 1; }
  const rows = readRows();
  if (!rows.length) { console.error("Dataset.csv has no rows"); return 1; }
  fs.writeFileSync(OUT, build(rows), "utf8");
  console.log(`  dashboard: ${OUT}  (${rows.length} sample(s))`);
  if (open) console.log(`  open: ${OUT}`);
  return 0;
}

function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0];
  if (cmd === "review") { review(argv[1], argv[2], argv.slice(3).join(" ")); return mainBuild(false); }
  if (cmd === "note") { note(argv[1], argv.slice(2).join(" ")); return mainBuild(false); }
  if (cmd === "attach") { attach(argv[1], argv.slice(2)); return mainBuild(false); }
  if (cmd === "journal") { journal(argv.slice(1).join(" ")); return 0; }
  return mainBuild(argv.includes("--open"));
}

process.exitCode = main();
