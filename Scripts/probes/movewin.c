#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* movewin <title substring> <x> <y> [w h] — position a window without touching
 * the cursor. */
struct find { const char *want; HWND found; };
static BOOL CALLBACK cb(HWND h, LPARAM l) {
    struct find *f = (struct find *)l;
    char t[256] = {0};
    GetWindowTextA(h, t, sizeof t);
    if (IsWindowVisible(h) && *t && strstr(t, f->want)) { f->found = h; return FALSE; }
    return TRUE;
}
int main(int argc, char **argv) {
    if (argc < 4) { printf("usage: movewin <title> <x> <y> [w h]\n"); return 2; }
    struct find f = { argv[1], NULL };
    EnumWindows(cb, (LPARAM)&f);
    if (!f.found) { printf("no window matching '%s'\n", argv[1]); return 1; }
    int x = atoi(argv[2]), y = atoi(argv[3]);
    UINT fl = SWP_NOZORDER | SWP_NOACTIVATE;
    int w = 0, h = 0;
    if (argc >= 6) { w = atoi(argv[4]); h = atoi(argv[5]); } else fl |= SWP_NOSIZE;
    SetWindowPos(f.found, NULL, x, y, w, h, fl);
    RECT r; GetWindowRect(f.found, &r);
    printf("moved %p to (%ld,%ld)-(%ld,%ld)\n", f.found, r.left, r.top, r.right, r.bottom);
    return 0;
}
