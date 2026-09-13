#!/usr/bin/env bash
# Launch GTA V Legacy through Rockstar Games Launcher in a Whisky bottle.
#
# Required:
#   WINEPREFIX=/path/to/Whisky/Bottles/<id>
#   GTA5_ROOT=/path/to/Grand Theft Auto V Legacy
#
# GTA V must be started by Rockstar Launcher. Set GTA_SAFE_MODE=1 when using
# ScriptHookV/ASI mods; this keeps the tested BattlEye-safe path explicit.

set -euo pipefail

LIBRARIES="${WHISKY_LIBRARIES:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries}"
BOTTLE="${WINEPREFIX:-}"
GAME_ROOT="${GTA5_ROOT:-}"
WINE="$LIBRARIES/Wine/bin/wine64"
LAUNCHER='C:\Program Files\Rockstar Games\Launcher\Launcher.exe'

[ -n "$BOTTLE" ] || { echo "Set WINEPREFIX to the Whisky bottle to use." >&2; exit 1; }
[ -n "$GAME_ROOT" ] || { echo "Set GTA5_ROOT to the GTA V Legacy install directory." >&2; exit 1; }
[ -x "$WINE" ] || { echo "Wine runtime not found at $WINE" >&2; exit 1; }
[ -f "$GAME_ROOT/GTA5.exe" ] || { echo "GTA5.exe not found below $GAME_ROOT" >&2; exit 1; }

export WINEPREFIX="$BOTTLE"
export DYLD_FALLBACK_LIBRARY_PATH="$LIBRARIES/Wine/lib:/usr/local/lib:/usr/lib"
export WINEMSYNC="${WINEMSYNC:-1}"
export WINEESYNC="${WINEESYNC:-1}"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
export DXMT_UNSUPPORTED_MTLAYER="${DXMT_UNSUPPORTED_MTLAYER:-1}"

cd "$GAME_ROOT"
if [ -f "$GAME_ROOT/dxmt.conf" ]; then
  export DXMT_CONFIG_FILE="$GAME_ROOT/dxmt.conf"
fi

args=(-skipPatcherCheck -minmodeApp=gta5 -nobattleye)
if [ "${GTA_SAFE_MODE:-0}" = 1 ]; then
  args+=(-safemode)
fi

exec "$WINE" "$LAUNCHER" "${args[@]}"
