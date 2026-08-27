# Upstream status: BOOLEAN syscall arguments

**Not filed upstream. Recommendation: do not file yet.** Two of three
confirmations fail. Details below so the next person does not have to redo them.

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

## Why not to file

**1. Never reproduced on a stock upstream build.** Everything above ran on
CrossOver 26.1.0's tree with our Hack 18311 patch, x86_64 under Rosetta 2 on
macOS/aarch64. Upstream master's *source* is identical, and the compiler
behaviour is reproduced with stock compilers, but that is assembling the
mechanism from parts — not an end-to-end reproduction on stock Wine.

**2. This is not a configuration upstream tests.** Wine's CI uses
gcc-mingw-w64 for x86_64; llvm-mingw appears only in the arm64 job
(`tools/gitlab/build-linux-arm64`, `--with-mingw=clang CC=clang`). x86_64 PE +
llvm-mingw is possible per their docs but untested by them. Rosetta 2 on Apple
Silicon is not tested by them at all.

**3. Prior art not cleared.** No matching report found, but
`bugs.winehq.org` search returns 403 to automated fetches, and a Wine merge
request branch `mr/syscalls-sysv_abi` (tmatthies) exists that may already be
reworking this exact boundary. It is behind Anubis and was not read.

## What would close it

1. Read `https://gitlab.winehq.org/tmatthies/wine/-/tree/mr/syscalls-sysv_abi`
   in a real browser. If it already changes the unix side's ABI, there is
   nothing to file.
2. Search `bugs.winehq.org` by hand for the dispatcher and argument extension.
3. Build stock upstream master with `--with-mingw=clang` on x86_64 and reproduce
   the hang with no CrossOver tree and no local patches.

If all three clear, the contribution is a question on wine-devel about whether
x86_64 + llvm-mingw is supported — not a patch. The fix belongs in the
dispatcher or in making the unix entry points `ms_abi`; the fork-local narrowing
in `Scripts/patches/ntdll-boolean-syscall-arg-abi.patch` does not scale to the
40 syscalls that take a sub-word argument.
