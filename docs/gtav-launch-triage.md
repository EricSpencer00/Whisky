# GTA V Legacy under the FOSS Wine bundle — launch triage

Status 2026-08-27: installed and entitled, does not reach gameplay. This is the
map of what was tried so the next session does not re-walk it.

## What works

- Rockstar launcher runs, signs in, renders (DXMT). Social Club installs.
- GTA V Legacy downloaded to the LaCie: 119 GB, version 1.0.3889.0, verified
  (`Checked 1593 chunk(s), 0 were empty`).
- Registry and filesystem paths resolve; `GTA5.exe` is reachable through the
  sparse-bundle symlink.

## What blocks gameplay

Two independent walls.

### 1. Direct GTA5.exe launch — anti-tamper abort

Running `GTA5.exe` outside the launcher aborts deterministically (3/3) at a
fixed address. winedbg gives the faulting instruction:

    0x141349e7c  gta5+0x1349e7c:  movl $0, 0
    Backtrace: gta5+0x1349e7c <- gta5+0x1352146 <- kernel32 thread thunk <- ntdll

`movl $0, 0` is a deliberate write-to-null, i.e. the game's own anti-tamper
killing itself because it was not started through the launcher handshake. This
is not a Wine bug and not fixable from our side. Confirmed backend-independent:
identical under DXMT and under CrossOver 26.1 D3DMetal. Ruled out along the way,
each reproducing the same address: d3d12 disabled, AMD vendor-ID spoof
(`dxgi.customVendorId`), `-scOfflineOnly`, and a pre-written `settings.xml`
(untouched by the game, so it dies before reading graphics settings). GTA5.exe
is packed, so static disassembly of the fault site is garbage.

### 2. Launcher PLAY — metadata parse failure

The supported path is to let the launcher start the game. It cannot:

    [metadatamanager] Unable to parse metadata from buffer, error 2
    [gamelaunch] Begin game launch: gta5
    [gamelaunch] Can't find game location to launch!   (LAUNCHER_ERR_NO_GAME_PATH 102)

`metadatamanager` fails to parse the title metadata for *every* title, so the
launch worker cannot build the exe path and PLAY dies before `Launch Path`.

The metadata files are the launcher's own cache in
`AppData/Local/Rockstar Games/Launcher/metadata/*.rgl`: magic `RGLM`
(52 47 4c 4d), version 1, then a 4-byte type/flags word (not a length —
values 0x630, 0x430, 0x1e00 do not match file sizes). Clearing the cache and
re-downloading does not help: fresh files fail identically, so it is not cache
corruption.

Traced `+bcrypt,+crypt32` across all launcher pids through a parse failure:
heavy `BCryptHashData` / `BCryptGenerateSymmetricKey` / `BCryptGenerateKeyPair`
but **no `BCryptVerifySignature` and no asymmetric verify**, and no crypto error
near the parse. So "error 2" is not a signature check Wine is failing; it reads
as an internal format/round-trip parse code on files the launcher itself wrote.
Mechanism not yet proven to a specific Wine API — proving it needs
launcher-internal instrumentation. Do NOT file this upstream until the API is
pinned; it would be a speculative issue.

## Dead ends — do not retry

- **Editing GTA5_BE.exe (BattlEye wrapper) or any game file.** The launcher's
  integrity check reverts it. It rewrote a replaced `GTA5_BE.exe` twice within
  minutes (service_log, 20:42). A shim there cannot survive.
- **Typing `-nobattleye` into the launcher's launch-arguments field by
  automation** — the keystrokes did not land (Chromium focus). If pursued, fix
  foreground/focus first.

## Legitimate next step

Nail the metadata parse mechanism (Wine-side, same class as the WQL fix in
`Scripts/patches/wbemprox-string-int-compare.patch`). Candidate approach:
`+relay` on the metadatamanager thread, or a targeted `+file,+ntdll` trace of
the read path for a single `.rgl`, to find the API whose Wine behaviour differs
from Windows. With the API in hand this becomes a real upstream issue and
probably a small patch. Not security work — ordinary app-compat.
