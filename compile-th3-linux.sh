#!/usr/bin/env bash
# ============================================================================
# compile-th3-linux.sh — Linux compile path for Biotak Trigger TH3 (MQL4)
#
# Compiles the project with the AMarkets MT4 metaeditor.exe running inside
# the Bottles "Tradeing" bottle. This is the Linux counterpart of
# compile-th3.ps1 (Windows) — that script is NEVER touched by this one.
#
# Usage:
#   ./compile-th3-linux.sh [full|lite|all]     (default: all)
#
# Optional environment overrides:
#   BOTTLE_NAME    Bottles bottle name            (default: Tradeing)
#   BOTTLE_PATH    Full path to the bottle dir    (auto-detected)
#   MT4_METAEDITOR Full unix path to metaeditor.exe (auto-detected)
#   MT4_MQL4_DIR   Full unix path to terminal MQL4 (auto-detected)
#
# How it works (see AGENTS.md P-BUILD-02 for the traps behind this design):
#   1. Mirrors the repo sources into an in-bottle build dir (C:\th3build).
#      MetaEditor CANNOT compile from Z:\ (host) paths under Bottles — it
#      exits 0 silently and writes neither .ex4 nor log. Everything the
#      compiler touches must live on C:\ (inside the bottle).
#   2. Syncs Files/Icons/*.bmp into the terminal's MQL4\Files\Icons, because
#      MetaEditor resolves #resource against the TERMINAL data folder
#      (same rule as compile-th3.ps1).
#   3. Generates a CRLF .bat on C:\ with the /compile /log /include calls
#      (quoting lives inside the .bat — bottles-cli arg forwarding is
#      unreliable, see P-BUILD-02) and runs it via:
#        flatpak run --command=bottles-cli ... run -b <bottle> -e <bat>
#   4. Copies the .ex4 + build log back into the repo and prints the
#      "Result: N errors" summary. Success = "Result: 0 errors".
# ============================================================================
set -u

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-all}"
BOTTLE_NAME="${BOTTLE_NAME:-Tradeing}"

case "$TARGET" in
  full|lite|all) ;;
  *) echo "Usage: $0 [full|lite|all]" >&2; exit 2 ;;
esac

# --- locate the bottle -------------------------------------------------------
if [ -z "${BOTTLE_PATH:-}" ]; then
  for base in \
    "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles" \
    "$HOME/.local/share/bottles/bottles"; do
    if [ -d "$base/$BOTTLE_NAME" ]; then BOTTLE_PATH="$base/$BOTTLE_NAME"; break; fi
  done
fi
if [ -z "${BOTTLE_PATH:-}" ] || [ ! -d "$BOTTLE_PATH/drive_c" ]; then
  echo "ERROR: bottle '$BOTTLE_NAME' not found. Set BOTTLE_PATH explicitly." >&2
  exit 1
fi

# --- locate metaeditor.exe ---------------------------------------------------
if [ -z "${MT4_METAEDITOR:-}" ]; then
  while IFS= read -r candidate; do
    if [ -f "$candidate" ]; then MT4_METAEDITOR="$candidate"; break; fi
  done < <(find "$BOTTLE_PATH/drive_c/Program Files (x86)" \
    -maxdepth 2 -iname "metaeditor.exe" 2>/dev/null | sort)
fi
if [ -z "${MT4_METAEDITOR:-}" ] || [ ! -f "$MT4_METAEDITOR" ]; then
  echo "ERROR: metaeditor.exe not found in bottle. Set MT4_METAEDITOR." >&2
  exit 1
fi
# Windows path of metaeditor (for inside the .bat)
MED_WIN="$(python3 -c "
import sys
p = sys.argv[1]
rest = p.split('/drive_c/', 1)[1]
print('C:\\\\' + rest.replace('/', '\\\\'))" "$MT4_METAEDITOR")"

# --- locate terminal MQL4 dir (for icon sync + BiotakProject link) ------------
if [ -z "${MT4_MQL4_DIR:-}" ]; then
  MT4_MQL4_DIR="$(python3 - "$BOTTLE_PATH" <<'EOF'
import glob, os, sys
cands = [m for m in glob.glob(os.path.join(
    sys.argv[1], "drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/*/MQL4"))
    if os.path.isdir(os.path.join(m, "Indicators"))]
hosted = [m for m in cands if os.path.lexists(os.path.join(m, "Indicators", "BiotakProject"))]
pool = hosted or cands
print(max(pool, key=os.path.getmtime) if pool else "")
EOF
)"
fi
if [ -z "${MT4_MQL4_DIR:-}" ] || [ ! -d "$MT4_MQL4_DIR/Indicators" ]; then
  echo "ERROR: terminal MQL4 dir not found (run terminal.exe once first)." >&2
  echo "HINT: set MT4_MQL4_DIR explicitly." >&2
  exit 1
fi

echo "Bottle:      $BOTTLE_PATH"
echo "MetaEditor:  $MT4_METAEDITOR"
echo "MQL4 dir:    $MT4_MQL4_DIR"
echo ""

# --- 1. mirror project into the terminal (REAL dir, not a symlink) ----------------
# Wine/Flatpak cannot read host paths through a symlink (nor via Z:\) — it
# fails silently. So Indicators\BiotakProject is a real directory, auto-synced
# from the repo on every run (rsync --delete). This is also what makes manual
# F7 compiles from MetaEditor work: open Indicators\BiotakProject\<file>.mq4.
TERM_PROJ="$MT4_MQL4_DIR/Indicators/BiotakProject"
mkdir -p "$TERM_PROJ"
sync_tree() {
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude '.git' --exclude 'build-logs' --exclude '*.ex4' \
      --include 'Biotak Trigger TH3.mq4' --include 'Biotak Trigger TH3 Lite.mq4' \
      --include 'Biotak/***' --include 'Files/' --include 'Files/Icons/' \
      --include 'Files/Icons/*.bmp' --exclude '*' "$SCRIPT_ROOT/" "$1/"
  else
    cp -ru "$SCRIPT_ROOT/Biotak Trigger TH3.mq4" \
           "$SCRIPT_ROOT/Biotak Trigger TH3 Lite.mq4" \
           "$SCRIPT_ROOT/Biotak" "$1/"
    mkdir -p "$1/Files"
    cp -ru "$SCRIPT_ROOT/Files/Icons" "$1/Files/"
  fi
}
sync_tree "$TERM_PROJ"
echo "Terminal project synced: Indicators/BiotakProject"

# --- 2. sync icons into terminal MQL4\Files\Icons ------------------------------
ICON_DST="$MT4_MQL4_DIR/Files/Icons"
mkdir -p "$ICON_DST"
copied=0
for bmp in "$SCRIPT_ROOT"/Files/Icons/*.bmp; do
  dst="$ICON_DST/$(basename "$bmp")"
  if [ ! -f "$dst" ] || ! cmp -s "$bmp" "$dst"; then cp -f "$bmp" "$dst"; copied=$((copied+1)); fi
done
[ "$copied" -gt 0 ] && echo "Icon sync: copied $copied updated BMP(s)"

# --- 3. mirror sources into the in-bottle build dir -----------------------------
BUILD_UNIX="$BOTTLE_PATH/drive_c/th3build"
BUILD_WIN='C:\th3build'
mkdir -p "$BUILD_UNIX/logs"
sync_tree "$BUILD_UNIX"
echo "Sources mirrored to $BUILD_WIN"

# --- 4. pick targets -------------------------------------------------------------
NAMES=()
SRCS=()
if [ "$TARGET" = "full" ] || [ "$TARGET" = "all" ]; then
  NAMES+=("full"); SRCS+=("Biotak Trigger TH3.mq4")
fi
if [ "$TARGET" = "lite" ] || [ "$TARGET" = "all" ]; then
  NAMES+=("lite"); SRCS+=("Biotak Trigger TH3 Lite.mq4")
fi

# --- 5. generate the CRLF .bat (quoting lives here, not on the CLI) --------------
BAT_UNIX="$BOTTLE_PATH/drive_c/compile-th3-linux.bat"
python3 - "$BAT_UNIX" "$MED_WIN" "$BUILD_WIN" "${NAMES[@]}" "${SRCS[@]}" <<'EOF'
import sys
bat, med, build = sys.argv[1:4]
rest = sys.argv[4:]
names, srcs = rest[:len(rest)//2], rest[len(rest)//2:]
lines = ["@echo off"]
for name, src in zip(names, srcs):
    lines.append(
        '"%s" /compile:"%s\\%s" /log:"%s\\logs\\%s.log" /include:"%s"'
        % (med, build, src, build, name, build))
    lines.append("echo EXIT-%s %%ERRORLEVEL%% > %s\\logs\\%s.done" % (name, build, name))
open(bat, "wb").write(("\r\n".join(lines) + "\r\n").encode("ascii"))
print("BAT:")
print("\n".join(lines))
EOF

# --- 6. run it --------------------------------------------------------------------
echo ""
echo "Compiling via Bottles (this takes ~1-2 min) ..."
if ! flatpak run --command=bottles-cli com.usebottles.bottles \
      run -b "$BOTTLE_NAME" -e "$BAT_UNIX"; then
  echo "ERROR: bottles-cli run failed." >&2
  exit 1
fi

# --- 7. collect artifacts + report --------------------------------------------------
mkdir -p "$SCRIPT_ROOT/build-logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
overall=0
for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"; src="${SRCS[$i]}"
  base="${src%.mq4}"
  log_unix="$BUILD_UNIX/logs/$name.log"
  ex4_unix="$BUILD_UNIX/$base.ex4"
  if [ ! -f "$log_unix" ]; then
    echo "[$name] FAIL: no compiler log (metaeditor produced nothing)" >&2
    overall=1; continue
  fi
  cp -f "$log_unix" "$SCRIPT_ROOT/build-logs/linux-$name-$STAMP.log"
  if [ -f "$ex4_unix" ]; then
    cp -f "$ex4_unix" "$SCRIPT_ROOT/$base.ex4"
    cp -f "$ex4_unix" "$TERM_PROJ/$base.ex4"
    echo "[$name] ex4: $base.ex4 ($(stat -c%s "$SCRIPT_ROOT/$base.ex4") bytes, deployed to terminal)"
  else
    echo "[$name] WARNING: no .ex4 produced" >&2
  fi
  python3 - "$SCRIPT_ROOT/build-logs/linux-$name-$STAMP.log" "$name" <<'EOF'
import re, sys
text = open(sys.argv[1], "rb").read().decode("utf-16", errors="replace")
lines = text.splitlines()
errs = [l for l in lines if re.search(r": error \d+:", l)]
warns = [l for l in lines if re.search(r": warning \d+:", l)]
res = [l for l in lines if l.startswith("Result:")]
print("[%s] %s | errors=%d warnings=%d" % (sys.argv[2], res[-1] if res else "NO RESULT LINE", len(errs), len(warns)))
for e in errs[:25]:
    print("  ERROR: " + e.strip())
for w in warns[:15]:
    print("  warn:  " + w.strip())
sys.exit(1 if errs or not res else 0)
EOF
  [ $? -ne 0 ] && overall=1
done

echo ""
if [ "$overall" -eq 0 ]; then
  echo "All compilations PASSED."
  echo "In MT4: remove & re-add the indicator (or restart the terminal)."
else
  echo "Some compilations FAILED." >&2
fi
exit "$overall"
