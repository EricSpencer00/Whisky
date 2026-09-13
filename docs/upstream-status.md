# Upstream status: BOOLEAN syscall arguments

**Not filed upstream. Recommendation: do not file yet.** One of three
confirmations fails. Details below so the next person does not have to redo
them. The text to send once it clears is in
[upstream-boolean-syscall-arg.md](upstream-boolean-syscall-arg.md).

## What is established

Mechanism, at instruction level, on this bundle:

- `dlls/kernelbase/volume.c` `GetLogicalDrives` loops
  `while (!NtQueryDirectoryObject( handle, info, sizeof(data), 1, 0, &ctx, &len ))`.
- Our llvm-mingw PE build emits `movb $0x0,0x20(%rsp)` for `restart` and
  `movb $0x1,%r9b` for `single_entry` — one byte each.
- `dlls/ntdll/unix/sync.c` compiles `restart ? 0 : *context` to
  `testl %r8d,%r8d` — 32 bits.
- `dlls/ntdll/unix/signal_x86_64.c` forwards the raw slot: `movq (%r15),%r8`.
- Result: `index` pinned at 0, 2,086,340 identical `get_directory_entries`
  requests on one thread. Causal test: patching that one instruction to
  `testb %r8b,%r8b` gives 5/5 launches reaching the main menu vs 0/5 unpatched.

Compiler difference reproduced locally on the same source line:

| compiler | `restart` | `single_entry` |
|---|---|---|
| gcc-mingw-w64 15.2.0 | `movl $0x0,0x20(%rsp)` | `mov $0x1,%r9d` |
| clang / LLVM | `movb $0x0,0x20(%rsp)` | `movb $0x1,%r9b` |

Both are legal: MS x64 leaves the high bits of a sub-word argument undefined,
System V requires the caller to extend them. Upstream master is unchanged in
both files (`ULONG index = restart ? 0 : *context;`, `movq (%r15),%r8`).

## Cleared, 30 Aug 2026

**2. Upstream CI does build x86_64 PE with llvm-mingw.**
`tools/gitlab/build-linux-arm64` runs
`configure --enable-archs=i386,x86_64,aarch64,arm64ec,arm --with-mingw=clang
CC=clang` with `/usr/local/llvm-mingw/bin` on PATH, so the x86_64 PE files in
that job come from clang. What no job has is a clang-built x86_64 PE side over
an x86_64 unix side: `tools/gitlab/build-mac` uses `--with-mingw` with brew's
gcc-mingw-w64, and the arm64 job's unix side is aarch64. So the toolchain is one
they build, the pairing is one they never run. That makes the question worth
asking rather than out of scope. Rosetta 2 is still untested by them.

**3. No prior report.** `bugs.winehq.org` sits behind an Anubis proof-of-work
check and returns the challenge page to `curl`, so the tracker was searched
through a search engine restricted to that domain rather than through its own
query form. Nothing matches. The nearest is bug 50189, "Multiple 64-bit
applications crash with Wine MinGW PE build due to violation of Windows 64-bit
ABI" — the same family, a different rule, and about stack alignment. Also not it:
`tmatthies/wine mr/syscalls-sysv_abi`, five commits from Dec 2022 that formalise
the unix side as explicitly `sysv_abi`. It never landed — 23,360 commits behind —
and it does not address argument narrowing. This is a search, not an exhaustive
one.

## What is still open

**1. Never reproduced on a stock upstream build.** Everything under "What is
established" ran on CrossOver 26.1.0's tree with our Hack 18311 patch, x86_64
under Rosetta 2 on macOS/aarch64. Upstream master's *source* is identical and
the compiler behaviour is reproduced with stock compilers, but that assembles
the mechanism from parts. `build-wine.sh` can now build the stock tree:

```sh
WINE_SOURCE=upstream WINE_UPSTREAM_REF=master ./Scripts/build-wine.sh
./Scripts/install-bundle.sh --no-verify out/Libraries.tar.gz
./Scripts/run-dosdev-probe.sh
```

It has not been run. It takes 1-3 hours and about 10 GB.

If it prints `### HUNG`, send the mail in
[upstream-boolean-syscall-arg.md](upstream-boolean-syscall-arg.md) — a question
on wine-devel about whether x86_64 PE + llvm-mingw is supported, not a patch.
The fix belongs in the dispatcher or in making the unix entry points `ms_abi`;
the fork-local narrowing in
`Scripts/patches/ntdll-boolean-syscall-arg-abi.patch` does not scale to the 40
syscalls that take a sub-word argument.

If it prints `### PASS`, the hang needs something CodeWeavers' tree adds, the
bug is ours, and nothing goes upstream.
