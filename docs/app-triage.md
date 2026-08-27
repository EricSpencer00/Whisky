# Working out where a Windows app breaks

Screenshots lie. A window that looks white may be fully transparent, may be a
window the app never painted, or may be another process's window on top. Three
separate wrong turns in this repo came from reading a picture instead of
measuring one. The probes in `Scripts/probes/` each answer one question, and
`Scripts/triage-app.sh` runs them in order and writes a report.

## Run it

```
BOTTLE=~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<id> \
  ./Scripts/triage-app.sh --tag steam --wait 70 'C:\Program Files (x86)\Steam\steam.exe'
```

Add `--cwd <unix dir>` when the app resolves data relative to the working
directory. Several do, and they fail with a missing-file dialog that the report
captures verbatim.

The report gives a verdict per on-screen window from pixel statistics:

- `renders` — real content
- `blank` — four colours or fewer
- `near-blank` — uniform to within a standard deviation of 3

## Order of questions

1. **Does the app say what is wrong?** The report lifts static text out of
   dialogs. Unigine names the file it cannot open. Rockstar writes
   `launcher.log` next to the executable. Read that before any Wine trace.
2. **Does a window exist?** `enumwin.exe` walks the whole child tree. A missing
   window and an unpainted window need different work.
3. **Is the window on screen?** `winshot` lists macOS windows on every Space.
   `screencapture -x -o -l <id>` captures one by id, which a full-screen grab
   cannot do when the window is on another Space or another display.
4. **Is anything drawn?** `imgstat` scores the capture.
5. **Only then, traces.** `WINEDEBUG=+relay` produces ~270 MB for a 20-second
   run; filter it to calls whose return address is inside the app's own module
   and the sequence becomes readable.

## Comparing against CrossOver

CrossOver runs the same binaries and is the reference for "this should work".
Two cautions learned the hard way:

- CrossOver's release build strips `+relay`, so no call trace comes out of it.
- Its `wine` wrapper needs `CX_BOTTLE` and writes debug output to `$CX_LOG`,
  not to stderr.

Running *our* Wine against a copy of a CrossOver prefix separates a Wine problem
from a prefix problem, and that is what produced the first real backtrace.

## What the probes established

- In-process GDI to a window DC composites.
- **Cross-process GDI to a foreign window's DC returns success and never
  reaches the screen.** Anything built on it fails silently.
- A `WS_CHILD` window created in process B and parented into a window owned by
  process A does composite, including its GDI drawing.
- A Metal layer on such a child does not. `winemac.drv` only has a Cocoa view
  when this process owns the top-level window, so `get_win_data` has nothing to
  give.
- **A window whose thread does not pump messages is never composited**, however
  it is drawn into. This one cost hours: the child was created, parented,
  visible, correctly placed and being blitted into every frame, and the window
  stayed empty. Painting it red unconditionally also showed nothing, which is
  what finally separated "our drawing is wrong" from "this window is not being
  composited at all". DXMT presents from a render thread that never answers
  messages, so the presentation window now owns a thread that does.
- `wined3d` over MoltenVK cannot reach any usable feature level here
  (`None of the requested D3D feature levels is supported`), so D3D11 apps need
  DXMT. It is not optional.

## Traps that produce false evidence

- `nohup` and other SIP-protected binaries strip `DYLD_*`, so Wine loses
  FreeType and renders no text. Export the variables inside the launched script.
- `setsid` does not exist on macOS; the launch silently does nothing and the
  empty log reads as a clean run.
- A stale `wineserver` ignores a new `WINEDEBUG`; traces come back nearly empty.
- Killing Wine by hand produces `wineserver crashed` and `services.exe exited`
  in the log. Neither is a bug.
- DXMT installs itself over Wine's own `d3d11`, `dxgi` and `d3d10core` inside
  the Wine tree, so `WINEDLLOVERRIDES=d3d11=b` still loads DXMT. Testing
  against real wined3d means restoring the `.dxmtbak-*` files first.
- Launchers are single-instance. A second copy signals the first and exits, and
  the log line is `Received command from another instance`.
- **A slept display captures as solid black.** Every window then scores as
  "drew nothing" at once, which reads as a regression from whatever you changed
  last. This cost an hour chasing a BeamNG failure that was not happening;
  BeamNG's own log said it had loaded the level. `pmset -g assertions` shows
  `UserIsActive 0` when it happens, and `caffeinate -u -t 3` wakes it. The
  harness now does that before it looks.
- Neither capture path covers every window. `screencapture -l` returns
  transparency for a window on another Space; ScreenCaptureKit refuses some
  windows with `Failed to start stream`. Try both.

## Results

| App | API | Verdict |
|---|---|---|
| BeamNG.drive | D3D11 | plays, 108–128 FPS |
| Steam | D3D11 + CEF | renders, store and library usable |
| Cave Story | DirectDraw | plays; its 320x240 output sits unscaled in the corner of a full-screen window |
| OpenTTD 14.1 | OpenGL | renders |
| Unigine Heaven | D3D11 via DXMT | renders correctly, 3–19 FPS depending on the view |
| SuperTuxKart 1.5 | OpenGL | runs, but sees OpenGL 2.1 and drops to reduced graphics |
| Rockstar Games Launcher | D3D11 + CEF | sign-in screen renders and holds |
| GZDoom (Vulkan) | Vulkan on MoltenVK | renders and animates; red and blue are pinned at 255 |
| GZDoom (OpenGL) | OpenGL | cannot run, see below |
| D3D9 probe | D3D9 via wined3d | correct, shader model 3.0 |

## Bugs this turned up

- **dbghelp divides by zero evaluating a DWARF expression.** Anything that
  loads dbghelp for a crash handler dies at startup with
  `Unhandled division by zero`. Our own build ships DWARF, so it trips on
  itself; GZDoom is where it showed up. `DW_OP_shra` was separately implemented
  as a division by `1 << n`, which truncates the wrong way for negative values
  and gives a zero divisor once `n` reaches the width of an `int`. It is a
  shift.

  Upstream Wine already fixed both, after the CrossOver 26.1.0 tree we build
  from. `Scripts/patches/dbghelp-dwarf-divide-guard.patch` is a backport of
  their fix, not our own. Worth checking upstream before writing a patch — the
  first version of this was a bespoke variant that would have diverged for no
  reason.

## Capability map

Every row measured by a probe in `Scripts/probes/` that creates a device, clears
to a known colour, presents, and has the capture scored per channel. Nothing
here is inferred.

| API | Word size | Result |
|---|---|---|
| D3D9 | 32-bit | works, shader model 3.0, colour correct |
| D3D9 | 64-bit | works, shader model 3.0, colour correct |
| D3D11 | 32-bit | works, feature level 11_0, colour correct |
| D3D11 | 64-bit | works, feature level 11_0 of 11_1 available, colour correct |
| D3D12 | 64-bit | works through DXMT, resource binding tier 2, colour correct |
| OpenGL | 64-bit | 2.1 compatibility, 4.1 core if the app asks for a core profile |
| Vulkan | 64-bit | works; the one colour fault seen is the app's own setup |

## Which graphics path to use

Measured, not assumed. The probe clears to a known colour and the capture is
scored per channel.

- **D3D11 through DXMT** is the path that works. BeamNG plays at 108–128 FPS.
- **D3D9 through wined3d** works and reports shader model 3.0. Colours are
  correct: a clear to (0, 200, 60) measures r=3 g=195 b=16.
- **D3D11 through wined3d** does not work at all —
  `None of the requested D3D feature levels is supported`. So "wined3d is
  broken" is too coarse: it is broken for D3D11 here, not for D3D9.
- **OpenGL is 2.1 unless the game asks for a core profile.** Wine reports
  `GL version 2.1` and `Core context GL version: 4.1`. SuperTuxKart takes the
  compatibility context, sees 2.1, and warns that the driver is very old.
- **OpenGL above 4.1 cannot work at all.** macOS has no
  `ARB_direct_state_access`. GZDoom asks for the 4.5 DSA entry points, every
  `glVertexArray*` lookup returns null, and it calls one. Games in this
  position need a Vulkan or D3D renderer; there is nothing to fix in Wine.

## Heaven is slow, and tessellation is not why

Heaven renders correctly through DXMT and runs at 3 FPS in the town and 18 FPS
facing the sky. Tessellation is the obvious suspect and it is wrong: the same
camera gives 18 FPS with `TESSELLATION_DISABLED` and 19 with
`TESSELLATION_NORMAL`, which is noise. DXMT does clamp Heaven's tessellation
factor from 15 to 8 for the mesh pipeline, fifteen times at startup, but that
costs nothing per frame. Whatever the cost is, it is elsewhere, and the next
person should not spend the evening on tessellation.
- **Vulkan straight to MoltenVK** works but is where the one colour bug is, and
  D3D9 reaching the same MoltenVK with correct colours says the fault is in how
  GZDoom sets up its swapchain, not in MoltenVK.

## D3D12

Measured with `Scripts/probes/d3d12probe.exe`, which creates a device and reports
the resource binding tier.

| dxgi.dll | d3d12.dll | Result |
|---|---|---|
| DXMT | Wine (vkd3d) | `D3D12CreateDevice` returns `E_NOINTERFACE`; no D3D12 at all |
| Wine | Wine (vkd3d) | device created, **resource binding tier 1** |
| DXMT | DXMT | device created, **resource binding tier 2** |

Replacing `dxgi.dll` is what breaks Wine's D3D12: vkd3d reaches the Vulkan
device through a private interface that only Wine's own DXGI answers, and DXMT's
adapter returns `E_NOINTERFACE` for it. So installing DXMT for D3D11 silently
removes D3D12 unless DXMT's own d3d12 goes in with it.

`d3d12clear.exe` goes further: swapchain, command allocator, command list,
barrier, `ClearRenderTargetView`, `Present`. On DXMT's d3d12 every call returns
`S_OK` and the window measures r=230 g=111 b=28 against the requested
(0.95, 0.45, 0.1). So D3D12 draws, at tier 2, with correct colour.

That corrects an earlier reading of this stack. D3D12 was written off here on
the grounds that MoltenVK caps samplers at 1024 against vkd3d-proton's
requirement. That is true of the vkd3d route and irrelevant to DXMT's, which
goes to Metal directly. What was actually stopping D3D12 was DXMT's dxgi.dll
removing Wine's, with DXMT's own d3d12 not built in release.

Upstream builds DXMT's d3d12 only in the debug configuration; the fork builds it
in release. It remains the experimental part of DXMT, and a clear is not a game.
