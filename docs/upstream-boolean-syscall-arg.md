# BOOLEAN syscall arguments: the report, ready to send

**Not sent.** One gate is still open — see the end. The text below is what goes
to wine-devel once it closes. Nothing here is filed anywhere.

The record of what is and is not established is
[upstream-status.md](upstream-status.md).

---

Subject: is x86_64 PE built with llvm-mingw supported?

Building Wine on macOS with llvm-mingw on PATH, `GetLogicalDrives()` never
returns.

`NtQueryDirectoryObject` takes two `BOOLEAN` arguments. clang writes one byte of
each argument slot:

    movb $0x0,0x20(%rsp)      ; restart
    movb $0x1,%r9b            ; single_entry

`dlls/ntdll/unix/sync.c` is compiled for System V, where the caller extends a
sub-word argument, so `ULONG index = restart ? 0 : *context;` becomes
`testl %r8d,%r8d`. `__wine_syscall_dispatcher` forwards the slot unchanged
(`dlls/ntdll/unix/signal_x86_64.c`, `movq (%r15),%r8`), so whatever the PE side
left above the low byte decides the branch. When that is not zero, `index` stays
0 and the loop in `GetLogicalDrives()` runs forever.

gcc-mingw-w64 15.2.0 writes the full width for the same source line:

    movl $0x0,0x20(%rsp)
    mov  $0x1,%r9d

Both are correct. The MS x64 ABI leaves the high bits of a sub-word argument
undefined.

Reproducer, 15 seconds, no application needed:
[`Scripts/dosdev-probe.c`](../Scripts/dosdev-probe.c). It fills 256 KB of stack
with `0xAA`, then enumerates `\DosDevices` and reports whether the context
advances. On a bundle built this way it hangs 3 times out of 3, and passes 3 out
of 3 once the argument is narrowed to one byte.

40 syscall entry points take a `BOOLEAN` or `UCHAR` argument, so narrowing them
one at a time does not scale. If this configuration is meant to work, the fix
belongs in the dispatcher, or in making the unix entry points `ms_abi`.

---

## Before sending

Reproduce it on a stock tree. `build-wine.sh` can build one:

```sh
WINE_SOURCE=upstream WINE_UPSTREAM_REF=master ./Scripts/build-wine.sh
./Scripts/install-bundle.sh --no-verify out/Libraries.tar.gz
./Scripts/run-dosdev-probe.sh
```

`### HUNG` on that bundle is the missing evidence, and the three commands above
are then the whole reproduction recipe for the mail. `### PASS` means the hang
needs something CodeWeavers' tree adds, and none of this should be sent.
