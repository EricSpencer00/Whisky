# Using the FOSS Wine bundle

This fork ships a fully open-source Wine bundle built from CodeWeavers'
LGPL-published CrossOver source via [`Scripts/build-wine.sh`](../Scripts/build-wine.sh)
and the [`BuildWine`](../.github/workflows/BuildWine.yml) GitHub Actions
workflow. Releases are tagged `wine-vX.Y.Z` and ship a `Libraries.tar.gz`
that drops in as a replacement for the archived upstream's CDN at
`data.getwhisky.app/Wine/Libraries.tar.gz`.

## What's in the bundle

- **Wine 11.0** — built from CrossOver 26.1.0 source under Rosetta 2,
  layout matches upstream Whisky exactly (`bin/wine64`,
  `bin/wine64-preloader`, `bin/wineserver`, `lib/wine/{i386-windows,
  x86_32on64-unix, x86_64-unix, x86_64-windows}/`).
- **MoltenVK 1.4.1** universal (x86_64 + arm64) at `lib/external/`,
  advertising Vulkan 1.4 — clears DXVK 2.7.1's Vulkan 1.3 minimum.
- **DXVK 2.7.1** D3D8/9/10/11 + DXGI DLLs at `lib/external/dxvk/`.

What's NOT bundled:
- **Apple's GPTK / D3DMetal.framework** — Apple's license forbids
  third-party redistribution. Drop it yourself into
  `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external/`
  if you need the D3D-on-Metal backend instead of DXVK.
- **gnutls / schannel SSL** — disabled in the current build because the
  CI runner's ARM64 brew can't link an x86_64 build. Steam HTTPS and
  any Windows app using SChannel will fall back to OpenSSL or fail.
  Tracked as a follow-up — re-enabled by installing x86_64 brew at
  `/usr/local` in CI alongside ARM brew.

## Pointing Whisky at this bundle

Set `WHISKY_WINE_BASE_URL` before launching Whisky.app for the first
time (or before deleting `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/`
to force re-bootstrap):

```sh
export WHISKY_WINE_BASE_URL="https://github.com/EricSpencer00/Whisky/releases/download/wine-v26.1.0-foss-phase1"
open -a Whisky
```

Whisky will fetch `$WHISKY_WINE_BASE_URL/Libraries.tar.gz` instead of
the upstream CDN. The override is read at
[`WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift`](../WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift).

If you already have a working Whisky install and want to swap in the
FOSS bundle without losing your bottles, back up `Libraries/` first
(NOT inside `~/Library/Application Support/com.isaacmarovitz.Whisky/`
— Whisky's installer will delete anything in there during re-bootstrap):

```sh
APP="$HOME/Library/Application Support/com.isaacmarovitz.Whisky"
cp -R "$APP/Libraries" "$HOME/whisky-libraries-bak"
rm -rf "$APP/Libraries"
WHISKY_WINE_BASE_URL="..." open -a Whisky
```

## Verified to work

End-to-end visual proof on M1 Max + macOS 26 Tahoe with this stack:

- `wine64 notepad` — Windows notepad renders, GDI text + scrollbars work
- `wine64 winecfg` — full tabbed dialog with controls, dropdowns, buttons
- BeamNG.drive — engine boots, FMOD inits, DXVK renders `Apple M1 Max
  (D3D11)` adapter, all shaders compile. World render blocked by
  Ultralight UI shared-texture handshake (see "Known limitations").

## Known limitations

- **Apps using `IDXGIResource::GetSharedHandle()` (NT handle variant)
  hang.** DXVK 2.7.1 doesn't implement NT shared handles — only legacy
  KMT. This blocks any app that composites GPU textures across process
  boundaries via shared D3D11 resources. Most notably: BeamNG.drive's
  Ultralight-based UI. Tracked at https://github.com/doitsujin/dxvk
  as "shared NT handle" issues.
- **No SChannel TLS** — see above. Use `WINEDLLOVERRIDES=schannel=n`
  with a native Windows `schannel.dll` if absolutely required, or wait
  for the x86_64-brew CI fix.
- **No GPTK / D3DMetal** — bring your own from Apple Developer or
  Gcenx tooling. The bundle pins DXVK as the D3D backend.

## Building it yourself

```sh
git clone https://github.com/EricSpencer00/Whisky.git
cd Whisky
CROSSOVER_VERSION=26.1.0 ./Scripts/build-wine.sh
# Output at out/Libraries.tar.gz
```

Build takes ~80 minutes on a fresh macos-15 GitHub runner under
Rosetta. Local builds need: `brew install bison flex gst-plugins-base
freetype molten-vk pkgconf sdl2 vulkan-headers vulkan-loader`.
