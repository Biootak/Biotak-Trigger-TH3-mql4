#!/usr/bin/env node
// th3-dataset-dashboard.js — P-TH3-DB: the dataset, read at a glance.
//
// WHAT THIS IS FOR. The recorder writes numbers; the formula is tuned by reading
// them against what the market did. Twenty TXT files in one folder is not a way
// to do that — the review takes one pass over the SET (is this error normal for
// this symbol? are the bad samples the same pattern?), and a set can only be
// seen as a set. So this renders the whole dataset as ONE page: every sample
// in its own card, the picture beside the numbers, filterable by symbol,
// timeframe, date and VERDICT, and sorted by the column being tuned.
//
// THE VERDICT IS THE POINT. Human visual discretion is what tells a real
// structure from an invented one (the recorder's own header says so), and a
// verdict is the one thing no formula can produce. So a sample carries
// `real | invented | unclear`, stored in Reviews.csv next to the dataset, and
// the dashboard counts, filters and colours by it — that is how "each real
// sample" becomes separable from the rest.
//
// JOURNAL. A review is only worth something if it leaves a trail, so writing a
// verdict also appends a line to journal.md, and the page shows the tail. The
// two are separate on purpose: Reviews.csv is keyed by sample (one current
// verdict each, re-writable) and journal.md is append-only history (what was
// decided, when, and why).
//
// The page is ONE HTML file with the images referenced by RELATIVE path, so it
// opens from disk with no server, no build and no install — a double-click is
// the whole deployment. `--inline` writes a second copy with the pictures as
// data URIs instead: bigger, but a SINGLE file that survives being attached to
// a message or moved to another machine, and the only form a browser sandbox
// (which serves one file and nothing beside it) can display at all.
//
//   node tools/th3-dataset-dashboard.js                        # build the page
//   node tools/th3-dataset-dashboard.js review Sample_015 real "clean AB=CD"
//   node tools/th3-dataset-dashboard.js review Sample_015 invented "no real turn"
//   node tools/th3-dataset-dashboard.js journal "K 3.5 looks too high on XAU"
//   node tools/th3-dataset-dashboard.js --inline               # ONE file, images inside
//   node tools/th3-dataset-dashboard.js --open                 # build + print path
//
// Exit 0 on a clean run, 1 when the dataset is missing or unreadable.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DS = path.join(ROOT, 'Samples', 'TH3_Dataset');
const DB = path.join(DS, 'Dataset.csv');
const REVIEWS = path.join(DS, 'Reviews.csv');
const JOURNAL = path.join(DS, 'journal.md');
const PAGE = path.join(DS, 'dashboard.html');

const VERDICTS = ['real', 'invented', 'unclear'];
const REVIEW_COLS = ['Sample_ID', 'Verdict', 'Note', 'Reviewer', 'Reviewed_At'];

function splitCsv(line) {
  return line.replace(/\r$/, '').split(',');
}

function readCsv(file) {
  if (!fs.existsSync(file)) return [];
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter((l) => l.length);
  if (!lines.length) return [];
  const head = splitCsv(lines[0]);
  return lines.slice(1).map((l) => {
    const cells = splitCsv(l);
    const row = {};
    head.forEach((h, i) => { row[h] = cells[i] == null ? '' : cells[i]; });
    return row;
  });
}

function nowStamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
         `${p(d.getHours())}:${p(d.getMinutes())}`;
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

function num(v) {
  const f = parseFloat(v);
  return Number.isFinite(f) ? f : null;
}

//--- the dataset, joined with the verdicts and pointed at its own files
function load(inline) {
  if (!fs.existsSync(DB)) return null;
  const rows = readCsv(DB);
  const reviews = new Map(readCsv(REVIEWS).map((r) => [r.Sample_ID, r]));
  const samples = rows.map((r) => {
    const folder = r.Folder || '';
    const shot = r.Screenshot || '';
    // the raw diagnostic, embedded. file:// forbids fetch() of a sibling file,
    // and the detail view must show the LOG AS WRITTEN — it is the record the
    // card's numbers are derived from, and reading a summary of it would be
    // exactly the "sample nobody can check" problem this page exists to fix.
    let txt = '';
    if (folder && r.Log_File) {
      const f = path.join(DS, 'Samples', folder, r.Log_File);
      if (fs.existsSync(f) && fs.statSync(f).size <= 64 * 1024) {
        txt = fs.readFileSync(f, 'utf8');
      }
    }
    const rev = reviews.get(r.Sample_ID) || {};
    return Object.assign({}, r, {
      Verdict: VERDICTS.includes(rev.Verdict) ? rev.Verdict : 'unreviewed',
      Note: rev.Note || '',
      Reviewer: rev.Reviewer || '',
      Reviewed_At: rev.Reviewed_At || '',
      Error: num(r.Error_Pips),
      Step: num(r.Step_Pips),
      Legs: [num(r.Leg_AB), num(r.Leg_BC), num(r.Leg_CD)],
      Targets: [num(r.Target_1), num(r.Target_3), num(r.Target_5), num(r.Target_7)],
      D: num(r.D_Price),
      Turn: num(r.Actual_Turn),
      Pip: num(r.Pip_Size) || 0.0001,
      // RELATIVE TO THE SAMPLES ROOT, not to the page: the page must work both
      // opened from disk (file://…/Samples/TH3_Dataset/dashboard.html) and
      // served from the repo root, and the two disagree about the prefix. The
      // page tries both (see BASE below) instead of being right about one.
      Txt: txt,
      ShotPath: folder && shot ? `${folder}/${shot}` : '',
      LogPath: folder && r.Log_File ? `${folder}/${r.Log_File}` : '',
    });
  });
  if (inline) {
    let bytes = 0;
    for (const s of samples) {
      if (!s.ShotPath) continue;
      const file = path.join(DS, 'Samples', s.ShotPath);
      if (!fs.existsSync(file)) continue;
      const buf = fs.readFileSync(file);
      bytes += buf.length;
      s.ShotPath = 'data:image/png;base64,' + buf.toString('base64');
    }
    return { generated: nowStamp(), samples, inlineBytes: bytes, journal: null };
  }
  return {
    generated: nowStamp(),
    samples,
    journal: fs.existsSync(JOURNAL)
      ? fs.readFileSync(JOURNAL, 'utf8').split(/\r?\n/).filter(Boolean).slice(-40)
      : [],
  };
}

const CSS = `
:root{--bg:#0e1116;--card:#161b22;--line:#2b3240;--txt:#d7dde6;--dim:#8b95a5;
      --real:#3fb950;--inv:#f85149;--unclear:#d29922;--none:#6e7681;--accent:#58a6ff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--txt);font:14px/1.6 "Segoe UI",Tahoma,sans-serif}
header{padding:18px 24px;border-bottom:1px solid var(--line);position:sticky;top:0;background:#0e1116f2;
       backdrop-filter:blur(6px);z-index:5}
h1{margin:0;font-size:19px} h1 small{color:var(--dim);font-weight:400;margin-right:8px}
.kpis{display:flex;flex-wrap:wrap;gap:10px;padding:14px 24px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px 12px;min-width:104px}
.kpi b{display:block;font-size:18px} .kpi span{color:var(--dim);font-size:12px}
.bar{height:6px;border-radius:4px;background:#21262d;overflow:hidden;margin-top:6px;display:flex}
.bar i{display:block;height:100%}
.filters{display:flex;flex-wrap:wrap;gap:8px;padding:0 24px 12px;align-items:center}
select,input,button{background:#0d1117;color:var(--txt);border:1px solid var(--line);
      border-radius:6px;padding:6px 8px;font:inherit;font-size:13px}
button{cursor:pointer} button:hover{border-color:var(--accent);color:#fff}
main{padding:0 24px 40px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.card>header{position:static;border:0;padding:10px 12px;display:flex;justify-content:space-between;
      align-items:center;gap:8px;background:#11161d}
.badge{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid;white-space:nowrap}
.b-real{color:var(--real);border-color:var(--real)} .b-invented{color:var(--inv);border-color:var(--inv)}
.b-unclear{color:var(--unclear);border-color:var(--unclear)} .b-unreviewed{color:var(--none);border-color:var(--none)}
.thumb{width:100%;display:block;background:#0a0d12;cursor:zoom-in;border-bottom:1px solid var(--line)}
.meta{padding:8px 12px;display:grid;grid-template-columns:repeat(3,1fr);gap:4px 10px;font-size:12px}
.meta div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card:hover{border-color:var(--accent)}
.meta span{color:var(--dim)}
.err{font-weight:700}
.foot{display:flex;gap:6px;padding:8px 12px;border-top:1px solid var(--line);flex-wrap:wrap}
.note{padding:0 12px 8px;color:var(--dim);font-size:12px}
section.panel{margin:22px 0;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 16px}
section.panel h2{margin:0 0 8px;font-size:15px}
table{width:100%;border-collapse:collapse;font-size:12px}
th,td{text-align:right;padding:4px 8px;border-bottom:1px solid var(--line)}
th{color:var(--dim);font-weight:600}
pre{white-space:pre-wrap;font:12px/1.5 Consolas,monospace;color:var(--dim);max-height:280px;overflow:auto}
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
.hint{color:var(--dim);font-size:12px;padding:0 24px 10px}
.card .meta{cursor:pointer}
.more{font-size:11px;color:var(--dim);background:none;border:1px dashed var(--line)}
.more:hover{color:var(--accent);border-color:var(--accent)}
.mdl{position:fixed;inset:0;background:#000c;display:none;align-items:flex-start;justify-content:center;
     z-index:8;overflow:auto;padding:24px}
.mdl.on{display:flex}
.mdlbox{background:var(--card);border:1px solid var(--line);border-radius:12px;width:min(1080px,96vw);
        margin:auto}
.mdlhead{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:12px 16px;
         border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--card);border-radius:12px 12px 0 0}
.mdlbody{padding:16px;display:grid;grid-template-columns:1.25fr 1fr;gap:16px}
@media (max-width:900px){.mdlbody{grid-template-columns:1fr}}
.mdlbody img{width:100%;border:1px solid var(--line);border-radius:8px;cursor:zoom-in;display:block}
.grp{margin-bottom:14px}
.grp h3{margin:0 0 6px;font-size:13px;color:var(--accent);font-weight:600}
.grp table td:first-child{color:var(--dim);width:42%}
.grp table td{font-variant-numeric:tabular-nums}
details{margin-top:10px} summary{cursor:pointer;color:var(--dim);font-size:12px}
`;

function script(src) {
  return src.replace(/<\/script>/gi, '<\\/script>');
}

function buildPage(data) {
  const payload = script(JSON.stringify(data));
  return `<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<title>داشبورد دیتاست TH3</title>
<style>${CSS}</style>
</head>
<body>
<header>
  <h1>داشبورد دیتاست TH3 <small>${esc(data.generated)} · ${data.samples.length} نمونه · منبع: Samples/TH3_Dataset/Dataset.csv</small></h1>
</header>
<section class="kpis" id="kpis"></section>
<div class="filters">
  <input id="q" placeholder="جستجو: نماد، الگو، پوشه، یادداشت…" size="28">
  <select id="sym"><option value="">همه نمادها</option></select>
  <select id="tf"><option value="">همه تایم‌فریم‌ها</option></select>
  <select id="verdict">
    <option value="">همه احکام</option>
    <option value="real">واقعی</option>
    <option value="invented">ساختگی</option>
    <option value="unclear">نامشخص</option>
    <option value="unreviewed">بررسی‌نشده</option>
  </select>
  <select id="sort">
    <option value="Capture_Stamp">ترتیب زمان</option>
    <option value="Error_Pips">خطا (صعودی)</option>
    <option value="Error_Pips_desc">خطا (نزولی)</option>
    <option value="Step_Pips">گام</option>
    <option value="Ratio_CD_BC">نسبت CD/BC</option>
    <option value="Sample_ID">شماره</option>
  </select>
  <input id="errMax" type="number" step="0.5" placeholder="خطای بیشتر از" style="width:110px">
  <button id="reset">پاک کردن فیلترها</button>
  <span class="hint" id="count"></span>
</div>
<div class="hint">هر نمونه یک کارت است: تصویر، اعداد فرمول، بازار واقعی، و حکم شما.
برای ثبت حکم از دکمه‌های زیر استفاده کنید (فرمان در حافظه کپی می‌شود، در ترمینال اجرا کنید).</div>
<main>
  <div class="cards" id="cards"></div>
  <section class="panel">
    <h2>توزیع خطا (پیپ)</h2>
    <div id="hist"></div>
  </section>
  <section class="panel">
    <h2>میانگین و میانه خطا به تفکیک نماد و تایم‌فریم</h2>
    <div id="groups"></div>
  </section>
  <section class="panel">
    <h2>ژورنال</h2>
    <pre id="journal">${esc((data.journal || []).join('\n'))}</pre>
  </section>
</main>
<div class="mdl" id="mdl">
  <div class="mdlbox">
    <div class="mdlhead"><b id="mdlTitle"></b><span style="display:flex;gap:8px;align-items:center">
      <span class="badge" id="mdlBadge"></span>
      <button id="mdlClose">بستن ✕</button></span></div>
    <div class="mdlbody">
      <div><div id="mdlShot"></div><div id="mdlNote" class="note"></div></div>
      <div>
        <div id="mdlFields"></div>
        <div class="foot" id="mdlFoot"></div>
        <details><summary>لاگ کامل (TXT خام)</summary><pre id="mdlTxt"></pre></details>
      </div>
    </div>
  </div>
</div>
<div class="lb" id="lb">
  <img id="lbimg" alt="" draggable="false">
  <div class="lbbar">
    <button id="lbOut" title="کوچک‌تر">−</button>
    <span class="z" id="lbz">100%</span>
    <button id="lbIn" title="بزرگ‌تر">+</button>
    <button id="lbReset">بازنشانی</button>
    <button id="lbClose">بستن ✕</button>
  </div>
  <div class="lbhint">چرخ ماوس = زوم · کشیدن = جابه‌جا · دابل‌کلیک = ۲۵۰٪ · Esc = بستن</div>
</div>
<script id="data" type="application/json">${payload}</script>
<script>
const DATA = JSON.parse(document.getElementById('data').textContent);
const S = DATA.samples;
const VERDICT_LABEL = { real:'واقعی', invented:'ساختگی', unclear:'نامشخص', unreviewed:'بررسی‌نشده' };
const VBADGE = { real:'b-real', invented:'b-invented', unclear:'b-unclear', unreviewed:'b-unreviewed' };
const $ = (id) => document.getElementById(id);
const fmt = (v, n = 1) => (v === null || v === undefined || v === '') ? '—' : Number(v).toFixed(n);
// the page needs its own esc(): the generator's is a Node function and does not
// exist here — a captured sample name goes into innerHTML, so it must be escaped
// on BOTH sides of the write.
const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"]/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
// P-TH3-DB: the page can be opened from disk OR served from the repo root, and
// the two need different prefixes for the same picture. Rather than guess, the
// img tag carries BOTH candidates and falls back on the first 404 — a broken
// thumbnail would read as "the sample has no picture", which is a lie.
const PREFIXES = location.pathname.indexOf('/TH3_Dataset/') >= 0
  ? ['Samples/', 'TH3_Dataset/Samples/'] : ['TH3_Dataset/Samples/', 'Samples/'];
const INLINE = DATA.inline === true;
const imgTag = (rel) => {
  if (!rel) return '';
  if (rel.startsWith('data:')) return '<img class="thumb" src="' + rel + '" alt="sample">';
  const [a, b] = [PREFIXES[0] + rel, PREFIXES[1] + rel];
  return '<img class="thumb" loading="lazy" src="' + a + '" data-alt="' + b +
    '" onerror="this.onerror=null;this.src=this.dataset.alt" alt="sample">';
};
const linkHref = (rel) => (rel ? (rel.startsWith('data:') ? rel : PREFIXES[0] + rel) : '#');

function reviewCmd(id, verdict, note) {
  return 'node tools/th3-dataset-dashboard.js review ' + id + ' ' + verdict +
    ' "' + (note || '') + '"';
}
function copy(text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    const old = btn.textContent; btn.textContent = 'کپی شد ✓';
    setTimeout(() => { btn.textContent = old; }, 1200);
  }, () => { window.prompt('کپی دستی:', text); });
}

/* --- KPI row: the set, not the sample --- */
function kpis(list) {
  const n = list.length;
  const errs = list.map((s) => s.Error).filter((e) => e !== null).sort((a, b) => a - b);
  const med = errs.length ? errs[Math.floor(errs.length / 2)] : null;
  const mean = errs.length ? errs.reduce((a, b) => a + b, 0) / errs.length : null;
  const within = errs.length ? errs.filter((e) => e <= 5).length / errs.length : 0;
  const count = (v) => list.filter((s) => s.Verdict === v).length;
  const cells = [
    ['نمونه', n, ''],
    ['واقعی', count('real'), 'var(--real)'],
    ['ساختگی', count('invented'), 'var(--inv)'],
    ['نامشخص', count('unclear'), 'var(--unclear)'],
    ['بررسی‌نشده', count('unreviewed'), 'var(--none)'],
    ['نماد', new Set(list.map((s) => s.Symbol)).size, ''],
    ['تایم‌فریم', new Set(list.map((s) => s.TF)).size, ''],
    ['میانه خطا (پیپ)', med === null ? '—' : med.toFixed(1), ''],
    ['میانگین خطا (پیپ)', mean === null ? '—' : mean.toFixed(1), ''],
    ['خطا ≤ ۵ پیپ', (within * 100).toFixed(0) + '٪', ''],
  ];
  $('kpis').innerHTML = cells.map(([label, v, c]) =>
    '<div class="kpi"><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v +
    '</b><span>' + label + '</span></div>').join('') +
    '<div class="kpi" style="min-width:220px"><b style="font-size:12px">' +
    'پوشش حکم</b><div class="bar">' +
    '<i style="width:' + (n ? count('real') / n * 100 : 0) + '%;background:var(--real)"></i>' +
    '<i style="width:' + (n ? count('unclear') / n * 100 : 0) + '%;background:var(--unclear)"></i>' +
    '<i style="width:' + (n ? count('invented') / n * 100 : 0) + '%;background:var(--inv)"></i>' +
    '<i style="width:' + (n ? count('unreviewed') / n * 100 : 0) + '%;background:var(--none)"></i>' +
    '</div><span>' + (n ? Math.round((count('real') + count('unclear') + count('invented')) / n * 100) : 0) +
    '٪ بررسی شده</span></div>';
}

/* --- P-TH3-DB: every column of Dataset.csv, named. The card shows the dozen
   numbers a review needs; the DETAIL view shows all 33, because a column nobody
   can read is a column nobody can trust, and this is the page that makes the
   dataset auditable. */
const GROUPS = [
  ['چه کسی و کِی', ['Sample_ID', 'Capture_Date', 'Capture_Clock', 'Capture_Stamp',
    'Symbol', 'TF', 'Owner_TF', 'Pattern', 'Direction']],
  ['ساختار', ['D_Time', 'D_Price', 'Digits', 'Pip_Size', 'Mother_Pips',
    'Leg_AB', 'Leg_BC', 'Leg_CD', 'Ratio_BC_AB', 'Ratio_CD_BC', 'K']],
  ['فرمول', ['Step_Mother', 'Step_Pattern', 'Step_Pips',
    'Target_1', 'Target_3', 'Target_5', 'Target_7']],
  ['بازار واقعی', ['Actual_Turn', 'Error_Pips', 'Rungs_Hit']],
  ['فایل‌ها', ['Folder', 'Log_File', 'Screenshot']],
];
const LABELS = {
  Sample_ID: 'شماره نمونه', Capture_Date: 'تاریخ ثبت', Capture_Clock: 'ساعت ثبت',
  Capture_Stamp: 'مهر زمانی', Symbol: 'نماد', TF: 'تایم‌فریم', Owner_TF: 'تایم‌فریم مالک',
  Pattern: 'الگو', Direction: 'جهت', D_Time: 'زمان D', D_Price: 'قیمت D',
  Digits: 'ارقام', Pip_Size: 'اندازه پیپ', Mother_Pips: 'مادر (پیپ)',
  Leg_AB: 'پای AB', Leg_BC: 'پای BC', Leg_CD: 'پای CD',
  Ratio_BC_AB: 'نسبت BC/AB', Ratio_CD_BC: 'نسبت CD/BC', K: 'ضریب K',
  Step_Mother: 'گام مادر', Step_Pattern: 'گام الگو', Step_Pips: 'گام نهایی (پیپ)',
  Target_1: 'هدف ۱', Target_3: 'هدف ۳', Target_5: 'هدف ۵', Target_7: 'هدف ۷',
  Actual_Turn: 'واکنش واقعی بازار', Error_Pips: 'خطا (پیپ)', Rungs_Hit: 'رانگ‌های لمس‌شده',
  Folder: 'پوشه', Log_File: 'فایل لاگ', Screenshot: 'تصویر',
};
const BY_ID = {};
S.forEach((x) => { BY_ID[x.Sample_ID] = x; });

function openDetail(id) {
  const s = BY_ID[id];
  if (!s) return;
  $('mdlTitle').textContent = id + ' — ' + (s.Symbol || '') + ' ' + (s.TF || '');
  $('mdlBadge').className = 'badge ' + VBADGE[s.Verdict];
  $('mdlBadge').textContent = VERDICT_LABEL[s.Verdict];
  $('mdlShot').innerHTML = s.ShotPath
    ? imgTag(s.ShotPath) : '<div class="hint">بدون تصویر</div>';
  $('mdlFields').innerHTML = GROUPS.map(([title, keys]) =>
    '<div class="grp"><h3>' + title + '</h3><table>' + keys.map((k) =>
      '<tr><td>' + (LABELS[k] || k) + '</td><td><bdi>' +
      (s[k] === '' || s[k] == null ? '—' : esc(s[k])) + '</bdi></td></tr>').join('') +
    '</table></div>').join('');
  // <bdi> around the timestamp again: this line mixes RTL text with an LTR date
  // and a bare one renders as 05-10-2026 — the review trail read backwards.
  $('mdlNote').innerHTML = (s.Note || s.Reviewed_At)
    ? 'حکم ثبت‌شده: <b>' + VERDICT_LABEL[s.Verdict] + '</b> — <bdi>' + esc(s.Reviewed_At) +
      '</bdi>' + (s.Reviewer ? ' (<bdi>' + esc(s.Reviewer) + '</bdi>)' : '') +
      '<br>' + esc(s.Note || '')
    : 'حکمی ثبت نشده — با دکمه‌های پایین یکی بگذار.';
  const btn = (v, label, note) => '<button data-cmd="' +
    esc(reviewCmd(id, v, note)).replace(/"/g, '&quot;') + '">' + label + '</button>';
  $('mdlFoot').innerHTML = btn('real', 'واقعی ✓') + btn('invented', 'ساختگی ✗') +
    btn('unclear', 'نامشخص ?');
  $('mdlTxt').textContent = s.Txt || '(لاگی در پوشه نیست)';
  $('mdl').classList.add('on');
}
function closeDetail() { $('mdl').classList.remove('on'); }

/* --- one card per sample: the picture, the formula, the market --- */
function card(s) {
  const img = s.ShotPath
    ? imgTag(s.ShotPath)
    : '<div class="thumb" style="height:90px;display:flex;align-items:center;color:var(--dim)">بدون تصویر</div>';
  // every value is wrapped in <bdi>: the page is RTL, and a bare "2026.10.05 17:01"
  // reorders itself on screen — a timestamp read backwards is a wrong timestamp.
  const cell = (k, v) => '<div><span>' + k + ': </span><bdi>' + v + '</bdi></div>';
  const errColor = s.Error === null ? 'var(--none)'
    : (s.Error <= 5 ? 'var(--real)' : (s.Error <= 15 ? 'var(--unclear)' : 'var(--inv)'));
  const review = (v, label, note) =>
    '<button data-cmd="' + esc(reviewCmd(s.Sample_ID, v, note)).replace(/"/g, '&quot;') +
    '">' + label + '</button>';
  return '<article class="card">' +
    '<header><b>' + s.Sample_ID + '</b><span class="badge ' + VBADGE[s.Verdict] + '">' +
    VERDICT_LABEL[s.Verdict] + '</span></header>' + img +
    '<div class="meta">' +
    cell('نماد', s.Symbol || '—') + cell('تایم‌فریم', (s.TF || '—') + (s.Owner_TF ? ' / ' + s.Owner_TF : '')) +
    cell('ثبت', (s.Capture_Date || '') + ' ' + (s.Capture_Clock || '')) +
    cell('D', (s.D_Time || '') + ' @ ' + (s.D_Price || '—')) +
    cell('پوشه', s.Folder || '—') +
    cell('الگو', s.Pattern || '—') +
    cell('AB / BC / CD', fmt(s.Legs[0]) + ' / ' + fmt(s.Legs[1]) + ' / ' + fmt(s.Legs[2]) + ' پیپ') +
    cell('نسبت CD/BC', fmt(s.Ratio_CD_BC, 3) + '  (K ' + fmt(s.K, 2) + ')') +
    cell('گام نهایی', '<b>' + fmt(s.Step) + '</b> پیپ') +
    cell('مادر', fmt(s.Mother_Pips) + ' پیپ') +
    cell('رانگ‌ها', s.Rungs_Hit || '—') +
    cell('واکنش بازار', s.Turn === null ? '—' : String(s.Turn)) +
    cell('خطا', '<span class="err" style="color:' + errColor + '">' +
      (s.Error === null ? '—' : s.Error.toFixed(1) + ' پیپ') + '</span>') +
    cell('نردبان T1/T3/T5/T7', s.Targets.map((t) => t === null ? '—' : t).join(' / ')) +
    '</div>' +
    (s.Note ? '<div class="note">' + esc(s.Reviewed_At) + ' — ' + esc(s.Note) + '</div>' : '') +
    '<div class="foot">' +
    (s.ShotPath && !s.ShotPath.startsWith('data:')
      ? '<a href="' + linkHref(s.ShotPath) + '" target="_blank"><button>تصویر کامل</button></a>' : '') +
    (s.LogPath ? '<a href="' + linkHref(s.LogPath) + '" target="_blank"><button>لاگ TXT</button></a>' : '') +
    review('real', 'واقعی ✓') + review('invented', 'ساختگی ✗') + review('unclear', 'نامشخص ?') +
    '<button class="more" data-open="' + s.Sample_ID + '">جزئیات کامل</button>' +
    '</div></article>';
}

function render() {
  const q = $('q').value.trim().toLowerCase();
  const sym = $('sym').value, tf = $('tf').value, vd = $('verdict').value;
  const sort = $('sort').value;
  const errMax = parseFloat($('errMax').value);
  let list = S.filter((s) => {
    if (sym && s.Symbol !== sym) return false;
    if (tf && s.TF !== tf) return false;
    if (vd && s.Verdict !== vd) return false;
    if (Number.isFinite(errMax) && (s.Error === null || s.Error > errMax)) return false;
    if (q) {
      const hay = [s.Sample_ID, s.Symbol, s.TF, s.Pattern, s.Folder, s.Note, s.D_Time].join(' ').toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });
  const dir = sort.endsWith('_desc') ? -1 : 1;
  const key = sort.replace('_desc', '');
  list = list.slice().sort((a, b) => {
    const av = a[key], bv = b[key];
    if (av === bv) return String(a.Sample_ID).localeCompare(String(b.Sample_ID));
    if (av === '' || av == null) return 1;
    if (bv === '' || bv == null) return -1;
    const an = parseFloat(av), bn = parseFloat(bv);
    if (Number.isFinite(an) && Number.isFinite(bn)) return (an - bn) * dir;
    return String(av).localeCompare(String(bv)) * dir;
  });
  $('count').textContent = list.length + ' از ' + S.length + ' نمونه';
  $('cards').innerHTML = list.length ? list.map(card).join('')
    : '<p class="hint">هیچ نمونه‌ای با این فیلترها پیدا نشد.</p>';
  kpis(list);
  charts(list);
}

function charts(list) {
  const errs = list.map((s) => s.Error).filter((e) => e !== null);
  const bins = [[0, 2], [2, 5], [5, 10], [10, 20], [20, 1e9]];
  const labels = ['۰–۲', '۲–۵', '۵–۱۰', '۱۰–۲۰', 'بیش از ۲۰'];
  const counts = bins.map(([lo, hi]) => errs.filter((e) => e > lo && e <= hi).length);
  const max = Math.max(1, ...counts);
  $('hist').innerHTML = '<table><tr>' + bins.map((b, i) =>
    '<th>' + labels[i] + '</th>').join('') + '</tr><tr>' + counts.map((c) =>
    '<td><div class="bar" style="width:120px"><i style="width:' + (c / max * 100) +
    '%;background:var(--accent)"></i></div>' + c + '</td>').join('') + '</tr></table>';

  const groups = {};
  list.forEach((s) => {
    const k = (s.Symbol || '?') + ' · ' + (s.TF || '?');
    (groups[k] = groups[k] || []).push(s);
  });
  const rows = Object.keys(groups).sort().map((k) => {
    const es = groups[k].map((s) => s.Error).filter((e) => e !== null).sort((a, b) => a - b);
    const mean = es.length ? es.reduce((a, b) => a + b, 0) / es.length : null;
    const med = es.length ? es[Math.floor(es.length / 2)] : null;
    const worst = es.length ? es[es.length - 1] : null;
    const real = groups[k].filter((s) => s.Verdict === 'real').length;
    return '<tr><td>' + k + '</td><td>' + groups[k].length + '</td><td>' + real +
      '</td><td>' + (mean === null ? '—' : mean.toFixed(1)) + '</td><td>' +
      (med === null ? '—' : med.toFixed(1)) + '</td><td>' + (worst === null ? '—' : worst.toFixed(1)) + '</td></tr>';
  });
  $('groups').innerHTML = rows.length
    ? '<table><tr><th>گروه</th><th>تعداد</th><th>واقعی</th><th>میانگین خطا</th>' +
      '<th>میانه</th><th>بدترین</th></tr>' + rows.join('') + '</table>'
    : '<p class="hint">داده‌ای نیست.</p>';
}

function fillSelect(id, values, label) {
  $(id).insertAdjacentHTML('beforeend', values.map((v) =>
    '<option value="' + esc(v) + '">' + esc(label ? label(v) : v) + '</option>').join(''));
}

fillSelect('sym', [...new Set(S.map((s) => s.Symbol))].filter(Boolean).sort());
fillSelect('tf', [...new Set(S.map((s) => s.TF))].filter(Boolean).sort());
['q', 'sym', 'tf', 'verdict', 'sort', 'errMax'].forEach((id) => {
  $(id).addEventListener('input', render);
  $(id).addEventListener('change', render);
});
$('reset').addEventListener('click', () => {
  ['q', 'sym', 'tf', 'verdict', 'sort', 'errMax'].forEach((id) => { $(id).value = id === 'sort' ? 'Capture_Stamp' : ''; });
  render();
});
document.addEventListener('click', (e) => {
  const cmd = e.target.getAttribute && e.target.getAttribute('data-cmd');
  if (cmd) { copy(cmd, e.target); return; }
  if (e.target.id === 'mdlClose' || e.target.id === 'mdl' ||
      (e.target.classList && e.target.classList.contains('thumb'))) {
    // a thumbnail always opens the PICTURE viewer, even inside the modal
  }
  const open = e.target.getAttribute && e.target.getAttribute('data-open');
  if (open) { openDetail(open); return; }
  if (e.target.id === 'mdlClose' || e.target.id === 'mdl') { closeDetail(); return; }
  const inBar = e.target.closest && e.target.closest('.lbbar');
  if (inBar) return;                       // the bar's own buttons, not a close
  if (e.target.classList && e.target.classList.contains('thumb')) {
    openViewer(e.target.src);
  } else if ($('lb').classList.contains('on') && !e.target.closest('.lbimg')) {
    closeViewer();
  } else if (e.target.classList && e.target.classList.contains('card')) {
    const id = (e.target.closest('.card').querySelector('[data-open]') || {}).dataset;
    if (id && id.open) openDetail(id.open);          // click anywhere on the card
  }
});

/* --- THE VIEWER. A rung price is read OFF the picture, so a viewer that only
   fits the image on screen is not enough: the capture is 1816x828 and the
   interesting part is the caption plate in the corner. Zoom about the CURSOR
   (not about the centre), pan by dragging, and never let the wheel scroll the
   page behind the viewer. */
const LB = $('lb'), LBIMG = $('lbimg');
let Z = 1, X = 0, Y = 0;
function applyZoom() {
  LBIMG.style.transform = 'translate(' + X + 'px,' + Y + 'px) scale(' + Z + ')';
  $('lbz').textContent = Math.round(Z * 100) + '%';
}
function zoomAt(px, py, k) {
  k = Math.min(10, Math.max(0.25, k));
  X = px - (px - X) * (k / Z);
  Y = py - (py - Y) * (k / Z);
  Z = k;
  applyZoom();
}
function zoomCentre(k) {
  const r = LB.getBoundingClientRect();
  zoomAt(0, 0, k);
}
function openViewer(src) {
  LBIMG.src = src;
  Z = 1; X = 0; Y = 0; applyZoom();
  LB.classList.add('on');
}
function closeViewer() { LB.classList.remove('on'); }
LB.addEventListener('wheel', (e) => {
  e.preventDefault();
  const r = LB.getBoundingClientRect();
  zoomAt(e.clientX - (r.left + r.width / 2), e.clientY - (r.top + r.height / 2),
    Z * (e.deltaY < 0 ? 1.15 : 1 / 1.15));
}, { passive: false });
LB.addEventListener('dblclick', (e) => {
  if (e.target !== LBIMG) return;
  if (Z > 1.5) { Z = 1; X = 0; Y = 0; applyZoom(); } else zoomCentre(2.5);
});
let drag = null;
LBIMG.addEventListener('pointerdown', (e) => {
  drag = { x: e.clientX, y: e.clientY };
  LBIMG.classList.add('drag');
  LBIMG.setPointerCapture(e.pointerId);
});
LBIMG.addEventListener('pointermove', (e) => {
  if (!drag) return;
  X += e.clientX - drag.x; Y += e.clientY - drag.y;
  drag = { x: e.clientX, y: e.clientY };
  applyZoom();
});
['pointerup', 'pointercancel'].forEach((ev) => LBIMG.addEventListener(ev, () => {
  drag = null; LBIMG.classList.remove('drag');
}));
$('lbIn').addEventListener('click', () => zoomCentre(Z * 1.4));
$('lbOut').addEventListener('click', () => zoomCentre(Z / 1.4));
$('lbReset').addEventListener('click', () => { Z = 1; X = 0; Y = 0; applyZoom(); });
$('lbClose').addEventListener('click', closeViewer);
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { closeViewer(); closeDetail(); }
  else if (e.key === '+' || e.key === '=') zoomCentre(Z * 1.4);
  else if (e.key === '-') zoomCentre(Z / 1.4);
});
render();
</script>
</body>
</html>
`;
}

const PAGE_INLINE = path.join(DS, 'dashboard.inline.html');

function build(inline) {
  const data = load(inline);
  if (!data) {
    console.error('no dataset at ' + path.relative(ROOT, DB));
    console.error('run: node tools/th3-dataset-sync.js');
    return 1;
  }
  data.inline = !!inline;
  fs.writeFileSync(inline ? PAGE_INLINE : PAGE, buildPage(data));
  return data;
}

function writeReviews(rows) {
  const body = [REVIEW_COLS.join(',')].concat(rows.map((r) =>
    REVIEW_COLS.map((c) => String(r[c] == null ? '' : r[c]).replace(/,/g, ' ')).join(','))).join('\n');
  fs.writeFileSync(REVIEWS, body + '\n');
}

function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];

  if (cmd === 'review') {
    const [id, verdict, ...note] = args.slice(1);
    if (!id || !VERDICTS.includes(verdict)) {
      console.error('usage: review <Sample_ID> <' + VERDICTS.join('|') + '> [note]');
      return 1;
    }
    const rows = readCsv(REVIEWS).filter((r) => r.Sample_ID !== id);
    rows.push({
      Sample_ID: id, Verdict: verdict, Note: note.join(' ').replace(/,/g, ' '),
      Reviewer: process.env.USER || process.env.USERNAME || 'trader',
      Reviewed_At: nowStamp(),
    });
    rows.sort((a, b) => String(a.Sample_ID).localeCompare(String(b.Sample_ID)));
    writeReviews(rows);
    const line = `- ${nowStamp()} | review ${id} = ${verdict}${note.length ? ' — ' + note.join(' ') : ''}`;
    const head = fs.existsSync(JOURNAL) && fs.statSync(JOURNAL).size > 0
      ? fs.readFileSync(JOURNAL, 'utf8').replace(/\s*$/, '\n') : '# TH3 dataset journal\n\n';
    fs.writeFileSync(JOURNAL, head + line + '\n');
    console.log(line);
  } else if (cmd === 'journal') {
    const text = args.slice(1).join(' ').trim();
    if (!text) { console.error('usage: journal <text>'); return 1; }
    const head = fs.existsSync(JOURNAL) && fs.statSync(JOURNAL).size > 0
      ? fs.readFileSync(JOURNAL, 'utf8').replace(/\s*$/, '\n') : '# TH3 dataset journal\n\n';
    const line = `- ${nowStamp()} | ${text}`;
    fs.writeFileSync(JOURNAL, head + line + '\n');
    console.log(line);
  } else if (cmd && cmd !== '--open' && cmd !== '--inline') {
    console.error('unknown command: ' + cmd);
    console.error('usage: (none) | --open | --inline | review <id> <real|invented|unclear> [note] | journal <text>');
    return 1;
  }

  const inline = args.includes('--inline');
  const data = build(inline);
  if (!data) return 1;
  const by = (v) => data.samples.filter((s) => s.Verdict === v).length;
  const out = inline ? PAGE_INLINE : PAGE;
  console.log(`th3-dataset-dashboard: ${data.samples.length} sample(s) -> ` +
    `${path.relative(ROOT, out)}  (real ${by('real')}, invented ${by('invented')}, ` +
    `unclear ${by('unclear')}, unreviewed ${by('unreviewed')})`);
  if (inline) {
    console.log(`  images inlined: ${(data.inlineBytes / 1024).toFixed(0)} KB of PNG ` +
      `(${data.samples.length} sample(s)); this file stands alone`);
  }
  if (args.includes('--open')) console.log(path.relative(ROOT, out));
  return 0;
}

process.exit(main());