# Rockstar Games Launcher under the FOSS Wine bundle

Goal: launcher usable enough to sign in and download GTA V to L: (LaCie).

Bottle: 8AAFE391-2633-47E7-9655-59BFD9270EF3
Launch: nohup /tmp/.../run-rglp.sh  (LauncherPatcher.exe)
Logs:   drive_c/users/crossover/Documents/Rockstar Games/Launcher/{launcher,prelauncher}.log

## State
- Launcher installed, v1.0.108.2970.
- VC++ x64+x86 redists installed (8 msvc runtime dlls in system32).
- DXMT swapped OUT (wined3d active) because DXMT lacks SwapDeviceContextState,
  which killed Launcher.exe outright. Launcher only asks for FL 10_0.
- LauncherPatcher.exe spawns Launcher.exe + RockstarService.exe.
- Reaches: init phase 2 -> diag -> net -> pools -> engine -> group 1 ->
  "localisation Language updated to: 0" then exits. No window.
- Social Club never installs (no C:\Program Files\Rockstar Games\Social Club).

## Ruled out
- Not TLS: the 112MB update download completed byte-exact.
- gnutls present, x86_64, resolvable.
- Not freetype: fixed by setting DYLD_* inside the launch script.
- Not the tool call killing it: nohup + in-script DYLD fixed that.

## Tried
| # | change | result |
|---|---|---|
| 1 | run installer | launcher installed; "exited unexpectedly" 00000010 |
| 2 | run Launcher.exe w/ DXMT | crash: SwapDeviceContextState unimplemented |
| 3 | dxmt-restore, run Launcher.exe | past init, exits at localisation, no window |
| 4 | install VC++ redists | same |
| 5 | LauncherPatcher.exe | spawns children, still no window |

## Root cause (iteration 2)

Both renderers fail, for different reasons:

- **DXMT**: gives FL 10_0, then `err: src/d3d11/d3d11_context_impl.cpp:SwapDeviceContextState`.
  One unimplemented method kills it.
- **wined3d**: `fixme:winediag:wined3d_select_feature_level None of the requested D3D
  feature levels is supported on this GPU`. It cannot reach FL 10_0 at all, so the
  renderer never initialises and Launcher.exe exits silently with no window and no
  exception. That is why the log stops after "localisation".

So the fix is to implement `ID3D11DeviceContext1::SwapDeviceContextState` in DXMT.
Everything else about the launcher already works.

## Iteration 2 action: implement SwapDeviceContextState in DXMT

Forked to EricSpencer00/dxmt. `UNIMPLEMENTED` calls `abort()`, which is why the
launcher dies instantly rather than degrading.

`MTLD3D11DeviceContextState` is an empty placeholder ("TODO: implement it
properly") and `CreateDeviceContextState` already returns one, so swapping only
has to hand back the previously bound object and reset the context:

```cpp
  SwapDeviceContextState(ID3DDeviceContextState *pState, ID3DDeviceContextState **ppPreviousState) override {
    std::lock_guard<mutex_t> lock(mutex);
    if (ppPreviousState)
      *ppPreviousState = device_context_state_.ref();
    if (!pState)
      return;
    device_context_state_ = pState;
    ResetEncodingContextState();
    ResetD3D11ContextState();
  }
```

Plus a `Com<ID3DDeviceContextState> device_context_state_;` member.

Cannot build locally: DXMT needs LLVM 15 built from source plus the Metal
toolchain. Using the fork's own CI instead. Note forks have Actions disabled by
default — enable with
`gh api -X PUT repos/OWNER/REPO/actions/permissions --input -` and a JSON body,
because `-f enabled=true` sends a string and 422s.

Build: https://github.com/EricSpencer00/dxmt/actions/runs/33040914946
Artifact to fetch when green: `dxmt-<tag>.tar.gz`.

## Next
1. Wait for the DXMT build; install its d3d11/dxgi/d3d10core + winemetal.so.
2. Re-run LauncherPatcher.exe with DXMT active.
3. If it hits another UNIMPLEMENTED, repeat. Grep candidates:
   `grep -n UNIMPLEMENTED src/d3d11/*.cpp`
