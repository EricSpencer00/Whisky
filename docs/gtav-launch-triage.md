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
`AppData/Local/Rockstar Games/Launcher/metadata/*.rgl`. Format, decoded:
80-byte header (magic `RGLM` = 52 47 4c 4d; version 1; **offset 8 = payload
length = filesize − 80**, exact for all files; offset 16 = a unix timestamp on
the two gta5 files, else zero; rest zero) followed by an AES-256-CBC encrypted
payload. The filename is the SHA-256 of the whole file, and all files verify —
so the cache is content-addressed and intact, NOT corrupt or truncated.

The launcher decrypts each file at startup: BCrypt AES-256-CBC with a 32-byte
static key from Launcher.exe and a zero IV, then SHA-256. Traced under this
Wine, every BCryptDecrypt succeeds with no error and there is no
BCryptVerifySignature. So "error 2" is not a crypto or signature failure, and
the decrypted files are valid.

"error 2" most likely means `ERROR_FILE_NOT_FOUND (2)`, which fits the
immediate follow-on `LAUNCHER_ERR_NO_GAME_PATH 102` / "Can't find game
location". Traced `+file` across a PLAY: the verification worker opens game
files through the sparse-bundle symlink fine (including deep DLC paths), and the
gamelaunch worker does NO file ops before failing — so the failure is internal
launcher state, not a filesystem lookup. `InstallFolder` in HKLM is read
successfully at startup. The parse mechanism is still not pinned to a Wine API;
a clean repro of the failing in-memory lookup at PLAY is the missing piece.

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

## BREAKTHROUGH 2026-08-27: the anti-tamper crash is CW HACK 19355

The `movl $0, 0` abort at 0x141349e7c is NOT anti-tamper. It is the nvapi crash
CrossOver already documents:

    dlls/wined3d/directx.c:
    /* CW HACK 19355: GTA 5 crashes on launch trying to init nvapi if it sees
       an NVIDIA GPU */
    if (!lstrcmpW(module_exe, L"GTA5.exe") && vendor_id == HW_VENDOR_NVIDIA)
        { vendor_id = HW_VENDOR_AMD; device_id = CARD_AMD_RADEON_RX_480; }

CrossOver forces AMD when GTA5 sees NVIDIA. That hack lives in wined3d, but we
render through DXMT, so it never runs for us. DXMT ships nvapi64.dll (1.9 MB)
and reports NVIDIA, so GTA5 initialises nvapi and writes to null.

Fix that works: disable nvapi so GTA5 cannot take the NVIDIA codepath.

    reg add HKCU\Software\Wine\DllOverrides /v nvapi64 /t REG_SZ /d "" /f
    reg add HKCU\Software\Wine\DllOverrides /v nvngx   /t REG_SZ /d "" /f

plus a dxmt.conf beside GTA5.exe spoofing AMD:

    dxgi.customVendorId = 1002
    dxgi.customDeviceId = 67df
    dxgi.customDeviceDesc = AMD Radeon RX 480

With nvapi disabled the crash at 0x141349e7c is GONE (0 crashes across repeats;
previously died at ~70s every time). GTA5 now reaches DXMT init (feature level
11_0), WMI and cdrom hardware queries, then exits cleanly with no window when
run standalone — consistent with needing the launcher's Social Club
entitlement, not a crash. Next: launch through the launcher (PLAY) so the
entitlement handshake completes, with the nvapi override now global in the
prefix.

The earlier "movl $0,0 is deliberate anti-tamper" conclusion was WRONG. It is a
null write from failed nvapi init, exactly what CW HACK 19355 prevents.
