import io

p = 'tools/th3-dataset-dashboard.js'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


# --- CSS: a real viewer, not a fullscreen <img>
rep('''.lb{position:fixed;inset:0;background:#000d;display:none;align-items:center;justify-content:center;z-index:9}
.lb img{max-width:94vw;max-height:94vh;border:1px solid var(--line)}
.lb.on{display:flex}''',
    '''.lb{position:fixed;inset:0;background:#000e;display:none;align-items:center;justify-content:center;z-index:9}
.lb.on{display:flex}
.lb img{max-width:94vw;max-height:88vh;border:1px solid var(--line);cursor:grab;
       transform-origin:center center;user-select:none;-webkit-user-drag:none}
.lb img.drag{cursor:grabbing}
.lbbar{position:absolute;top:12px;left:50%;transform:translateX(-50%);display:flex;gap:6px;
       align-items:center;background:#161b22ee;border:1px solid var(--line);border-radius:8px;padding:6px 10px}
.lbbar .z{color:var(--dim);min-width:52px;text-align:center;font-size:12px}
.lbhint{position:absolute;bottom:12px;left:50%;transform:translateX(-50%);color:var(--dim);font-size:12px;
        background:#161b22dd;border:1px solid var(--line);border-radius:8px;padding:4px 10px}''')

rep('''<div class="lb" id="lb"><img id="lbimg" alt=""></div>''',
    '''<div class="lb" id="lb">
  <img id="lbimg" alt="" draggable="false">
  <div class="lbbar">
    <button id="lbOut" title="کوچک‌تر">−</button>
    <span class="z" id="lbz">100%</span>
    <button id="lbIn" title="بزرگ‌تر">+</button>
    <button id="lbReset">بازنشانی</button>
    <button id="lbClose">بستن ✕</button>
  </div>
  <div class="lbhint">چرخ ماوس = زوم · کشیدن = جابه‌جا · دابل‌کلیک = ۲۵۰٪ · Esc = بستن</div>
</div>''')

rep('''document.addEventListener('click', (e) => {
  const cmd = e.target.getAttribute && e.target.getAttribute('data-cmd');
  if (cmd) { copy(cmd, e.target); return; }
  if (e.target.classList && e.target.classList.contains('thumb')) {
    $('lbimg').src = e.target.src; $('lb').classList.add('on');
  } else if ($('lb').classList.contains('on')) {
    $('lb').classList.remove('on');
  }
});''',
    '''document.addEventListener('click', (e) => {
  const cmd = e.target.getAttribute && e.target.getAttribute('data-cmd');
  if (cmd) { copy(cmd, e.target); return; }
  const inBar = e.target.closest && e.target.closest('.lbbar');
  if (inBar) return;                       // the bar's own buttons, not a close
  if (e.target.classList && e.target.classList.contains('thumb')) {
    openViewer(e.target.src);
  } else if ($('lb').classList.contains('on') && !e.target.closest('.lbimg')) {
    closeViewer();
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
  if (e.key === 'Escape') closeViewer();
  else if (e.key === '+' || e.key === '=') zoomCentre(Z * 1.4);
  else if (e.key === '-') zoomCentre(Z / 1.4);
});''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('viewer zoom added')