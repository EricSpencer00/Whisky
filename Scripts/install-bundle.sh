#!/usr/bin/env bash
#
# Installs and verifies a self-contained BuildWine bundle.
#
#   ./Scripts/install-bundle.sh --release            # latest published release
#   ./Scripts/install-bundle.sh --release wine-v26.3.0-foss-phase3
#   ./Scripts/install-bundle.sh Libraries.tar.gz
#   ./Scripts/install-bundle.sh --run-id 33028180731
#   ./Scripts/install-bundle.sh --no-verify Libraries.tar.gz
#
# --no-verify installs and makes a bottle but does not run the two probes, so a
# caller that wants to assert its own result can run them itself. It prints the
# bottle it used on a line that reads "bottle <path>".
#
# The current BuildWine tarball carries Wine, MoltenVK, DXVK, DXMT, the required
# relative Vulkan symlink, and a manifest tying the versions together. Older
# Wine-only tarballs are still accepted through the legacy fallback path below.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${LIB:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries}"
BOTTLES="${BOTTLES:-$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles}"
export WHISKY_LIBS="$LIB/Wine"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

verify=1
[ "${1:-}" = "--no-verify" ] && { verify=0; shift; }

RELEASES="${RELEASES:-https://github.com/EricSpencer00/Whisky/releases}"

tarball=""
case "${1:-}" in
  # The release is the path for someone who just wants to play a game: no gh,
  # no login, and the checksum is published next to the tarball.
  --release)
    base="$RELEASES/latest/download"
    [ -n "${2:-}" ] && base="$RELEASES/download/$2"
    tmp=$(mktemp -d)
    log "downloading ${2:-latest} release"
    curl -fL --retry 3 -o "$tmp/Libraries.tar.gz" "$base/Libraries.tar.gz"
    if curl -fsL -o "$tmp/sha256" "$base/Libraries.tar.gz.sha256"; then
      want=$(awk '{print $1}' "$tmp/sha256")
      got=$(shasum -a 256 "$tmp/Libraries.tar.gz" | awk '{print $1}')
      [ "$want" = "$got" ] || { echo "checksum mismatch: $got != $want" >&2; exit 1; }
      log "checksum ok"
    else
      log "WARNING: no published checksum for this release"
    fi
    tarball="$tmp/Libraries.tar.gz"
    ;;
  --run-id)
    [ -n "${2:-}" ] || { echo "usage: $0 --run-id <id>" >&2; exit 1; }
    tmp=$(mktemp -d)
    log "downloading artifact from run $2"
    gh run download "$2" --repo EricSpencer00/Whisky --dir "$tmp"
    tarball=$(find "$tmp" -name 'Libraries.tar.gz' | head -1)
    ;;
  "") echo "usage: $0 --release [tag] | <Libraries.tar.gz> | --run-id <id>" >&2; exit 1 ;;
  *)  tarball="$1" ;;
esac
[ -f "$tarball" ] || { echo "no tarball at $tarball" >&2; exit 1; }

tmpx=$(mktemp -d)
tar xzf "$tarball" -C "$tmpx"
src=$(find "$tmpx" -maxdepth 3 -type d -name Wine | head -1)
[ -d "$src" ] || { echo "no Wine/ inside $tarball" >&2; exit 1; }
bundle_root="$(dirname "$src")"
manifest="$bundle_root/WhiskyWineManifest.plist"
current_bundle=0
if [ -f "$manifest" ]; then
  plutil -lint "$manifest" >/dev/null || { echo "invalid WhiskyWineManifest.plist" >&2; exit 1; }
  current_bundle=1
  for required in \
    "$bundle_root/WhiskyWineVersion.plist" \
    "$bundle_root/MoltenVK/libMoltenVK.dylib" \
    "$bundle_root/MoltenVK/icd.d/MoltenVK_icd.json" \
    "$src/bin/wine64" \
    "$src/bin/wineserver" \
    "$src/lib/wine/x86_64-unix/winemetal.so" \
    "$src/lib/wine/x86_64-windows/d3d11.dll" \
    "$src/lib/wine/x86_64-windows/d3d12.dll" \
    "$src/lib/wine/x86_64-windows/dxgi.dll"; do
    [ -e "$required" ] || { echo "current bundle is missing $required" >&2; exit 1; }
  done
  link="$src/lib/wine/x86_64-unix/libvulkan.1.dylib"
  [ -L "$link" ] || { echo "current bundle is missing the MoltenVK symlink" >&2; exit 1; }
  [ "$(readlink "$link")" = "../../../../MoltenVK/libMoltenVK.dylib" ] || {
    echo "current bundle has an invalid MoltenVK symlink" >&2
    exit 1
  }
fi
stamp=$(date +%Y%m%d-%H%M%S)
if [ -d "$LIB/Wine" ]; then
  log "backing up current Wine to Wine.bak-$stamp"
  mv "$LIB/Wine" "$LIB/Wine.bak-$stamp"
fi
mkdir -p "$LIB"
cp -a "$src" "$LIB/Wine"
log "installed Wine from $tarball"

# The tarball also carries MoltenVK. A machine that has run Whisky already has
# it; a CI runner does not, and the symlink below needs the dylib to exist.
mvk_src=$(find "$tmpx" -maxdepth 3 -type d -name MoltenVK | head -1)
if [ -n "$mvk_src" ]; then
  if [ -d "$LIB/MoltenVK" ]; then
    mv "$LIB/MoltenVK" "$LIB/MoltenVK.bak-$stamp"
  fi
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
if [ "$current_bundle" = 1 ]; then
  [ -f "$LIB/MoltenVK/libMoltenVK.dylib" ] || { echo "installed bundle lacks MoltenVK" >&2; exit 1; }
  [ -f "$wine_unix/winemetal.so" ] || { echo "installed bundle lacks DXMT winemetal.so" >&2; exit 1; }
  [ -L "$wine_unix/libvulkan.1.dylib" ] || { echo "installed bundle lacks the MoltenVK symlink" >&2; exit 1; }
  log "bundle manifest and renderer files verified"
elif [ -e "$wine_unix/libvulkan.1.dylib" ] && [ -f "$wine_unix/winemetal.so" ]; then
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
