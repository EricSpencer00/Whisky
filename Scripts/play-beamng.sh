#!/usr/bin/env bash
# Launch BeamNG.drive through the Wine/DXMT bundle built by this fork.
#
# Required:
#   WINEPREFIX=/path/to/Whisky/Bottles/<id>
# Optional:
#   BEAMNG_ROOT=/path/to/BeamNG.drive
#
# Modes:
#   direct     launch the game without Steam
#   autostart  launch directly and load the test freeroam scene
#   steam      launch through the Steam client

set -euo pipefail

LIBRARIES="${WHISKY_LIBRARIES:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries}"
BOTTLE="${WINEPREFIX:-}"
BEAMNG_ROOT="${BEAMNG_ROOT:-}"
MODE="${1:-direct}"
WINE="$LIBRARIES/Wine/bin/wine64"

[ -n "$BOTTLE" ] || { echo "Set WINEPREFIX to the Whisky bottle to use." >&2; exit 1; }
[ -x "$WINE" ] || { echo "Wine runtime not found at $WINE" >&2; exit 1; }

if [ -z "$BEAMNG_ROOT" ]; then
  BEAMNG_ROOT="$BOTTLE/drive_c/steamcmd/steamapps/common/BeamNG.drive"
fi
[ -f "$BEAMNG_ROOT/Bin64/BeamNG.drive.x64.exe" ] || {
  echo "BeamNG.drive.x64.exe not found below $BEAMNG_ROOT" >&2
  exit 1
}

export WINEPREFIX="$BOTTLE"
export DYLD_FALLBACK_LIBRARY_PATH="$LIBRARIES/Wine/lib:/usr/local/lib:/usr/lib"
export WINEMSYNC="${WINEMSYNC:-1}"
export WINEESYNC="${WINEESYNC:-1}"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"

if [ -f "$BEAMNG_ROOT/dxmt.conf" ]; then
  export DXMT_CONFIG_FILE="$BEAMNG_ROOT/dxmt.conf"
fi

GAME="$BEAMNG_ROOT/Bin64/BeamNG.drive.x64.exe"
STEAM="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"

case "$MODE" in
  direct)
    exec "$WINE" start /unix "$GAME" -nosteam -noeos
    ;;
  autostart)
    exec "$WINE" start /unix "$GAME" -nosteam -noeos \
      -lua "extensions.load('autostart')"
    ;;
  steam)
    [ -f "$STEAM" ] || { echo "Steam not found at $STEAM" >&2; exit 1; }
    exec "$WINE" start /unix "$STEAM" -- -applaunch 284160
    ;;
  *)
    echo "Usage: $0 [direct|autostart|steam]" >&2
    exit 2
    ;;
esac
