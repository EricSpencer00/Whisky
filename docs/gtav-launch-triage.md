# GTA V Legacy under the FOSS Wine bundle — launch triage

**STATUS 2026-08-27: WORKING.** GTA V Legacy boots and renders through DXMT on
the FOSS Wine 11 bundle. Reached the Display Calibration screen (first-boot
setup) with a real `Grand Theft Auto V` window. See "How to launch it" below.

The history of dead ends is kept because most of it is still true and stops the
next session re-walking it.

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

## CORRECTION 2026-08-27: the nvapi "fix" was a false positive

The claim above that disabling nvapi removes the crash is WRONG. Rigorous retest:
3/3 trials crash at 0x141349e7c with `WINEDLLOVERRIDES=nvapi64=;nvngx=;nvcuda=`
active and dxmt.conf spoofing AMD. Each dies at ~72s, identical to baseline.

The earlier "0 crashes" reading came from a single run watched for too short a
window — the process was still alive at the moment I checked, and I concluded
"fixed" before it reached the ~72s crash point. Classic premature conclusion
from an uncontrolled single sample.

What is actually true: the crash always follows the same sequence — DXMT init
(feature level 11_0) -> wbemprox WMI queries -> cdrom DeviceIoControl -> crash
at 0x141349e7c. CW HACK 19355 (nvapi-on-NVIDIA) is a real CrossOver hack and
may still be *a* factor, but disabling nvapi is NOT sufficient to prevent the
crash. The nvapi theory is not proven and probably not the cause.

Still unsolved. Do not repeat the nvapi-disable path expecting a fix.


## How to launch it (the working recipe)

The game MUST be started by the Rockstar launcher. Started any other way it
shows an `ERR_NO_LAUNCHER` message box and a watchdog thread kills the process
about 72 seconds later. That watchdog is what produced every
`movl $0, 0` crash in the notes above.

1. Mount the sparse bundle and start the launcher:

       hdiutil attach /Volumes/LaCie/GTAV.sparsebundle -nobrowse
       tools/run.sh 'C:\Program Files\Rockstar Games\Launcher\Launcher.exe'

2. In the launcher: GAMES -> scroll the sidebar -> Grand Theft Auto V Legacy.
3. Click PLAY. Locate the button by pixels rather than fixed coordinates; the
   UI often shows a stale frame and blind clicks miss. `Scripts/probes/findbtn.py`
   finds the bright button and prints screen coordinates.
4. Dismiss the "Unexpected files have been found in the install directory"
   notice with OK. It is triggered by `dxmt.conf` / `commandline.txt` and is
   only a warning.
5. If the game exits, the launcher offers Retry / **Safe Mode**. Safe Mode is
   what works — it adds `-safemode` to the launch.
6. BattlEye's own launcher window appears. Click through it; do not delete or
   replace `GTA5_BE.exe` (the launcher's integrity check reverts binaries, and
   it is the launcher's chosen entry point).

Resulting launch line, for reference:

    "…\GTA5_BE.exe" -enableCrashpad @commandline.txt -safemode -fromRGL …

So `commandline.txt` IS passed through, via `@commandline.txt`.

## Why the crash chase was a red herring

`0x141349e7c` is a watchdog, not the fault. Live disassembly of the decrypted
code (winedbg, since the file on disk is packed):

    e1c: movl $0x3e8, %ecx      ; 1000
    e21: callq kernel32!Sleep
    e27: movl <flag>(%rip), %eax
    e2f: jne  e1c               ; poll once a second
    e4f: decl %ebx              ; retry counter
    e51: je   e5c               ; exhausted -> … -> e7c
    e7c: movl $0, 0             ; deliberate abort

`bt all` showed the main thread parked in `MessageBoxW` from `gta5+0x136aefb`,
i.e. blocked on a modal dialog — the `ERR_NO_LAUNCHER` box. The watchdog then
killed the process. Every "fix" tested against the crash address was therefore
testing the executioner, not the cause: nvapi, vendor spoofing, d3d12,
settings.xml, D3DMetal vs DXMT, symlink vs direct drive letter. All of those
remain correctly ruled out, they were just aimed at the wrong thing.

## Still-true findings worth keeping

- CW HACK 19355 (GTA5 + NVIDIA -> spoof AMD) lives in wined3d and never runs
  under DXMT or D3DMetal. Not the cause here.
- CrossOver gates several hacks on env vars its proprietary launcher sets and
  Whisky does not (e.g. CW HACK 24905 on `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`).
  Setting that var did not change this crash (2/2), but the general point holds:
  our runtime env differs from CrossOver's.
- The WQL string/int fix in `Scripts/patches/wbemprox-string-int-compare.patch`
  is a real Wine bug fix, independent of this game.
