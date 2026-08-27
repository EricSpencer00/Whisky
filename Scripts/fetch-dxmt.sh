#!/usr/bin/env bash
#
# fetch-dxmt.sh
#
# Download the DXMT "builtin" tarball and stage it under $OUT_DIR/DXMT/.
#
# DXMT implements D3D11/D3D10 on Metal directly and reaches feature level 11_1
# here. wined3d over MoltenVK does not: Direct2D's DC render target fails to
# create, and the geometry-shader path is missing. It is LGPL-2.1-or-later, so
# it ships inside the bundle.
#
# DXMT_URL points at a fork build while the SwapDeviceContextState fix is
# unreleased upstream. Set it back to 3Shain/dxmt once that lands.

set -euo pipefail

DXMT_VERSION="${DXMT_VERSION:-v0.80}"
DXMT_URL="${DXMT_URL:-https://github.com/3Shain/dxmt/releases/download/${DXMT_VERSION}/dxmt-${DXMT_VERSION}-builtin.tar.gz}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

log() { printf '[dxmt] %s\n' "$*" >&2; }

mkdir -p "$WORK_DIR" "$OUT_DIR/DXMT"
tarball="$WORK_DIR/dxmt-${DXMT_VERSION}-builtin.tar.gz"
if [ ! -f "$tarball" ]; then
  log "Downloading DXMT ${DXMT_VERSION}"
  curl -fL --retry 3 --max-time 300 -o "$tarball.part" "$DXMT_URL"
  mv "$tarball.part" "$tarball"
fi

extract="$WORK_DIR/dxmt-extract"
rm -rf "$extract"; mkdir -p "$extract"
tar -xzf "$tarball" -C "$extract" --strip-components=1

for want in x86_64-windows/d3d11.dll x86_64-windows/dxgi.dll x86_64-unix/winemetal.so; do
  [ -f "$extract/$want" ] || { log "ERROR: $want missing from DXMT tarball"; exit 1; }
done

rm -rf "$OUT_DIR/DXMT"
cp -a "$extract" "$OUT_DIR/DXMT"
log "Staged at $OUT_DIR/DXMT/ ($(du -sh "$OUT_DIR/DXMT" | cut -f1))"
