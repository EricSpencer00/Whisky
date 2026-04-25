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
  # winebuild calls bare 'dlltool' / 'lld-link' / 'ld' / 'windres' — put
  # triplet-free symlinks alongside the triplet-prefixed binaries.
  (
    cd "$dest/bin"
    for tool in dlltool windres ar nm objcopy ranlib strip lld-link; do
      [ -e "$tool" ] || [ ! -e "llvm-$tool" ] || ln -s "llvm-$tool" "$tool"
    done
    # lld is available as ld.lld; winebuild may invoke bare 'ld'
    [ ! -e ld ] && [ -e ld.lld ] && ln -s ld.lld ld
  )
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

  patch_source
}

# CrossOver's Mac graphics driver gates WineMetalLayer behind
# `#if defined(__x86_64__)` in d3dmetal_objc.h but uses it unconditionally in
# cocoa_window.m:985 (CW HACK 22435). On aarch64 this breaks the build with
# "use of undeclared identifier 'WineMetalLayer'". Drop the guard — the class
# is a trivial CAMetalLayer subclass and builds fine on aarch64.
patch_source() {
  local d="$WORK_DIR/src/wine/dlls/winemac.drv"
  for f in "$d/d3dmetal_objc.h" "$d/d3dmetal_objc.m" "$d/d3dmetal.c"; do
    [ -f "$f" ] || continue
    # Replace '#if defined(__x86_64__)' → '#if 1' and corresponding '#endif'
    # is harmless left in place.
    if grep -q 'defined(__x86_64__)' "$f"; then
      log "Patching $(basename $f) to also compile on aarch64"
      /usr/bin/sed -i.orig 's|#if defined(__x86_64__)|#if 1 /* was: defined(__x86_64__) — patched for aarch64 */|g' "$f"
    fi
  done

  # Hack 18311: prefer wined3d-vulkan on macOS so DXVK-style rendering is default.
  # Source: CrossOver 26.1.0 LGPL drop, dlls/wined3d/directx.c. LGPL-2.1+.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local hack18311="$script_dir/patches/hack-18311-wined3d-vulkan-default.patch"
  local wine_src="$WORK_DIR/src/wine"
  [ -d "$wine_src" ] || wine_src="$WORK_DIR/src/sources/wine"
  if [ -f "$hack18311" ] && [ -f "$wine_src/dlls/wined3d/directx.c" ]; then
    log "Applying Hack 18311 (wined3d-vulkan default on macOS)"
    if ( cd "$wine_src" && patch -p1 --forward --silent < "$hack18311" ); then
      :
    else
      log "WARN: Hack 18311 patch returned non-zero — may already be applied"
    fi
  else
    log "WARN: Hack 18311 patch or wined3d directx.c not found — skipping"
  fi
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

  # Match upstream Whisky's bundle exactly: x86_64-only Wine, runs via Rosetta 2
  # on Apple Silicon. Bundle layout produced is:
  #   bin/wine64, bin/wine64-preloader, bin/wineserver
  #   lib/wine/{i386-windows, x86_32on64-unix, x86_64-unix, x86_64-windows}
  # The aarch64,x86_64 multi-arch path was producing a broken stub bundle —
  # x86_64-unix backend was silently failing and the strip step was destroying
  # what little remained. Run the entire build under `arch -x86_64` so configure
  # auto-detects host=x86_64-apple-darwin.
  log "Configuring wine x86_64 (host build under Rosetta, $(sysctl -n hw.ncpu) cores)"
  (
    cd "$build64"
    arch -x86_64 "$src/configure" \
      --prefix="$prefix" \
      --enable-win64 \
      --disable-tests \
      --without-alsa --without-capi --without-dbus --without-inotify \
      --without-oss --without-pulse --without-udev --without-v4l2 --without-x \
      --without-opengl \
      --without-gnutls \
      --with-freetype --with-gstreamer --with-mingw \
      --with-vulkan --with-coreaudio
  )

  log "Building wine with $JOBS jobs (under Rosetta)"
  arch -x86_64 make -C "$build64" -j"$JOBS"

  log "Installing to $prefix"
  arch -x86_64 make -C "$build64" install

  # Wine 11 unified the `wine` and `wine64` launcher binaries. Whisky and most
  # tooling still expect `wine64`. If only `wine` exists, link it.
  if [ -x "$prefix/bin/wine" ] && [ ! -e "$prefix/bin/wine64" ]; then
    ln -sf wine "$prefix/bin/wine64"
  fi

  # Sanity-check the produced bundle. If wine64 is missing or absurdly small,
  # the build silently failed and we should NOT publish a release.
  local wine64_path="$prefix/bin/wine64"
  if [ ! -e "$wine64_path" ]; then
    log "ERROR: $wine64_path not produced by build — aborting"
    exit 1
  fi
  local wine64_size
  wine64_size=$(stat -f%z "$wine64_path" 2>/dev/null || stat -c%s "$wine64_path" 2>/dev/null || echo 0)
  if [ "$wine64_size" -lt 8000 ]; then
    log "ERROR: $wine64_path is suspiciously small ($wine64_size bytes) — likely a broken build"
    exit 1
  fi
  if [ ! -d "$prefix/lib/wine/x86_64-unix" ]; then
    log "ERROR: $prefix/lib/wine/x86_64-unix backend missing — broken build"
    exit 1
  fi
  if [ ! -e "$prefix/bin/wine64-preloader" ] && [ ! -e "$prefix/bin/wine-preloader" ]; then
    log "ERROR: wine-preloader not produced — required on macOS for address-space setup"
    exit 1
  fi
  log "Wine bundle sanity check OK: wine64=${wine64_size}B, x86_64-unix backend present, preloader present"

  # NOTE: Do NOT strip the binaries. Wine binaries on macOS rely on symbol
  # information for runtime resolution; strip -x corrupted prior bundles.
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

  # Fetch + bundle MoltenVK 1.4.1 universal so Wine's Vulkan loader can resolve
  # libMoltenVK.dylib at runtime without relying on a Homebrew install.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  log "Fetching MoltenVK"
  OUT_DIR="$OUT_DIR" WORK_DIR="$WORK_DIR" bash "$script_dir/fetch-moltenvk.sh"
  mkdir -p "$stage/Libraries/MoltenVK/icd.d"
  cp "$OUT_DIR/MoltenVK/libMoltenVK.dylib" "$stage/Libraries/MoltenVK/libMoltenVK.dylib"
  cp "$OUT_DIR/MoltenVK/icd.d/MoltenVK_icd.json" "$stage/Libraries/MoltenVK/icd.d/MoltenVK_icd.json"

  # Fetch + bundle DXVK 2.7.1 full DLL set (incl. dxgi.dll, missing from older Whisky).
  log "Fetching DXVK"
  OUT_DIR="$OUT_DIR" WORK_DIR="$WORK_DIR" bash "$script_dir/fetch-dxvk.sh"
  mkdir -p "$stage/Libraries/DXVK"
  cp -R "$OUT_DIR/DXVK"/* "$stage/Libraries/DXVK/"

  # Ad-hoc codesign so the unsigned wine binaries don't get SIGKILL'd by
  # macOS hardened runtime at launch. Users who have a Developer ID should
  # re-sign with their own identity after download; ad-hoc is enough for
  # the local-dev use case.
  log "Ad-hoc codesigning Unix-side binaries + libs"
  find "$stage/Libraries/Wine/bin" -type f -perm +111 -exec codesign --force --sign - {} + 2>/dev/null || true
  find "$stage/Libraries/Wine/lib/wine/x86_64-unix" -name '*.so' -exec codesign --force --sign - {} + 2>/dev/null || true
  find "$stage/Libraries/Wine/lib/wine/x86_32on64-unix" -name '*.so' -exec codesign --force --sign - {} + 2>/dev/null || true
  find "$stage/Libraries/Wine/lib" -maxdepth 2 -name '*.dylib' -exec codesign --force --sign - {} + 2>/dev/null || true

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
