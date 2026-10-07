import io

p = 'tools/th3-dataset-dashboard.js'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


# --- the payload now carries folder-relative names, not a page-relative path
rep('''      ShotPath: folder && shot ? `Samples/${folder}/${shot}` : '',
      LogPath: folder && r.Log_File ? `Samples/${folder}/${r.Log_File}` : '',''',
    '''      // RELATIVE TO THE SAMPLES ROOT, not to the page: the page must work both
      // opened from disk (file://…/Samples/TH3_Dataset/dashboard.html) and
      // served from the repo root, and the two disagree about the prefix. The
      // page tries both (see BASE below) instead of being right about one.
      ShotPath: folder && shot ? `${folder}/${shot}` : '',
      LogPath: folder && r.Log_File ? `${folder}/${r.Log_File}` : '',''')

rep('''const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"]/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
''',
    '''const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"]/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
// P-TH3-DB: the page can be opened from disk OR served from the repo root, and
// the two need different prefixes for the same picture. Rather than guess, the
// img tag carries BOTH candidates and falls back on the first 404 — a broken
// thumbnail would read as "the sample has no picture", which is a lie.
const PREFIXES = location.pathname.indexOf('/TH3_Dataset/') >= 0
  ? ['Samples/', 'TH3_Dataset/Samples/'] : ['TH3_Dataset/Samples/', 'Samples/'];
const imgTag = (rel) => {
  if (!rel) return '';
  const [a, b] = [PREFIXES[0] + rel, PREFIXES[1] + rel];
  return '<img class="thumb" loading="lazy" src="' + a + '" data-alt="' + b +
    '" onerror="this.onerror=null;this.src=this.dataset.alt" alt="sample">';
};
const linkHref = (rel) => (rel ? PREFIXES[0] + rel : '#');
''')

rep('''  const img = s.ShotPath
    ? '<img class="thumb" loading="lazy" src="' + s.ShotPath + '" alt="' + s.Sample_ID + '">'
    : '<div class="thumb" style="height:90px;display:flex;align-items:center;color:var(--dim)">بدون تصویر</div>';''',
    '''  const img = s.ShotPath
    ? imgTag(s.ShotPath)
    : '<div class="thumb" style="height:90px;display:flex;align-items:center;color:var(--dim)">بدون تصویر</div>';''')

rep('''    (s.ShotPath ? '<a href="' + s.ShotPath + '" target="_blank"><button>تصویر کامل</button></a>' : '') +
    (s.LogPath ? '<a href="' + s.LogPath + '" target="_blank"><button>لاگ TXT</button></a>' : '') +''',
    '''    (s.ShotPath ? '<a href="' + linkHref(s.ShotPath) + '" target="_blank"><button>تصویر کامل</button></a>' : '') +
    (s.LogPath ? '<a href="' + linkHref(s.LogPath) + '" target="_blank"><button>لاگ TXT</button></a>' : '') +''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('dashboard paths patched')