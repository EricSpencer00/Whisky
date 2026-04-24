#!/usr/bin/env bash
#
# fetch-moltenvk.sh
#
# Download MoltenVK 1.4.1 universal dylib + ICD manifest into $OUT_DIR/MoltenVK/.
# Source: https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.1
# License: Apache-2.0.
#
# The Whisky fork bundles MoltenVK inside Libraries.tar.gz so Wine 11's Vulkan
# loader can find libMoltenVK.dylib at runtime via DYLD_FALLBACK_LIBRARY_PATH
# + VK_ICD_FILENAMES, without relying on a Homebrew install on the user's box.

set -euo pipefail

MOLTENVK_VERSION="${MOLTENVK_VERSION:-1.4.1}"
MOLTENVK_URL="${MOLTENVK_URL:-https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-macos.tar}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

log() { printf '[moltenvk] %s\n' "$*" >&2; }

mkdir -p "$WORK_DIR" "$OUT_DIR/MoltenVK/icd.d"
tarball="$WORK_DIR/MoltenVK-macos-${MOLTENVK_VERSION}.tar"
if [ ! -f "$tarball" ]; then
  log "Downloading MoltenVK ${MOLTENVK_VERSION}"
  curl -fL --retry 3 --max-time 600 -o "$tarball.part" "$MOLTENVK_URL"
  mv "$tarball.part" "$tarball"
fi

extract="$WORK_DIR/MoltenVK-extract"
rm -rf "$extract"
mkdir -p "$extract"
log "Extracting"
tar -xf "$tarball" -C "$extract"

dylib="$(find "$extract" -path '*/dynamic/dylib/macOS/libMoltenVK.dylib' -print -quit)"
icd_src="$(find "$extract" -path '*/dynamic/dylib/macOS/MoltenVK_icd.json' -print -quit)"

if [ -z "$dylib" ]; then
  log "ERROR: libMoltenVK.dylib not found. Layout of extract dir:"
  find "$extract" -maxdepth 5 -type f -name '*.dylib' -o -name '*.json' | head -20 >&2
  exit 1
fi
if [ -z "$icd_src" ]; then
  log "ERROR: MoltenVK_icd.json not found. Layout:"
  find "$extract" -maxdepth 5 -name '*.json' | head -20 >&2
  exit 1
fi

cp "$dylib" "$OUT_DIR/MoltenVK/libMoltenVK.dylib"

# Rewrite the ICD JSON so library_path is a relative sibling — the Swift side
# sets VK_ICD_FILENAMES to the absolute path of this file at bottle launch, and
# a relative library_path lets the bundled folder move (e.g. Application Support)
# without breaking the loader.
python3 - "$icd_src" "$OUT_DIR/MoltenVK/icd.d/MoltenVK_icd.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
data.setdefault("ICD", {})["library_path"] = "../libMoltenVK.dylib"
with open(dst, "w") as f:
    json.dump(data, f, indent=2)
PY

codesign --force --sign - "$OUT_DIR/MoltenVK/libMoltenVK.dylib" 2>/dev/null || true

log "Staged at $OUT_DIR/MoltenVK/ ($(du -sh "$OUT_DIR/MoltenVK" | cut -f1))"
