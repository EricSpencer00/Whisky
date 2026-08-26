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
# d3dmetal-install copies the D3DMetal d3d11/dxgi PE + unixlib pair out of an
# installed CrossOver 26.1.0. Both halves are required: the PE alone loads and
# silently falls through to wined3d. The pair must come from the same CrossOver
# whose LGPL source built this Wine — Apple's GPTK 3.0 copy is built against the
# Wine 8.0.1 unixlib ABI and aborts on 'ntdll.dll.__wine_unix_call'.
#
# Apple's GPTK licence does not permit redistribution, so nothing here is
# bundled; the files are read from the user's own CrossOver install.
#
# Status: the drop-in gets D3DMetal.framework mapped into the process, then
# D3D11CreateDevice faults on a NULL host callback. See docs/open-source-roadmap.md.

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
    -ld3d11 -ldxgi -luuid
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
  echo "$out" | grep -E "D3D11CreateDevice|adapter=" || {
    echo "$out" | tail -20 >&2
    die "probe produced no result"
  }
}

cmd_d3dmetal_install() {
  [ -d "$GPTK" ] || die "no apple_gptk in $CROSSOVER (need CrossOver 26.1.0 installed)"
  local w="$WHISKY_LIBS/lib/wine" prefix ts
  prefix=$(pick_bottle); ts=$(date +%s)
  for f in d3d11.dll dxgi.dll; do
    cp -n "$w/x86_64-windows/$f" "$w/x86_64-windows/$f.bak-$ts" || true
    cp -n "$prefix/drive_c/windows/system32/$f" \
          "$prefix/drive_c/windows/system32/$f.bak-$ts" || true
    cp "$GPTK/wine/x86_64-windows/$f" "$w/x86_64-windows/$f"
    cp "$GPTK/wine/x86_64-windows/$f" "$prefix/drive_c/windows/system32/$f"
  done
  cp "$GPTK/wine/x86_64-unix/d3d11.so" "$GPTK/wine/x86_64-unix/dxgi.so" "$w/x86_64-unix/"
  # libd3dshared and the framework must sit next to the unixlibs: d3d11.so
  # links @rpath/libd3dshared.dylib with an LC_RPATH of @loader_path, and
  # libd3dshared dlopens @rpath/D3DMetal.framework/D3DMetal from there.
  cp "$GPTK/external/libd3dshared.dylib" "$w/x86_64-unix/"
  rm -rf "$w/x86_64-unix/D3DMetal.framework"
  cp -R "$GPTK/external/D3DMetal.framework" "$w/x86_64-unix/"
  log "installed; backups tagged .bak-$ts"
  cat >&2 <<EOF

Run the probe with the backend switched on:

  CX_GRAPHICS_BACKEND=d3dmetal CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal \\
  CX_APPLEGPTK_LIBD3DSHARED_PATH="$w/x86_64-unix/libd3dshared.dylib" \\
  $0 probe
EOF
}

cmd_d3dmetal_restore() {
  local w="$WHISKY_LIBS/lib/wine" prefix bak
  prefix=$(pick_bottle)
  for f in d3d11.dll dxgi.dll; do
    bak=$(ls -t "$w/x86_64-windows/$f.bak-"* 2>/dev/null | head -1) || true
    [ -n "$bak" ] && cp "$bak" "$w/x86_64-windows/$f" && log "restored $f"
    bak=$(ls -t "$prefix/drive_c/windows/system32/$f.bak-"* 2>/dev/null | head -1) || true
    [ -n "$bak" ] && cp "$bak" "$prefix/drive_c/windows/system32/$f"
  done
  rm -f "$w/x86_64-unix/d3d11.so" "$w/x86_64-unix/dxgi.so" \
        "$w/x86_64-unix/libd3dshared.dylib"
  rm -rf "$w/x86_64-unix/D3DMetal.framework"
  log "restored"
}

case "${1:-probe}" in
  probe)            cmd_probe ;;
  d3dmetal-install) cmd_d3dmetal_install ;;
  d3dmetal-restore) cmd_d3dmetal_restore ;;
  *) die "usage: $0 {probe|d3dmetal-install|d3dmetal-restore}" ;;
esac
