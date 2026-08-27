# Running Windows games on Apple Silicon with no paid software

This fork builds Wine from [CodeWeavers' LGPL-published CrossOver source](https://www.codeweavers.com/crossover/source)
and pairs it with [DXMT](https://github.com/3Shain/dxmt) for Direct3D 11.
Nothing here requires CrossOver, Apple's Game Porting Toolkit, or a developer
account. Every component is redistributable.

**Status:** BeamNG.drive 0.38.5 is playable — 108-128 FPS at 1280x720 on an
M1 Max, driving a vehicle, with the in-game HTML UI compositing correctly.

## Requirements

- Apple Silicon Mac, macOS 26 or later
- Rosetta 2 (`softwareupdate --install-rosetta`) — see the caveat at the bottom
- Your own legally obtained copy of whatever you want to run

## Quick start

```sh
git clone https://github.com/EricSpencer00/Whisky
cd Whisky

# Download the prebuilt bundle from the latest release, install it, and add DXMT
./Scripts/install-bundle.sh --run-id <id-of-a-successful-BuildWine-run>

# or, if you already have Libraries.tar.gz
./Scripts/install-bundle.sh path/to/Libraries.tar.gz
```

`install-bundle.sh` exists because the release tarball is **Wine only**.
Installing it by hand and stopping there drops two things and then fails
*quietly*, reporting Direct3D feature level 9_3 instead of erroring:

- `lib/wine/x86_64-unix/libvulkan.1.dylib`, a symlink to MoltenVK. `win32u`
  dlopens that exact filename from that exact directory and searches nowhere
  else.
- `lib/wine/x86_64-unix/winemetal.so`, DXMT's unixlib.

The script does the tarball, the symlink, DXMT, and then verifies.

## Check that it works

```sh
./Scripts/run-dosdev-probe.sh    # bundle sane?    exits 2 if not
./Scripts/run-d3d11-probe.sh probe   # renderer sane?
```

Expected:

```
### PASS
device    hr=0x00000000 featurelevel=0xb100
adapter=Apple M1 Max vendor=0x106b device=0x0000
swapchain hr=0x00000000 featurelevel=0xb100
present   hr=0x00000000
```

`0xb100` is feature level 11_1. If you see `0x9300` the renderer fell back to
wined3d and DXMT is not installed.

## Building Wine yourself

```sh
./Scripts/build-wine.sh          # 60-90 min cold, much less with a warm ccache
WINE_ARCHS=x86_64 ./Scripts/build-wine.sh   # 64-bit only
```

Or run the `BuildWine` workflow and take the artifact.

## Installing games

The bottle is a normal Wine prefix, so anything that works in Wine works here.
For Steam games, `steamcmd` is the path of least resistance — it is a console
app, needs no CEF, and downloads games you already own:

```sh
export WINEPREFIX=~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<uuid>
wine64 'C:\steamcmd\steamcmd.exe' +login <your-account> +app_update <appid> +quit
```

The Steam client itself also runs, including its seven CEF helper processes, but
its own UI hits a DXMT limitation ([3Shain/dxmt#141](https://github.com/3Shain/dxmt/issues/141)),
so use `steamcmd` for installing and updating.

## Triage when something does not work

Run the two probes above first. They tell you which layer is at fault, which is
worth far more than guessing:

| probe result | meaning |
|---|---|
| `run-dosdev-probe.sh` fails | the Wine bundle is bad — rebuild or reinstall |
| probe passes, `run-d3d11-probe.sh` shows `0x9300` | DXMT is not installed |
| both pass, game is broken or slow | the renderer or the game — report to DXMT, not here |

That last row matters. A game that launches and renders but runs badly is
almost always a DXMT maturity issue, not a bundle issue, and patching Wine will
not help.

## Known limitations

- **Direct3D 12 is not supported.** DXMT implements D3D11 and D3D10.
- **Direct3D 9 and older** bypass DXMT and go through wined3d and MoltenVK,
  which is a different and much less capable path.
- **Anti-cheat** (BattlEye, EAC) does not work and is not a goal.
- **Heavy tessellation workloads** are weak. Unigine Heaven stalls before asset
  loading under D3D11 while the same build runs it fine under D3D9.
- **Apple is removing Rosetta 2.** macOS 27 (Sept 2026) still supports it but
  uninstalls it on upgrade; macOS 28 (fall 2027) largely removes it. Everything
  here is x86_64 under Rosetta. Tracking issue: #20.
