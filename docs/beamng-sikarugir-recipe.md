# BeamNG.drive via Sikarugir + DXMT — the actually-working recipe

After exhausting the Whisky-internal paths documented in
[`beamng-runbook.md`](beamng-runbook.md), the only Wine-based wrapper that
currently reaches the BeamNG rendering stage on Apple Silicon is
[Sikarugir](https://github.com/Sikarugir-App/Sikarugir) (Gcenx's Wineskin
successor) with DXMT 0.74 manually installed over the default Wine 10.0
engine's D3D11 DLLs. This is a Whisky-family tool (Wine + per-app wrappers)
so it satisfies the "via Whisky/Wine" constraint without depending on
archived upstream Whisky.

## Verified with this recipe

- ✅ Wine 10.0 launches cleanly
- ✅ MoltenVK 1.4.1 + 153 Vulkan extensions enumerated
- ✅ BeamNG detects `Apple M1 Max (D3D11)` as the adapter (via DXMT → Metal)
- ✅ `GFXD3D11Device::init Hardware occlusion query detected: Yes` — feature
  level 11 confirmed
- ✅ BeamNG window created: `BeamNG.drive - 0.38.5.0.19602 - RELEASE - Direct3D11`
- ⚠️ CEF helper subprocesses still crash (~30–167 winedbg auto-attaches per
  run). Main menu doesn't come up. This is the next blocker, but it's a
  meaningfully different (and better) blocker than Whisky's FL9 refusal.

## One-time setup

```bash
# 1. Sikarugir Creator (used once to download state dirs; not needed for the
#    manual wrapper build that follows)
brew install --cask Sikarugir-App/sikarugir/sikarugir

# 2. Rosetta 2 (BeamNG.drive.x64.exe is x86_64 PE)
/usr/sbin/softwareupdate --install-rosetta --agree-to-license
```

## Build the wrapper manually (no Creator GUI required)

```bash
set -e
mkdir -p /tmp/sik && cd /tmp/sik

# Template + engine
curl -fL -o Template-1.0.11.tar.xz \
  https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz
curl -fL -o WS11Wine10.0_3.tar.xz \
  https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS11Wine10.0_3.tar.xz
curl -fL -o dxmt.tar.gz \
  https://github.com/3Shain/dxmt/releases/download/v0.74/dxmt-v0.74-builtin.tar.gz

tar -xJf Template-1.0.11.tar.xz
tar -xJf WS11Wine10.0_3.tar.xz
tar -xzf dxmt.tar.gz
mkdir -p ~/Applications/Sikarugir

# Build wrapper
WRAPPER=~/Applications/Sikarugir/BeamNG.app
cp -R Template-1.0.11.app "$WRAPPER"

# Install Wine 10 engine
mv wswine.bundle "$WRAPPER/Contents/SharedSupport/wswine.bundle"

# Install DXMT 0.74 over default Wine D3D11 DLLs
ENG64="$WRAPPER/Contents/SharedSupport/wswine.bundle/lib/wine/x86_64-windows"
ENG32="$WRAPPER/Contents/SharedSupport/wswine.bundle/lib/wine/i386-windows"
ENGU="$WRAPPER/Contents/SharedSupport/wswine.bundle/lib/wine/x86_64-unix"
cp -f v0.74/x86_64-windows/{d3d11,dxgi,d3d10core,winemetal}.dll "$ENG64/"
cp -f v0.74/i386-windows/{d3d11,dxgi,d3d10core,winemetal}.dll "$ENG32/" 2>/dev/null || true
cp -f v0.74/x86_64-unix/winemetal.so "$ENGU/"

# freetype needs to sit in the engine lib dir for rpath resolution
cp -f "$WRAPPER/Contents/Frameworks/libfreetype.6.dylib" \
      "$WRAPPER/Contents/SharedSupport/wswine.bundle/lib/"

# Initialise Wine prefix
WINE="$WRAPPER/Contents/SharedSupport/wswine.bundle/bin/wine"
env \
  DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wswine.bundle/lib" \
  WINEPREFIX="$WRAPPER/Contents/SharedSupport/prefix" \
  "$WINE" wineboot -u

# Link BeamNG (from the old Whisky install — avoids re-downloading 30 GB)
PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
mkdir -p "$PREFIX/drive_c/steamcmd/steamapps/common"
ln -s "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<YOUR-BOTTLE-UUID>/drive_c/steamcmd/steamapps/common/BeamNG.drive" \
  "$PREFIX/drive_c/steamcmd/steamapps/common/BeamNG.drive"

# Copy VC++ runtime from the same place
OLD="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<YOUR-BOTTLE-UUID>"
for arch in system32 syswow64; do
  cp -f "$OLD/drive_c/windows/$arch"/{msvcp140*,vcruntime140*,ucrtbase,concrt140}.dll \
    "$PREFIX/drive_c/windows/$arch/" 2>/dev/null
done

# Mark wrapper's DXMT = on in Info.plist (future Sikarugir SDK launcher support)
plutil -replace DXMT -integer 1 "$WRAPPER/Contents/Info.plist"
plutil -replace "Program Name and Path" -string \
  "C:\\steamcmd\\steamapps\\common\\BeamNG.drive\\Bin64\\BeamNG.drive.x64.exe" \
  "$WRAPPER/Contents/Info.plist"
plutil -replace "Program Flags" -string "-nosteam -noeos" "$WRAPPER/Contents/Info.plist"
```

## Launch

The Sikarugir SDK launcher has trouble with our manually-installed DXMT
DLLs (it returns `WineAppInitializationError error 1`), so use direct Wine:

```bash
WRAPPER=~/Applications/Sikarugir/BeamNG.app
env \
  DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wswine.bundle/lib" \
  WINEPREFIX="$WRAPPER/Contents/SharedSupport/prefix" \
  WINEDEBUG=-all \
  WINEESYNC=1 \
  WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b" \
  "$WRAPPER/Contents/SharedSupport/wswine.bundle/bin/wine" \
  "$WRAPPER/Contents/drive_c/steamcmd/steamapps/common/BeamNG.drive/Bin64/BeamNG.drive.x64.exe" \
  -nosteam -noeos
```

Wine may place the window off-screen by default. Use `Mission Control`
(swipe up three fingers) to find it, drag to a visible area, and click to
focus.

## Additional runtime components (required)

The initial recipe above reaches a rendering BeamNG window but CEF
subprocesses crash (~170 `winedbg --auto` invocations per session).
Installing the missing Microsoft Visual C++ and font runtime via
winetricks drops the crash count dramatically and makes the game render
its window at full size. Run once per wrapper:

```bash
brew install cabextract  # winetricks dependency
curl -fL -o /tmp/winetricks \
  https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x /tmp/winetricks

WRAPPER=~/Applications/Sikarugir/BeamNG.app
# libinotify needs to be alongside wineserver (@rpath resolution)
cp -f "$WRAPPER/Contents/Frameworks/libinotify.0.dylib" \
      "$WRAPPER/Contents/SharedSupport/wswine.bundle/lib/"

env \
  DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wswine.bundle/lib" \
  WINEPREFIX="$WRAPPER/Contents/SharedSupport/prefix" \
  WINE="$WRAPPER/Contents/SharedSupport/wswine.bundle/bin/wine" \
  WINESERVER="$WRAPPER/Contents/SharedSupport/wswine.bundle/bin/wineserver" \
  PATH="$WRAPPER/Contents/SharedSupport/wswine.bundle/bin:/opt/homebrew/bin:$PATH" \
  /tmp/winetricks -q corefonts vcrun2019 d3dcompiler_47
```

After this:
- `winedbg --auto` crash count: 170 → 20 (per session)
- BeamNG opens a full-size D3D11 window titled
  `BeamNG.drive - 0.38.5.0.19602 - RELEASE - Direct3D11` via DXMT/Metal
- Game log progresses to game-time ~7–10 s then stalls

## Remaining blocker (2026-04-17)

~20 `winedbg --auto` subprocesses still crash per run, and the BeamNG
window stays black (CEF subprocess never completes its initial paint).
The main process survives indefinitely at 30 % CPU / 950 MB RSS, so
autostart.lua's 25 s-game-time gridmap_v2 load never executes (game's
main loop is blocked on the CEF wait).

Next investigations (not done yet):
- `winetricks dotnet48` — some CEF versions require .NET Framework at
  load time.
- `winetricks -q --force ie8` to seed additional IE/MSHTML state.
- Replace libcef.dll with a matched-version build from CEF's own
  distribution that may have different subprocess-handling quirks.
- Force CEF single-process mode via
  `WINEDLLOVERRIDES` plus a Chromium-compatible wrapper around
  `libcef.dll`'s entry points that injects `--single-process` into the
  command line before `CefExecuteProcess`. Needs a small shim DLL.

Tracked in [issue #1](https://github.com/EricSpencer00/Whisky/issues/1).

## Why this is the best-case today

Prior Whisky-based attempts all fail at `D3D11::init → Incompatible
DirectX Device / Highest DX version supported: 9` because Wine 7.7's
wined3d/DXVK-async stack returns feature level 9 on MoltenVK. DXMT's
Metal-native D3D11 is the only path that reports feature level 11 on
Apple Silicon without CodeWeavers' proprietary D3DMetal/GPTK binaries.
This recipe gets BeamNG further than anything else we've tried in the
Whisky family — just not yet to the main menu.

## Best currently-working path: CrossOver 26

Homebrew cask: `brew install --cask crossover` — CrossOver 26 is free for 14 days.

```bash
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver

# Create 64-bit bottle
"$CX/bin/cxbottle" --bottle BeamNG --create --template win10_64

# Link your BeamNG install (adjust path to your Whisky bottle's BeamNG.drive)
BNG_SRC="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<UUID>/drive_c/steamcmd/steamapps/common/BeamNG.drive"
mkdir -p ~/Library/Application\ Support/CrossOver/Bottles/BeamNG/drive_c/steamcmd/steamapps/common
ln -s "$BNG_SRC" ~/Library/Application\ Support/CrossOver/Bottles/BeamNG/drive_c/steamcmd/steamapps/common/BeamNG.drive

# Install VC runtime via winetricks
curl -fL -o /tmp/winetricks \
  https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x /tmp/winetricks
env WINEPREFIX=~/Library/Application\ Support/CrossOver/Bottles/BeamNG \
    WINE="$CX/bin/wine" \
    WINESERVER="$CX/bin/wineserver" \
    PATH="$CX/bin:/opt/homebrew/bin:$PATH" \
    /tmp/winetricks -q vcrun2019 d3dcompiler_47

# Launch
"$CX/bin/cxstart" --bottle BeamNG \
  'C:\steamcmd\steamapps\common\BeamNG.drive\Bin64\BeamNG.drive.x64.exe' \
  -- -nosteam -noeos
```

**What CrossOver 26 achieves vs every FOSS Wine path tested:**
- CefManager::init completes (game-time 21s, not a timeout)
- Shader compile runs (game-time 33s, past where Sikarugir stalled)
- fmod audio banks load completely (game-time 23s)
- D3D11 device reset succeeds at 1280x720
- No `winedbg --auto` crashes at all

CrossOver bundles CodeWeavers' patched Wine **plus** Apple's D3DMetal 3.0
with the matching `__wine_unix_call` internals. That integration is what
makes BeamNG's CEF work — and why Sikarugir's generic Wine 10 fails even
when it has the same D3DMetal.framework on disk.

**Limitation observed in this session**: game still stalls around
game-time 33s with a black window on this specific macOS 26 / M1 Max
config. Additional CrossOver-side tweaks (winecfg, registry overrides,
further winetricks components) are needed — MacGamingDB community reports
show BeamNG fully playable on CrossOver 26 with specific per-user config,
so this is a config gap rather than a code gap.

