# Open-source Windows games on Mac — roadmap

**Mission:** enable open-source gaming on macOS without CrossOver.

**Status as of 2026-04-18:** No pure open-source stack reaches a playable state for BeamNG.drive on M1 Max / macOS 26. Gaps are specific and fixable. This doc lists what works, what's blocking, and what needs building.

## What we've tested empirically

| Wrapper | Wine | D3D11 engine | Window visible? | UI renders? | Blocker |
|---|---|---|---|---|---|
| Whisky 2.3.5 | 8.0.1 | D3DMetal | ? | ✗ | D3DMetal `OpenSharedResource` hangs 120s |
| Whisky 2.3.5 | 8.0.1 | DXVK (old) | ? | ✗ | Feature level reported as 9 → exit |
| Sikarugir 1.0.11 | 8.0.1 | DXMT v0.74 | ✗ (1×29 "Detecting controllers") | — | Game crashes with SEH frame corruption before window transitions |
| Sikarugir 1.0.11 | 8.0.1 | DXVK 1.10.3-async (bundled) | ✗ | — | Only ships d3d11+d3d10core, no dxgi; ABI incompatible with Wine 8.0.1 + winemetal |
| Sikarugir 1.0.11 | 8.0.1 | DXVK 2.7.1 (swapped in) | — | ✗ | Requires Vulkan 1.3; platform can only produce 1.2 via MoltenVK |
| CrossOver 26.1.0 | 11.0 | D3DMetal | ✓ (1280×748, proper title) | ✗ (black framebuffer) | Ultralight shared-texture handshake times out at ~100s |
| CrossOver 26.1.0 | 11.0 | DXVK 2.7.1 | ✗ | — | `Skipping Vulkan 1.2 adapter: Apple M1 Max` — CrossOver's x86_64 MoltenVK caps at 1.2 |
| CrossOver 26.1.0 | 11.0 | DXVK 2.3.1 (older) | ✗ | — | Still requires Vulkan 1.3 (started in 2.3 or earlier) |

## The real architectural problems

1. **CrossOver is sealed.** `/Applications/CrossOver.app` is signed and macOS won't let us `cp`/`mv` into it without turning off System Integrity Protection. We can't swap in newer MoltenVK. It's a dead end for modding.
2. **CrossOver's bundled MoltenVK is x86_64-only and caps at Vulkan 1.2.** Even though MoltenVK 1.4.1 (Aug 2025) supports Vulkan 1.4 on M1 via `VK_KHR_buffer_device_address`, CrossOver ships an older build that doesn't expose 1.3.
3. **Sikarugir's bundled Wine is 8.0.1.** That's 3 years old. Its bundled DXVK is 1.10.3-async from 2023, missing dxgi.dll. Its bundled DXMT v0.74 works enough to reach main loop but the SEH crash is flaky.
4. **BeamNG's Ultralight UI uses D3D11 shared textures.** `IDXGIResource::GetSharedHandle` → `ID3D11Device::OpenSharedResource` handshake must complete for the menu to paint. It hangs on D3DMetal and currently isn't reached cleanly on DXMT because the game crashes first.
5. **No open-source wrapper implements CrossOver's Hack 18311.** That's the patch in `dlls/wined3d/directx.c` that force-defaults to `wined3d_adapter_vk_create` on macOS, bypassing D3DMetal. It's publicly LGPL in CrossOver 26.1.0's source drop.
6. **Wine's HID device enumeration refuses Mac USB devices.** Log: `err:hid:handle_DeviceMatchingCallback Ignoring HID device ... not a joystick or gamepad`. BeamNG waits on controller detection. Not a hard block, but it delays the window transition.

## Path forward — build what doesn't exist yet

### Phase 1: minimum viable open-source wrapper (MVP)

Goal: a `.app` bundle that can launch a Windows `.exe` on M1 macOS 26 and get visible, working D3D11 graphics for a non-trivial game.

Components, all open source, all with clear provenance:

- **Wine 11.0** — WineHQ upstream, https://gitlab.winehq.org/wine/wine
  - Patch with Hack 18311 from CrossOver 26.1.0 LGPL source drop (`dlls/wined3d/directx.c`)
  - Patch with Mac HID device enumeration fix if present upstream
- **MoltenVK 1.4.1** — Khronos, https://github.com/KhronosGroup/MoltenVK/releases/v1.4.1
  - Universal binary (x86_64 + arm64) — usable by x86_64 Wine and native arm64 tooling
- **DXVK 2.7.1** — https://github.com/doitsujin/dxvk/releases/v2.7.1
  - All DLLs: `d3d11.dll`, `d3d10core.dll`, `d3d9.dll`, `d3d8.dll`, `dxgi.dll` (x64 and x32)
- **Bundle shell** — a minimal Cocoa `.app` bundle that:
  - Sets `DYLD_FALLBACK_LIBRARY_PATH` to include MoltenVK + Wine libs
  - Sets `WINEPREFIX` to the bundled prefix
  - Sets `WINEDLLOVERRIDES` to prefer DXVK's d3d11/dxgi/d3d10core
  - Invokes Wine with the target `.exe`
  - Registers as a proper `LSUIElement = NO` app so Wine windows become native `NSWindow`s

Reference: `ericspencer00/Whisky` (this repo, fork of isaacmarovitz/Whisky) is a starting point. Its Swift wrapper code handles bottles, the GUI, and Wine invocation. What needs to change: bundled Wine 8.0.1 → 11.0+hack18311, bundled DXVK (none currently) → 2.7.1 full set, bundled MoltenVK → 1.4.1 universal.

### Phase 2: reach playable for BeamNG

Once the MVP launches a D3D11 app to a visible window, iterate on the specific blockers:

1. **Controller detection.** Either patch Wine's HID driver to fast-accept non-gamepad devices, or populate BeamNG's `inputMaps.json` with preset keyboard/mouse bindings so the game skips enumeration.
2. **Ultralight shared-texture.** With DXVK 2.7.1 as D3D11, the `IDXGIResource::GetSharedHandle` path goes through DXVK → Vulkan `VK_KHR_external_memory_host` → Metal `MTLHeap`. This path is well-tested on Linux; should work on macOS too. Verify empirically.
3. **Persistent SEH crash.** If still present on Wine 11 + DXVK 2.7, trace the exception frame with winedbg. Likely fixed by newer Wine.

### Phase 3: ergonomics and packaging

- One-click `.app` installer that doesn't require terminal
- Per-game profile system (renderer choice, mods, saves)
- Steam library integration
- CI that produces signed notarized builds under EricSpencer00's Apple Developer ID

## Build order (concrete next steps)

1. Update `ericspencer00/Whisky`'s bundled Wine:
   - Pull WineHQ 11.0 source
   - Apply Hack 18311 from crossover-sources-26.1.0 (extract the diff from `wine/dlls/wined3d/directx.c`)
   - Build universal binary (x86_64 + arm64) on macOS 26
   - Drop into `Whisky/Libraries/Wine/`
2. Update bundled libraries:
   - Download MoltenVK 1.4.1 `MoltenVK-all.tar`, extract `dynamic/dylib/macOS/libMoltenVK.dylib` (universal)
   - Download DXVK 2.7.1 `dxvk-2.7.1.tar.gz`, extract `x64/` and `x32/` into `Whisky/Libraries/DXVK/`
3. Update Whisky's Swift code (`Whisky/Models/WineInterop/Wine.swift` and related):
   - Bottle templates must install DXVK DLLs + DllOverrides when creating a bottle
   - Bottle launch must set `DYLD_FALLBACK_LIBRARY_PATH` to include MoltenVK
4. Build and test with BeamNG, document results in this file.

## Files and references

- CrossOver 26.1.0 LGPL source drop (for Hack 18311 and others): `https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.1.0.tar.gz` — audited 2026-04-17, see `docs/gptk-3-swap-experiment.md`.
- Wine 11.0: `https://gitlab.winehq.org/wine/wine/-/releases`
- DXVK: `https://github.com/doitsujin/dxvk/releases`
- MoltenVK: `https://github.com/KhronosGroup/MoltenVK/releases`
- DXMT (reference): `https://github.com/3Shain/dxmt`
- Sikarugir (for inspiration — not using its bundle directly): `https://github.com/Sikarugir-App/Sikarugir`

## What's in this repo right now (from 2026-04-17 to 2026-04-18 sessions)

- `docs/beamng-runbook.md` — CrossOver-based BeamNG launch walkthrough (WORKING but paid)
- `docs/beamng-sikarugir-recipe.md` — Sikarugir+DXMT recipe (PARTIAL — reaches main loop, window doesn't expand)
- `docs/gptk-3-swap-experiment.md` — GPTK 3.0-3 swap test results
- `Scripts/play-beamng.sh` — one-command CrossOver launcher
- THIS FILE — the open-source roadmap

## Current playable state

**None on open source alone.** CrossOver-with-D3DMetal gets the closest playable experience today (visible window, reaches main loop), but it's paid and the UI doesn't paint. The open-source plan above is the path out.
