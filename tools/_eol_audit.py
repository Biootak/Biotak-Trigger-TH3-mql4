import os, sys
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Biotak')
EXP = {
    'BiotakHomes.mqh': 'CRLF',
    'BiotakMenu_A.mqh': 'CRLF',
    'BiotakMenu_B.mqh': 'LF',
    'BiotakMenu_C.mqh': 'LF',
    'BiotakMenu_Ring.mqh': 'LF',
    'BiotakPanels_Build.mqh': 'CRLF',
    'DrawStrip_Paint.mqh': 'CRLF',
    'DrawStrip_Router.mqh': 'CRLF',
    'Sessions_Time.mqh': 'LF',
    'Sessions_Model.mqh': 'LF',
    'Sessions_Draw.mqh': 'LF',
    'BiotakPanels_PalSpec.mqh': 'LF',
    'BiotakPanels_DynDef.mqh': 'LF',
}
bad = 0
for f, e in EXP.items():
    p = os.path.join(BASE, f)
    b = open(p, 'rb').read()
    crlf = b.count(b'\r\n')
    lf = b.count(b'\n') - crlf
    cr = b.count(b'\r') - crlf
    if crlf and not lf and not cr:
        got = 'CRLF'
    elif lf and not crlf and not cr:
        got = 'LF'
    else:
        got = 'MIXED'
    flag = ''
    if got != e:
        flag = '   <<< CHANGED'
        bad += 1
    print('%-26s want=%-4s got=%-5s CRLF=%-5d loneLF=%-5d loneCR=%-5d%s' % (f, e, got, crlf, lf, cr, flag))
print('BAD =', bad)
sys.exit(1 if bad else 0)
