#!/usr/bin/env bash
#
# triage-app.sh — run a Windows app under the FOSS stack and report where it stops.
#
#   ./Scripts/triage-app.sh --tag steam 'C:\Program Files (x86)\Steam\steam.exe'
#   WAIT=90 ./Scripts/triage-app.sh --bottle "$B" --tag beamng 'C:\...\BeamNG.drive.exe'
#
# Writes <out>/<tag>.md with the window tree, the DXMT and Wine complaints, a
# capture of every on-screen window, and a verdict. The verdict comes from pixel
# statistics, not from looking, because a blank window and a rendered one are
# otherwise the same to a script.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probes="$script_dir/probes"
WINE="${WINE:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine}"
BOTTLE="${BOTTLE:-}"
TAG="app"
OUT="${OUT:-$script_dir/../out/triage}"
WAIT="${WAIT:-60}"
CWD="${CWD:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --bottle) BOTTLE="$2"; shift 2 ;;
    --tag)    TAG="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    --wait)   WAIT="$2"; shift 2 ;;
    --cwd)    CWD="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { echo "usage: $0 [--bottle DIR] [--tag NAME] [--wait N] <windows path> [args...]" >&2; exit 1; }
[ -n "$BOTTLE" ] || { echo "set --bottle or \$BOTTLE" >&2; exit 1; }

mkdir -p "$OUT"
report="$OUT/$TAG.md"
wlog="$OUT/$TAG.wine.log"

export WINEPREFIX="$BOTTLE"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE/lib:/usr/local/lib:/usr/lib"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"

"$WINE/bin/wineserver" -k 2>/dev/null; sleep 2
pkill -9 -f wineserver 2>/dev/null; sleep 1

# Several games resolve their data relative to the working directory and abort
# with a missing-file dialog when it is wrong.
[ -n "$CWD" ] && cd "$CWD"
"$WINE/bin/wine64" "$@" >"$wlog" 2>&1 &
sleep "$WAIT"

# A slept display captures as solid black, which scores as "drew nothing" for
# every window and reads as a regression. Wake it before looking.
caffeinate -u -t 3 2>/dev/null || true
sleep 2

cp "$probes/enumwin.exe" "$BOTTLE/drive_c/" 2>/dev/null
tree=$("$WINE/bin/wine64" 'C:\enumwin.exe' 2>/dev/null)

{
  echo "# $TAG"
  echo
  echo "\`$*\`  waited ${WAIT}s"
  echo
  echo '## Verdict'
  echo
} >"$report"

verdicts=""
while read -r line; do
  id=$(echo "$line" | sed -n 's/^id=\([0-9]*\).*/\1/p')
  [ -n "$id" ] || continue
  name=$(echo "$line" | sed -n 's/.*name=\(.*\) bounds=.*/\1/p')
  shot="$OUT/$TAG-$id.png"
  # Neither capture path covers everything: screencapture reads the active Space
  # and returns transparency for a window on another one, and ScreenCaptureKit
  # refuses some windows outright. Take whichever produces an image.
  "$probes/winshot2" "$id" "$shot" >/dev/null 2>&1
  [ -s "$shot" ] || screencapture -x -o -l "$id" "$shot" 2>/dev/null
  [ -s "$shot" ] || continue
  stat=$("$probes/imgstat" "$shot" 2>/dev/null)
  verdicts="$verdicts$(echo "$stat" | sed 's/verdict=//;s/ .*//') "
  echo "- \`${name:-untitled}\` — $stat — [capture]($(basename "$shot"))" >>"$report"
done < <("$probes/winshot" wine 2>/dev/null | grep -v "name= ")

if [ -z "$verdicts" ]; then
  if pgrep -f "$(basename "${1//\\//}")" >/dev/null 2>&1; then
    echo "- no on-screen window; process still running" >>"$report"
  else
    echo "- no on-screen window; process exited" >>"$report"
  fi
fi

{
  echo
  echo '## Window tree'
  echo '```'
  echo "${tree:-<none>}"
  echo '```'
  echo
  echo '## DXMT'
  echo '```'
  grep -E "^(err|warn|info):" "$wlog" | sort | uniq -c | sort -rn | head -25
  echo '```'
  echo
  echo '## Wine, most frequent first'
  echo '```'
  grep -oE "(fixme|err|warn):[a-z0-9_]+:[A-Za-z0-9_]+" "$wlog" | sort | uniq -c | sort -rn | head -25
  echo '```'
} >>"$report"

"$WINE/bin/wineserver" -k 2>/dev/null
echo "$report"
