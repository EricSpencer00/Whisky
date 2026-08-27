/* dosdev-probe.c — regression probe for the BOOLEAN-syscall-argument ABI bug.
 *
 * Wine's kernelbase GetLogicalDrives() and QueryDosDeviceW(NULL,...) both loop
 *
 *     while (!NtQueryDirectoryObject( h, info, sizeof(data), 1, 0, &ctx, &len ))
 *
 * over \DosDevices. The PE side is Microsoft-x64-ABI code and may write only
 * the low byte of the `restart` argument's stack slot; the unix side is
 * System-V code and tests the full 32-bit register. Stale garbage in the high
 * bits makes `restart` read TRUE, which pins the enumeration index at 0 and the
 * loop never terminates. See Scripts/patches/ntdll-boolean-syscall-arg-abi.patch
 * and docs/open-source-roadmap.md.
 *
 * A healthy build prints ctx advancing 0 -> 1 -> 2 ... and reaches "probe done".
 * A broken build either prints "ctx DID NOT ADVANCE" or hangs in
 * GetLogicalDrives(). Note the bug is stack-garbage dependent, so a single
 * clean run does not prove a build is fixed — the BeamNG A/B in the roadmap is
 * the load-bearing test.
 *
 * Build:  x86_64-w64-mingw32-gcc -O1 -o dosdev-probe.exe Scripts/dosdev-probe.c -lntdll
 */
#include <windows.h>
#include <winternl.h>
#ifndef OBJ_CASE_INSENSITIVE
#define OBJ_CASE_INSENSITIVE 0x00000040L
#endif
#include <stdio.h>

typedef struct { UNICODE_STRING ObjectName; UNICODE_STRING ObjectTypeName; } DIRBASIC;

typedef NTSTATUS (WINAPI *pNtOpenDirectoryObject_t)(HANDLE*, ACCESS_MASK, OBJECT_ATTRIBUTES*);
typedef NTSTATUS (WINAPI *pNtQueryDirectoryObject_t)(HANDLE, void*, ULONG, BOOLEAN, BOOLEAN, ULONG*, ULONG*);
typedef void (WINAPI *pRtlInitUnicodeString_t)(UNICODE_STRING*, const WCHAR*);

static pNtQueryDirectoryObject_t pNtQueryDirectoryObject;

int main(void)
{
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    pNtOpenDirectoryObject_t   pOpen = (void*)GetProcAddress(nt, "NtOpenDirectoryObject");
    pRtlInitUnicodeString_t    pInit = (void*)GetProcAddress(nt, "RtlInitUnicodeString");
    pNtQueryDirectoryObject = (void*)GetProcAddress(nt, "NtQueryDirectoryObject");

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("### probe start\n");

    UNICODE_STRING us; OBJECT_ATTRIBUTES attr; HANDLE h = NULL;
    pInit(&us, L"\\DosDevices");
    InitializeObjectAttributes(&attr, &us, OBJ_CASE_INSENSITIVE, NULL, NULL);
    NTSTATUS st = pOpen(&h, 0x0001 /*DIRECTORY_QUERY*/, &attr);
    printf("### NtOpenDirectoryObject = 0x%08lx handle=%p\n", (unsigned long)st, h);
    if (st) return 1;

    /* Exactly kernelbase's loop, but bounded and instrumented. */
    char data[1024];
    DIRBASIC *info = (DIRBASIC *)data;
    ULONG ctx = 0, len = 0;
    int i;
    for (i = 0; i < 24; i++)
    {
        ULONG ctx_before = ctx;
        st = pNtQueryDirectoryObject(h, info, sizeof(data), 1, 0, &ctx, &len);
        printf("### [%2d] status=0x%08lx ctx %lu -> %lu len=%lu name=\"%.*S\"\n",
               i, (unsigned long)st, (unsigned long)ctx_before, (unsigned long)ctx,
               (unsigned long)len,
               st ? 0 : (int)(info->ObjectName.Length / sizeof(WCHAR)),
               st ? L"" : info->ObjectName.Buffer);
        if (st) break;
        if (ctx == ctx_before) { printf("### ctx DID NOT ADVANCE -> this is the infinite loop\n"); break; }
    }

    /* Same thing with an explicit ULONG-sized restart arg forced to 0, to see
     * whether the BOOLEAN stack argument is what is arriving wrong. */
    printf("### now calling GetLogicalDrives() (hangs if the loop is unbounded)\n");
    DWORD mask = GetLogicalDrives();
    printf("### GetLogicalDrives() = 0x%08lx\n", (unsigned long)mask);

    printf("### now calling QueryDosDeviceW(NULL, buf, 65536)\n");
    static WCHAR big[65536];
    DWORD n = QueryDosDeviceW(NULL, big, 65536);
    printf("### QueryDosDeviceW = %lu (err=%lu)\n", (unsigned long)n, (unsigned long)GetLastError());

    printf("### probe done\n");
    return 0;
}
