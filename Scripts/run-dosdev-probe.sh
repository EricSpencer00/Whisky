#!/usr/bin/env bash
#
# Builds and runs Scripts/dosdev-probe.c in a Whisky bottle.
#
# Exit 0  = enumeration advances and GetLogicalDrives returns (bundle is good).
# Exit 2  = hung, which is the BOOLEAN syscall-argument bug.
# Exit 1  = the probe could not run.
#
# The probe dirties the stack before each call, so the result is the same every
# run rather than depending on what the stack happened to hold. Verified 3/3
# hung against an unpatched ntdll and 3/3 pass against a patched one.
set -euo pipefail

MINGW_CC="${MINGW_CC:-x86_64-w64-mingw32-gcc}"
WHISKY_LIBS="${WHISKY_LIBS:-$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine}"
BUILD_DIR="${BUILD_DIR:-$(pwd)/build/dosdev-probe}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prefix="${1:-}"
if [ -z "$prefix" ]; then
  prefix=$(ls -td "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"/*/ 2>/dev/null | head -1)
fi
[ -d "$prefix" ] || { echo "no bottle found; pass one as \$1" >&2; exit 1; }

mkdir -p "$BUILD_DIR"
"$MINGW_CC" -O1 -Wall -o "$BUILD_DIR/dosdev-probe.exe" "$script_dir/dosdev-probe.c" -lntdll
cp "$BUILD_DIR/dosdev-probe.exe" "$prefix/drive_c/dosdev-probe.exe"

export WINEPREFIX="$prefix"
export WINEDEBUG="${WINEDEBUG:--all}"
export DYLD_FALLBACK_LIBRARY_PATH="$WHISKY_LIBS/lib:$WHISKY_LIBS/lib/external:/usr/local/lib:/usr/lib"

out=$("$WHISKY_LIBS/bin/wine64" 'C:\dosdev-probe.exe' 2>/dev/null | grep '^###' || true)
"$WHISKY_LIBS/bin/wineserver" -k >/dev/null 2>&1 || true

echo "$out"
case "$out" in
  *PASS*) exit 0 ;;
  *HUNG*) echo "FAIL: hung — this bundle has the BOOLEAN syscall-argument bug" >&2; exit 2 ;;
  *)      echo "FAIL: probe did not run" >&2; exit 1 ;;
esac
