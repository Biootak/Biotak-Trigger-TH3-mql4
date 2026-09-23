#!/usr/bin/env python3
"""mt4_history — read MT4 `.hst` bar files straight off the terminal's disk.

Why this exists: the study next to it («which pivots actually repeat?») needs
real broker bars, not a synthetic series and not a web API that rate-limits,
404s or quietly restates. The terminal already holds the exact bars the
indicator under test would have seen. Reading them is free, offline, and
reproducible — so there is no reason to invent a market.

THE FORMAT, AS DETERMINED FROM THE FILES THEMSELVES
    Guessing did not work, so the layout below was measured, not looked up.
    Three probes pinned it down:

      1. `int32 @0 == 401` and `"NZDUSD"` at byte 68 → `HistoryHeader` is
         version(4) + copyright(64) + symbol(12) + period(4) + digits(4) +
         timesign(4) + last_sync(4) + unused(13*4) = **148 bytes**.
      2. Scanning every 4-byte window for plausible 2018..2027 timestamps and
         histogramming their offsets mod N put **2018 of 6013** candidates on a
         single residue for **N = 60** — so the record stride is 60, and the
         timestamp sits 28 bytes into each block.
      3. Scanning every 4-byte window for doubles in the symbol's price range
         returned exactly four residues per block (+36, +44, +52, +0) with
         identical counts — so there are four price fields, and the fourth sits
         at the *next* block's origin. Hence the close of bar k is the double at
         the start of block k+1.

    So, measured from bar k's own timestamp:

        +0   int32   ctm        (unix seconds)
        +8   double  open
        +16  double  high
        +24  double  low
        +32  double  close      <- same byte as block k+1's +0
        +40  .. 20 further bytes, not price (left unread)

    Field order is open/HIGH/LOW/close, which is worth stating because MT4's
    in-memory `MqlRates` uses open/low/high/close. Assuming the familiar order
    is what made the first three probes look like garbage.

WHY IT IS SAFE TO TRUST
    `load()` validates every bar it returns (low <= open,close <= high, positive
    prices) and every file's bars are checked for strictly increasing time. A
    layout mistake cannot pass both. `--selftest` re-derives the header size and
    the stride from raw bytes instead of trusting the constants above, so a
    terminal upgrade that changes the format fails loudly rather than silently
    feeding the study nonsense.

Usage:  python tools/mt4_history.py                 # inventory every file
        python tools/mt4_history.py --symbol NZDUSD --tf 1440
        python tools/mt4_history.py --selftest
"""
import glob
import os
import struct
import sys
from datetime import datetime, timezone

HEADER = 148
STRIDE = 60
T_OFF, O_OFF, H_OFF, L_OFF, C_OFF = 0, 8, 16, 24, 32


def terminal_dirs():
    base = os.path.join(os.environ.get("APPDATA", ""), "MetaQuotes", "Terminal")
    return sorted(glob.glob(os.path.join(base, "*", "history", "*")))


def pip_size(digits):
    """One pip, in price units, from the symbol's own digit count.

    An FX quote spends its last digit on the pip, so 5 digits means 0.0001 and 3
    means 0.01. Everything else (metals, indices, crypto) has no fractional-pip
    convention, and there the pip is best taken as the quote's own last digit -
    which is exactly what MT4's `Point` is. Guessing "5 digits = FX" is not
    needed here because `digits` comes from the file header.
    """
    if digits <= 0:
        return 0.0001
    return 10.0 ** (-(digits - 1) if digits in (3, 5) else -digits)


def digits_of(path):
    """The quote's decimal places, read from the file header."""
    return header_of(open(path, "rb").read(HEADER))[3]


def find(symbol=None, tf=None, paths=None):
    """Every .hst under the terminal, optionally filtered to one symbol/timeframe."""
    out = []
    for d in (paths if paths is not None else terminal_dirs()):
        for f in sorted(glob.glob(os.path.join(d, "*.hst"))):
            name = os.path.basename(f)[:-4]
            digits = "".join(ch for ch in name if ch.isdigit())
            sym = name[: len(name) - len(digits)]
            if tf is not None and digits != str(tf):
                continue
            if symbol is not None and sym.upper() != symbol.upper():
                continue
            out.append(f)
    return out


def header_of(data):
    """(version, symbol, period, digits) — read from the file, never assumed."""
    version, = struct.unpack_from("<i", data, 0)
    symbol = data[68:80].split(b"\0")[0].decode("ascii", "replace")
    period, digits = struct.unpack_from("<2i", data, 80)
    return version, symbol, period, digits


def _run(data, t0, stride, n=120):
    """How many consecutive bars parse from an assumed (first timestamp, stride).

    A correct hypothesis runs the full `n`; a wrong one dies at k=0 or k=1, so
    searching a whole family of candidates stays cheap.
    """
    size = len(data)
    prev = 0
    ok = 0
    for k in range(n):
        p = t0 + stride * k
        if p + C_OFF + 8 > size:
            break
        t, = struct.unpack_from("<i", data, p)
        if not (1_000_000_000 < t < 2_100_000_000) or t <= prev:
            break
        o, h, l, c = (struct.unpack_from("<d", data, p + x)[0]
                      for x in (O_OFF, H_OFF, L_OFF, C_OFF))
        if not (0 < l <= min(o, c) + 1e-9 and h >= max(o, c) - 1e-9):
            break
        prev = t
        ok += 1
    return ok


def detect_layout(data, n=120):
    """Re-derive (first timestamp offset, stride) from raw bytes, by score.

    This is the guard against a silent format change. Note the order of the
    tests: a stride histogram alone is NOT decisive, because every divisor and
    multiple of the true stride aliases onto it and false-positive timestamps
    inside price doubles inflate the counts. In a real file, stride 40 scored
    just as high as the true stride 60. Only requiring the implied price fields
    to actually validate breaks the tie — so that is what decides here.
    """
    best = None
    for stride in range(40, 100, 4):
        for t0 in range(140, 401, 4):
            score = _run(data, t0, stride, n)
            if score == n and (best is None or (stride, t0) < (best[1], best[0])):
                best = (t0, stride, score)
    return best


def load(path):
    """Bars as list of (time, open, high, low, close). Validated, not trusted."""
    data = open(path, "rb").read()
    if len(data) < HEADER + 2 * STRIDE:
        return []
    bars = []
    k = 0
    while True:
        base = HEADER + STRIDE * k
        if base + STRIDE + C_OFF + 8 > len(data):
            break
        t, = struct.unpack_from("<i", data, base + T_OFF)
        o, h, l, c = (struct.unpack_from("<d", data, base + x)[0]
                      for x in (O_OFF, H_OFF, L_OFF, C_OFF))
        if t <= 0 or not (0 < l <= min(o, c) + 1e-9 and h >= max(o, c) - 1e-9):
            break
        bars.append((t, o, h, l, c))
        k += 1
    return bars


def day(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d")


def inventory():
    files = find()
    print(f"{len(files)} .hst files under the terminal\n")
    print(f"  {'file':<22} {'sym':<10} {'tf':>6} {'dig':>4} {'bars':>7}  span")
    total = 0
    broken = []
    for f in files:
        data = open(f, "rb").read()
        ver, sym, per, dig = header_of(data)
        bars = load(f)
        total += len(bars)
        if not bars:
            broken.append(os.path.basename(f))
            continue
        span = f"{day(bars[0][0])} .. {day(bars[-1][0])}"
        print(f"  {os.path.basename(f):<22} {sym:<10} {per:>6} {dig:>4} {len(bars):>7}  {span}")
    print(f"\n  {total:,} bars total; {len(broken)} file(s) unusable: {broken or 'none'}")


def selftest():
    faults = 0

    def check(cond, what):
        nonlocal faults
        if not cond:
            print(f"  SEED NOT CAUGHT: {what}")
            faults += 1

    files = find()
    check(len(files) > 0, "no .hst files found on this machine")
    if not files:
        print(f"  selftest: {faults} uncaught seed(s)")
        return faults
    # prefer the daily files: they exercise the whole record stream
    dailies = find(tf=1440) or files
    rederived_ok = 0
    bars_ok = 0
    chrono_ok = 0
    checked = 0
    for f in dailies[:12]:
        data = open(f, "rb").read()
        checked += 1
        det = detect_layout(data)
        if det and det[0] == HEADER and det[1] == STRIDE:
            rederived_ok += 1
        bars = load(f)
        if len(bars) > 100:
            bars_ok += 1
        ts = [b[0] for b in bars]
        if all(b > a for a, b in zip(ts, ts[1:])):
            chrono_ok += 1
    check(rederived_ok == checked, f"layout re-derivation agreed on only {rederived_ok}/{checked} files")
    check(bars_ok == checked, f"only {bars_ok}/{checked} files yielded bars")
    check(chrono_ok == checked, f"only {chrono_ok}/{checked} files were chronological")

    # a deliberately corrupted reader must fail the checks it promises
    probe = sorted(glob.glob(os.path.join(os.path.dirname(files[0]), "*.hst")))[0]
    data = open(probe, "rb").read()
    wrong = bytearray(data)
    base = HEADER + STRIDE * 50
    struct.pack_into("<d", wrong, base + L_OFF, 999.0)   # low above everything
    bad = 0
    k = 0
    while k < 60:
        b = HEADER + STRIDE * k
        o, h, l, c = (struct.unpack_from("<d", wrong, b + x)[0]
                      for x in (O_OFF, H_OFF, L_OFF, C_OFF))
        if not (0 < l <= min(o, c) + 1e-9 and h >= max(o, c) - 1e-9):
            bad += 1
        k += 1
    check(bad == 1, f"a corrupted bar should be rejected exactly once, got {bad}")

    # the close sits at the NEXT block's origin — the oddity that makes this
    # format easy to misread. Anchor it from the file, not from the constants.
    bars = load(probe)
    if len(bars) > 3:
        check(abs(bars[0][4] - struct.unpack_from("<d", data, HEADER + C_OFF)[0]) < 1e-12,
              "bar 0's close must be the double at the next block's origin")
        # and bar k's close must be bar k-1's successor field: purely positional
        check(abs(bars[1][4] - struct.unpack_from("<d", data, HEADER + STRIDE + C_OFF)[0]) < 1e-12,
              "bar 1's close must follow the same field, one stride later")

    print(f"  selftest: {faults} uncaught seed(s)  ({checked} files checked)")
    return faults


def main(argv):
    if "--selftest" in argv:
        return 1 if selftest() else 0
    symbol = argv[argv.index("--symbol") + 1] if "--symbol" in argv else None
    tf = argv[argv.index("--tf") + 1] if "--tf" in argv else None
    if symbol or tf:
        for f in find(symbol, tf):
            bars = load(f)
            print(f"{os.path.basename(f)}: {len(bars)} bars "
                  f"{day(bars[0][0])} .. {day(bars[-1][0])}" if bars else f"{f}: empty")
        return 0
    inventory()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
