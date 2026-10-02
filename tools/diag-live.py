#!/usr/bin/env python3
"""diag-live.py — read the *freshest* DrawStrip diag output, and drop the rest.

Why this exists (P-DRAW-126, 2026-10-01):
    MT4 buffers its own Experts journal in RAM and flushes on its own schedule.
    Measured 2026-10-01 20:15: the live terminal showed a full `20:03:44` frame
    in the Experts window while `MQL4\\Logs\\20261001.log` still ended at
    `20:01:38.319` and had not grown for fourteen minutes.  A reader that only
    opens that file is therefore ALWAYS minutes behind the tab it should witness.

    So the EA now mirrors every `[dsdiag] EXPECT` / `[drawstrip] TABCENSUS` line
    into `<data folder>\\MQL4\\Files\\biotak_diag_<SYMBOL>.txt` and calls
    `FileFlush` after each line (see `DrawStripDiagEmit` in DrawStrip_Base.mqh).
    That file is current the moment the line is produced.

P-LOG-2 (2026-10-01) — NEWEST WINS, AND THE OLD ONES ARE DELETED.
    A flushed diag file belongs to the attach that wrote it: it is truncated only
    when a NEW attach emits its FIRST line.  So between a restart and the first
    panel open the PREVIOUS session's frame is still on disk and, by mtime, can
    still be the newest diag file — indistinguishable from a live frame.  This
    reader therefore (a) ranks EVERY source by mtime and reads the top one, (b)
    refuses to present a diag frame older than the terminal's own journal without
    saying so, and (c) with `--prune` deletes every diag frame except the one it
    reads (or all of them when the newest source is a journal, i.e. no frame is
    current).  The build does the same at every restart — `Clear-StaleDiagFiles`
    in `compile-th3.ps1`, run while terminal.exe is STOPPED so no handle can hold
    the file open.

Usage:
    python tools/diag-live.py                 # newest source, last 220 lines
    python tools/diag-live.py -n 400
    python tools/diag-live.py --all           # list every candidate source
    python tools/diag-live.py --prune         # delete every stale diag frame, then read
"""

import argparse
import glob
import os
import sys
import time

TERMINAL_ROOT = os.path.expandvars(r"%APPDATA%\MetaQuotes\Terminal")
DEFAULT_STALE_AFTER = 900   # a diag frame older than this is called out as STALE


def _stamp(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    return st.st_mtime, st.st_size


def diag_files():
    """Every flushed diag frame, newest first: (mtime, size, path)."""
    out = []
    for f in glob.glob(os.path.join(TERMINAL_ROOT, "*", "MQL4", "Files", "biotak_diag_*.txt")):
        s = _stamp(f)
        if s:
            out.append((s[0], s[1], f))
    out.sort(key=lambda r: r[0], reverse=True)
    return out


def candidates():
    """Every diag source worth reading, newest first.

    Flushed diag files outrank Experts logs: they are the only source whose
    arrival the terminal cannot delay.  The RANK is still mtime — a log written
    after the last frame proves that frame is not current, and saying so is the
    point (P-LOG-2).
    """
    out = []
    for mt, size, f in diag_files():
        out.append((mt, size, "flush", f))
    for f in glob.glob(os.path.join(TERMINAL_ROOT, "*", "MQL4", "Logs", "*.log")):
        s = _stamp(f)
        if s:
            out.append((s[0], s[1], "experts", f))
    out.sort(key=lambda r: r[0], reverse=True)
    return out


def prune_stale(keep_path):
    """Delete every diag frame except `keep_path` (None = delete all).

    Files the terminal still holds open cannot be removed on Windows; those are
    reported as locked instead of silently ignored.
    """
    removed, locked = [], []
    keep = os.path.normcase(os.path.abspath(keep_path)) if keep_path else None
    for _, _, f in diag_files():
        if keep and os.path.normcase(os.path.abspath(f)) == keep:
            continue
        try:
            os.remove(f)
            removed.append(f)
        except OSError:
            locked.append(f)
    return removed, locked


def read_text(path):
    """The terminal writes ANSI/CP1252 (Persian text breaks under utf-8)."""
    with open(path, "rb") as fh:
        return fh.read().decode("cp1252", "replace").replace("\r", "")


EXPECT_MARK = "[dsdiag] EXPECT"
CENSUS_MARK = "[drawstrip] TABCENSUS"


def split_frames(body):
    """One frame per panel open: a run of EXPECT lines, then its own census run.

    P-LOG-3 (2026-10-01): the writer appends a whole frame per open and never
    truncates, so a file with two opens carries two declarations and two censuses.
    A reader that shows them as one stream shows a state that never existed.
    """
    frames, cur, prev = [], [], None
    for ln in body:
        if EXPECT_MARK in ln:
            k = "E"
        elif CENSUS_MARK in ln:
            k = "C"
        else:
            continue
        if k == "E" and prev == "C":
            frames.append(cur)
            cur = []
        cur.append(ln)
        prev = k
    if cur:
        frames.append(cur)
    return frames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--lines", type=int, default=220)
    ap.add_argument("--all", action="store_true", help="list every candidate and exit")
    ap.add_argument("--prune", action="store_true",
                    help="delete every stale diag frame (keep only the one read)")
    ap.add_argument("--stale-after", type=int, default=DEFAULT_STALE_AFTER,
                    help="seconds after which a diag frame is called STALE (default %d)"
                         % DEFAULT_STALE_AFTER)
    ap.add_argument("--diff", action="store_true",
                    help="also run tools/diag-diff.py on the SAME frame and print its verdict")
    ap.add_argument("--frame", type=int, default=0,
                    help="which panel frame to show: 0 = the last one (default), "
                         "1..N by number, negative counts back from the end")
    args = ap.parse_args()

    cands = candidates()
    if not cands:
        print("no diag source under", TERMINAL_ROOT, file=sys.stderr)
        return 2

    if args.all:
        for mt, size, kind, path in cands:
            print("%s  %-7s %8d  %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mt)),
                                        kind, size, path))
        return 0

    mt, size, kind, path = cands[0]

    # P-LOG-2: the frame worth reading is the newest source ONLY if it is a diag
    # frame; if a journal is newer, no frame is current and every diag file on disk
    # is a previous session's.
    keep = path if kind == "flush" else None
    older = [r for r in cands if r[2] == "flush" and r[3] != path]

    if args.prune:
        removed, locked = prune_stale(keep)
        for f in removed:
            print("pruned : removed stale diag frame %s" % f)
        for f in locked:
            print("locked : could not remove %s (still held open by a terminal)" % f)
        if not removed and not locked:
            print("pruned : nothing to remove")

    lines = read_text(path).split("\n")
    body = [ln for ln in lines if ln]
    frames = split_frames(body)

    age = time.time() - mt
    print("source : %s (%s)" % (path, kind))
    print("  mtime  : %s   age: %.0fs   lines: %d"
          % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mt)),
             age, len(body)))
    shown = body
    if frames:
        want = args.frame
        idx = (len(frames) - 1) if want == 0 else (want - 1 if want > 0 else len(frames) + want)
        idx = max(0, min(idx, len(frames) - 1))
        shown = frames[idx]
        print("  frame  : %d of %d (%d lines) - the file carries one frame per panel open"
              % (idx + 1, len(frames), len(shown)))
    if kind == "experts":
        print("WARN   : falling back to the Experts journal - it may lag the tab by minutes.")
        if older:
            print("STALE  : %d diag frame(s) on disk predate this journal - no panel has "
                  "opened since the last restart (run --prune to drop them)." % len(older))
    elif age > args.stale_after:
        print("STALE  : this diag frame is %.0fs old (> %ds) - open the panel for a fresh one."
              % (age, args.stale_after))
    if older:
        print("note   : %d older diag frame(s) present - run --prune to delete them."
              % len(older))
    # --- P-LOG-6: ONE command answers both halves. The diff runs on the SAME frame
    # --- index this reader chose, because both split frames by the same rule.
    if args.diff:
        import subprocess
        sub = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "diag-diff.py")]
        if frames:
            sub += ["--frame", str(idx + 1)]
        sub.append(path)
        print("-" * 78)
        subprocess.call(sub)
        print("-" * 78)
    print("-" * 78)
    # `shown[-0:]` is the WHOLE list, not an empty tail — say what was asked for.
    for ln in (shown[-args.lines:] if args.lines > 0 else []):
        print(ln)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
