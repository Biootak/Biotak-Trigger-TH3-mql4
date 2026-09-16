#!/usr/bin/env python3
"""Apply the R-TF-UNIT replacements with an occurrence-count assertion.

Every entry states how many times the pattern MUST occur. If the file does not
match, nothing is written for that entry and the run reports it - so a silent
partial application is impossible.

Usage:  python apply-tf-unit.py [--dry-run]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
B = ROOT / 'Biotak'

LADDER_OLD = """   static int ladder[9] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
                           PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1};"""

LADDER_NEW = """   // R-TF-UNIT: the ladder is in MINUTES, which is what `mins` is - and what
   // every caller compares the result against (`rung > Period()`,
   // `tf <= Period()`, `g_HTFPeriod`). On MT4 the PERIOD_* constants held these
   // same numbers, so writing them as constants read as minutes by accident.
   // On MT5 they hold 1/5/15/30/16385/16388/16408/32769/49153, so every rung
   // above M30 was snapped against a nonsense distance: an H1 chart asked for a
   // 960-minute rung and got MN1 instead of H4, and the overlay then hid itself
   // behind the `rung > Period()` gate. Written as minutes the ladder means on
   // MT5 exactly what it has always meant on MT4.
   static int ladder[9] = {1, 5, 15, 30, 60, 240, 1440, 10080, 43200};"""

# (file, old, new, expected_count, label)
EDITS = [
    ('HTFCandles.mqh', LADDER_OLD, LADDER_NEW, 1, 'HTF snap ladder -> minutes'),

    ('HTFCandles.mqh',
     '   if(tf == PERIOD_MN1)\n',
     '   if(tf == 43200)   // R-TF-UNIT: MN1 in minutes; `tf` is a minute count\n',
     1, 'HTFBarCloseTime MN1 test -> minutes'),

    ('HTFCandles.mqh',
     'static int    g_HTFPeriod = PERIOD_H4;',
     'static int    g_HTFPeriod = 240;   // R-TF-UNIT: minutes (H4), not PERIOD_H4',
     1, 'g_HTFPeriod default -> minutes'),

    ('HTFCandles.mqh',
     '   g_HTFPeriod = PERIOD_H4;',
     '   g_HTFPeriod = 240;   // R-TF-UNIT: minutes (H4)',
     1, 'g_HTFPeriod reset -> minutes'),

    ('BaseKnotTool.mqh',
     '(ENUM_TIMEFRAMES)tfMin, s2, false)',
     'CompatTF(tfMin), s2, false)',
     1, 'BaseKnot iBarShift(tfMin, s2)'),

    ('BaseKnotTool.mqh',
     '(ENUM_TIMEFRAMES)tfRead, t2, false)',
     'CompatTF(tfRead), t2, false)',
     1, 'BaseKnot iBarShift(tfRead, t2)'),

    ('BaseKnotTool.mqh',
     '(ENUM_TIMEFRAMES)tfRead, tFrom, false)',
     'CompatTF(tfRead), tFrom, false)',
     1, 'BaseKnot iBarShift(tfRead, tFrom)'),
]


def main(argv):
    dry = '--dry-run' in argv
    ok = fail = 0
    for name, old, new, want, label in EDITS:
        p = B / name
        text = p.read_text(encoding='utf-8')
        got = text.count(old)
        if got != want:
            print(f"SKIP  {name:24s} {label:38s} expected {want}, found {got}")
            fail += 1
            continue
        if not dry:
            p.write_text(text.replace(old, new), encoding='utf-8')
        print(f"{'DRY ' if dry else 'OK   '}{name:24s} {label:38s} {got} replacement(s)")
        ok += 1
    print(f"\napplied {ok}, skipped {fail}")
    return 0 if fail == 0 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
