# Maintaining this fork

Upstream [Whisky-App/Whisky](https://github.com/Whisky-App/Whisky) was archived on
**2025-05-11** and the original maintainer [endorsed CrossOver](https://docs.getwhisky.app/maintenance-notice).
This fork (`EricSpencer00/Whisky`) is a community-maintenance continuation: keep
the app compiling on current macOS and Xcode, keep the bundled Wine/GPTK in
pace with [Gcenx's releases](https://github.com/Gcenx/game-porting-toolkit), and
accept targeted bug fixes. No promises about parity with commercial tools like
CrossOver.

## Build

Prereqs on macOS 26 / Apple Silicon:

```
xcode-select -p                # Xcode 26+ required
brew install swiftlint          # used by project's build phase
```

Then:

```
git clone https://github.com/EricSpencer00/Whisky.git
cd Whisky
xcodebuild \
  -scheme Whisky \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./build \
  build
```

The app lands at `build/Build/Products/Debug/Whisky.app` (~16 MB, unsigned —
macOS will prompt with a Gatekeeper warning; either sign with your own
Developer ID or run via `xattr -dr com.apple.quarantine Whisky.app`).

### What had to change to build on macOS 26 / Xcode 26 / Swift 6.2

- `.swiftlint.yml` — expand `excluded:` to cover `build` and `build/SourcePackages`.
  The project's "SwiftLint" build phase runs `swiftlint --strict` against
  everything under the current working directory, including SPM-fetched source
  in `build/SourcePackages/checkouts/Sparkle/*` which does not match Whisky's
  file-header rule and hits many force-unwrap / trailing-comma / syntactic-sugar
  violations. Narrowing the lint scope fixes the build without lowering
  strictness on first-party code.

## Runtime Wine / GPTK

Whisky downloads its bundled Wine from `https://data.getwhisky.app/Wine/Libraries.tar.gz`
on first run. The default-served version (`WhiskyWineVersion.plist` → `2.5.0`)
bundles Wine 7.7 + D3DMetal 2.0 (GPTK 1.x). For newer titles that want the
D3DMetal 3.0 runtime, the hand-swap recipe is at
[docs/gptk-3-swap-experiment.md](docs/gptk-3-swap-experiment.md).

### Open-source-from-source story (CrossOver LGPL)

CodeWeavers publishes the Wine tree that underlies CrossOver as LGPL source —
see [their source page](https://www.codeweavers.com/crossover/source). This
fork uses that directly:

- [`Scripts/build-wine.sh`](Scripts/build-wine.sh) fetches
  `crossover-sources-<ver>.tar.gz` from `media.codeweavers.com`, builds Wine
  with the Homebrew cross-compile toolchain, and packages the result in the
  same `Libraries/` layout that `WhiskyWineInstaller` expects. Output lands in
  `out/Libraries.tar.gz`.
- [`.github/workflows/BuildWine.yml`](.github/workflows/BuildWine.yml) runs
  that script on a `macos-15` runner, triggered manually
  (`gh workflow run BuildWine.yml`) or by pushing a `wine-vX.Y.Z` tag, and
  publishes the tarball + SHA-256 as a release asset on this fork.
- `WhiskyWineInstaller.swift` reads `WHISKY_WINE_BASE_URL` from the process
  environment. Set that to the fork's release URL (e.g.
  `https://github.com/EricSpencer00/Whisky/releases/download/wine-v26.1.0`)
  to pull the FOSS-built tarball instead of the upstream CDN.

**Not bundled, and intentionally so**: Apple's Game Porting Toolkit
(`D3DMetal.framework`). Apple's GPTK license does not permit third-party
redistribution. Users who want D3DMetal drop it into
`$LIBRARIES/Wine/lib/external/` themselves. The build script documents the
exact path.

## CI

A minimal GitHub Actions build workflow is configured at
`.github/workflows/Build.yml` — runs on every push + PR, builds Whisky.app on
a macOS-15 runner, uploads the unsigned .app as an artifact. The original
SwiftLint workflow is preserved.

## Scope

This fork will accept:

- Build / xcodebuild fixes against newer Xcode / Swift / macOS SDKs.
- Wine/GPTK bundle bumps when a newer Gcenx GPTK ships.
- Targeted bug fixes with a clear repro and a test path.
- Documentation updates (README, build notes, troubleshooting).

This fork will NOT take on:

- Feature parity with CrossOver.
- A full rewrite against newer Wine source.
- Gatekeeper-signed releases (users must sign with their own Developer ID or
  use `xattr -dr com.apple.quarantine`).

## How to contribute

1. Fork this repo, branch off `main`.
2. Build and run the fix locally (`xcodebuild` per the steps above).
3. Verify that your change doesn't break lint (`swiftlint --strict` in the
   repo root, excluding `build/` per the checked-in `.swiftlint.yml`).
4. PR against `main`. Include:
   - What broke / what you're changing and why.
   - macOS + Xcode versions you tested on.
   - For bundle bumps, the Gcenx GPTK tag you pulled from.
