#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

/* The cursor is sticky global state: a window that never answers WM_SETCURSOR
 * leaves whatever the last window set. Park over a window with a null class
 * cursor first, so a non-null reading means this arm really set one. */
static void moveto(int x, int y)
{
    SetCursorPos(x, y); Sleep(150);
    SetCursorPos(x + 2, y + 2); Sleep(250);
}

int main(int argc, char **argv)
{
    POINT save; GetCursorPos(&save);
    int rx = atoi(argv[1]), ry = atoi(argv[2]);
    int x = atoi(argv[3]), y = atoi(argv[4]);

    moveto(rx, ry);
    CURSORINFO r = { .cbSize = sizeof(r) }; GetCursorInfo(&r);

    moveto(x, y);
    CURSORINFO ci = { .cbSize = sizeof(ci) }; GetCursorInfo(&ci);
    POINT p = { x + 2, y + 2 };
    HWND u = WindowFromPoint(p);
    WCHAR cls[64] = {0}; if (u) GetClassNameW(u, cls, 64);

    INPUT in[2] = {0};
    in[0].type = INPUT_MOUSE; in[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    in[1].type = INPUT_MOUSE; in[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(2, in, sizeof(INPUT));
    Sleep(400);

    printf("reset=%p cursor=%p under=%ls", r.hCursor, ci.hCursor, cls);
    SetCursorPos(save.x, save.y);
    return 0;
}
