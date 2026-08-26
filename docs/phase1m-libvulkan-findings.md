# Phase 1m — missing `libvulkan.1.dylib` and the DXVK / wined3d-vulkan gaps

This doc captures three findings from a 2026-05-13 test session that swapped
the phase 1l Libraries bundle into a real M1 Max machine and tried to run
Rocket League (Update 58.1, CL-517210) through it. All three are blockers
for the "Wine 11 + DXVK 2.7.1 + MoltenVK 1.4.1" stack on macOS today; the
first is fixed by this branch.

## Finding 1 (fixed here): bundle was missing the Vulkan loader dylib

Phase 1l's `Libraries.tar.gz` ships `MoltenVK/libMoltenVK.dylib` (the ICD)
and `MoltenVK/icd.d/MoltenVK_icd.json`, but **not** `libvulkan.1.dylib`
(the Vulkan loader). On a clean machine without LunarG SDK installed,
Wine 11's `winevulkan.so` startup logs:

```
err:vulkan:vulkan_init_once Failed to load libvulkan.1.dylib:
  dlopen(libvulkan.1.dylib, 0x0002): tried:
  'libvulkan.1.dylib' (no such file),
  '/System/Volumes/Preboot/Cryptexes/OSlibvulkan.1.dylib' (no such file),
  '<bundle>/Wine/lib/wine/x86_64-unix/libvulkan.1.dylib' (no such file),
  '/usr/lib/libvulkan.1.dylib' (no such file, not in dyld cache),
  '<bundle>/MoltenVK/libvulkan.1.dylib' (no such file)
err:vulkan:init_vulkan Failed to load Wine graphics driver supporting Vulkan.
```

…and Hack 18311's whole purpose (default to `wined3d_adapter_vk_create`
on macOS) silently no-ops because wined3d-vulkan never reaches an ICD.

**Fix:** add [`Scripts/fetch-vulkan-loader.sh`](../Scripts/fetch-vulkan-loader.sh)
that produces a universal `libvulkan.1.dylib` (arm64 + x86_64 via `lipo`)
into `out/MoltenVK/`, alongside the existing `libMoltenVK.dylib`. The
script harvests from dual-Homebrew installs when present, otherwise
builds Vulkan-Loader v1.4.341 from source per-arch and lipos. The
packaging step in `build-wine.sh` then picks it up automatically.

Verified locally on M1 Max / macOS 26 Tahoe: once the loader is
present, MoltenVK reports `Apple M1 Max` GPU and `Created VkInstance
for Vulkan version 1.3.334` succeeds.

## Finding 2 (still open): DXVK 2.7.1 release lacks `VK_KHR_portability_enumeration`

The DXVK build we pull from `https://github.com/doitsujin/dxvk/releases/v2.7.1`
is the upstream Linux release. Its `DxvkInstance::createInstance` enables
exactly one instance extension on Wine:

```
info:  Enabled instance extensions:
info:    VK_KHR_win32_surface
```

It does not enable `VK_KHR_portability_enumeration` or set
`VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`. MoltenVK on macOS
is a portability driver (`is_portability_driver: true` in the ICD JSON);
per the spec, applications must opt in to portability enumeration or
the loader filters MoltenVK out of `vkEnumeratePhysicalDevices`. Result:

```
info:  DXVK: v2.7.1
[mvk-info] Created VkInstance for Vulkan version 1.3.334
warn:  DXVK: No adapters found. Please check your device filter settings
       and Vulkan drivers. A Vulkan 1.3 capable setup is required.
err:   Failed to initialize DXVK.
```

The "flip `is_portability_driver` to `false` in MoltenVK_icd.json"
workaround (documented in [`foss-bundle-usage.md`](foss-bundle-usage.md))
lets the instance create but doesn't help adapter enumeration — MoltenVK
is still the portability subset internally and DXVK's adapter probe
hides it.

**Next:** ship a DXVK build that explicitly enables portability_enumeration
on macOS. Options, in increasing order of effort:

1. **Drop in a prebuilt macOS DXVK from a known fork.** Gcenx's
   `DXVK-macOS` or `lozanov95/dxvk-macOS` releases ship dxgi/d3d11
   DLLs compiled with the portability handshake.
2. **Patch DXVK source and rebuild.** A ~10-line diff to
   `src/dxvk/dxvk_instance.cpp` adds
   `VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME` to the requested
   instance extensions when `defined(__APPLE__)` and sets
   `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR` in
   `VkInstanceCreateInfo::flags`. Wrap it in a `Scripts/build-dxvk.sh`
   to mirror `build-wine.sh`.
3. **Switch to DXMT.** 3Shain's DXMT bypasses Vulkan entirely and emits
   Metal directly. Different architecture; different bugs. Tracked
   separately in `docs/beamng-sikarugir-recipe.md`.

## Finding 3 (still open): wined3d-vulkan requests Vulkan 1.0 instance

With DXVK overrides removed and Wine's builtin d3d11.dll active (the path
Hack 18311 is designed to feed), wined3d-vulkan still fails:

```
[mvk-info] Created VkInstance for Vulkan version 1.0.334, as requested by
            app, with the following 3 Vulkan extensions enabled:
  VK_KHR_external_memory_capabilities v1
  VK_KHR_external_semaphore_capabilities v1
  VK_KHR_get_physical_device_properties2 v2
Warning, Command line -d3d11 set, but D3D11 is not supported on this machine.
```

Wine's `wined3d/adapter_vk.c` requests `apiVersion = VK_API_VERSION_1_0`
during instance creation. D3D11 feature-level support on top of wined3d-vulkan
needs Vulkan 1.2-tier features (host_query_reset, timeline_semaphore,
descriptor_indexing) to be reachable as core, which requires the instance
to declare API version 1.2+. With a 1.0 instance, the adapter probe
finishes but cannot satisfy D3D11_FEATURE_LEVEL_11_0; wined3d returns
"no adapter" and RL aborts.

**Next:** carry a small Wine patch (likely just a one-liner in
`dlls/wined3d/adapter_vk.c`) raising the requested instance apiVersion
to at least 1.2, gated on `__APPLE__`. Apply alongside Hack 18311 in
`Scripts/build-wine.sh`'s `patch_source` step. Add a regression-test
runbook entry that runs `wine winecfg` and checks for a Vulkan adapter
in the Graphics tab.

## Current playable state after applying Finding 1's fix

Same as phase 1l: notepad/winecfg/wine64 native UI render, BeamNG.drive
reaches main loop with DXVK adapter "Apple M1 Max (D3D11)", Ultralight
shared-handle block remains. Rocket League still won't open a window —
both backends (DXVK and wined3d-vulkan) fail before D3D11 device
creation. Findings 2 and 3 are the two remaining hard blockers for a
non-trivial UE3/UE4 title.
