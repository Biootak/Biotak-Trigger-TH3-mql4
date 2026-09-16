#!/usr/bin/env python3
"""tf-unit-audit - R-TF-UNIT gate.

INVARIANT
    A timeframe value in the shared source is ALWAYS a minute count.
    `Period()` and `GetCachedPeriod()` yield minutes. `PERIOD_*` constants appear
    only where an ENUM_TIMEFRAMES is genuinely required, and minutes cross to an
    enum exactly once, at the point of use, through `CompatTF()`.

WHY IT NEEDS A GATE
    On MT4 the ENUM_TIMEFRAMES constants ARE the minute counts (PERIOD_H1 == 60),
    so a shared line that treats a timeframe as minutes is correct there and
    silently wrong on MT5 (PERIOD_H1 == 16385, Period() == 16385). 16385 is a
    perfectly good integer, so nothing complains: the HTF snap ladder picks the
    wrong rung, the ATR ladder misses its W1/MN1 override, the lock badge reads
    "16385", and iBarShift/iBars simply return nothing. These are exactly the
    defects that made the MT5 mirror look "half implemented".

WHAT IT CHECKS
    1. A list of BANNED constructs - each one is a crossing that skips
       CompatTF() and therefore yields an invalid enum on MT5.
    2. That the bridge itself is present on both platforms.
    3. INFO: every remaining candidate site, for human classification.

Exit code 0 = pass.

Usage:  python tf-unit-audit.py [entry.mq4|entry.mq5 ...]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# The MT5 half of the bridge lives in the sibling repository (the MT5 workspace
# is a shell that junctions this one's Biotak/ directory).
MT5_ROOT = ROOT.parent / 'Biotak-Trigger-TH3-mql5'
DEFAULT_ENTRY = ROOT / 'Biotak Trigger TH3.mq4'

INCLUDE = re.compile(r'#\s*include\s+"([^"]+)"')

# A line carrying this marker is exempt from the banned-construct scan. It exists
# for exactly one reason: CompatMinutes() has to ask the terminal whether a value
# is a valid ENUM_TIMEFRAMES constant, which is the one place where casting an
# unknown int to an enum is the point rather than a mistake.
ALLOW = 'tf-unit-audit:allow'

# Each banned construct is a way to reach an ENUM_TIMEFRAMES parameter without
# going through CompatTF(). All of them are correct on MT4 and wrong on MT5.
BANNED = [
    (re.compile(r'\(ENUM_TIMEFRAMES\)\s*Period\(\)'),
     'a bare cast of Period() - 60 becomes an invalid enum on MT5; use CompatTF()'),
    (re.compile(r'\(ENUM_TIMEFRAMES\)\s*GetCachedPeriod\(\)'),
     'a bare cast of GetCachedPeriod() - use CompatTF()'),
    (re.compile(r'\(ENUM_TIMEFRAMES\)\s*GetEffectiveTimeframe\(\)'),
     'a bare cast of GetEffectiveTimeframe() - use CompatTF()'),
    (re.compile(r'PeriodSeconds\s*\(\s*\(ENUM_TIMEFRAMES\)'),
     'PeriodSeconds() of a cast minute count returns 0 on MT5; use PeriodSeconds(CompatTF(x))'),
    (re.compile(r'iBarShift\s*\([^;]*\(ENUM_TIMEFRAMES\)'),
     'iBarShift() has no shim macro, so the enum crossing must be explicit: CompatTF()'),
    (re.compile(r'int\s+ladder\s*\[\s*9\s*\]\s*=\s*\{\s*PERIOD_'),
     'a minute ladder written with PERIOD_* constants'),
    (re.compile(r'int\s+g_HTFPeriod\s*=\s*PERIOD_'),
     'a minute-valued default written as a PERIOD_* constant'),
    (re.compile(r'int\s+InpHTFTimeframe\s*=\s*PERIOD_'),
     'a minute-valued default written as a PERIOD_* constant'),
    (re.compile(r'if\s*\(\s*p\s*==\s*PERIOD_'),
     'a minute value compared against PERIOD_* constants'),
]

# The bridge must exist, in the right places.
REQUIRED = [
    ('Biotak/BuildConfig.mqh', r'int\s+CompatPeriodMinutes\s*\(',
     'CompatPeriodMinutes() accessor'),
    ('Biotak/BuildConfig.mqh', r'ENUM_TIMEFRAMES\s+CompatTF\s*\(\s*const\s+int',
     'CompatTF() converter'),
    ('Biotak/BuildConfig.mqh', r'int\s+CompatMinutes\s*\(\s*const\s+int',
     'CompatMinutes() normaliser'),
    ('Biotak/BuildConfig.mqh', r'#ifdef\s+__MQL5__',
     'the platform split'),
    ('MT5Compat/MQL5Compat.mqh', r'#define\s+Period\(\)\s+CompatPeriodMinutes\(\)',
     'the MT5 Period() remap to minutes'),
    ('MT5Compat/MQL5Compat.mqh', r'ENUM_TIMEFRAMES\s+CompatRawPeriod\s*\(',
     'CompatRawPeriod(), the pre-macro handle on the builtin'),
]

# Everything that mentions a timeframe, so the residue can be eyeballed.
CANDIDATE = re.compile(
    r'\b(PERIOD_(?:CURRENT|M1|M2|M3|M4|M5|M6|M10|M12|M15|M20|M30|'
    r'H1|H2|H3|H4|H6|H8|H12|D1|W1|MN1))\b|\bPeriod\s*\(\s*\)')
ENUM_ROLE = [
    re.compile(r'\bi(?:Bars|Time|High|Low|Open|Close|BarShift)\s*\('),
    re.compile(r'\bPeriodSeconds\s*\('),
    re.compile(r'\bCopy(?:Rates|Time|High|Low|Close|Open|Tick|Buffer)\s*\('),
    re.compile(r'\bEnumToString\s*\('),
    re.compile(r'^\s*case\s'),
    re.compile(r'\bENUM_TIMEFRAMES\b'),
    re.compile(r'\bCompatTF\s*\('),
    re.compile(r'\bCompatMinutes\s*\('),
]


def closure(entry: Path, seen=None, out=None):
    if seen is None:
        seen, out = set(), []
    if not entry.exists():
        return out
    for line in entry.read_text(encoding='utf-8', errors='replace').splitlines():
        m = INCLUDE.match(line.strip())
        if not m:
            continue
        inc = (entry.parent / m.group(1).replace('\\', '/')).resolve()
        if inc in seen or not inc.exists():
            continue
        seen.add(inc)
        out.append(inc)
        closure(inc, seen, out)
    return out


def compiled(entries):
    files, seen = [], set()
    for e in entries:
        for f in [e] + closure(e):
            if f not in seen:
                seen.add(f)
                files.append(f)
    return files


def main(argv):
    entries = [Path(a).resolve() for a in argv[1:]] or [DEFAULT_ENTRY]
    files = compiled(entries)

    print(f"tf-unit-audit - R-TF-UNIT  ({len(files)} compiled files)")
    print(f"entry: {', '.join(e.name for e in entries)}\n")

    failures = 0

    print("--- bridge present")
    for rel, pat, label in REQUIRED:
        p = ROOT / rel
        if not p.exists():
            p = MT5_ROOT / rel
        text = p.read_text(encoding='utf-8', errors='replace') if p.exists() else ''
        ok = bool(re.search(pat, text))
        print(f"  {'ok  ' if ok else 'FAIL'} {label:52s} {rel}")
        if not ok:
            failures += 1

    print("\n--- banned constructs")
    for f in files:
        for i, line in enumerate(f.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
            if ALLOW in line:
                continue
            for pat, why in BANNED:
                if pat.search(line):
                    print(f"  FAIL {f.name}({i}): {why}")
                    print(f"       {line.strip()[:130]}")
                    failures += 1

    # INFO only - the residue, for classification.
    residue = []
    for f in files:
        for i, line in enumerate(f.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
            if not CANDIDATE.search(line):
                continue
            s = line.strip()
            if s.startswith('//') or s.startswith('*'):
                continue
            if any(r.search(line) for r in ENUM_ROLE):
                continue
            residue.append((f.name, i, s))

    print(f"\n--- INFO: {len(residue)} candidate site(s) left for review")
    for name, i, s in residue:
        print(f"  {name}({i}): {s[:120]}")

    print(f"\n{'PASS' if failures == 0 else 'FAIL'} - {failures} violation(s)")
    return 0 if failures == 0 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
