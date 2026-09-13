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
# SHA256 of dxvk-<version>.tar.gz, one line per pinned version. Add a line when
# you move DXVK_VERSION. A version that is not listed downloads with a warning
# and no check.
DXVK_SHA256SUMS="\
2.7.1 d85ce7c79f57ecd765aaa1b9e7007cb875e6fde9f6d331df799bce73d513ce87
"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

log() { printf '[dxvk] %s\n' "$*" >&2; }

# Refuse a tarball whose SHA256 does not match the pin. An empty pin means the
# artifact is not pinned, so warn and continue.
verify_sha256() {
  local file="$1" want="$2" got
  if [ -z "$want" ]; then
    log "WARNING: $(basename "$file") is not pinned, skipping checksum"
    return 0
  fi
  got=$(shasum -a 256 "$file" | cut -d' ' -f1)
  [ "$got" = "$want" ] || {
    log "ERROR: SHA256 mismatch for $file"
    log "  want $want"
    log "  got  $got"
    exit 1
  }
  log "SHA256 ok"
}

mkdir -p "$WORK_DIR" "$OUT_DIR/DXVK/x64" "$OUT_DIR/DXVK/x32"
tarball="$WORK_DIR/dxvk-${DXVK_VERSION}.tar.gz"
if [ ! -f "$tarball" ]; then
  log "Downloading DXVK ${DXVK_VERSION}"
  curl -fL --retry 3 --max-time 300 -o "$tarball.part" "$DXVK_URL"
  mv "$tarball.part" "$tarball"
fi
want_sha=$(printf '%s' "$DXVK_SHA256SUMS" | awk -v v="$DXVK_VERSION" '$1 == v { print $2 }')
# DXVK_SHA256= (empty) skips the check, for a custom DXVK_URL.
verify_sha256 "$tarball" "${DXVK_SHA256-$want_sha}"

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
