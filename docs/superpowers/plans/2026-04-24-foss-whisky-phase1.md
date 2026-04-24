# FOSS Whisky Phase 1 — Wine 11 + Hack 18311 + MoltenVK 1.4.1 + DXVK 2.7.1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the EricSpencer00/Whisky fork ship a fully open-source Wine/DXVK/MoltenVK stack that boots modern D3D11 Windows games (Steam → Portal 2 as acceptance) on Apple Silicon macOS 26, with zero dependency on CrossOver.app or Apple GPTK.

**Architecture:** Extend `Scripts/build-wine.sh` to (1) apply Hack 18311 from CrossOver 26.1.0 LGPL source to force `wined3d-vulkan` default on macOS, (2) download and bundle MoltenVK 1.4.1 universal dylib, (3) download and bundle DXVK 2.7.1 full DLL set (x64+x32, including dxgi). Teach the Swift side (`Wine.swift`, `WhiskyWineInstaller.swift`) about the new `MoltenVK/` and expanded `DXVK/` folders and inject `DYLD_FALLBACK_LIBRARY_PATH` / `VK_ICD_FILENAMES` at bottle launch. Produce a signed `Libraries.tar.gz` release asset hosted on the fork's GitHub releases; point Whisky at it via `WHISKY_WINE_BASE_URL`.

**Tech Stack:** Bash build pipeline, Swift/SwiftUI (WhiskyKit + Whisky app), Wine 11.0 from CrossOver LGPL source, DXVK 2.7.1 (Vulkan backend), MoltenVK 1.4.1 (Vulkan→Metal translation), llvm-mingw for PE cross-compilation, GitHub Actions CI, ad-hoc codesign for local-dev binaries.

---

## File Structure

**New files:**
- `Scripts/patches/hack-18311-wined3d-vulkan-default.patch` — the extracted Hack 18311 diff applied to `dlls/wined3d/directx.c`
- `Scripts/fetch-moltenvk.sh` — downloads MoltenVK 1.4.1 universal dylib and writes it to `$OUT_DIR/MoltenVK/`
- `Scripts/fetch-dxvk.sh` — downloads DXVK 2.7.1, extracts x64/x32 DLL sets into `$OUT_DIR/DXVK/`
- `WhiskyKit/Tests/WhiskyKitTests/BottleEnvironmentTests.swift` — XCTest suite verifying the new env vars

**Modified files:**
- `Scripts/build-wine.sh` — extend `patch_source()` to apply Hack 18311, call fetch scripts, bundle outputs into tarball
- `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift:29-32` — add `dxvkFolder`, `moltenvkFolder` static URLs
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:217-226` — `enableDXVK` copies `dxgi.dll` in addition to the d3d DLLs
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:229-241` — `constructWineEnvironment` prepends bundled MoltenVK to `DYLD_FALLBACK_LIBRARY_PATH` and exports `VK_ICD_FILENAMES`
- `.github/workflows/*.yml` — if present, update to drive the extended build script
- `docs/open-source-roadmap.md` — Phase 1 results row and next steps

---

## Task 1: Extract Hack 18311 patch from CrossOver source

**Files:**
- Create: `Scripts/patches/hack-18311-wined3d-vulkan-default.patch`

**Background:** Hack 18311 (CW-Bug-18311) changes `dlls/wined3d/directx.c` so that on macOS, `wined3d_select_feature_level()` prefers `wined3d_adapter_vk_create` over the D3DMetal-backed GL path, making DXVK-style Vulkan the default adapter.

- [ ] **Step 1: Fetch CrossOver 26.1.0 source and diff the upstream Wine 11.0 tree against it**

Run:
```bash
cd /tmp
curl -fL -o crossover-sources-26.1.0.tar.gz \
  https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.1.0.tar.gz
mkdir -p crossover-src && tar -xzf crossover-sources-26.1.0.tar.gz -C crossover-src --strip-components=1

git clone --depth 1 --branch wine-11.0 https://gitlab.winehq.org/wine/wine.git wine-11.0-upstream

# Locate the wine tree inside the crossover drop
find crossover-src -maxdepth 4 -type d -name 'wine' | head -5
```
Expected: a path like `crossover-src/sources/wine` or `crossover-src/wine` that contains `dlls/wined3d/directx.c`.

- [ ] **Step 2: Produce the minimal Hack 18311 diff**

Run:
```bash
# Replace CX_WINE with the path found in step 1
CX_WINE=crossover-src/sources/wine
diff -u "wine-11.0-upstream/dlls/wined3d/directx.c" "$CX_WINE/dlls/wined3d/directx.c" \
  | grep -A200 -B5 '18311' \
  | tee hack-18311-raw.patch
```
Expected: a hunk whose context includes the `CW-Bug-18311` comment CodeWeavers ships in their tree. If the grep is empty, widen: `diff -u ... | head -400` and inspect manually for the Mac adapter-selection change.

- [ ] **Step 3: Rewrite the raw diff as a clean patch file targeting `a/`/`b/` prefixes**

Create `/Users/eric/GitHub/Whisky/Scripts/patches/hack-18311-wined3d-vulkan-default.patch` with header:
```
# Hack 18311: force wined3d to prefer the Vulkan adapter on macOS.
#
# Source: CrossOver 26.1.0, dlls/wined3d/directx.c, CW-Bug-18311.
# Distributed under LGPL-2.1+ (same as Wine).
#
# Apply with:  cd <wine-src> && patch -p1 < hack-18311-wined3d-vulkan-default.patch

--- a/dlls/wined3d/directx.c
+++ b/dlls/wined3d/directx.c
<hunks from step 2, rewritten with a/b prefixes>
```
Write the body with the actual hunks — do not use placeholders; the engineer reads this patch file verbatim during the build.

- [ ] **Step 4: Verify the patch applies to a fresh Wine 11.0 checkout**

Run:
```bash
cd /tmp/wine-11.0-upstream
git reset --hard HEAD
git apply --check /Users/eric/GitHub/Whisky/Scripts/patches/hack-18311-wined3d-vulkan-default.patch
```
Expected: exit 0, no output. If it fails, inspect the offending hunk and realign line numbers.

- [ ] **Step 5: Commit**

```bash
cd /Users/eric/GitHub/Whisky
git add Scripts/patches/hack-18311-wined3d-vulkan-default.patch
git commit -m "Scripts: add extracted Hack 18311 patch for wined3d-vulkan default on macOS"
```

---

## Task 2: Wire Hack 18311 into `build-wine.sh`

**Files:**
- Modify: `Scripts/build-wine.sh:138-149` (the `patch_source()` function)

- [ ] **Step 1: Extend `patch_source()` to also apply Hack 18311**

Open `Scripts/build-wine.sh`. Replace the current `patch_source()` function (lines 138–149) with:
```bash
patch_source() {
  local d="$WORK_DIR/src/wine/dlls/winemac.drv"
  for f in "$d/d3dmetal_objc.h" "$d/d3dmetal_objc.m" "$d/d3dmetal.c"; do
    [ -f "$f" ] || continue
    if grep -q 'defined(__x86_64__)' "$f"; then
      log "Patching $(basename $f) to also compile on aarch64"
      /usr/bin/sed -i.orig 's|#if defined(__x86_64__)|#if 1 /* was: defined(__x86_64__) — patched for aarch64 */|g' "$f"
    fi
  done

  # Hack 18311: prefer wined3d-vulkan on macOS so DXVK-style rendering becomes default.
  local hack18311="$(pwd)/Scripts/patches/hack-18311-wined3d-vulkan-default.patch"
  local wine_src="$WORK_DIR/src/wine"
  [ -d "$wine_src" ] || wine_src="$WORK_DIR/src/sources/wine"
  if [ -f "$hack18311" ] && [ -d "$wine_src" ]; then
    log "Applying Hack 18311 (wined3d-vulkan default on macOS)"
    ( cd "$wine_src" && patch -p1 --forward --silent < "$hack18311" ) \
      || log "WARN: Hack 18311 already applied or failed — continuing"
  else
    log "WARN: Hack 18311 patch not found at $hack18311 — skipping"
  fi
}
```

- [ ] **Step 2: Smoke test the build locally up to the configure step**

Run:
```bash
cd /Users/eric/GitHub/Whisky
bash -n Scripts/build-wine.sh   # syntax check
```
Expected: exit 0. Then run a full `Scripts/build-wine.sh` in a scratch shell with `WORK_DIR=/tmp/wine-smoke OUT_DIR=/tmp/wine-out bash Scripts/build-wine.sh` and confirm the log line "Applying Hack 18311" appears before "Configuring wine".

- [ ] **Step 3: Commit**

```bash
git add Scripts/build-wine.sh
git commit -m "build-wine: apply Hack 18311 during patch_source stage"
```

---

## Task 3: MoltenVK 1.4.1 universal bundling

**Files:**
- Create: `Scripts/fetch-moltenvk.sh`
- Modify: `Scripts/build-wine.sh:213-255` (the `package()` function)

- [ ] **Step 1: Write `Scripts/fetch-moltenvk.sh`**

Create with content:
```bash
#!/usr/bin/env bash
# fetch-moltenvk.sh — download MoltenVK 1.4.1 universal dylib into $OUT_DIR/MoltenVK/.
# Source: https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.1
set -euo pipefail

MOLTENVK_VERSION="${MOLTENVK_VERSION:-1.4.1}"
MOLTENVK_URL="${MOLTENVK_URL:-https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-macos.tar}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

mkdir -p "$WORK_DIR" "$OUT_DIR/MoltenVK/icd.d"
tarball="$WORK_DIR/MoltenVK-macos-${MOLTENVK_VERSION}.tar"
if [ ! -f "$tarball" ]; then
  echo "Downloading MoltenVK ${MOLTENVK_VERSION}"
  curl -fL --retry 3 --max-time 600 -o "$tarball.part" "$MOLTENVK_URL"
  mv "$tarball.part" "$tarball"
fi

extract="$WORK_DIR/MoltenVK-extract"
rm -rf "$extract" && mkdir -p "$extract"
tar -xf "$tarball" -C "$extract"

dylib="$(find "$extract" -path '*/dynamic/dylib/macOS/libMoltenVK.dylib' -print -quit)"
icd_src="$(find "$extract" -path '*/dynamic/dylib/macOS/MoltenVK_icd.json' -print -quit)"
if [ -z "$dylib" ] || [ -z "$icd_src" ]; then
  echo "ERROR: could not locate libMoltenVK.dylib / MoltenVK_icd.json in $extract" >&2
  exit 1
fi

cp "$dylib" "$OUT_DIR/MoltenVK/libMoltenVK.dylib"
# Rewrite the ICD JSON so library_path is a relative sibling — the Swift side
# sets VK_ICD_FILENAMES to the absolute path of this file at bottle launch.
python3 - "$icd_src" "$OUT_DIR/MoltenVK/icd.d/MoltenVK_icd.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
data.setdefault("ICD", {})["library_path"] = "../libMoltenVK.dylib"
with open(dst, "w") as f:
    json.dump(data, f, indent=2)
PY

codesign --force --sign - "$OUT_DIR/MoltenVK/libMoltenVK.dylib" || true
echo "MoltenVK $MOLTENVK_VERSION staged at $OUT_DIR/MoltenVK/"
```
Then: `chmod +x Scripts/fetch-moltenvk.sh`.

- [ ] **Step 2: Invoke it from `build-wine.sh` `package()`**

In `Scripts/build-wine.sh`, modify `package()` (lines 213–255) so that immediately after the existing `mkdir -p "$stage/Libraries/Wine"` and before `mkdir -p "$stage/Libraries/DXVK"`, insert:
```bash
  log "Fetching MoltenVK"
  OUT_DIR="$OUT_DIR" WORK_DIR="$WORK_DIR" bash "$(pwd)/Scripts/fetch-moltenvk.sh"
  mkdir -p "$stage/Libraries/MoltenVK/icd.d"
  cp "$OUT_DIR/MoltenVK/libMoltenVK.dylib" "$stage/Libraries/MoltenVK/libMoltenVK.dylib"
  cp "$OUT_DIR/MoltenVK/icd.d/MoltenVK_icd.json" "$stage/Libraries/MoltenVK/icd.d/MoltenVK_icd.json"
```

- [ ] **Step 3: Verify the fetch script standalone**

Run:
```bash
cd /Users/eric/GitHub/Whisky
WORK_DIR=/tmp/mvk-work OUT_DIR=/tmp/mvk-out bash Scripts/fetch-moltenvk.sh
file /tmp/mvk-out/MoltenVK/libMoltenVK.dylib
```
Expected: `Mach-O universal binary with 2 architectures: [x86_64:...] [arm64:...]`.

- [ ] **Step 4: Commit**

```bash
git add Scripts/fetch-moltenvk.sh Scripts/build-wine.sh
git commit -m "build-wine: bundle MoltenVK 1.4.1 universal dylib + ICD into Libraries/MoltenVK"
```

---

## Task 4: DXVK 2.7.1 bundling (full DLL set including dxgi)

**Files:**
- Create: `Scripts/fetch-dxvk.sh`
- Modify: `Scripts/build-wine.sh` `package()` (same region as Task 3)

- [ ] **Step 1: Write `Scripts/fetch-dxvk.sh`**

Create with content:
```bash
#!/usr/bin/env bash
# fetch-dxvk.sh — download DXVK 2.7.1 and stage x64/x32 DLLs under $OUT_DIR/DXVK/.
set -euo pipefail

DXVK_VERSION="${DXVK_VERSION:-2.7.1}"
DXVK_URL="${DXVK_URL:-https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
WORK_DIR="${WORK_DIR:-$(pwd)/build/wine-build}"

mkdir -p "$WORK_DIR" "$OUT_DIR/DXVK/x64" "$OUT_DIR/DXVK/x32"
tarball="$WORK_DIR/dxvk-${DXVK_VERSION}.tar.gz"
if [ ! -f "$tarball" ]; then
  echo "Downloading DXVK ${DXVK_VERSION}"
  curl -fL --retry 3 --max-time 300 -o "$tarball.part" "$DXVK_URL"
  mv "$tarball.part" "$tarball"
fi

extract="$WORK_DIR/dxvk-extract"
rm -rf "$extract" && mkdir -p "$extract"
tar -xzf "$tarball" -C "$extract" --strip-components=1

for dll in d3d8.dll d3d9.dll d3d10core.dll d3d11.dll dxgi.dll; do
  cp "$extract/x64/$dll" "$OUT_DIR/DXVK/x64/$dll"
  cp "$extract/x32/$dll" "$OUT_DIR/DXVK/x32/$dll"
done
echo "DXVK $DXVK_VERSION staged at $OUT_DIR/DXVK/"
```
Then: `chmod +x Scripts/fetch-dxvk.sh`.

- [ ] **Step 2: Invoke it from `build-wine.sh` `package()`**

In `Scripts/build-wine.sh` `package()`, replace the placeholder `mkdir -p "$stage/Libraries/DXVK"` line with:
```bash
  log "Fetching DXVK"
  OUT_DIR="$OUT_DIR" WORK_DIR="$WORK_DIR" bash "$(pwd)/Scripts/fetch-dxvk.sh"
  mkdir -p "$stage/Libraries/DXVK"
  cp -R "$OUT_DIR/DXVK"/* "$stage/Libraries/DXVK/"
```

- [ ] **Step 3: Verify the fetch script standalone**

Run:
```bash
cd /Users/eric/GitHub/Whisky
WORK_DIR=/tmp/dxvk-work OUT_DIR=/tmp/dxvk-out bash Scripts/fetch-dxvk.sh
ls /tmp/dxvk-out/DXVK/x64 /tmp/dxvk-out/DXVK/x32
```
Expected: each directory contains `d3d8.dll d3d9.dll d3d10core.dll d3d11.dll dxgi.dll`.

- [ ] **Step 4: Commit**

```bash
git add Scripts/fetch-dxvk.sh Scripts/build-wine.sh
git commit -m "build-wine: bundle DXVK 2.7.1 full DLL set including dxgi.dll"
```

---

## Task 5: WhiskyKit — add MoltenVK + DXVK folder statics

**Files:**
- Modify: `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift:29-33`

- [ ] **Step 1: Write the failing test**

Create `/Users/eric/GitHub/Whisky/WhiskyKit/Tests/WhiskyKitTests/BottleEnvironmentTests.swift` with:
```swift
import XCTest
@testable import WhiskyKit

final class WhiskyWineInstallerPathsTests: XCTestCase {
    func testMoltenvkFolderUnderLibraryFolder() {
        let expected = WhiskyWineInstaller.libraryFolder.appending(path: "MoltenVK")
        XCTAssertEqual(WhiskyWineInstaller.moltenvkFolder.path, expected.path)
    }

    func testMoltenvkIcdPathPointsAtMoltenvkIcdJson() {
        XCTAssertTrue(
            WhiskyWineInstaller.moltenvkIcdPath.path.hasSuffix("MoltenVK/icd.d/MoltenVK_icd.json"),
            "Got \(WhiskyWineInstaller.moltenvkIcdPath.path)"
        )
    }

    func testDxvkFolderUnderLibraryFolder() {
        let expected = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
        XCTAssertEqual(WhiskyWineInstaller.dxvkFolder.path, expected.path)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/eric/GitHub/Whisky/WhiskyKit && swift test --filter WhiskyWineInstallerPathsTests`
Expected: FAIL with `value of type 'WhiskyWineInstaller.Type' has no member 'moltenvkFolder'`.

- [ ] **Step 3: Add the statics to `WhiskyWineInstaller`**

In `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift`, replace lines 29–33 (the existing `libraryFolder` + `binFolder` declarations) with:
```swift
    /// The folder of all the library files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    /// Folder containing the bundled universal `libMoltenVK.dylib` and `icd.d/MoltenVK_icd.json`.
    public static let moltenvkFolder: URL = libraryFolder.appending(path: "MoltenVK")

    /// Absolute path to the bundled MoltenVK ICD manifest — used as `VK_ICD_FILENAMES` at bottle launch.
    public static let moltenvkIcdPath: URL = moltenvkFolder
        .appending(path: "icd.d").appending(path: "MoltenVK_icd.json")

    /// Folder containing the DXVK DLL set: `x64/{d3d8,d3d9,d3d10core,d3d11,dxgi}.dll` and `x32/…`.
    public static let dxvkFolder: URL = libraryFolder.appending(path: "DXVK")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/eric/GitHub/Whisky/WhiskyKit && swift test --filter WhiskyWineInstallerPathsTests`
Expected: 3/3 PASS.

- [ ] **Step 5: Commit**

```bash
git add WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift \
        WhiskyKit/Tests/WhiskyKitTests/BottleEnvironmentTests.swift
git commit -m "WhiskyWineInstaller: expose moltenvkFolder + moltenvkIcdPath + dxvkFolder"
```

---

## Task 6: Wine.swift — copy dxgi.dll in `enableDXVK`

**Files:**
- Modify: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:217-226`

**Background:** `enableDXVK` currently copies every `.dll` from `DXVK/x64/` → `system32/` via `FileManager.replaceDLLs`. With the full DXVK 2.7.1 set on disk this already ships `dxgi.dll`, so the behavior gets stronger for free. The test below pins that behavior so a future refactor can't silently drop dxgi.

- [ ] **Step 1: Write the failing test**

Append to `WhiskyKit/Tests/WhiskyKitTests/BottleEnvironmentTests.swift`:
```swift
final class EnableDXVKCopiesDxgiTests: XCTestCase {
    func testEnableDXVKCopiesDxgiDllIntoSystem32() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "whisky-enable-dxvk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        let bottleURL = tmp.appending(path: "bottle")
        let sys32 = bottleURL.appending(path: "drive_c").appending(path: "windows").appending(path: "system32")
        try fm.createDirectory(at: sys32, withIntermediateDirectories: true)

        let dxvkSource = tmp.appending(path: "dxvk-src").appending(path: "x64")
        try fm.createDirectory(at: dxvkSource, withIntermediateDirectories: true)
        for name in ["d3d11.dll", "d3d10core.dll", "dxgi.dll"] {
            try Data("stub".utf8).write(to: dxvkSource.appending(path: name))
        }

        try fm.replaceDLLs(in: sys32, withContentsIn: dxvkSource)

        for name in ["d3d11.dll", "d3d10core.dll", "dxgi.dll"] {
            XCTAssertTrue(fm.fileExists(atPath: sys32.appending(path: name).path),
                          "\(name) not copied to system32")
        }
    }
}
```

- [ ] **Step 2: Run to verify baseline behavior**

Run: `cd /Users/eric/GitHub/Whisky/WhiskyKit && swift test --filter EnableDXVKCopiesDxgiTests`
Expected: PASS if `replaceDLLs` already copies every file in the source dir (it does today). If it FAILS with "file not copied", inspect `FileManager+Extensions.swift` and widen `replaceDLLs` to copy non-matching files too — but pause to ask first since that changes broader behavior.

- [ ] **Step 3: No code change needed if Step 2 passed; otherwise fix `replaceDLLs`**

Read `WhiskyKit/Sources/WhiskyKit/Extensions/FileManager+Extensions.swift`. If `replaceDLLs` only overwrites DLLs that already exist in the target, change it to instead copy every `.dll` in the source (overwriting) so new DXVK DLLs like `dxgi.dll` land in freshly-created bottles.

- [ ] **Step 4: Commit**

```bash
git add WhiskyKit/Tests/WhiskyKitTests/BottleEnvironmentTests.swift \
        WhiskyKit/Sources/WhiskyKit/Extensions/FileManager+Extensions.swift
git commit -m "Wine: ensure enableDXVK copies the full DXVK 2.7 DLL set incl. dxgi"
```

---

## Task 7: Wine.swift — inject MoltenVK into bottle launch environment

**Files:**
- Modify: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:229-241` (`constructWineEnvironment`)

**Background:** Wine 11 loads MoltenVK via the Vulkan loader's ICD lookup. We must (a) point the loader at our bundled ICD JSON via `VK_ICD_FILENAMES` and (b) put our bundled `libMoltenVK.dylib` on the dyld search path so the ICD can resolve it.

- [ ] **Step 1: Write the failing test**

Append to `BottleEnvironmentTests.swift`:
```swift
final class ConstructWineEnvironmentMoltenVKTests: XCTestCase {
    func testEnvironmentIncludesMoltenvkIcdAndDyldPath() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "whisky-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bottle = Bottle(bottleUrl: tmp, isActive: true, inFlight: false)
        let env = Wine.testableConstructWineEnvironment(for: bottle)

        XCTAssertEqual(env["VK_ICD_FILENAMES"], WhiskyWineInstaller.moltenvkIcdPath.path)
        let dyld = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
        XCTAssertTrue(dyld.contains(WhiskyWineInstaller.moltenvkFolder.path),
                      "DYLD_FALLBACK_LIBRARY_PATH did not include \(WhiskyWineInstaller.moltenvkFolder.path); got: \(dyld)")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/eric/GitHub/Whisky/WhiskyKit && swift test --filter ConstructWineEnvironmentMoltenVKTests`
Expected: FAIL with "has no member 'testableConstructWineEnvironment'" (and `VK_ICD_FILENAMES` would be nil even if it compiled).

- [ ] **Step 3: Update `constructWineEnvironment` and expose a test hook**

In `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` replace the private `constructWineEnvironment` (lines 229–241) with:
```swift
    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        let moltenvkDir = WhiskyWineInstaller.moltenvkFolder.path
        let existingDyld = ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
        let dyldPath = existingDyld.isEmpty
            ? "\(moltenvkDir):/usr/local/lib:/usr/lib"
            : "\(moltenvkDir):\(existingDyld)"

        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1",
            "VK_ICD_FILENAMES": WhiskyWineInstaller.moltenvkIcdPath.path,
            "DYLD_FALLBACK_LIBRARY_PATH": dyldPath
        ]
        bottle.settings.environmentVariables(wineEnv: &result)
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    #if DEBUG
    /// Test-only passthrough — do not call from production code.
    public static func testableConstructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        constructWineEnvironment(for: bottle, environment: environment)
    }
    #endif
```

Apply the same `DYLD_FALLBACK_LIBRARY_PATH` + `VK_ICD_FILENAMES` pair to `constructWineServerEnvironment` (lines 243–255) so wineserver child processes see MoltenVK too.

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/eric/GitHub/Whisky/WhiskyKit && swift test --filter ConstructWineEnvironmentMoltenVKTests`
Expected: PASS.

- [ ] **Step 5: Run the full WhiskyKit test suite for regressions**

Run: `cd /Users/eric/GitHub/Whisky/WhiskyKit && swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift \
        WhiskyKit/Tests/WhiskyKitTests/BottleEnvironmentTests.swift
git commit -m "Wine: inject bundled MoltenVK via VK_ICD_FILENAMES + DYLD_FALLBACK_LIBRARY_PATH"
```

---

## Task 8: Produce the FOSS `Libraries.tar.gz` release asset

**Files:**
- None changed — this task runs the pipeline

- [ ] **Step 1: Prerequisite check**

Run:
```bash
brew install bison flex gst-plugins-base freetype gnutls molten-vk pkgconf sdl2 vulkan-headers vulkan-loader
```
Expected: all installed or already present. (Skips when already present.)

- [ ] **Step 2: Full build**

Run:
```bash
cd /Users/eric/GitHub/Whisky
rm -rf build out
bash Scripts/build-wine.sh 2>&1 | tee /tmp/whisky-build.log
```
Expected (from the log tail):
```
Wine built from CrossOver LGPL source. Next steps:
  ...
Output: out/Libraries.tar.gz (~NN MB)
```

- [ ] **Step 3: Inspect the tarball layout**

Run:
```bash
tar -tzf out/Libraries.tar.gz | head -30
tar -tzf out/Libraries.tar.gz | grep -E 'MoltenVK|DXVK/(x64|x32)/dxgi|wine64$'
```
Expected: entries include `Libraries/Wine/bin/wine64`, `Libraries/MoltenVK/libMoltenVK.dylib`, `Libraries/MoltenVK/icd.d/MoltenVK_icd.json`, `Libraries/DXVK/x64/dxgi.dll`, `Libraries/DXVK/x32/dxgi.dll`.

- [ ] **Step 4: Record SHA256 and file size**

Run:
```bash
shasum -a 256 out/Libraries.tar.gz
ls -lh out/Libraries.tar.gz
```
Capture output; you'll paste it into the release description in the next task.

- [ ] **Step 5: Commit the build log (optional) and tag the release**

```bash
cd /Users/eric/GitHub/Whisky
git tag -a whisky-wine-26.1.0-foss-phase1 -m "Phase 1 FOSS build: Wine 11 + Hack 18311 + MoltenVK 1.4.1 + DXVK 2.7.1"
git push origin whisky-wine-26.1.0-foss-phase1
```

---

## Task 9: Publish the release on EricSpencer00/Whisky

**Files:**
- None (GitHub release metadata only)

- [ ] **Step 1: Create the release and upload the tarball**

Run:
```bash
cd /Users/eric/GitHub/Whisky
gh release create whisky-wine-26.1.0-foss-phase1 \
  out/Libraries.tar.gz \
  --title "Whisky Wine 26.1.0 FOSS Phase 1" \
  --notes "$(cat <<'EOF'
Full-FOSS Wine+DXVK+MoltenVK bundle.

Contents:
- Wine 11.0 built from CrossOver 26.1.0 LGPL source drop, with Hack 18311 applied (wined3d-vulkan default on macOS)
- MoltenVK 1.4.1 universal (x86_64 + arm64)
- DXVK 2.7.1 full DLL set (d3d8/9/10core/11 + dxgi, x64+x32)

Use with WHISKY_WINE_BASE_URL=https://github.com/EricSpencer00/Whisky/releases/download/whisky-wine-26.1.0-foss-phase1

SHA256 / size: fill in from Task 8 Step 4.
EOF
)"
```

- [ ] **Step 2: Verify the asset is downloadable**

Run: `curl -sfI https://github.com/EricSpencer00/Whisky/releases/download/whisky-wine-26.1.0-foss-phase1/Libraries.tar.gz | head -1`
Expected: `HTTP/2 200` or `HTTP/1.1 302 Found`.

- [ ] **Step 3: Publish the version plist alongside (so `shouldUpdateWhiskyWine` works)**

Create a tiny plist and upload it to the same release:
```bash
cat > /tmp/WhiskyWineVersion.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>version</key>
  <dict>
    <key>build</key><string>foss-phase1</string>
    <key>major</key><integer>26</integer>
    <key>minor</key><integer>1</integer>
    <key>patch</key><integer>0</integer>
    <key>preRelease</key><string></string>
  </dict>
</dict>
</plist>
PLIST
gh release upload whisky-wine-26.1.0-foss-phase1 /tmp/WhiskyWineVersion.plist
```

---

## Task 10: Build and launch the fork's Whisky.app against the new release

**Files:**
- None (Xcode build + runtime test)

- [ ] **Step 1: Build Whisky.app**

Run:
```bash
cd /Users/eric/GitHub/Whisky
xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Debug \
  -derivedDataPath build/xc \
  build | xcbeautify || true
```
Expected: exit 0. Binary at `build/xc/Build/Products/Debug/Whisky.app`.

- [ ] **Step 2: Launch pointing at the new release**

Run:
```bash
WHISKY_WINE_BASE_URL="https://github.com/EricSpencer00/Whisky/releases/download/whisky-wine-26.1.0-foss-phase1" \
  open -W ./build/xc/Build/Products/Debug/Whisky.app
```
In the Whisky UI: click through Setup, let it download `Libraries.tar.gz` from the overridden URL.

- [ ] **Step 3: Verify installed Wine version**

Run: `~/Library/Application\ Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64 --version`
Expected: `wine-11.0` (or `wine-11.0.1`).

- [ ] **Step 4: Verify MoltenVK is discoverable**

Run:
```bash
WINEPREFIX=/tmp/vk-test-prefix \
VK_ICD_FILENAMES=~/Library/Application\ Support/com.isaacmarovitz.Whisky/Libraries/MoltenVK/icd.d/MoltenVK_icd.json \
DYLD_FALLBACK_LIBRARY_PATH=~/Library/Application\ Support/com.isaacmarovitz.Whisky/Libraries/MoltenVK \
vulkaninfo --summary 2>&1 | grep -E 'apiVersion|deviceName|MoltenVK'
```
Expected: `apiVersion = 1.3.x` or `1.4.x`, `deviceName = Apple M1 Max` (or local equivalent), `driverName = MoltenVK`.

---

## Task 11: Acceptance test — Steam in a bottle, Portal 2 renders

**Files:**
- None (runtime test)

- [ ] **Step 1: Create a fresh bottle in Whisky**

Through the Whisky UI, click + to create a bottle. Name it `steam-foss`. Set Windows version = Windows 10.

- [ ] **Step 2: Install Steam**

Download the Steam installer (`https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe`). In the Whisky UI, use "Run…" on that installer inside the `steam-foss` bottle. Complete the installer.

- [ ] **Step 3: Launch Steam and install Portal 2**

Launch `C:\Program Files (x86)\Steam\Steam.exe` inside the bottle. Log in. Install Portal 2 (small, well-understood D3D11 workload, ~14 GB).

- [ ] **Step 4: Launch Portal 2**

Press Play in Steam. Wait up to 120 seconds for first-run compile.

Expected: Portal 2 main menu renders on-screen (not black, not hung). Controller enumeration may delay; skip to keyboard input if needed.

- [ ] **Step 5: Capture evidence**

Screenshot the main menu. Save to `docs/evidence/2026-04-24-portal2-foss-phase1.png`.

- [ ] **Step 6: Record the result**

Edit `docs/open-source-roadmap.md`. Add a new row to the "What we've tested empirically" table:
```
| EricSpencer00/Whisky foss-phase1 | 11.0+Hack18311 | DXVK 2.7.1 / MoltenVK 1.4.1 | ✓ | ✓ | First fully-FOSS renderer path that reaches Portal 2 menu |
```
Then under "Current playable state" replace "None on open source alone" with the new state.

- [ ] **Step 7: Commit**

```bash
cd /Users/eric/GitHub/Whisky
git add docs/open-source-roadmap.md docs/evidence/
git commit -m "docs: Phase 1 FOSS path reaches Portal 2 main menu on M1 Max / macOS 26"
```

---

## Task 12: CI for the Phase 1 build

**Files:**
- Create or modify: `.github/workflows/build-wine.yml`

- [ ] **Step 1: Inspect current CI**

Run:
```bash
ls /Users/eric/GitHub/Whisky/.github/workflows/
```
If a workflow for `build-wine.sh` already exists, modify it to also run `fetch-moltenvk.sh` + `fetch-dxvk.sh`. If not, create `.github/workflows/build-wine.yml`:
```yaml
name: build-wine
on:
  push:
    tags: ['whisky-wine-*']
  workflow_dispatch: {}

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v5
      - name: Install Homebrew deps
        run: brew install bison flex gst-plugins-base freetype gnutls molten-vk pkgconf sdl2 vulkan-headers vulkan-loader
      - name: Build Libraries.tar.gz
        run: bash Scripts/build-wine.sh
      - name: Upload artifact
        uses: actions/upload-artifact@v5
        with:
          name: Libraries
          path: out/Libraries.tar.gz
      - name: Attach to release
        if: startsWith(github.ref, 'refs/tags/whisky-wine-')
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release upload "${GITHUB_REF_NAME}" out/Libraries.tar.gz --clobber
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/build-wine.yml
git commit -m "CI: build+publish FOSS Libraries.tar.gz on whisky-wine-* tags"
git push origin main
```

- [ ] **Step 3: Verify CI runs**

Run: `gh run list --workflow build-wine.yml --limit 3`
Expected: a run in `completed` / `success` status for the latest push.

---

## Out of scope (defer to Phase 2 / 3)

- Per-game native `.app` bundles that auto-launch Steam into a specific title (Phase 3 ergonomics)
- BeamNG-specific Ultralight shared-texture fixes (Phase 2, tracked separately in `docs/beamng-runbook.md`)
- Controller HID enumeration patch for Mac USB devices (Phase 2)
- Notarized/Developer-ID signed Whisky.app builds (Phase 3)
- Automatic migration of existing bottles from the legacy `data.getwhisky.app` Wine to the new FOSS Wine

Each of those becomes its own spec + plan once Phase 1 is green.
