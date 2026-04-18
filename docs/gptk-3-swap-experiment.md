# GPTK 3.0-3 Wine experiment — 2026-04-17

## Context
Whisky is archived. Its bundled Wine/GPTK (v2.5.0 "WhiskyWine") contains:
- Wine 7.7 (CrossOver 22.1.1 base)
- D3DMetal.framework 2.0 (Apple GPTK 1.x)

On macOS 26 / Apple Silicon / BeamNG.drive 0.38.5, the D3D11 device is created,
shaders compile, the scene loads, but CEF's `MainGEUI` subprocess times out on
`CefTexture::initializePing` at game-time 126s → "Unresponsive UI Process".
The root cause is `IDXGIResource::GetSharedHandle()` not working across a
Wine-subprocess boundary in this Wine+GPTK combo.

## Attempts

### Surgical swap (D3DMetal.framework + libd3dshared.dylib only)
Replaced `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external/{D3DMetal.framework,libd3dshared.dylib}`
with the D3DMetal 3.0 versions from
[Gcenx/game-porting-toolkit Game-Porting-Toolkit-3.0-3](https://github.com/Gcenx/game-porting-toolkit/releases/tag/Game-Porting-Toolkit-3.0-3).

Result: BeamNG log still ends with
```
126.12651|E|engine::CefTexture::initializePing| Timeout of 120s on CefTexture renderer: timeToInitFailure -0.002 <= 0
126.12702|E|engine::BNGCefClient::OnRenderProcessTerminated| CEF client ID: "MainGEUI"
Description: Timeout in CefTexture::update()
```

Same exact timeout as with D3DMetal 2.0 → the D3DMetal version alone does not
address the cross-process shared-texture path.

### Full Wine dir replacement (GPTK 3.0-3 wine tree → Whisky Libraries/Wine)
`mv Libraries/Wine → Libraries/Wine.whisky-bak; cp -R gptk-3.0-3/wine Libraries/Wine`
Hung at startup (5 MB RSS, 0% CPU, one "esync: up and running" line). GPTK
3.0-3's Wine tree is not drop-in compatible with a Whisky bottle initialised
by the older WhiskyWine — probably a registry / dosdevices mismatch.

## Prerequisite fix: DX11 feature-level detection (already solved)
BeamNG's original failure on Whisky-stock was "Incompatible DirectX Device /
Highest DX version supported: 9". Fix:
- Disable DXVK in the bottle (`Metadata.plist :dxvkConfig:dxvk false`)
- Restore Wine builtin `d3d11.dll` / `dxgi.dll` in `drive_c/windows/{system32,syswow64}`
- Remove `"d3d11"="native"` and `"dxgi"="native"` from `user.reg`
  `[Software\\Wine\\DllOverrides]`

After this, the device is created as `AMD Compatibility Mode (D3D11)` at
feature level 11_0 and the game runs through engine init.

## What would be needed to fully fix BeamNG CEF

1. Bottle rebuild against newer Wine (`wineboot -u` with fresh prefix on the new
   Wine) so registry layouts match.
2. Possibly a `WINED3DMETAL_SHARED_TEXTURE` env var or equivalent — D3DMetal 3
   documents improved shared-texture interop but it may only trigger under the
   right launcher env that Whisky doesn't emit.
3. Or move to [Sikarugir](https://github.com/Sikarugir-App/Sikarugir), which
   exposes the `DXMT` (Metal-backed D3D11) engine, sidestepping D3DMetal
   shared-texture semantics entirely.

## Backups left on disk
- `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external/D3DMetal.framework.whisky-bak` (original D3DMetal 2.0)
- `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external/libd3dshared.dylib.whisky-bak`
- Bottle `8AAFE391-2633-47E7-9655-59BFD9270EF3`:
  - `Metadata.plist.bak-20260417-183520`
  - `user.reg.bak-20260417-183639`
  - `drive_c/windows/system32/{d3d11,dxgi}.dll.dxvk-bak`
  - `drive_c/windows/syswow64/{d3d11,dxgi}.dll.dxvk-bak`
