#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* postclick <title substring> <client-x> <client-y> — post a click straight to
 * the window's message queue. The physical cursor never moves. */
struct find { const char *want; HWND found; };
static BOOL CALLBACK cb(HWND h, LPARAM l) {
    struct find *f = (struct find *)l;
    char t[256] = {0};
    GetWindowTextA(h, t, sizeof t);
    if (IsWindowVisible(h) && *t && strstr(t, f->want)) { f->found = h; return FALSE; }
    return TRUE;
}
static HWND child_at(HWND root, POINT pt) {
    HWND h = root, prev = NULL;
    while (h && h != prev) {
        prev = h;
        POINT c = pt;
        ScreenToClient(h, &c);
        HWND n = ChildWindowFromPointEx(h, c, CWP_SKIPINVISIBLE | CWP_SKIPTRANSPARENT);
        if (!n || n == h) break;
        h = n;
    }
    return h;
}
int main(int argc, char **argv) {
    if (argc < 4) { printf("usage: postclick <title> <x> <y>\n"); return 2; }
    struct find f = { argv[1], NULL };
    EnumWindows(cb, (LPARAM)&f);
    if (!f.found) { printf("no window '%s'\n", argv[1]); return 1; }
    RECT r; GetWindowRect(f.found, &r);
    POINT pt = { r.left + atoi(argv[2]), r.top + atoi(argv[3]) };
    HWND tgt = child_at(f.found, pt);
    POINT c = pt; ScreenToClient(tgt, &c);
    LPARAM lp = MAKELPARAM(c.x, c.y);
    SetForegroundWindow(f.found);
    Sleep(150);
    PostMessageA(tgt, WM_MOUSEMOVE, 0, lp);
    PostMessageA(tgt, WM_LBUTTONDOWN, MK_LBUTTON, lp);
    Sleep(60);
    PostMessageA(tgt, WM_LBUTTONUP, 0, lp);
    printf("posted click to %p at client (%ld,%ld)\n", tgt, c.x, c.y);
    return 0;
}
