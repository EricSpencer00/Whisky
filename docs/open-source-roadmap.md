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

## 2026-08-22 session: DXVK 3.0.2 tested — the NT-handle plan is dead on macOS; wined3d-vk reaches device creation but caps at FL9

Empirical results on M1 Max / macOS 26 / phase1l bundle (Wine 11 + MoltenVK 1.4.1), BeamNG 0.38.5:

| Stack | Result | Blocker |
|---|---|---|
| DXVK **3.0.2** (ships PR 5257 NT shared handles, merged 2025-11) | ✗ no adapter | `Skipping: Device does not support required feature 'geometryShader'` — DXVK 3.x hard-filters devices on GS; Metal/MoltenVK has none (MoltenVK 1.4.2, Jul 2026, still no GS — KhronosGroup/MoltenVK#203 open) |
| wined3d-vulkan (`WINEDLLOVERRIDES="dxgi,d3d11,d3d10core,d3d9=b"`) | ✗ but CLOSE | Adapter enumerates as "Apple M1 Max (D3D11)", device creates, modes enumerate — then BeamNG rejects: "Highest DX version supported: 9". wined3d caps the feature level without GS/other Vulkan features |

So the two April "workarounds in test" both resolved negative for BeamNG:
DXVK-with-NT-handles can't even init on macOS, and wined3d-vk initializes but
reports FL 9. **FL11-on-FOSS is blocked upstream on geometry-shader support
in the Vulkan-on-Metal layer**, not on anything in this repo.

Practical paths, in order:
1. **D3DMetal drop-in** (user-installs GPTK; not redistributable): FL11 with GS emulated. Remaining bug is the April Ultralight shared-texture timeout — worth retesting on Wine 11 + this bundle, since wineserver mediates NT handles for D3DMetal the same way CrossOver does.
2. **MoltenVK GS emulation** — upstream, tracked in MoltenVK#203; no ETA.
3. **KosmicKrisp / Mesa Vulkan-on-Metal** — full-featured Vulkan driver effort; needs an x86_64 or universal build before Rosetta Wine can use it.

### Environment fixes that ARE ours and now work (keep these)

- Wine's `win32u` dlopens `libvulkan.1.dylib` and does NOT search `/usr/local/lib`
  or the bundle. Fix that unblocked everything: symlink MoltenVK into the Wine
  unix dir it *does* search:
  `ln -s ../../../external/libMoltenVK.dylib $WINE/lib/wine/x86_64-unix/libvulkan.1.dylib`
  (a `CX_LIBVULKAN` env override exists in the binary but did not take effect).
  This also bypasses the Vulkan loader, making the ICD portability workaround
  unnecessary for the wined3d/DXVK path.
- MoltenVK 1.4.1 then enumerates fine: Vulkan 1.4, 153 extensions, M1 Max visible.

### New bug found: BeamNG DirectInput init race (Wine 11 phase1l)

With `WINEDEBUG=-all`, BeamNG reliably stalls forever right after
"Initializing DirectInput..." (game+wineserver both ~50% CPU;
libScePad's HID SetupDi poll loop runs but is benign). With `WINEDEBUG=+relay`
the same binary/bottle passes enumeration in 0.03s every time — a timing race
somewhere in dinput/rawinput init, not present in April's phase1k tests
(64-bit-only bundle, winebus couldn't load). Not root-caused yet. Workarounds
tried that did NOT help: WINEESYNC/WINEMSYNC off, winebus Start=4, parking
winebus/winehid/winebth/winexinput.sys, purging HID Enum/DeviceClasses from
system.reg. April's runs launched via Whisky.app (GUI session) — untested
whether that avoids it.

Caveat for future sessions: `HKLM\...\Services\winebus Start=4` while
winedevice processes are being SIGKILLed can wedge the prefix so hard that
`wineboot -u` hangs; revert to Start=3 fixes it.

### D3DMetal drop-in tested (same session) — installs, loads, does NOT take over

GPTK 3.0 D3DMetal was recovered locally from the Sikarugir BeamNG wrapper
(`~/Applications/Sikarugir/BeamNG.app/Contents/Frameworks/renderer/d3dmetal`,
`CFBundleShortVersionString 3.0`, x86_64) — framework + `libd3dshared.dylib`
+ paired PE/unixlib `d3d11`/`d3d12`/`dxgi`. Installed both supported ways:

1. PE+unixlib into the Wine bundle (`lib/wine/x86_64-{windows,unix}/`) —
   breaks the loader outright: `import_dll ... d3d11.dll not found`, exit 53.
2. Framework in `lib/external/`, GPTK PE DLLs native in the bottle's
   `system32` (the layout the April `.d3dmetal-bak` files show) —
   DLLs load (`loaddll: Loaded C:\windows\system32\d3d11.dll ... builtin`),
   but D3DMetal is **never mapped into the process** (`vmmap` shows no
   D3DMetal / libd3dshared), wined3d logs `Using the Vulkan renderer for
   d3d10/11 applications`, and BeamNG again reports **"Highest DX version
   supported: 9"**.

This build does carry CrossOver's backend switch (`CX_ACTIVE_GRAPHICS_BACKEND`
with a `d3dmetal` value is present in `win32u.so`), and setting it
`=d3dmetal` changes nothing on its own.

Read: GPTK 3.0's unixlib is built against the Wine unixlib ABI of its host
(Sikarugir ships Wine 8.0.1), so on this Wine 11 build the PE half loads and
silently falls back to wined3d instead of reaching Metal. Making D3DMetal
work here needs a GPTK build matching this Wine's unixlib version — i.e.
the D3DMetal shipped with the CrossOver whose Wine we build from (26.1.0),
not the Sikarugir/GPTK-3.0 copy. That is the next thing to try.

Net: all three FOSS-ish D3D11 backends are now characterized on Wine 11 —
DXVK blocked by geometry shaders, wined3d-vulkan caps at FL9, D3DMetal 3.0
ABI-mismatched. No FL11 path on this bundle today.

### 2026-08-26: FL 11_1 on a free stack — DXMT on the FOSS Wine 11 bundle

**This is the one that matters.** DXMT (github.com/3Shain/dxmt, LGPL-2.1-or-later)
implements D3D11 and D3D10 on Metal directly. No Vulkan, so the geometry-shader
wall that stops DXVK and wined3d does not apply, and no paid software anywhere
in the stack.

```
$ ./Scripts/run-d3d11-probe.sh dxmt-install
$ ./Scripts/run-d3d11-probe.sh probe
device    hr=0x00000000 featurelevel=0xb100
adapter=Apple M1 Max vendor=0x106b device=0x0000 vram=26542MB
swapchain hr=0x00000000 featurelevel=0xb100
present   hr=0x00000000
```

Feature level **11_1**, device and swapchain, clear and Present both S_OK, on
the Wine 11 bundle `Scripts/build-wine.sh` produces. The adapter is the real
Apple M1 Max rather than the spoofed AMD card D3DMetal reports.

The v0.80 `-builtin` release is laid out for exactly this: pure-PE
`d3d11`/`dxgi`/`d3d10core` plus one `winemetal.so` unixlib, so it has none of
the symlink trouble the GPTK layout has. `dxmt-install` fetches and installs it;
`dxmt-restore` puts the bundle back to 9_3.

Every piece is redistributable: Wine is LGPL, DXMT is LGPL-2.1. Nothing in this
path requires CrossOver or an Apple Developer account.

### 2026-08-26: the same number via CrossOver's D3DMetal — reference only

`Scripts/run-d3d11-probe.sh d3dmetal-install` on the FOSS Wine 11 bundle, then
`Scripts/d3d11-probe.c`:

```
device    hr=0x00000000 featurelevel=0xb100
adapter=AMD Compatibility Mode vendor=0x1002 device=0x66af vram=53084MB
swapchain hr=0x00000000 featurelevel=0xb100
present   hr=0x00000000
```

Feature level **11_1**, device and swapchain, with a clear and a Present that
both return S_OK. CrossOver 26.1.0 on the same machine returns exactly the same
numbers. The stock bundle returns `0x9300` (9_3), so the delta is real and
measured by the same binary in the same bottle.

D3DMetal is Apple's, under a licence that forbids redistribution, and it ships
inside CrossOver, which is paid. This path is therefore a **reference
measurement only** — it proved the bundle can carry an 11_1 D3D11 device before
DXMT was tried, and it is useful for A/B when DXMT misbehaves. Use
`dxmt-install` for anything real.

#### What the layout has to be

CrossOver keeps D3DMetal in `lib64/apple_gptk/`:

```
apple_gptk/external/D3DMetal.framework
apple_gptk/external/libd3dshared.dylib
apple_gptk/wine/x86_64-windows/{d3d11,d3d12,dxgi,atidxx64,nvapi64,nvngx}.dll
apple_gptk/wine/x86_64-unix/{d3d11,d3d12,dxgi,atidxx64,nvapi64,nvngx}.so
```

Three things have to be right:

1. **Both halves.** The PE alone leaves the unixlib orphaned and the loader
   falls through to wined3d — that is why the earlier "framework in
   `lib/external`, PE native in system32" attempt showed D3DMetal never mapped.
2. **The same CrossOver whose LGPL source built this Wine.** Apple's GPTK 3.0
   copy targets the Wine 8.0.1 unixlib ABI and aborts on
   `ntdll.dll.__wine_unix_call`.
3. **The unixlibs are symlinks, not copies.** Every `.so` in
   `apple_gptk/wine/x86_64-unix/` is a 33-byte symlink to the single
   `../../external/libd3dshared.dylib`. `libd3dshared.dylib` and
   `D3DMetal.framework` go beside them, because the unixlib links
   `@rpath/libd3dshared.dylib` with an `LC_RPATH` of `@loader_path` and
   libd3dshared then dlopens `@rpath/D3DMetal.framework/D3DMetal`.

#### The bug that cost a day, and how it was found

Point 3 is not cosmetic. `cp` dereferences those symlinks, so copying gives
dyld two independent Mach-O images of the same dylib, each with its own copy of
`gWin32Dispatch` and the `dispatch_once` guards. The PE half initialises one
image's dispatch table; D3DMetal then calls through the other image's, which is
still all NULL. It faults with `rip=0` inside `InitSharedState`, long before
any call into `winemac.drv` — which is why `+macdrv_d3dmtl` printed nothing.

Located by having the probe install a vectored exception handler that dumps the
faulting context and the raw stack, sleeping so `vmmap` could resolve the
return address:

```
### VEH code=0xc0000005 rip=0000000000000000 rsp=000000000031fbc8
### [rsp+000] = 0000000208b46721
__TEXT  208b44000-208b4c000  .../x86_64-unix/d3d11.so
```

`d3d11.so+0x2721`, immediately after
`callq *0x6aef(%rip)  ## gWin32Dispatch+0x28` — and `d3d11.so` having its own
`__TEXT` range, distinct from `libd3dshared.dylib` at `208aff000`, is the whole
bug in one line of `vmmap`.

lldb is not usable for this: attaching to Wine under Rosetta leaves an
orphaned `debugserver` that wedges every subsequent x86_64 process in
uninterruptible wait. If Wine suddenly hangs at 0.02s CPU with no output,
`pkill -9 debugserver` before assuming the bundle is broken.

#### Corrections to earlier conclusions in this document

- **`cxcompatdb.so` is not required.** It is closed-source and absent from the
  LGPL tarball, and ntdll's `dlopen` of it fails here — but that dlopen is a
  soft failure (CW Hack 24067, WARN only) and D3DMetal works without it.
- **No environment variable turns D3DMetal on.** `CX_ACTIVE_GRAPHICS_BACKEND`
  and `CX_GRAPHICS_BACKEND` make no difference; the probe returns 11_1 with an
  empty environment. A working CrossOver run does not have
  `CX_ACTIVE_GRAPHICS_BACKEND` in its environment either — inside CrossOver it
  is a `+process` trace, not a switch anything reads at device creation.
  `CX_APPLEGPTK_LIBD3DSHARED_PATH` is worth setting anyway: ntdll uses it to
  register PE images as non-native code regions with Rosetta.
- **"Blocked upstream on geometry shaders" applies to DXVK and wined3d only.**
  Both go through Vulkan, and MoltenVK has no geometry shaders. D3DMetal talks
  to Metal directly and never asks the question. The conclusion that no FL11
  path exists on this bundle was wrong.
- **The earlier `Highest DX version supported: 9` and DXVK measurements came
  from a poisoned bottle**, whose `system32/{d3d11,dxgi,d3d10core}.dll` had been
  renamed to `.dxvk-bak` / `.dxvk302` / `.d3dmetal-bak-<epoch>` and never
  restored, so `LoadLibrary` returned `c0000135` before a renderer was reached.
  `run-d3d11-probe.sh` detects this and runs `wineboot -u`.

#### Not yet established

BeamNG is not installed on the test machine, so this is a feature-level and
swapchain result, not a "BeamNG runs" result. What the numbers license: a
D3D11 11_1 device on the FOSS Wine 11 bundle, with a working swapchain and
Present, matching CrossOver. What they do not: anything about the Ultralight
NT-shared-handle path, the DirectInput race, or frame rate.

### 2026-08-26 (later): BeamNG on the free stack — boots, then hangs in input init

BeamNG.drive 0.38.5 (build 19602) **is** installed on the test machine, at
`drive_c/steamcmd/steamapps/common/BeamNG.drive` in bottle `8AAFE391…` — 48 GB,
downloaded via steamcmd. It was missed earlier by searching only `Program Files`.
The binary is verified pristine: byte-identical to
`BeamNG.drive.x64.exe.foss-noCefFatal-bak`, and differing from
`.foss-broken-bak-*` by exactly the one patched byte (`C3` → `E8`) at
`0xBD9240`.

On the FOSS bundle (Wine 11 + DXMT 0.80) it boots through version save, crash
reporter, VFS, CPU detect, then stops at:

```
0.72|D|input| Initializing DirectInput...
```

with one core spinning. Two separate blockers, both diagnosed:

**1. `dinput8.dll` load deadlocks on the Wine loader lock.**

```
err:sync:RtlpWaitForCriticalSection section ... "loader.c: loader_section"
    wait timed out in thread 0178, blocked by 0024
```

Thread 0024 holds the loader lock inside `LoadLibrary("DInput8.dll")`; thread
0178 needs the same lock for `LdrResolveDelayLoadedAPI` after finishing its
`THREAD_ATTACH` callouts. The earlier "DirectInput race — passes under
`+relay`" note was reading the symptom: `+relay` only changes which thread
takes the lock first.

`WINEDLLOVERRIDES="dinput8="` gets past it. BeamNG treats it as non-fatal
(`Failed to initialize Direct Input`) and continues — at the cost of wheel and
gamepad support.

**2. A second hang immediately after platform detection.** Last line is
`platform| Microsoft Windows 10 (v10.0), 64-bit, Wine 11.0`; CrossOver's next
lines are `blacklist::getDLLInfo`, then `Physical memory`. The spin is BeamNG's
own wait-for-worker helper at `BeamNG.drive.x64.exe+0xdf9a30`:

```
cmp  %sil, 0x14220479b        ; done flag
je   exit
call 0x140e001f0              ; poll (drives the setupapi HID enumeration)
...
call *timeBeginPeriod ; Sleep(4) ; call *timeEndPeriod
```

`GlobalMemoryStatusEx`, `GetSystemPowerStatus` and `GetPriorityClass` all
return correctly on this build when called from a standalone probe, so the
platform calls themselves are not the hang.

**CrossOver 26.1.0 runs the same binary past both**, on the same machine, from
a bottle symlinked to the same game directory: DirectInput enumerates Wine
Mouse and Wine Keyboard in 0.1 s, all 119 modules load, FMOD initialises, and
it creates a D3D11 device — `AMD Compatibility Mode (D3D11)`, shader model 5.0,
26 video modes. So the blockers are in **this Wine build**, not in Wine 11, not
in DXMT, and not in the game.

Ruled out as causes, each tested:

- the prefix — a brand-new prefix hangs identically
- `WINEESYNC=1`, `WINEMSYNC=1`, `WINEDEBUG=+timestamp` — no change
- `crashrpt`, `xinput1_4`/`1_3`/`9_1_0` disabled — no change
- winebus `DisableInput=1`; parking winebus/winehid/winexinput — no change
- swapping in CrossOver's `dinput8.dll` PE — no change, so it is the loader
  environment rather than dinput8 itself
- missing HID devices — both prefixes register `HID\VID_845E&PID_0001/0002`
  (ours under `ControlSet001`, which is why an early grep missed them)
- a per-app CrossOver hack — `cxcompatdb.so` only supports appending a command
  line, replacing an exe path, adding env vars, and the nvngx redirect, and has
  no BeamNG entry

Note also that `-windowed` is **not** a valid BeamNG argument: it makes
`parseArgs.lua` fail with `attempt to call global 'setFullScreen'` and kills
startup. Do not pass it.

**Next**: the difference is build configuration or toolchain. Our PE DLLs are
roughly 4x the size of CrossOver's (unstripped), and this build uses
llvm-mingw for the PE side and `--enable-archs=i386,x86_64`. The roadmap
already records that the DirectInput stall appeared with phase1l, which is
exactly when WoW64 was turned on — a 64-bit-only rebuild is the first bisection
step.

### Steam client and CEF on Wine 11

The earlier "Wine 7.7 + macOS 26 + CEF = universally broken" finding does not
carry over. On this Wine 11 bundle the Steam client starts, reaches the network
(`Connectivity test ... OK!`) and keeps **seven `steamwebhelper.exe` CEF
processes alive** with no "Steamwebhelper is not responding". Steam's own UI
does hit DXMT's `CreateSwapChain: cross-process swapchain not supported yet`
(3Shain/dxmt#141), so use `steamcmd` for installing and updating games — it is
a console app and needs no CEF at all.
