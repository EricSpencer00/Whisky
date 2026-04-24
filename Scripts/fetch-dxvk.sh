#!/usr/bin/env bash
#
# fetch-dxvk.sh
#
# Download DXVK 2.7.1 and stage the full D3D DLL set (x64 + x32, including
# dxgi.dll — the missing piece in older Whisky bundles) under $OUT_DIR/DXVK/.
#
# Source: https://github.com/doitsujin/dxvk/releases/tag/v2.7.1
# License: zlib (DXVK itself) — redistributable.

set -euo pipefail

DXVK_VERSION="${DXVK_VERSION:-2.7.1}"
DXVK_URL="${DXVK_URL:-https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

log() { printf '[dxvk] %s\n' "$*" >&2; }

mkdir -p "$WORK_DIR" "$OUT_DIR/DXVK/x64" "$OUT_DIR/DXVK/x32"
tarball="$WORK_DIR/dxvk-${DXVK_VERSION}.tar.gz"
if [ ! -f "$tarball" ]; then
  log "Downloading DXVK ${DXVK_VERSION}"
  curl -fL --retry 3 --max-time 300 -o "$tarball.part" "$DXVK_URL"
  mv "$tarball.part" "$tarball"
fi

extract="$WORK_DIR/dxvk-extract"
rm -rf "$extract"
mkdir -p "$extract"
log "Extracting"
tar -xzf "$tarball" -C "$extract" --strip-components=1

for dll in d3d8.dll d3d9.dll d3d10core.dll d3d11.dll dxgi.dll; do
  for arch in x64 x32; do
    src="$extract/$arch/$dll"
    if [ ! -f "$src" ]; then
      log "ERROR: $arch/$dll missing from DXVK tarball"
      exit 1
    fi
    cp "$src" "$OUT_DIR/DXVK/$arch/$dll"
  done
done

log "Staged at $OUT_DIR/DXVK/ ($(du -sh "$OUT_DIR/DXVK" | cut -f1))"
