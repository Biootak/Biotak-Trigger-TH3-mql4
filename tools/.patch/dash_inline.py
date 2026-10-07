import io

p = 'tools/th3-dataset-dashboard.js'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


rep('''//   node tools/th3-dataset-dashboard.js --open                 # build + print path''',
    '''//   node tools/th3-dataset-dashboard.js --inline               # ONE file, images inside
//   node tools/th3-dataset-dashboard.js --open                 # build + print path''')

rep('''// The page is ONE self-contained HTML file with the images referenced by
// relative path, so it opens from disk with no server, no build and no install
// — a double-click is the whole deployment.''',
    '''// The page is ONE HTML file with the images referenced by RELATIVE path, so it
// opens from disk with no server, no build and no install — a double-click is
// the whole deployment. `--inline` writes a second copy with the pictures as
// data URIs instead: bigger, but a SINGLE file that survives being attached to
// a message or moved to another machine, and the only form a browser sandbox
// (which serves one file and nothing beside it) can display at all.''')

# --- load(): inline mode
rep('''function load() {
  if (!fs.existsSync(DB)) return null;''',
    '''function load(inline) {
  if (!fs.existsSync(DB)) return null;''')

rep('''  return {
    generated: nowStamp(),
    samples,
    journal:''',
    '''  if (inline) {
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
    journal:''')

# --- the page: data URIs must pass through the prefix logic untouched
rep('''const imgTag = (rel) => {
  if (!rel) return '';
  const [a, b] = [PREFIXES[0] + rel, PREFIXES[1] + rel];
  return '<img class="thumb" loading="lazy" src="' + a + '" data-alt="' + b +
    '" onerror="this.onerror=null;this.src=this.dataset.alt" alt="sample">';
};
const linkHref = (rel) => (rel ? PREFIXES[0] + rel : '#');''',
    '''const INLINE = DATA.inline === true;
const imgTag = (rel) => {
  if (!rel) return '';
  if (rel.startsWith('data:')) return '<img class="thumb" src="' + rel + '" alt="sample">';
  const [a, b] = [PREFIXES[0] + rel, PREFIXES[1] + rel];
  return '<img class="thumb" loading="lazy" src="' + a + '" data-alt="' + b +
    '" onerror="this.onerror=null;this.src=this.dataset.alt" alt="sample">';
};
const linkHref = (rel) => (rel ? (rel.startsWith('data:') ? rel : PREFIXES[0] + rel) : '#');''')

# --- the lightbox must not prefix a data URI either (it copies e.target.src)
rep('''    (s.ShotPath ? '<a href="' + linkHref(s.ShotPath) + '" target="_blank"><button>تصویر کامل</button></a>' : '') +''',
    '''    (s.ShotPath && !s.ShotPath.startsWith('data:')
      ? '<a href="' + linkHref(s.ShotPath) + '" target="_blank"><button>تصویر کامل</button></a>' : '') +''')

rep('''  <section class="panel">
    <h2>ژورنال</h2>
    <pre id="journal">${esc(data.journal.join('\\n'))}</pre>
  </section>''',
    '''  <section class="panel">
    <h2>ژورنال</h2>
    <pre id="journal">${esc((data.journal || []).join('\\n'))}</pre>
  </section>''')

# --- build(): the two outputs
rep('''function build() {
  const data = load();
  if (!data) {
    console.error('no dataset at ' + path.relative(ROOT, DB));
    console.error('run: node tools/th3-dataset-sync.js');
    return 1;
  }
  fs.writeFileSync(PAGE, buildPage(data));
  return data;
}''',
    '''const PAGE_INLINE = path.join(DS, 'dashboard.inline.html');

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
}''')

rep('''  const data = build();
  if (!data) return 1;
  const by = (v) => data.samples.filter((s) => s.Verdict === v).length;
  console.log(`th3-dataset-dashboard: ${data.samples.length} sample(s) -> ` +
    `${path.relative(ROOT, PAGE)}  (real ${by('real')}, invented ${by('invented')}, ` +
    `unclear ${by('unclear')}, unreviewed ${by('unreviewed')})`);
  if (args.includes('--open')) console.log(path.relative(ROOT, PAGE));
  return 0;''',
    '''  const inline = args.includes('--inline');
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
  return 0;''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('inline mode added')