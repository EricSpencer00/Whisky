---
name: wine-app-triage
description: Use when a Windows app fails under the FOSS Wine bundle in this repo — it will not start, shows no window, hangs, or exits with a code. Gives the order to suspect things in, a fast test loop, and the traps that produce false evidence. Read before writing any patch.
---

# Triaging a Windows app on the FOSS bundle

Most failures are configuration, environment, or process lifecycle. Very few
need new code. Suspect in this order and stop at the first hit.

## Order of suspicion

1. **Your own recent changes.** Did a script revert them? `dxmt-install`
   reinstalls stock DXMT and silently overwrote a patched build here.
   Check the file size or hash of what is actually installed.
2. **The launch environment.** See the traps below. Most "the app is broken"
   reports in this repo were the launcher script, not the app.
3. **Config and registry.** Missing settings file, unset key, wrong Windows
   version, missing redistributable.
4. **Process and service lifecycle.** Did a helper process or service start,
   and is it still alive when the app needs it? Is the app waiting on a pipe
   that does not exist yet?
5. **Data.** Missing asset, unreadable font, malformed manifest.
6. **Code.** Last. Only after a named, unimplemented function appears in a log.

## Run the probes first

```sh
./Scripts/run-dosdev-probe.sh        # bundle sane?   exits 2 if not
./Scripts/run-d3d11-probe.sh probe   # renderer sane? want featurelevel=0xb100
```

If both pass and the app still fails, the bundle is not the problem.

## Build the fast loop before investigating

Never `sleep 60` and hope. Watch for the actual event: the process dying, a log
line appearing, an exit code being written. In this repo that took an attempt
from 90 seconds to 13, which is the difference between six experiments an hour
and thirty.

## Timebox the drill

After **three** failed hypotheses, stop and A/B against a known-good instead of
forming a fourth. CrossOver is allowed as a diagnostic reference. Install the
same app in a CrossOver bottle, run both, and diff the app's own log at the
first line where they differ. That is what found the BeamNG bug and the
Rockstar service-connection point, in minutes each, after hours of guessing.

Ask early: is this app worth it? A DRM launcher for a game the user does not
own is not the same value as the game.

## Traps that produce false evidence

- **You killed it.** `pkill -9` on a wine process makes `wineserver crashed`
  appear in the log. Killing the last process in a prefix makes `services.exe
  exited with code 0` appear, which looks like a service crash and is not.
  Record what you killed and when. Ask the user whether they killed something.
- **`nohup` strips `DYLD_*`.** macOS removes those variables when it execs a
  SIP-protected binary. Wine then cannot find `libfreetype.6.dylib` and renders
  no text. Set `DYLD_FALLBACK_LIBRARY_PATH` **inside** the launched script.
- **`setsid` does not exist on macOS.** A launch that uses it silently does
  nothing and the empty log looks like a clean run.
- **A stale `wineserver` disables tracing.** `WINEDEBUG` is read when
  `wineserver` starts. If one is already running, your trace is empty. Kill it
  first and confirm `pgrep -f wineserver` is empty.
- **MoltenVK floods stderr.** Set `MVK_CONFIG_LOG_LEVEL=0` or real errors are
  buried in 153 lines of Vulkan extensions.
- **Backgrounded processes die when the tool call ends.** Launch through the
  bottle runner, which detaches properly.
- **Stale log text.** Check the timestamps inside a log before believing it.
  A DxDiag block from an earlier run was read as current for two iterations.

## Reading logs

The app's own log usually names the subsystem that failed. Find the last line
before the gap, then measure the gap. A multi-second gap with no output is a
wait or a timeout, not a crash. Confirm with the wineserver view: `WINEDEBUG=+server`
shows the request flood, and `select(timeout=...)` shows real waits. All
`timeout=0` means it is doing work, not blocking.

A clean `PROCESS_DETACH` sequence in a relay trace means the app chose to exit.
Search the trace for `ExitProcess` and `TerminateProcess` and read the exit
code; it is often the code the launcher reports.
