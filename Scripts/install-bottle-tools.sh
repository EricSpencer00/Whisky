#!/usr/bin/env bash
#
# Installs the app runner into a bottle, at <bottle>/tools/.
#
#   ./Scripts/install-bottle-tools.sh [bottle-path]
#
# The runner lives in the bottle, not in the Wine bundle, so replacing the
# bundle (install-bundle.sh, a new BuildWine release) does not remove it. It
# resolves the bundle at run time rather than baking a path in.
set -euo pipefail

prefix="${1:-}"
if [ -z "$prefix" ]; then
  prefix=$(ls -td "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"/*/ 2>/dev/null | head -1)
fi
prefix="${prefix%/}"
[ -d "$prefix" ] || { echo "no bottle at $prefix" >&2; exit 1; }

mkdir -p "$prefix/tools"

cat > "$prefix/tools/run.sh" <<'RUNNER'
#!/bin/bash
#
# Run a Windows program in this bottle.
#
#   tools/run.sh 'C:\path\to\app.exe' [args...]
#
# Env:
#   TRACE=server|relay|seh|warn   turn on a WINEDEBUG preset
#   WAIT=<seconds>                block until the app exits, or this long
#   LOG=<path>                    where to write output (default tools/last.log)
#
# DYLD_FALLBACK_LIBRARY_PATH is exported *here*, on purpose. macOS strips
# DYLD_* when it execs a SIP-protected binary such as /usr/bin/nohup, so
# setting it in the calling shell does not survive. Wine then fails to find
# libfreetype and renders no text.
set -u

BOTTLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
WINE="$LIB/Wine"
[ -x "$WINE/bin/wine64" ] || { echo "no wine at $WINE" >&2; exit 1; }

export WINEPREFIX="$BOTTLE"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE/lib:/usr/local/lib:/usr/lib"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"   # or 153 lines of Vulkan extensions

case "${TRACE:-}" in
  server) export WINEDEBUG=+server ;;
  relay)  export WINEDEBUG=+relay ;;
  seh)    export WINEDEBUG=+seh,+loaddll,+process ;;
  warn)   export WINEDEBUG=warn+all ;;
  *)      export WINEDEBUG="${WINEDEBUG:--all}" ;;
esac

LOG="${LOG:-$BOTTLE/tools/last.log}"

# WINEDEBUG is read when wineserver starts. A stale one silently disables
# tracing and produces an empty log that looks like a clean run.
if [ -n "${TRACE:-}" ]; then
  "$WINE/bin/wineserver" -k >/dev/null 2>&1 || true
  sleep 1
fi

: > "$LOG"
"$WINE/bin/wine64" "$@" >> "$LOG" 2>&1 &
pid=$!
disown 2>/dev/null || true
echo "pid=$pid log=$LOG"

[ -n "${WAIT:-}" ] || exit 0
for _ in $(seq 1 "$WAIT"); do
  kill -0 "$pid" 2>/dev/null || { echo "exited after ~${SECONDS}s"; exit 0; }
  sleep 1
done
echo "still running after ${WAIT}s"
RUNNER

cat > "$prefix/tools/stop.sh" <<'STOPPER'
#!/bin/bash
# Stop everything in this bottle. Note that killing wine processes makes
# "wineserver crashed" and "services.exe exited with code 0" appear in logs.
# Those are your kill, not evidence.
BOTTLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WINE="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine"
WINEPREFIX="$BOTTLE" "$WINE/bin/wineserver" -k >/dev/null 2>&1
sleep 1
echo "stopped (wine procs left: $(pgrep -f 'wine64|wineserver' | wc -l | tr -d ' '))"
STOPPER

chmod +x "$prefix/tools/run.sh" "$prefix/tools/stop.sh"
echo "installed into $prefix/tools/"
ls -1 "$prefix/tools/"
