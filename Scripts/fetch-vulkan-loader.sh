#!/usr/bin/env bash
#
# fetch-vulkan-loader.sh
#
# Builds (or harvests) a universal libvulkan.1.dylib (x86_64 + arm64)
# and drops it into out/MoltenVK/ alongside libMoltenVK.dylib so the
# packaged Libraries.tar.gz has the complete Vulkan stack.
#
# Why this exists:
#   Wine 11's winevulkan.so dlopens libvulkan.1.dylib at process startup
#   to find the Vulkan loader. MoltenVK alone is not enough — it is the
#   ICD (driver), not the loader. Without libvulkan.1.dylib present:
#       err:vulkan:vulkan_init_once Failed to load libvulkan.1.dylib
#       err:vulkan:init_vulkan Failed to load Wine graphics driver
#                              supporting Vulkan.
#   …and the wined3d-vulkan path (the whole point of Hack 18311) never
#   activates. Both DXVK and Wine's builtin d3d11 fall back to GL or
#   refuse to initialize. Phase 1l shipped without this and is the
#   reason "Libraries.broken-fossphase1" backups exist in users' Whisky
#   data directories.
#
# Source: https://github.com/KhronosGroup/Vulkan-Loader (Apache 2.0).
#
# Strategy:
#   1. If x86_64 brew (/usr/local) and arm64 brew (/opt/homebrew) both
#      have vulkan-loader installed, lipo their dylibs into a universal
#      binary. This is the fast path on a developer machine that already
#      has both Homebrews set up (as the build-wine.sh prerequisites
#      require for symmetry with the FOSS Wine build).
#   2. Otherwise build from source via cmake with
#      -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64". Pin to the v1.4.341 tag
#      to match the headers shipped with this fork's Wine 11 build.
#
# License: this script is Apache-2.0; the produced binary is Apache-2.0
# (Vulkan-Loader's license). Both compatible with Whisky's GPLv3+.

set -euo pipefail

VULKAN_LOADER_VERSION="${VULKAN_LOADER_VERSION:-v1.4.341}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

log() { printf '[vulkan-loader] %s\n' "$*" >&2; }

mkdir -p "$OUT_DIR/MoltenVK" "$WORK_DIR"

# --- Fast path: harvest from dual Homebrew install -------------------------
ARM_LOADER="$(/usr/bin/find /opt/homebrew/Cellar/vulkan-loader -maxdepth 4 \
  -name 'libvulkan.1.*.dylib' -type f 2>/dev/null | head -1)"
X86_LOADER="$(/usr/bin/find /usr/local/Cellar/vulkan-loader -maxdepth 4 \
  -name 'libvulkan.1.*.dylib' -type f 2>/dev/null | head -1)"

if [ -n "$ARM_LOADER" ] && [ -n "$X86_LOADER" ]; then
  log "Found arm64 loader at $ARM_LOADER"
  log "Found x86_64 loader at $X86_LOADER"
  log "Combining into universal binary at $OUT_DIR/MoltenVK/libvulkan.1.dylib"
  /usr/bin/lipo -create "$ARM_LOADER" "$X86_LOADER" \
    -output "$OUT_DIR/MoltenVK/libvulkan.1.dylib"
  /usr/bin/file "$OUT_DIR/MoltenVK/libvulkan.1.dylib"
  exit 0
fi

# --- Build from source -----------------------------------------------------
log "Dual-Homebrew not available; building Vulkan-Loader $VULKAN_LOADER_VERSION from source"

require() { command -v "$1" >/dev/null 2>&1 || {
  echo "missing: $1 — install via brew" >&2; exit 1
}; }
require git
require cmake
require python3

src="$WORK_DIR/Vulkan-Loader"
if [ ! -d "$src" ]; then
  log "Cloning Vulkan-Loader at $VULKAN_LOADER_VERSION"
  git clone --depth 1 --branch "$VULKAN_LOADER_VERSION" \
    https://github.com/KhronosGroup/Vulkan-Loader.git "$src"
fi

cd "$src"

if [ ! -d external/Vulkan-Headers ]; then
  log "Fetching matching Vulkan-Headers"
  python3 scripts/update_deps.py --dir external
fi

# Build each arch separately and lipo together — Vulkan-Loader's universal
# CMake support is flaky around generated dispatch tables. Per-arch builds
# avoid the "unknown type name PFN_*ARM" duplicate-symbol errors.
for arch in x86_64 arm64; do
  log "Building libvulkan ($arch)"
  rm -rf "build-$arch"
  cmake -S . -B "build-$arch" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DUPDATE_DEPS=OFF \
    -DBUILD_TESTS=OFF \
    >/dev/null
  cmake --build "build-$arch" --config Release -j"$(/usr/sbin/sysctl -n hw.ncpu)" >/dev/null
done

LIB_X86="$(/usr/bin/find "$src/build-x86_64" -name 'libvulkan.1.*.dylib' -type f | head -1)"
LIB_ARM="$(/usr/bin/find "$src/build-arm64" -name 'libvulkan.1.*.dylib' -type f | head -1)"

log "Combining into universal binary at $OUT_DIR/MoltenVK/libvulkan.1.dylib"
/usr/bin/lipo -create "$LIB_X86" "$LIB_ARM" \
  -output "$OUT_DIR/MoltenVK/libvulkan.1.dylib"
/usr/bin/file "$OUT_DIR/MoltenVK/libvulkan.1.dylib"
