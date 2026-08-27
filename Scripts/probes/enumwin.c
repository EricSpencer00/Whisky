#include <windows.h>
#include <stdio.h>
static void dump(HWND h, int depth) {
    char cls[128] = {0}, title[256] = {0};
    RECT r; DWORD pid = 0;
    GetClassNameA(h, cls, sizeof cls);
    GetWindowTextA(h, title, sizeof title);
    GetWindowRect(h, &r);
    GetWindowThreadProcessId(h, &pid);
    printf("%*shwnd=%p pid=%lu vis=%d rect=(%ld,%ld)-(%ld,%ld) cls=%s title=%s\n",
           depth * 2, "", h, (unsigned long)pid, IsWindowVisible(h) ? 1 : 0,
           r.left, r.top, r.right, r.bottom, cls, title);
}
static BOOL CALLBACK child_cb(HWND h, LPARAM l) { dump(h, (int)l); EnumChildWindows(h, child_cb, l + 1); return TRUE; }
static BOOL CALLBACK cb(HWND h, LPARAM l) {
    char cls[128] = {0};
    GetClassNameA(h, cls, sizeof cls);
    if (strstr(cls, "IME") || strstr(cls, "MSCTF")) return TRUE;
    dump(h, 0);
    EnumChildWindows(h, child_cb, 1);
    return TRUE;
}
int main(void) { EnumWindows(cb, 0); return 0; }
