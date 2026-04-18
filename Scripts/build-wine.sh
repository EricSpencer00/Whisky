#!/usr/bin/env bash
#
# build-wine.sh
#
# Builds a Whisky-compatible Wine bundle from CodeWeavers' LGPL-published
# CrossOver source tree. Produces a tarball named Libraries.tar.gz in ./out/
# whose internal layout matches what WhiskyWineInstaller.swift expects.
#
# Legal: CrossOver's Wine tree is distributed under the GNU LGPL v2.1+.
# This script downloads the upstream source, builds it, and produces a
# binary Wine. Both the source and the resulting binaries may be freely
# redistributed under the LGPL, provided the source is also made available.
# See LICENSE.md and CodeWeavers' source page for the canonical list of
# licenses.
#
# NOT covered by this script: Apple's Game Porting Toolkit (D3DMetal.framework).
# Apple's GPTK is distributed under a separate license that does NOT permit
# redistribution by third parties. If you want D3DMetal, download it yourself
# from Apple Developer or use Gcenx's tooling, and drop
#     Game\ Porting\ Toolkit.app/Contents/Resources/wine/lib/external/
# into $OUT_DIR/Wine/lib/external/ before packaging.

set -euo pipefail

# ---- configurable inputs ----
CROSSOVER_VERSION="${CROSSOVER_VERSION:-26.1.0}"
CROSSOVER_SRC_URL="${CROSSOVER_SRC_URL:-https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CROSSOVER_VERSION}.tar.gz}"

DXVK_VERSION="${DXVK_VERSION:-}"   # empty = skip DXVK; set e.g. '2.3' to bundle
DXVK_URL="${DXVK_URL:-}"

# Output locations
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ---- prerequisite check ----
require() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 — install via brew" >&2; exit 1; }
}
require curl
require tar
require make
require pkg-config
require xcrun

# ---- homebrew deps ----
# The Alex4386 gist (https://gist.github.com/Alex4386/4cce275760367e9f5e90e2553d655309)
# has the definitive CrossOver Mac build recipe. We replicate the essential
# dependency set here. Users on a fresh macOS will need:
BREW_DEPS=(
  bison
  flex
  gst-plugins-base
  freetype
  gnutls
  molten-vk
  pkgconf
  sdl2
  vulkan-headers
  vulkan-loader
)

# llvm-mingw (for aarch64 PE cross-compilation) is not in Homebrew core. We
# download mstorsjo's prebuilt bundle (~116 MB).
LLVM_MINGW_VERSION="${LLVM_MINGW_VERSION:-20260407}"
LLVM_MINGW_TARBALL="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-macos-universal.tar.xz"
LLVM_MINGW_URL="${LLVM_MINGW_URL:-https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${LLVM_MINGW_TARBALL}}"

check_brew() {
  command -v brew >/dev/null 2>&1 || {
    echo "Homebrew required. Install: https://brew.sh" >&2
    exit 1
  }
  local missing=()
  for p in "${BREW_DEPS[@]}"; do
    brew list --formula "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "Missing Homebrew deps: ${missing[*]}" >&2
    echo "Run: brew install ${missing[*]}" >&2
    exit 1
  fi
}

install_llvm_mingw() {
  local dest="$WORK_DIR/llvm-mingw"
  if [ -x "$dest/bin/aarch64-w64-mingw32-clang" ]; then
    log "llvm-mingw already present"
  else
    mkdir -p "$WORK_DIR"
    log "Downloading llvm-mingw ${LLVM_MINGW_VERSION}"
    curl -fL --retry 3 --max-time 600 -o "$WORK_DIR/$LLVM_MINGW_TARBALL" "$LLVM_MINGW_URL"
    log "Extracting llvm-mingw"
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xJf "$WORK_DIR/$LLVM_MINGW_TARBALL" -C "$dest" --strip-components=1
  fi
  export PATH="$dest/bin:$PATH"
  log "llvm-mingw in PATH: $(which aarch64-w64-mingw32-clang)"
}

# ---- fetch source ----
fetch_source() {
  local tarball="$WORK_DIR/crossover-sources-${CROSSOVER_VERSION}.tar.gz"
  mkdir -p "$WORK_DIR"
  if [ ! -f "$tarball" ]; then
    log "Downloading CrossOver ${CROSSOVER_VERSION} source (~150 MB)"
    curl -fL --retry 3 --max-time 900 -o "$tarball.part" "$CROSSOVER_SRC_URL"
    mv "$tarball.part" "$tarball"
  fi

  log "Extracting"
  rm -rf "$WORK_DIR/src"
  mkdir -p "$WORK_DIR/src"
  tar -xzf "$tarball" -C "$WORK_DIR/src" --strip-components=1
}

# ---- configure + build wine ----
build_wine() {
  local src="$WORK_DIR/src/sources/wine"
  local build64="$WORK_DIR/build-wine64"
  local prefix="$OUT_DIR/Wine"

  if [ ! -d "$src" ]; then
    # CrossOver source tree layout varies; try a couple common roots.
    for alt in "$WORK_DIR/src/wine" "$WORK_DIR/src"; do
      if [ -f "$alt/configure" ]; then src="$alt"; break; fi
    done
  fi
  if [ ! -f "$src/configure" ]; then
    log "ERROR: could not find wine configure script under $WORK_DIR/src"
    log "Layout of extracted tree:"
    find "$WORK_DIR/src" -maxdepth 3 -type d | head -30
    exit 1
  fi

  rm -rf "$build64" "$prefix"
  mkdir -p "$build64" "$prefix"

  # Use brew paths for ICU/GStreamer etc.
  export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
  local BREW_PREFIX
  BREW_PREFIX="$(brew --prefix)"
  export PKG_CONFIG_PATH="$BREW_PREFIX/opt/gstreamer/lib/pkgconfig:$BREW_PREFIX/opt/gst-plugins-base/lib/pkgconfig:$BREW_PREFIX/opt/freetype/lib/pkgconfig:$BREW_PREFIX/opt/vulkan-loader/lib/pkgconfig:$BREW_PREFIX/opt/molten-vk/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CFLAGS="-O2 -g -I$BREW_PREFIX/include"
  export LDFLAGS="-L$BREW_PREFIX/lib -L$BREW_PREFIX/opt/vulkan-loader/lib -L$BREW_PREFIX/opt/molten-vk/lib"

  log "Configuring wine64 ($(nproc 2>/dev/null || sysctl -n hw.ncpu) cores)"
  (
    cd "$build64"
    "$src/configure" \
      --prefix="$prefix" \
      --enable-win64 \
      --disable-tests \
      --without-alsa --without-capi --without-dbus --without-inotify \
      --without-oss --without-pulse --without-udev --without-v4l2 --without-x \
      --without-opengl \
      --with-freetype --with-gnutls --with-gstreamer --with-mingw \
      --with-vulkan --with-coreaudio
  )

  log "Building wine64 with $JOBS jobs"
  make -C "$build64" -j"$JOBS"

  log "Installing to $prefix"
  make -C "$build64" install

  # Strip to save space
  if command -v strip >/dev/null; then
    find "$prefix/bin" -type f -perm +111 -exec strip -x {} + 2>/dev/null || true
    find "$prefix/lib" -name "*.dylib" -exec strip -x {} + 2>/dev/null || true
  fi
}

# ---- package in Whisky Libraries layout ----
package() {
  local stage="$WORK_DIR/stage"
  rm -rf "$stage"
  mkdir -p "$stage/Libraries/Wine"

  cp -R "$OUT_DIR/Wine"/* "$stage/Libraries/Wine/"

  # WhiskyWineVersion.plist — a minimal plist that Whisky recognises
  cat > "$stage/Libraries/WhiskyWineVersion.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>version</key>
  <dict>
    <key>build</key><string>community</string>
    <key>major</key><integer>26</integer>
    <key>minor</key><integer>1</integer>
    <key>patch</key><integer>0</integer>
    <key>preRelease</key><string></string>
  </dict>
</dict>
</plist>
PLIST

  # DXVK and verbs.txt left as placeholder — community maintainers can populate
  mkdir -p "$stage/Libraries/DXVK"

  log "Creating Libraries.tar.gz"
  mkdir -p "$OUT_DIR"
  tar -czf "$OUT_DIR/Libraries.tar.gz" -C "$stage" Libraries
  log "Output: $OUT_DIR/Libraries.tar.gz ($(du -sh "$OUT_DIR/Libraries.tar.gz" | cut -f1))"
}

# ---- main ----
main() {
  check_brew
  install_llvm_mingw
  fetch_source
  build_wine
  package
  cat <<'DONE'

Wine built from CrossOver LGPL source. Next steps:

  1) Compute SHA256:
     shasum -a 256 out/Libraries.tar.gz
  2) Upload out/Libraries.tar.gz as a release asset on the fork.
  3) Point WhiskyWineInstaller.swift at the new URL and publish a release
     that matches WhiskyWineVersion.plist.

DONE
}

main "$@"
