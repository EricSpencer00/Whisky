#include <windows.h>
#include <stdio.h>
#include <string.h>

/* Brings a window to the front so a capture can see it. A Wine window created
 * while another Space was active stays there, and both screencapture modes
 * then report it as transparent, which reads as "the app drew nothing". */
static BOOL CALLBACK cb(HWND h, LPARAM l) {
    char title[256] = {0};
    GetWindowTextA(h, title, sizeof title);
    if (*(const char **)l && strstr(title, *(const char **)l) && IsWindowVisible(h)) {
        ShowWindow(h, SW_RESTORE);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        printf("fronted hwnd=%p title=%s\n", h, title);
    }
    return TRUE;
}
int main(int argc, char **argv) {
    const char *want = argc > 1 ? argv[1] : "";
    EnumWindows(cb, (LPARAM)&want);
    return 0;
}
