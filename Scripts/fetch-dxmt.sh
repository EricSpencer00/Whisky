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
# The fixes this stack needs are not in an upstream release yet, so point the
# script at a build that has them:
#
#   DXMT_TARBALL=/path/to/dxmt-builtin.tar.gz ./Scripts/fetch-dxmt.sh
#   DXMT_RUN_ID=<fork CI run> ./Scripts/fetch-dxmt.sh
#
# With neither, it takes the upstream release, and the Rockstar launcher and
# anything else presenting cross-process will not draw.

set -euo pipefail

DXMT_VERSION="${DXMT_VERSION:-v0.80}"
DXMT_URL="${DXMT_URL:-https://github.com/3Shain/dxmt/releases/download/${DXMT_VERSION}/dxmt-${DXMT_VERSION}-builtin.tar.gz}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

log() { printf '[dxmt] %s\n' "$*" >&2; }

mkdir -p "$WORK_DIR" "$OUT_DIR/DXMT"
tarball="${DXMT_TARBALL:-}"
if [ -n "$tarball" ]; then
  log "Using $tarball"
elif [ -n "${DXMT_RUN_ID:-}" ]; then
  tarball="$WORK_DIR/dxmt-run-${DXMT_RUN_ID}.tar.gz"
  if [ ! -f "$tarball" ]; then
    log "Downloading artifact from fork run $DXMT_RUN_ID"
    dl=$(mktemp -d)
    gh run download "$DXMT_RUN_ID" --repo EricSpencer00/dxmt --dir "$dl" --pattern 'dxmt-*'
    found=$(find "$dl" -name '*.tar.gz' | head -1)
    [ -n "$found" ] || { log "ERROR: no tarball in run $DXMT_RUN_ID"; exit 1; }
    cp "$found" "$tarball"
  fi
else
  tarball="$WORK_DIR/dxmt-${DXMT_VERSION}-builtin.tar.gz"
  if [ ! -f "$tarball" ]; then
    log "Downloading DXMT ${DXMT_VERSION} (upstream; without the fork fixes)"
    curl -fL --retry 3 --max-time 300 -o "$tarball.part" "$DXMT_URL"
    mv "$tarball.part" "$tarball"
  fi
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
