#!/usr/bin/env bash
# ============================================================================
# compile-th3-linux.sh — Linux compile path for Biotak Trigger TH3 (MQL4)
#
# Compiles the project with the Bottles Flatpak's Wine (wine-11.0) inside a
# DEDICATED build prefix. This is the Linux counterpart of compile-th3.ps1
# (Windows) — that script is NEVER touched by this one.
#
# Usage:
#   ./compile-th3-linux.sh [full|lite|all]     (default: all)
#
# Optional environment overrides:
#   BOTTLE_NAME    Bottles bottle name            (default: Tradeing)
#   BOTTLE_PATH    Full path to the bottle dir    (auto-detected)
#   MT4_METAEDITOR Full unix path to metaeditor.exe (auto-detected in bottle)
#   MT4_MQL4_DIR   Full unix path to terminal MQL4 (auto-detected)
#   TH3_WINEPREFIX Full unix path to the isolated build prefix
#                  (default: <Bottles-data>/th3build-wine)
#
# How it works (see AGENTS.md P-BUILD-02 / P-BUILD-04 for the traps):
#   1. Syncs the repo sources into the terminal's REAL
#      Indicators/BiotakProject dir (for manual MetaEditor F7) and syncs
#      Files/Icons/*.bmp into the terminal's MQL4\Files\Icons, because
#      MetaEditor resolves #resource against the TERMINAL data folder.
#      Plain file copies — safe while the terminal runs.
#   2. Mirrors the sources into an ISOLATED Wine prefix
#      (<Bottles-data>/th3build-wine, C:\th3build inside) that hosts its own
#      copy of metaeditor.exe (C:\mt4). The compile runs there via:
#        flatpak run --command=wine com.usebottles.bottles cmd /c <bat>
#      The running terminal is NEVER touched by Wine: every `flatpak run`
#      sandbox gets a PRIVATE /tmp (proven — a host /tmp probe file is
#      invisible inside), so a second wineserver on the SAME prefix would
#      corrupt/close the live terminal. The isolated prefix has its own
#      wineserver, so the terminal stays open (P-BUILD-04).
#   3. metaeditor.exe MUST be driven through cmd.exe with a CRLF .bat holding
#      QUOTED paths: passing a spaced /compile path as a direct wine argv
#      silently compiles NOTHING (BOM-only log, exit 0, no .ex4 — verified).
#   4. Copies the .ex4 + build log back into the repo, deploys the .ex4 to
#      the terminal project dir, and prints the "Result: N errors" summary.
#      Success = "Result: 0 errors".
# ============================================================================
#
# P-TOOL-04 (2026-09-25): this script is bash + coreutils ONLY. The four python3
# heredocs it used to carry (MQL4-dir scan, build-prefix path, the CRLF .bat
# emitter, the UTF-16 log parser) are rewritten in bash: no Python interpreter,
# matching the repo rule that no Python ships or runs here.
# ============================================================================
set -u

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-all}"
BOTTLE_NAME="${BOTTLE_NAME:-Tradeing}"

case "$TARGET" in
  full|lite|all) ;;
  *) echo "Usage: $0 [full|lite|all]" >&2; exit 2 ;;
esac

# --- locate the bottle (metaeditor seed + terminal deploy dir) -----------------
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

# --- locate metaeditor.exe (seed source for the build prefix) ------------------
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

# --- locate terminal MQL4 dir (for icon sync + BiotakProject link) ------------
if [ -z "${MT4_MQL4_DIR:-}" ]; then
  # P-TOOL-04: pure bash (was python3). Candidates are every terminal MQL4 dir
  # that has an Indicators/; the pool prefers the ones already hosting
  # Indicators/BiotakProject (a symlink counts — hence -e OR -L), and the newest
  # mtime wins. No interpreter, no temp file: the glob and stat are the job.
  mql4_cands=()
  for m in "$BOTTLE_PATH"/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/*/MQL4; do
    [ -d "$m/Indicators" ] && mql4_cands+=("$m")
  done
  mql4_pool=()
  for m in ${mql4_cands[@]+"${mql4_cands[@]}"}; do
    if [ -e "$m/Indicators/BiotakProject" ] || [ -L "$m/Indicators/BiotakProject" ]; then
      mql4_pool+=("$m")
    fi
  done
  [ ${#mql4_pool[@]} -gt 0 ] || mql4_pool=(${mql4_cands[@]+"${mql4_cands[@]}"})
  MT4_MQL4_DIR=""
  mql4_newest=-1
  for m in ${mql4_pool[@]+"${mql4_pool[@]}"}; do
    t="$(stat -c %Y "$m" 2>/dev/null || echo 0)"
    if [ "$t" -gt "$mql4_newest" ]; then mql4_newest="$t"; MT4_MQL4_DIR="$m"; fi
  done
fi
if [ -z "${MT4_MQL4_DIR:-}" ] || [ ! -d "$MT4_MQL4_DIR/Indicators" ]; then
  echo "ERROR: terminal MQL4 dir not found (run terminal.exe once first)." >&2
  echo "HINT: set MT4_MQL4_DIR explicitly." >&2
  exit 1
fi

# --- isolated build prefix (visible inside the flatpak sandbox at same path) ---
if [ -z "${TH3_WINEPREFIX:-}" ]; then
  # P-TOOL-04: pure bash (was python3). <data>/bottles/bottles/<name> -> <data>
  # is three dirnames; the trailing slash is stripped first so a user-supplied
  # BOTTLE_PATH with one still lands in <data>.
  _bp="${BOTTLE_PATH%/}"
  case "$_bp" in /*) ;; *) _bp="$PWD/$_bp" ;; esac
  TH3_WINEPREFIX="$(dirname "$(dirname "$(dirname "$_bp")")")/th3build-wine"
fi

echo "Bottle:      $BOTTLE_PATH"
echo "MetaEditor:  $MT4_METAEDITOR"
echo "MQL4 dir:    $MT4_MQL4_DIR"
echo "Build prefix:$TH3_WINEPREFIX"
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
    rm -rf "$1/Biotak" "$1/Files"
    cp -f "$SCRIPT_ROOT/Biotak Trigger TH3.mq4" \
          "$SCRIPT_ROOT/Biotak Trigger TH3 Lite.mq4" \
          "$1/"
    cp -r "$SCRIPT_ROOT/Biotak" "$1/Biotak"
    mkdir -p "$1/Files/Icons"
    cp -f "$SCRIPT_ROOT"/Files/Icons/*.bmp "$1/Files/Icons/"
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

# --- 3. init the isolated prefix once + seed metaeditor.exe --------------------
BUILD_UNIX="$TH3_WINEPREFIX/drive_c/th3build"
MT4_UNIX="$TH3_WINEPREFIX/drive_c/mt4"
if [ ! -d "$TH3_WINEPREFIX/drive_c" ]; then
  echo "First run: initializing isolated Wine prefix (one-time, ~1 min) ..."
  mkdir -p "$TH3_WINEPREFIX"
  if ! flatpak run \
      --env=WINEPREFIX="$TH3_WINEPREFIX" \
      --env=WINEARCH=win64 \
      --env=WINEDEBUG=-all \
      --command=wine com.usebottles.bottles wineboot --init; then
    echo "ERROR: wineboot --init failed." >&2
    exit 1
  fi
fi
mkdir -p "$MT4_UNIX" "$BUILD_UNIX/logs"
if [ ! -f "$MT4_UNIX/metaeditor.exe" ] || [ "$MT4_METAEDITOR" -nt "$MT4_UNIX/metaeditor.exe" ]; then
  cp -f "$MT4_METAEDITOR" "$MT4_UNIX/metaeditor.exe"
  echo "metaeditor.exe seeded into build prefix"
fi
sync_tree "$BUILD_UNIX"
echo "Sources mirrored to C:\\th3build (isolated prefix)"

# --- 4. drop legacy build artefacts from the LIVE bottle (P-BUILD-04) -----------
# The old script compiled inside the live bottle (C:\th3build + .bat there);
# that second wineserver on the live prefix is what closed the terminal.
for legacy in "$BOTTLE_PATH/drive_c/th3build" "$BOTTLE_PATH/drive_c/compile-th3-linux.bat"; do
  case "$legacy" in
    */drive_c/*) [ -e "$legacy" ] && rm -rf "$legacy" && echo "Removed legacy: $legacy" ;;
  esac
done

# --- 5. pick targets -------------------------------------------------------------
NAMES=()
SRCS=()
if [ "$TARGET" = "full" ] || [ "$TARGET" = "all" ]; then
  NAMES+=("full"); SRCS+=("Biotak Trigger TH3.mq4")
fi
if [ "$TARGET" = "lite" ] || [ "$TARGET" = "all" ]; then
  NAMES+=("lite"); SRCS+=("Biotak Trigger TH3 Lite.mq4")
fi

# --- 6. generate the CRLF .bat (quoting lives here — direct argv with spaces
#        silently compiles nothing, see header) -----------------------------------
BAT_UNIX="$BUILD_UNIX/compile.bat"
# P-TOOL-04: pure bash (was python3). printf emits the CRLF bytes and the quoted
# Windows paths directly — no interpreter, no encode step, byte-identical .bat.
{
  printf '@echo off\r\n'
  for i in "${!NAMES[@]}"; do
    printf '"C:\\mt4\\metaeditor.exe" /compile:"C:\\th3build\\%s" /log:"C:\\th3build\\logs\\%s.log" /include:"C:\\th3build"\r\n' \
      "${SRCS[$i]}" "${NAMES[$i]}"
  done
} > "$BAT_UNIX"
echo "BAT:"
sed 's/\r$//' "$BAT_UNIX"

# --- 7. run it (isolated prefix — the live terminal stays open) -------------------
echo ""
echo "Compiling in isolated prefix (this takes ~1-2 min, terminal stays open) ..."
if ! flatpak run \
    --env=WINEPREFIX="$TH3_WINEPREFIX" \
    --env=WINEARCH=win64 \
    --env=WINEDEBUG=-all \
    --command=wine com.usebottles.bottles \
    cmd /c "C:\\th3build\\compile.bat"; then
  echo "WARNING: wine/cmd exited non-zero (metaeditor exit codes are unreliable;" >&2
  echo "proceeding to log parse, which is the real success gate)." >&2
fi

# --- 8. collect artifacts + report --------------------------------------------------
# report_log <metaeditor-log> <target-name> — decode the compiler log, print the
# verdict, and return 0 only for a clean compile. P-TOOL-04: pure bash (was
# python3). The log is UTF-16 with a BOM so iconv does the decode, and a host
# without iconv still works through the NUL-strip fallback — the payload here is
# ASCII and UTF-16LE keeps every byte of it beside a NUL.
report_log() {
  local log="$1" name="$2" bom txt errs warns res
  bom="$(head -c 2 "$log" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  txt=""
  if command -v iconv >/dev/null 2>&1; then
    case "$bom" in
      # `-f UTF-16` (not LE/BE) on purpose: it consumes the BOM instead of
      # emitting it as a U+FEFF into the first line.
      feff|fffe) txt="$(iconv -f UTF-16 -t UTF-8 "$log" 2>/dev/null)";;
    esac
  fi
  [ -n "$txt" ] || txt="$(tr -d '\000' < "$log")"
  txt="$(printf '%s\n' "$txt" | tr -d '\r')"
  # The real MetaEditor shape is `file.mq4(12,5) : error 256: 'x' - msg` (no
  # space before the colon); the ` *` keeps a spaced variant matched too.
  errs="$(printf '%s\n' "$txt" | grep -cE ': error [0-9]+ *:')"
  warns="$(printf '%s\n' "$txt" | grep -cE ': warning [0-9]+ *:')"
  res="$(printf '%s\n' "$txt" | grep -E '^Result:' | tail -n 1)"
  echo "[$name] ${res:-NO RESULT LINE} | errors=$errs warnings=$warns"
  printf '%s\n' "$txt" | grep -E ': error [0-9]+ *:' | head -n 25 | sed -E 's/^[[:space:]]*/  ERROR: /'
  printf '%s\n' "$txt" | grep -E ': warning [0-9]+ *:' | head -n 15 | sed -E 's/^[[:space:]]*/  warn:  /'
  [ -z "$res" ] && return 1
  [ "$errs" -ne 0 ] && return 1
  return 0
}
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
  report_log "$SCRIPT_ROOT/build-logs/linux-$name-$STAMP.log" "$name" || overall=1
done

echo ""
if [ "$overall" -eq 0 ]; then
  echo "All compilations PASSED (terminal untouched)."
  echo "In MT4: remove & re-add the indicator (or restart the terminal)."
else
  echo "Some compilations FAILED." >&2
fi
exit "$overall"
