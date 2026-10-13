"""Read MT4's profiles/gvariables.dat (stride 80: name ASCII in bytes 0..64,
little-endian double at 64..72) and print the BIOMENU_HOME_* / BIOMENU_UI keys."""
import struct, sys

PATH = sys.argv[1] if len(sys.argv) > 1 else \
    r"C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\profiles\gvariables.dat"

b = open(PATH, 'rb').read()
STRIDE = 80
n = len(b) // STRIDE
rows = []
for i in range(n):
    off = i * STRIDE
    raw = b[off:off + 64]
    name = raw.split(b'\x00', 1)[0].decode('ascii', 'replace')
    if not name:
        continue
    val = struct.unpack_from('<d', b, off + 64)[0]
    rows.append((name, val))

want = ('BIOMENU_HOME_', 'BIOMENU_UI_', 'BIOMENU_TIP', 'BIOMENU_MEN', 'BIOMENU_STRIP')
print('file   :', PATH)
print('bytes  :', len(b), ' entries:', len(rows))
print('--- homes / ui ---')
for name, val in rows:
    if name.startswith(want):
        print('  %-34s %r' % (name, val))
