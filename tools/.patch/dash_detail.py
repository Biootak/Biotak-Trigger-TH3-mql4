import io

p = 'tools/th3-dataset-dashboard.js'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


# --- 1. the payload carries the raw TXT, so the detail view needs no fetch
rep('''  const samples = rows.map((r) => {
    const folder = r.Folder || '';
    const shot = r.Screenshot || '';''',
    '''  const samples = rows.map((r) => {
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
    }''')

rep('''      ShotPath: folder && shot ? `${folder}/${shot}` : '',''',
    '''      Txt: txt,
      ShotPath: folder && shot ? `${folder}/${shot}` : '',''')

# --- 2. CSS for the detail layer
rep('''.hint{color:var(--dim);font-size:12px;padding:0 24px 10px}''',
    '''.hint{color:var(--dim);font-size:12px;padding:0 24px 10px}
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
details{margin-top:10px} summary{cursor:pointer;color:var(--dim);font-size:12px}''')

# --- 3. the modal skeleton
rep('''<div class="lb" id="lb">''',
    '''<div class="mdl" id="mdl">
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
<div class="lb" id="lb">''')

# --- 4. every column gets a Persian name and a group
rep('''/* --- one card per sample: the picture, the formula, the market --- */''',
    '''/* --- P-TH3-DB: every column of Dataset.csv, named. The card shows the dozen
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
  $('mdlNote').innerHTML = (s.Note || s.Reviewed_At)
    ? 'حکم ثبت‌شده: <b>' + VERDICT_LABEL[s.Verdict] + '</b> — ' + esc(s.Reviewed_At) +
      (s.Reviewer ? ' (' + esc(s.Reviewer) + ')' : '') + '<br>' + esc(s.Note || '')
    : 'حکمی ثبت نشده — با دکمه‌های پایین یکی بگذار.';
  const btn = (v, label, note) => '<button data-cmd="' +
    esc(reviewCmd(id, v, note)).replace(/"/g, '&quot;') + '">' + label + '</button>';
  $('mdlFoot').innerHTML = btn('real', 'واقعی ✓') + btn('invented', 'ساختگی ✗') +
    btn('unclear', 'نامشخص ?');
  $('mdlTxt').textContent = s.Txt || '(لاگی در پوشه نیست)';
  $('mdl').classList.add('on');
}
function closeDetail() { $('mdl').classList.remove('on'); }

/* --- one card per sample: the picture, the formula, the market --- */''')

rep('''    review('real', 'واقعی ✓') + review('invented', 'ساختگی ✗') + review('unclear', 'نامشخص ?') +
    '</div></article>';''',
    '''    review('real', 'واقعی ✓') + review('invented', 'ساختگی ✗') + review('unclear', 'نامشخص ?') +
    '<button class="more" data-open="' + s.Sample_ID + '">جزئیات کامل</button>' +
    '</div></article>';''')

rep('''.meta div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}''',
    '''.meta div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card:hover{border-color:var(--accent)}''')

# --- the openers, and the close paths
rep('''document.addEventListener('click', (e) => {
  const cmd = e.target.getAttribute && e.target.getAttribute('data-cmd');
  if (cmd) { copy(cmd, e.target); return; }
  const inBar = e.target.closest && e.target.closest('.lbbar');''',
    '''document.addEventListener('click', (e) => {
  const cmd = e.target.getAttribute && e.target.getAttribute('data-cmd');
  if (cmd) { copy(cmd, e.target); return; }
  if (e.target.id === 'mdlClose' || e.target.id === 'mdl' ||
      (e.target.classList && e.target.classList.contains('thumb'))) {
    // a thumbnail always opens the PICTURE viewer, even inside the modal
  }
  const open = e.target.getAttribute && e.target.getAttribute('data-open');
  if (open) { openDetail(open); return; }
  if (e.target.id === 'mdlClose' || e.target.id === 'mdl') { closeDetail(); return; }
  const inBar = e.target.closest && e.target.closest('.lbbar');''')

rep('''  if (e.target.classList && e.target.classList.contains('thumb')) {
    openViewer(e.target.src);
  } else if ($('lb').classList.contains('on') && !e.target.closest('.lbimg')) {
    closeViewer();
  }
});''',
    '''  if (e.target.classList && e.target.classList.contains('thumb')) {
    openViewer(e.target.src);
  } else if ($('lb').classList.contains('on') && !e.target.closest('.lbimg')) {
    closeViewer();
  } else if (e.target.classList && e.target.classList.contains('card')) {
    const id = (e.target.closest('.card').querySelector('[data-open]') || {}).dataset;
    if (id && id.open) openDetail(id.open);          // click anywhere on the card
  }
});''')

rep('''document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeViewer();''',
    '''document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { closeViewer(); closeDetail(); }''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('detail modal added')