#include <windows.h>
#include <winternl.h>
#include <stdio.h>

#ifndef OBJ_CASE_INSENSITIVE
#define OBJ_CASE_INSENSITIVE 0x00000040L
#endif

#define WATCHDOG_SECONDS 15
#define DIRTY_BYTES      (256 * 1024)
#define DIRTY_PATTERN    0xAA

typedef struct { UNICODE_STRING ObjectName; UNICODE_STRING ObjectTypeName; } DIRBASIC;
typedef NTSTATUS (WINAPI *open_dir_t)(HANDLE *, ACCESS_MASK, OBJECT_ATTRIBUTES *);
typedef NTSTATUS (WINAPI *query_dir_t)(HANDLE, void *, ULONG, BOOLEAN, BOOLEAN, ULONG *, ULONG *);
typedef void (WINAPI *init_us_t)(UNICODE_STRING *, const WCHAR *);

static DWORD WINAPI watchdog(void *unused)
{
    (void)unused;
    Sleep(WATCHDOG_SECONDS * 1000);
    printf("### HUNG: no progress in %d s\n", WATCHDOG_SECONDS);
    fflush(stdout);
    ExitProcess(2);
    return 0;
}

/* GetLogicalDrives passes `restart` as a BOOLEAN in a stack slot. A PE compiler
 * that writes only the low byte leaves whatever was already there in the rest of
 * it, so whether the bug fires depends on what the stack happened to hold. Fill
 * that region first to make the outcome the same every run. */
static void dirty_stack(void)
{
    volatile unsigned char buf[DIRTY_BYTES];
    size_t i;

    for (i = 0; i < sizeof(buf); i++)
        buf[i] = DIRTY_PATTERN;
}

static int enumerate(void)
{
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    open_dir_t open_dir = (open_dir_t)GetProcAddress(ntdll, "NtOpenDirectoryObject");
    query_dir_t query_dir = (query_dir_t)GetProcAddress(ntdll, "NtQueryDirectoryObject");
    init_us_t init_us = (init_us_t)GetProcAddress(ntdll, "RtlInitUnicodeString");
    OBJECT_ATTRIBUTES attr;
    UNICODE_STRING name;
    HANDLE dir = NULL;
    NTSTATUS status;
    char data[1024];
    DIRBASIC *info = (DIRBASIC *)data;
    ULONG ctx = 0, len = 0;
    int i;

    init_us(&name, L"\\DosDevices");
    InitializeObjectAttributes(&attr, &name, OBJ_CASE_INSENSITIVE, NULL, NULL);
    if ((status = open_dir(&dir, 0x0001, &attr)))
    {
        printf("### NtOpenDirectoryObject failed 0x%08lx\n", (unsigned long)status);
        return 1;
    }

    for (i = 0; i < 64; i++)
    {
        ULONG before = ctx;

        if ((status = query_dir(dir, info, sizeof(data), TRUE, FALSE, &ctx, &len)))
            break;
        if (ctx == before)
        {
            printf("### FAIL: context stuck at %lu after entry \"%.*S\"\n",
                   (unsigned long)ctx,
                   (int)(info->ObjectName.Length / sizeof(WCHAR)), info->ObjectName.Buffer);
            return 1;
        }
    }
    return 0;
}

int main(void)
{
    DWORD mask;

    setvbuf(stdout, NULL, _IONBF, 0);
    CreateThread(NULL, 0, watchdog, NULL, 0, NULL);

    dirty_stack();
    if (enumerate())
        return 1;

    dirty_stack();
    mask = GetLogicalDrives();
    printf("### GetLogicalDrives = 0x%08lx\n", (unsigned long)mask);

    printf("### PASS\n");
    return 0;
}
