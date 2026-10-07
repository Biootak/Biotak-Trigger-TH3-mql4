import io

p = 'tools/th3-dataset-sync.js'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


# --- a helper for retiring the flat copies
rep('''/**
 * The FIRST layout: Logs/Sample_NNN.txt''',
    '''/** Retire the flat copies once the folder holds them: two layouts for one
 *  dataset is one dataset nobody can count (and here it was stored TWICE —
 *  0.71 MB of flat PNGs left beside the 0.71 MB of folders). */
function dropFlat(txtPath, shotPath, dirs) {
  if (fs.existsSync(txtPath)) fs.unlinkSync(txtPath);
  if (shotPath && fs.existsSync(shotPath)) fs.unlinkSync(shotPath);
  for (const dir of dirs) {
    if (fs.existsSync(dir) && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
  }
}

/**
 * The FIRST layout: Logs/Sample_NNN.txt''')

rep('''    if (fs.existsSync(path.join(targetDir, name)) && fs.existsSync(path.join(targetDir, 'sample.csv'))) {
      state.skipped++;
      continue;
    }''',
    '''    if (fs.existsSync(path.join(targetDir, name)) && fs.existsSync(path.join(targetDir, 'sample.csv'))) {
      // already migrated by an earlier run (or by the terminal pass a moment
      // ago): count it, and inside the repo still retire the flat original.
      if (move) {
        dropFlat(txtPath, shotName ? path.join(shotDir, shotName) : '', [logDir, shotDir]);
        state.migrated++;
      } else {
        state.skipped++;
      }
      continue;
    }''')

rep('''      if (move) {
        fs.unlinkSync(txtPath);
        if (shotName) fs.unlinkSync(path.join(shotDir, shotName));
        for (const dir of [logDir, shotDir]) {
          if (fs.existsSync(dir) && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
        }
      }''',
    '''      if (move) dropFlat(txtPath, shotName ? path.join(shotDir, shotName) : '', [logDir, shotDir]);''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('sync patched')