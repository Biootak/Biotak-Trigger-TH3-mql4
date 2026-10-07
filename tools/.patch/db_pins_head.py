import io

p = 'tests/Biotak_TH3_Test.mq4'
raw = io.open(p, encoding='utf-8', newline='').read()
norm = raw.replace('\r\n', '\n')
lines = norm.split('\n')

i = next(k for k, l in enumerate(lines) if 'THE DATASET TREE' in l)
# drop the three stale header lines and the unused local, replace with one header
end = i
while 'TH3RecorderEnsureDirs(dirsOk);' not in lines[end]:
    end += 1

new = [
    '    // P-TH3-DB ' + chr(8212) + ' THE DATASET TREE AND THE DATABASE. The recorder\'s',
    '    // paths are behaviour: a reader who opens TH3_Dataset\\Samples must find',
    '    // the sample the folder name promises. The folder name, the path joiner and',
    '    // the column list are all pure, so all of it is pinned here without a chart.',
    '    {',
]
lines[i:end + 1] = new

# the trailing blank line the old block left behind
j = next(k for k, l in enumerate(lines) if '"Sample_001.png");' in l)
if lines[j + 1].strip() == '' and lines[j + 2].strip() == '}':
    del lines[j + 1]

io.open(p, 'w', encoding='utf-8', newline='').write('\n'.join(lines).replace('\n', '\r\n'))
print('harness header cleaned')