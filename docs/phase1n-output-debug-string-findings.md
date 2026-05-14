# Phase 1n — OutputDebugStringA/W exception suppression on macOS Wine

This patch fixes a class of crashes affecting Unreal Engine games (and any
other Windows app that ships a Vectored Exception Handler crash reporter)
running under Wine on macOS. Empirically validated to be the proximate
cause of Rocket League's `App.cpp:367` "HasFocusFunction" silent-exit on
the Wine 11 + Whisky FOSS stack and on CrossOver 26.

## Symptom

UE games crash silently ~10–20 seconds into engine init, during or right
after `FApp::HasFocus()` is called for the first time. Game log ends
mid-write to a `Log: Network Adapter:` line. No macOS crash report is
generated (it's a clean `ExitProcess`, not a `SIGKILL`). With
`WINEDEBUG=+seh,+process,+module,+threadname,+timestamp` the chain is
visible:

```
trace:seh:dispatch_exception code=4001000a flags=0 addr=...
trace:seh:RtlUnwindEx code=4001000a flags=2 target_ip=...
warn:seh:OutputDebugStringA "Assertion failed: HasFocusFunction
                             [File:D:\\build\\++Distro\\Sync\\Engine\\Source\\Runtime\\Core\\Private\\Misc\\App.cpp]
                             [Line: 367] \n\n"
trace:seh:dispatch_exception code=40010006 (DBG_PRINTEXCEPTION_C)
trace:seh:call_seh_handlers calling TEB handler 0x...
trace:seh:EnumProcessModulesEx (...)            ← UE crash handler running
trace:seh:RtlCaptureStackBackTrace (0, 100, ...) ← UE crash handler running
[process exits]
```

## Root cause

Wine's `OutputDebugStringA` (`dlls/kernelbase/debug.c`) raises a
`DBG_PRINTEXCEPTION_C` exception (`0x40010006`) so that an attached
debugger can intercept the debug message via `WaitForDebugEvent`. The
raise is wrapped in a local `__TRY/__EXCEPT(debug_exception_handler)`
that consumes the exception when no debugger is attached. The handler
matches `DBG_PRINTEXCEPTION_C` and returns `EXCEPTION_EXECUTE_HANDLER`,
so on Linux this works fine.

On macOS, UE games install a **Vectored Exception Handler** (VEH) as
part of their crash reporter (`FCrashHandler::AddVectoredHandler`). VEHs
run **before** SEH frame walking reaches Wine's local `__EXCEPT`. UE's
handler treats `DBG_PRINTEXCEPTION_C` as fatal: captures the stack via
`RtlCaptureStackBackTrace`, dumps a crash log, calls `ExitProcess`.

The Linux SEH ordering puts the local `__EXCEPT` ahead of VEHs in this
specific path (different `winex11.drv` vs `winemac.drv` exception
plumbing). On macOS it doesn't, so UE's VEH wins the race and the
process dies. UE's `check()` macro fires `OutputDebugStringA` for
**every** assertion in the engine, so this affects every UE-on-macOS-Wine
title that has an active VEH crash handler.

## Fix

`dlls/kernelbase/debug.c`: skip the `RaiseException` call in
`OutputDebugStringA` and `OutputDebugStringW`. The debug log message is
still emitted via the `WARN()` macro (visible with `WINEDEBUG=+module`).
Patch in [`Scripts/patches/cw-hack-output-debug-string-suppress.patch`](../Scripts/patches/cw-hack-output-debug-string-suppress.patch).

The Whisky FOSS bundle is macOS-only, so the patch is applied
unconditionally. Upstream Wine should gate this on `__APPLE__`, but
that macro isn't defined when cross-compiling Windows-target DLLs with
llvm-mingw — Wine doesn't currently surface a "PE build for macOS host"
compile-time check. Long-term, the right place to fix this is the VEH
ordering in `winemac.drv` (Phase 1o), making the local `__EXCEPT` win
the race like it does on Linux.

## Trade-offs

- **Cost:** apps running under a debugger lose the debug-print event
  notification. This is a debugging-only feature; production runs are
  unaffected.
- **Benefit:** every UE-on-macOS-Wine title that has been silently
  exiting on `check()` assertions can now proceed past them.

## Limitations of the runtime test

This patch only matters when running through a Wine bundle whose
`lib/wine/x86_64-windows/kernelbase.dll` we control. On the sealed
`/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/...`
path, the patched DLL cannot be substituted (SIP / signing); a
`DllOverride=native` in the bottle is silently ignored for KnownDLLs
like `kernelbase`. The Whisky FOSS bundle ships its own `kernelbase.dll`
under `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/`,
so the patch takes effect there immediately.

End-to-end RL test still needs phase-1l libvulkan loader (phase-1m PR
[#17](https://github.com/EricSpencer00/Whisky/pull/17)) plus DXVK
portability fix (phase-1o) and/or wined3d-vulkan 1.2 instance bump
(phase-1p) before the Whisky FOSS bundle reaches the `check(HasFocusFunction)`
codepath where this patch would be exercised in the wild.

## Reproduction

```sh
# In the Whisky source tree:
cd build/wine-build/src/wine
patch -p1 < ../../../../Scripts/patches/cw-hack-output-debug-string-suppress.patch
cd ../../build-wine64
PATH="$(pwd)/../llvm-mingw/bin:$PATH" \
  make -j$(sysctl -n hw.ncpu) dlls/kernelbase/x86_64-windows/kernelbase.dll
# Drop the result into your Whisky Libraries:
cp dlls/kernelbase/x86_64-windows/kernelbase.dll \
  "$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/wine/x86_64-windows/"
```

Verify via `WINEDEBUG=+seh,+module` that `OutputDebugStringA` log lines
appear (`warn:seh:OutputDebugStringA`) but no `DBG_PRINTEXCEPTION_C`
follows them.
