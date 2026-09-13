#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Drives an app past a menu so the harness can see more than a title screen.
 * Posts to the window and also raises it first, because a game reading input
 * through DirectInput or raw input only sees the foreground window. */
struct find { const char *want; HWND found; };

static BOOL CALLBACK cb(HWND h, LPARAM l) {
    struct find *f = (struct find *)l;
    char title[256] = {0};
    GetWindowTextA(h, title, sizeof title);
    if (IsWindowVisible(h) && *title && strstr(title, f->want)) { f->found = h; return FALSE; }
    return TRUE;
}

int main(int argc, char **argv) {
    if (argc < 3) { printf("usage: sendkeys <window title substring> <vk hex> [vk hex...]\n"); return 2; }
    struct find f = { argv[1], NULL };
    EnumWindows(cb, (LPARAM)&f);
    if (!f.found) { printf("no window matching '%s'\n", argv[1]); return 1; }
    printf("window=%p\n", f.found);
    ShowWindow(f.found, SW_RESTORE);
    BringWindowToTop(f.found);
    SetForegroundWindow(f.found);
    Sleep(500);
    for (int i = 2; i < argc; i++) {
        WORD vk = (WORD)strtoul(argv[i], NULL, 16);
        INPUT in[2] = {0};
        in[0].type = INPUT_KEYBOARD; in[0].ki.wVk = vk;
        in[1] = in[0]; in[1].ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput(2, in, sizeof(INPUT));
        PostMessageA(f.found, WM_KEYDOWN, vk, 0);
        PostMessageA(f.found, WM_KEYUP, vk, 0xC0000000);
        printf("sent vk=0x%x\n", vk);
        Sleep(400);
    }
    return 0;
}
