# BeamNG.drive runbook (Whisky, macOS 26, Apple Silicon)

This is the current state of BeamNG.drive support on the community-maintained
Whisky fork, and the concrete steps to get the furthest-currently-possible.

## Current reality (2026-04-17)

| State | Works? | Blocker |
|---|---|---|
| D3D11 device creation at feature level 11_0 | ✅ | — |
| Shader compilation / level / fmod load | ✅ | — |
| CEF UI (main menu, freeroam launcher, etc.) | ❌ | `CefTexture::initializePing` times out at 120 s — Wine 7.7 + D3DMetal can't cross-process-share the CEF texture handle |
| `-noui` mode + autostart.lua (jumps straight to gridmap_v2) | ⚠️ sometimes | CEF init itself still runs briefly and sometimes hangs there even with `-noui` |

So the game engine is fine; CEF's shared-texture path is the sole blocker.
Upstream Whisky's bundled Wine is 7.7, based on CrossOver 22.1.1. Fixing CEF
on this version is not tractable from the Whisky side.

## Workaround: `-noui` + autostart

BeamNG ships `lua/ge/extensions/autostart.lua` which, if reached, simulates UI
events at t=3/4/6/25s and drops the player into `gridmap_v2` freeroam.
`-noui` skips the main-menu CEF UI, making this path viable:

```bash
BOTTLE="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<your-bottle-uuid>"
WINE="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"
cd "$BOTTLE/drive_c/steamcmd/steamapps/common/BeamNG.drive/Bin64"
WINEPREFIX="$BOTTLE" WINEDEBUG=-all WINEESYNC=1 WINEMSYNC=1 \
  "$WINE" start /unix "$PWD/BeamNG.drive.x64.exe" -nosteam -noeos -noui
```

It's sometimes hit-or-miss (the libcef.dll still gets loaded even with
`-noui`, and init sometimes blocks). Your mileage varies until the Wine swap
below lands.

## Prereqs for a bottle that will run BeamNG at all

1. **Disable DXVK** in the bottle's `Metadata.plist`
   (`dxvkConfig:dxvk = false`). Without this, BeamNG's D3D11 device comes
   back at feature level 9_x and the game refuses to start with
   "Incompatible DirectX Device".
2. **Restore Wine builtin d3d11/dxgi** in
   `drive_c/windows/{system32,syswow64}/{d3d11,dxgi}.dll` (the Whisky bottle
   template replaces these with DXVK).
3. **Remove DllOverrides** for `d3d11`/`dxgi` under
   `[Software\\Wine\\DllOverrides]` in `user.reg` (it has
   `"d3d11"="native"` / `"dxgi"="native"` — both need to go).
4. **Visual C++ runtime DLLs** in both `drive_c/windows/system32/` and
   `drive_c/windows/syswow64/`:
   `msvcp140*.dll`, `vcruntime140*.dll`, `ucrtbase.dll`. Fresh bottles made
   by `wineboot -u` don't get these; copy them from a Steam-initialised
   Whisky bottle, or install via winetricks `vcrun2015 vcrun2019`.

## Real fix: swap to Wine 11 via the fork's BuildWine

CodeWeavers' `crossover-sources-26.1.0.tar.gz` ships **Wine 11.0** (vs the
Whisky tarball's 7.7). Wine 11 has four years of
`IDXGIResource::GetSharedHandle()` and CEF-interop work that Wine 7.7 doesn't.
Once [`BuildWine`](../.github/workflows/BuildWine.yml) produces
`Libraries.tar.gz` on a fork Release (tag `wine-vX.Y.Z`):

```bash
# Point Whisky's first-run installer at the fork's build
export WHISKY_WINE_BASE_URL="https://github.com/EricSpencer00/Whisky/releases/download/wine-v26.1.0"
open /Applications/Whisky.app     # or the locally-built Debug Whisky.app
# Whisky prompts to re-download WhiskyWine; it pulls the fork-built tarball.
# Create a fresh bottle, install BeamNG, test.
```

This is the actually-tractable path to BeamNG's CEF UI working. Track in
[issue #1](https://github.com/EricSpencer00/Whisky/issues/1).

## Files I've kept for backup

If you reverted the bottle on an already-modified Whisky install, these
backups are (or were) left on disk:

- `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external/D3DMetal.framework.whisky-bak`
- `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external/libd3dshared.dylib.whisky-bak`
- Per-bottle: `Metadata.plist.bak-*`, `user.reg.bak-*`,
  `drive_c/windows/{system32,syswow64}/{d3d11,dxgi}.dll.dxvk-bak`.
