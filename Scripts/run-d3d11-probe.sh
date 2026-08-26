#!/usr/bin/env bash
#
# run-d3d11-probe.sh
#
# Builds Scripts/d3d11-probe.c and runs it in a Whisky bottle, so the D3D
# feature level a bundle actually exposes can be read directly instead of
# inferred from a game's log.
#
#   ./Scripts/run-d3d11-probe.sh probe             # measure the current bundle
#   ./Scripts/run-d3d11-probe.sh d3dmetal-install  # drop in CrossOver's D3DMetal
#   ./Scripts/run-d3d11-probe.sh d3dmetal-restore  # put the bundle back
#
# d3dmetal-install copies the D3DMetal PE + unixlib set out of an installed
# CrossOver 26.1.0, reproducing CrossOver's own layout. Three things have to be
# right or it silently falls back to wined3d, or crashes:
#
#   1. Both halves. The PE alone leaves the unixlib orphaned.
#   2. Same CrossOver as the LGPL source this Wine was built from. Apple's
#      GPTK 3.0 copy targets the Wine 8.0.1 unixlib ABI and aborts on
#      'ntdll.dll.__wine_unix_call'.
#   3. The unixlibs must be SYMLINKS to one libd3dshared.dylib, never copies.
#      CrossOver ships d3d11.so, dxgi.so, d3d12.so, atidxx64.so, nvapi64.so and
#      nvngx.so as symlinks to a single dylib. Copying them makes dyld load
#      independent images, each with its own gWin32Dispatch table; the PE half
#      initialises one copy and D3DMetal calls through the other's NULL slots,
#      faulting in InitSharedState with rip=0.
#
# No environment variable turns this on. CX_ACTIVE_GRAPHICS_BACKEND is set by
# CrossOver's closed cxcompatdb.so and is not needed here — a working CrossOver
# run does not have it in the environment either.
#
# Apple's GPTK licence does not permit redistribution, so nothing here is
# bundled; the files are read from the user's own CrossOver install.
#
# Verified on M1 Max / macOS 26: featurelevel=0xb100 (11_1), adapter
# 'AMD Compatibility Mode', Present() succeeds — matching CrossOver 26.1.0.

set -euo pipefail

WHISKY_LIBS="${WHISKY_LIBS:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine}"
CROSSOVER="${CROSSOVER:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
GPTK="$CROSSOVER/lib64/apple_gptk"
BUILD_DIR="${BUILD_DIR:-$(pwd)/build/d3d11-probe}"
MINGW_CC="${MINGW_CC:-x86_64-w64-mingw32-gcc}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

pick_bottle() {
  [ -n "${WINEPREFIX:-}" ] && { echo "$WINEPREFIX"; return; }
  local dir="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"
  local b
  b=$(ls -td "$dir"/*/ 2>/dev/null | head -1) || true
  [ -n "$b" ] || die "no bottle found; set WINEPREFIX"
  echo "${b%/}"
}

build_probe() {
  command -v "$MINGW_CC" >/dev/null 2>&1 || die "$MINGW_CC not found (brew install mingw-w64)"
  mkdir -p "$BUILD_DIR"
  "$MINGW_CC" -O1 -o "$BUILD_DIR/probe.exe" "$(dirname "$0")/d3d11-probe.c" \
    -ld3d11 -ldxgi -luuid -lgdi32
  log "built $BUILD_DIR/probe.exe"
}

cmd_probe() {
  build_probe
  local prefix; prefix=$(pick_bottle)
  log "bottle: $prefix"
  cp "$BUILD_DIR/probe.exe" "$prefix/drive_c/probe.exe"
  # The bottle must have real d3d11/dxgi in system32. Past DXVK/D3DMetal
  # experiments renamed them to .dxvk-bak / .d3dmetal-bak-* and left the prefix
  # unable to load d3d11 at all, which reads as a renderer bug but is not one.
  local sys32="$prefix/drive_c/windows/system32"
  if [ ! -f "$sys32/d3d11.dll" ] || [ ! -f "$sys32/dxgi.dll" ]; then
    log "d3d11.dll/dxgi.dll missing from system32 — running wineboot -u"
    WINEPREFIX="$prefix" WINEDEBUG=-all "$WHISKY_LIBS/bin/wine64" wineboot -u >/dev/null 2>&1
  fi
  # probe.exe exits 2 on a sub-11_0 level, which is a result, not a failure —
  # so capture first and let the caller read the printed level.
  local out
  out=$(WINEPREFIX="$prefix" WINEDEBUG="${WINEDEBUG:--all}" \
        "$WHISKY_LIBS/bin/wine64" 'C:\probe.exe' 2>&1 || true)
  echo "$out" | grep -E "^(device|swapchain|present) |^adapter=" || {
    echo "$out" | tail -20 >&2
    die "probe produced no result"
  }
}

GPTK_DLLS="d3d11 dxgi d3d12 atidxx64 nvapi64 nvngx"

cmd_d3dmetal_install() {
  [ -d "$GPTK" ] || die "no apple_gptk in $CROSSOVER (need CrossOver 26.1.0 installed)"
  local w="$WHISKY_LIBS/lib/wine" prefix ts
  prefix=$(pick_bottle); ts=$(date +%s)

  # libd3dshared and the framework go next to the unixlibs: the unixlib links
  # @rpath/libd3dshared.dylib with an LC_RPATH of @loader_path, and
  # libd3dshared dlopens @rpath/D3DMetal.framework/D3DMetal from there.
  cp "$GPTK/external/libd3dshared.dylib" "$w/x86_64-unix/"
  rm -rf "$w/x86_64-unix/D3DMetal.framework"
  cp -R "$GPTK/external/D3DMetal.framework" "$w/x86_64-unix/"

  for n in $GPTK_DLLS; do
    [ -f "$GPTK/wine/x86_64-windows/$n.dll" ] || continue
    cp -n "$w/x86_64-windows/$n.dll" "$w/x86_64-windows/$n.dll.bak-$ts" 2>/dev/null || true
    cp -n "$prefix/drive_c/windows/system32/$n.dll" \
          "$prefix/drive_c/windows/system32/$n.dll.bak-$ts" 2>/dev/null || true
    cp "$GPTK/wine/x86_64-windows/$n.dll" "$w/x86_64-windows/$n.dll"
    cp "$GPTK/wine/x86_64-windows/$n.dll" "$prefix/drive_c/windows/system32/$n.dll"
    # Symlink, not copy — see the header. One dylib, one set of globals.
    rm -f "$w/x86_64-unix/$n.so"
    ln -s libd3dshared.dylib "$w/x86_64-unix/$n.so"
  done
  log "installed $GPTK_DLLS; backups tagged .bak-$ts"
}

cmd_d3dmetal_restore() {
  local w="$WHISKY_LIBS/lib/wine" prefix bak
  prefix=$(pick_bottle)
  for n in $GPTK_DLLS; do
    bak=$(ls -t "$w/x86_64-windows/$n.dll.bak-"* 2>/dev/null | head -1) || true
    [ -n "$bak" ] && cp "$bak" "$w/x86_64-windows/$n.dll" && log "restored $n.dll"
    bak=$(ls -t "$prefix/drive_c/windows/system32/$n.dll.bak-"* 2>/dev/null | head -1) || true
    [ -n "$bak" ] && cp "$bak" "$prefix/drive_c/windows/system32/$n.dll"
    rm -f "$w/x86_64-unix/$n.so"
  done
  rm -f "$w/x86_64-unix/libd3dshared.dylib"
  rm -rf "$w/x86_64-unix/D3DMetal.framework"
  log "restored"
}

case "${1:-probe}" in
  probe)            cmd_probe ;;
  d3dmetal-install) cmd_d3dmetal_install ;;
  d3dmetal-restore) cmd_d3dmetal_restore ;;
  *) die "usage: $0 {probe|d3dmetal-install|d3dmetal-restore}" ;;
esac
