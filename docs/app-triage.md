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

## Results

| App | API | Verdict |
|---|---|---|
| BeamNG.drive | D3D11 | plays, 108–128 FPS |
| Steam | D3D11 + CEF | renders, store and library usable |
| Cave Story | DirectDraw | renders |
| OpenTTD 14.1 | OpenGL | renders |
| Unigine Heaven | D3D11 | runs, needs its own launcher for arguments |
| Rockstar Games Launcher | D3D11 + CEF | initialises fully, UI window stays unpainted |
| GZDoom (Vulkan) | Vulkan on MoltenVK | renders, but the green channel is missing |
| GZDoom (OpenGL) | OpenGL | null function pointer; macOS OpenGL lacks entry points it calls |

## Bugs this turned up

- **Wine's dbghelp divides by zero evaluating a DWARF expression.** Anything
  that loads dbghelp for a crash handler dies at startup with
  `Unhandled division by zero`. Our own build ships DWARF, so it trips on
  itself. Fixed by `Scripts/patches/dbghelp-dwarf-divide-guard.patch`.
- **`DW_OP_shra` was implemented as a division by `1 << n`.** That truncates the
  wrong way for negative values and gives a zero divisor once `n` reaches the
  width of an `int`. It is a shift.
