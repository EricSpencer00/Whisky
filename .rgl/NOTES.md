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

## Iteration 3-4: DXMT fix works, launcher still exits

The `SwapDeviceContextState` fix is **confirmed good**. Built on the fork's CI
(run 33040914946, all 14 jobs green), installed, and:
- zero `SwapDeviceContextState` aborts
- d3d11 probe still `featurelevel=0xb100`
- launcher error changed `00000010` -> `FFFF7001`, so it now gets much further

### Where it dies now

`Launcher.exe` calls `TerminateProcess(self, 0xFFFF7001)` from `Launcher.exe+0x3f994d`.
Its own code, deliberately, not a crash. Sequence from launcher.log:

```
:30.330 [subsystem] Initializing group 1...
        <-- 7.4 second gap -->
:37.770 [DxDia] [diag] DxDiag info:        <- captured as failure diagnostics
        TerminateProcess(self, ffff7001)
```

RGL dumps DxDiag when it is about to report a failure, so DxDiag is a symptom.
The 7.4s gap looks like a timeout, not a crash.

### Ruled out this iteration
- **Not wineserver.** "wineserver crashed" only appeared when I `pkill -9`'d it myself.
- **Not dxdiag.exe.** Disabling it changes nothing; RGL uses the dxdiagn COM API.
- **Not dxdiagn.** `WINEDLLOVERRIDES=dxdiagn=d` and `=n` both give the same FFFF7001.
- **Not GetDpiAwarenessContextForProcess.** Our user32 exports it (that fix is for older Wine).
- **Not the Windows version.** Prefix reports build 19043 (Win10). The
  "Windows XP Professional" line is Wine's dxdiagn stub, and is stale text.
- **Not DXMT.** With `DXMT_LOG_LEVEL=3` it logs only the device creation at
  FL 10_0 and nothing else. No errors, no warnings.
- **Not Social Club.** Never installs, but modern RGL only version-checks it.
- **Not VC++ runtimes.** Installed, 8 msvc dlls in system32.

### Next: A/B against CrossOver

Same method that found the BeamNG BOOLEAN bug. CrossOver is allowed as a
diagnostic reference. Install RGL into a CrossOver bottle; if it runs there,
diff the two environments to find what group 1 is waiting on.
