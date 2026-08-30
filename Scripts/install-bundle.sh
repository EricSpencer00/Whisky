#!/usr/bin/env bash
#
# Installs a BuildWine bundle and the two things it does not contain.
#
#   ./Scripts/install-bundle.sh Libraries.tar.gz
#   ./Scripts/install-bundle.sh --run-id 33028180731
#   ./Scripts/install-bundle.sh --no-verify Libraries.tar.gz
#
# --no-verify installs and makes a bottle but does not run the two probes, so a
# caller that wants to assert its own result can run them itself. It prints the
# bottle it used on a line that reads "bottle <path>".
#
# The tarball BuildWine produces is Wine only. A working stack also needs the
# MoltenVK symlink (win32u dlopens libvulkan.1.dylib by that name, from that
# directory, and searches nowhere else) and DXMT's winemetal.so unixlib.
# Installing the tarball on its own silently downgrades D3D11 to 9_3.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${LIB:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries}"
BOTTLES="${BOTTLES:-$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles}"
export WHISKY_LIBS="$LIB/Wine"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

verify=1
[ "${1:-}" = "--no-verify" ] && { verify=0; shift; }

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

# The tarball also carries MoltenVK. A machine that has run Whisky already has
# it; a CI runner does not, and the symlink below needs the dylib to exist.
mvk_src=$(find "$tmpx" -maxdepth 3 -type d -name MoltenVK | head -1)
if [ -n "$mvk_src" ] && [ ! -f "$LIB/MoltenVK/libMoltenVK.dylib" ]; then
  cp -a "$mvk_src" "$LIB/MoltenVK"
  log "installed MoltenVK from $tarball"
fi

# Both probes need a prefix, and dxmt-install writes into one. A CI runner has
# no bottle, so make one. wineboot -i takes about 30 seconds.
prefix=$(ls -td "$BOTTLES"/*/ 2>/dev/null | head -1) || true
prefix="${prefix%/}"
if [ -z "$prefix" ]; then
  prefix="$BOTTLES/probe"
  log "no bottle found; creating $prefix"
  mkdir -p "$prefix"
  (
    export WINEPREFIX="$prefix" WINEDEBUG=-all
    export DYLD_FALLBACK_LIBRARY_PATH="$LIB/Wine/lib:$LIB/Wine/lib/external:/usr/local/lib:/usr/lib"
    "$LIB/Wine/bin/wine64" wineboot -i >/dev/null 2>&1
    "$LIB/Wine/bin/wineserver" -w
  )
  # wineboot copies the bundle's PE builtins into system32, but not d3d11.dll:
  # with a fork DXMT build that file is 21 MB, and while dxgi, d3d10core,
  # nvapi64 and winemetal all land in system32, d3d11 ends up in syswow64 or
  # nowhere. d3d11 then fails to load and the probe reports no result. Copy the
  # set from the bundle, so the bottle gets the bundle's own DXMT rather than
  # the upstream release that dxmt-install would download.
  for n in d3d11 dxgi d3d10core d3d12 nvapi64 nvngx winemetal; do
    [ -f "$LIB/Wine/lib/wine/x86_64-windows/$n.dll" ] || continue
    cp "$LIB/Wine/lib/wine/x86_64-windows/$n.dll" \
       "$prefix/drive_c/windows/system32/$n.dll"
  done
fi
export WINEPREFIX="$prefix"
log "bottle $prefix"

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

[ "$verify" = 1 ] || { log "--no-verify: skipping the probes"; exit 0; }

log "verifying $prefix"
"$script_dir/run-dosdev-probe.sh" "$prefix"
"$script_dir/run-d3d11-probe.sh" probe
