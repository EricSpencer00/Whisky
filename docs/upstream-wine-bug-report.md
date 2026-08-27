# Upstream bug report (draft): sub-word syscall arguments are not narrowed at the PE→unix boundary on x86_64

**Status:** drafted 2026-08-26, not yet filed. Target: https://bugs.winehq.org
(component `ntdll`), or the wine-devel list, since the fix is a design question
rather than a one-line bug.

Everything below is reproduced from a from-source build of CrossOver 26.1.0's
Wine tree (Wine 11.0) on macOS 26 / Apple M1 Max under Rosetta 2, PE side built
with llvm-mingw 20260407. Full detail and the measurements are in
`docs/open-source-roadmap.md`.

---

## Summary

`__wine_syscall_dispatcher` on x86_64 forwards raw 8-byte argument slots from
Microsoft-x64-ABI PE code into System-V unix code without narrowing arguments
that are smaller than 32 bits. The two ABIs disagree about who owns the high
bits, so a `BOOLEAN` argument can arrive as `TRUE` when the caller passed
`FALSE`.

This is normally invisible, because most PE compilers happen to zero-extend. It
becomes visible as soon as one does not.

## The two rules that conflict

- **Microsoft x64:** for an argument narrower than 64 bits, the high bits of the
  register or stack slot are **undefined**. A caller may legally write only the
  low byte.
- **System V AMD64:** the caller is required to sign- or zero-extend arguments
  narrower than 32 bits, so the callee's compiler may test the full 32-bit
  register.

`dlls/ntdll/unix/signal_x86_64.c` bridges them:

```asm
movq %r10,%rdi          /* 1st argument */
movq %r11,%rsi          /* 2nd argument */
movq %r8,%rdx           /* 3rd argument */
movq %r9,%rcx           /* 4th argument */
movq (%r15),%r8         /* 5th argument */
movq 8(%r15),%r9        /* 6th argument */
callq *%r12
```

Whole slots, no narrowing. The syscall table's `ArgumentTable` records the total
argument **byte count**, not per-argument types, so the dispatcher has no way to
know which arguments need it.

## Concrete failure

`NtQueryDirectoryObject( HANDLE, DIRECTORY_BASIC_INFORMATION *, ULONG size,
BOOLEAN single_entry, BOOLEAN restart, ULONG *context, ULONG *ret_size )`.

`dlls/kernelbase/volume.c`, `GetLogicalDrives`:

```c
    char data[1024];
    ULONG ctx = 0, len;
    while (!NtQueryDirectoryObject( handle, info, sizeof(data), 1, 0, &ctx, &len ))
```

llvm-mingw compiles the loop-body call to:

```asm
    movb   $0x0,0x20(%rsp)   ; restart = FALSE — one byte only
    mov    $0x1,%r9b         ; single_entry = TRUE — low byte of r9 only
    call   *%r15
```

`dlls/ntdll/unix/sync.c` compiles `ULONG index = restart ? 0 : *context;` to:

```asm
    testl  %r8d, %r8d        ; tests 32 bits
    jne    ...               ; nonzero -> index stays 0
    movl   (%r9), %r13d      ; else index = *context
```

With stale garbage above the low byte, `restart` reads `TRUE`, `index` is pinned
at 0, the same directory entry is returned forever, and `GetLogicalDrives` never
returns. A `+server` trace shows 2,086,340 identical `get_directory_entries`
requests on one thread, same handle, `index=00000000` every time.

Because the looping thread was inside a `DllMain` and therefore held ntdll's
loader lock, every other thread then timed out in `LdrResolveDelayLoadedAPI` on
`loader_section` — the process looked deadlocked rather than spinning.

Note that `single_entry` survives only by accident: the same function reads it
with `cmpb $0x1,%bl`.

## Why it is easy to miss

- It depends on whatever stack garbage happens to sit above the low byte, so it
  is **stochastic**. In a 5-launch A/B of the affected application, 0/5
  succeeded unpatched and 5/5 succeeded patched — but a single control run had
  passed, which is exactly how this gets misfiled as a race.
- Running under `+relay` changes the garbage and appears to "fix" it, which
  strongly suggests a timing race that is not there.
- CrossOver's own builds are unaffected because their PE compiler emits
  `movl $0x0,0x20(%rsp)` / `mov $0x1,%r9d` at the same source line. That is
  luck, not a guarantee, and it means the bug is invisible to the vendor whose
  tree this is.

## Scope

40 syscall entry points in `dlls/ntdll/unix/` take a by-value sub-word argument
and are subject to the same failure. A partial list of the ones where a spurious
`TRUE` changes semantics rather than merely being ignored:

| syscall | argument | effect if wrongly TRUE |
|---|---|---|
| `NtQueryDirectoryObject` | `restart` | infinite enumeration loop (this report) |
| `NtQueryDirectoryFile` | `restart_scan` | infinite enumeration loop |
| `NtQueryEaFile` | `restart` | infinite enumeration loop |
| `NtCreateEvent` | `state` | event created already signalled |
| `NtCreateMutant` | `owned` | mutant created already owned |
| `NtCreateThread` | `suspended` | thread never runs |
| `NtLockFile` | `dont_wait`, `exclusive` | wrong locking semantics |
| `NtWaitForSingleObject` and friends | `alertable` | spurious `STATUS_USER_APC` |
| `NtNotifyChangeKey` | `subtree`, `async` | wrong notification semantics |
| `NtDuplicateToken` | `effective_only` | wrong token contents |

## Possible fixes

1. **Generate per-syscall narrowing metadata.** The syscall tables are already
   generated; emit a bitmask of which arguments are sub-word alongside
   `ArgumentTable` and have the dispatcher `movzbl` those slots. Complete and
   cheap at runtime, but touches the generator and the asm on every architecture
   with an ABI transition.
2. **Make the unix-side syscall entry points `ms_abi`.** Removes the ABI
   transition entirely, so the compiler knows the high bits are undefined and
   narrows on its own. Cleanest, largest change.
3. **Narrow defensively in each affected function.** What this fork does today,
   for `NtQueryDirectoryObject` only:

   ```c
   static inline int syscall_bool_arg( BOOLEAN value )
   {
       return *(volatile unsigned char *)&value != 0;
   }
   ```

   Compiles to `movb`/`cmpb` instead of `testl`. Correct but does not scale to 40
   call sites and is easy to regress.

(1) or (2) is the real fix. This fork carries (3) as
`Scripts/patches/ntdll-boolean-syscall-arg-abi.patch` because it is the minimal
change that unblocks a shipping bundle.

## Reproducer

`Scripts/dosdev-probe.c` in this repo enumerates `\DosDevices` directly and
prints whether the context advances. Note that it will often pass on an affected
build — the garbage has to be non-zero — so it is a confirmation tool, not a
detector. The load-bearing test is the repeated-launch A/B described above.
