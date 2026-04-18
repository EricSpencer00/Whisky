#!/usr/bin/env bash
# play-beamng.sh — launch BeamNG.drive through Steam running in CrossOver's
# BeamNG bottle. Assumes:
#   - CrossOver 26 installed at /Applications/CrossOver.app
#   - Bottle named 'BeamNG' already set up (by this session's earlier commands)
#   - Steam is signed in (one-time user step)
#
# Run:
#   ~/bin/play-beamng.sh
# or:
#   ~/bin/play-beamng.sh steam    # just launch Steam (to log in once)

set -euo pipefail

CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver
BOTTLE=BeamNG
BOTTLE_DIR="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
MODE="${1:-beamng}"

if [ ! -x "$CX/bin/cxstart" ]; then
  echo "ERROR: CrossOver not found. Install: brew install --cask crossover" >&2
  exit 1
fi
if [ ! -d "$BOTTLE_DIR" ]; then
  echo "ERROR: BeamNG bottle missing at $BOTTLE_DIR" >&2
  echo "Create with: $CX/bin/cxbottle --bottle $BOTTLE --create --template win10_64" >&2
  exit 1
fi

# Ensure any stale Wine processes from a prior hang are cleaned up
pkill -9 -f "BeamNG.drive.x64|cxstart|steam\.exe" 2>/dev/null || true
sleep 1

# Make sure BeamNG is pre-staged in Steam's library (symlinked to the
# existing Whisky install so Steam sees it as installed without a 30 GB
# re-download). Idempotent — does nothing if already in place.
STEAMAPPS="$BOTTLE_DIR/drive_c/Program Files (x86)/Steam/steamapps"
WHISKY_BNG="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/8AAFE391-2633-47E7-9655-59BFD9270EF3/drive_c/steamcmd/steamapps"
mkdir -p "$STEAMAPPS/common"
if [ ! -e "$STEAMAPPS/common/BeamNG.drive" ] && [ -d "$WHISKY_BNG/common/BeamNG.drive" ]; then
  ln -s "$WHISKY_BNG/common/BeamNG.drive" "$STEAMAPPS/common/BeamNG.drive"
fi
if [ ! -f "$STEAMAPPS/appmanifest_284160.acf" ] && [ -f "$WHISKY_BNG/appmanifest_284160.acf" ]; then
  cp "$WHISKY_BNG/appmanifest_284160.acf" "$STEAMAPPS/"
  # Retarget LauncherPath to the CrossOver Steam
  /usr/bin/sed -i.bak \
    's|C:\\\\steamcmd\\\\steamcmd.exe|C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe|' \
    "$STEAMAPPS/appmanifest_284160.acf" || true
fi

case "$MODE" in
  steam)
    echo "Launching Steam in CrossOver bottle '$BOTTLE'. Sign in once."
    exec "$CX/bin/cxstart" --bottle "$BOTTLE" \
      'C:\Program Files (x86)\Steam\steam.exe'
    ;;
  beamng)
    echo "Launching BeamNG.drive via Steam URI (steam://run/284160)..."
    # Launch Steam with a run URL; Steam finds the manifest, launches the
    # game as its child process. If Steam isn't running this boots it first.
    exec "$CX/bin/cxstart" --bottle "$BOTTLE" \
      'C:\Program Files (x86)\Steam\steam.exe' -- -applaunch 284160
    ;;
  direct)
    echo "Launching BeamNG.drive directly (no Steam parent) — may hit CEF issues."
    exec "$CX/bin/cxstart" --bottle "$BOTTLE" \
      'C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\Bin64\BeamNG.drive.x64.exe' \
      -- -nosteam -noeos
    ;;
  *)
    echo "Usage: $0 [steam|beamng|direct]"
    echo "  steam   — launch Steam client (for first-time login)"
    echo "  beamng  — launch BeamNG via Steam (default, recommended)"
    echo "  direct  — launch BeamNG without Steam parent (fallback)"
    exit 1
    ;;
esac
