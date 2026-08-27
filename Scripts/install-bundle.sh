#!/usr/bin/env bash
#
# Installs a BuildWine bundle and the two things it does not contain.
#
#   ./Scripts/install-bundle.sh Libraries.tar.gz
#   ./Scripts/install-bundle.sh --run-id 33028180731
#
# The tarball BuildWine produces is Wine only. A working stack also needs the
# MoltenVK symlink (win32u dlopens libvulkan.1.dylib by that name, from that
# directory, and searches nowhere else) and DXMT's winemetal.so unixlib.
# Installing the tarball on its own silently downgrades D3D11 to 9_3.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${LIB:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

tarball=""
case "${1:-}" in
  --run-id)
    [ -n "${2:-}" ] || { echo "usage: $0 --run-id <id>" >&2; exit 1; }
    tmp=$(mktemp -d)
    log "downloading artifact from run $2"
    gh run download "$2" --repo EricSpencer00/Whisky --dir "$tmp"
    tarball=$(find "$tmp" -name 'Libraries.tar.gz' | head -1)
    ;;
  "") echo "usage: $0 <Libraries.tar.gz> | --run-id <id>" >&2; exit 1 ;;
  *)  tarball="$1" ;;
esac
[ -f "$tarball" ] || { echo "no tarball at $tarball" >&2; exit 1; }

stamp=$(date +%Y%m%d-%H%M%S)
if [ -d "$LIB/Wine" ]; then
  log "backing up current Wine to Wine.bak-$stamp"
  mv "$LIB/Wine" "$LIB/Wine.bak-$stamp"
fi

tmpx=$(mktemp -d)
tar xzf "$tarball" -C "$tmpx"
src=$(find "$tmpx" -maxdepth 3 -type d -name Wine | head -1)
[ -d "$src" ] || { echo "no Wine/ inside $tarball" >&2; exit 1; }
mkdir -p "$LIB"
cp -a "$src" "$LIB/Wine"
log "installed Wine from $tarball"

# A bundle built after this change already carries DXMT and the MoltenVK
# symlink. Doing either step again replaces the bundle's DXMT with the upstream
# release, which is the one without the cross-process presentation fixes.
wine_unix="$LIB/Wine/lib/wine/x86_64-unix"
if [ -e "$wine_unix/libvulkan.1.dylib" ] && [ -f "$wine_unix/winemetal.so" ]; then
  log "bundle is self-contained; nothing to add"
else
  mvk="$LIB/MoltenVK/libMoltenVK.dylib"
  if [ -f "$mvk" ]; then
    ln -sf "$mvk" "$wine_unix/libvulkan.1.dylib"
    log "linked libvulkan.1.dylib -> $mvk"
  else
    log "WARNING: $mvk missing; Vulkan will not initialise"
  fi

  log "older bundle: installing DXMT separately"
  "$script_dir/run-d3d11-probe.sh" dxmt-install
fi

log "verifying"
"$script_dir/run-dosdev-probe.sh"
"$script_dir/run-d3d11-probe.sh" probe
