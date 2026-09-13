#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    POINT save; GetCursorPos(&save);
    int x = atoi(argv[1]), y = atoi(argv[2]);
    for (int i = 0; i < 8; i++)
    {
        SetCursorPos(x + (i % 2), y + (i % 2));
        Sleep(500);
        CURSORINFO ci = { .cbSize = sizeof(ci) };
        GetCursorInfo(&ci);
        { HWND fg = GetForegroundWindow(); WCHAR ft[80] = {0}; if (fg) GetWindowTextW(fg, ft, 80);
           printf("t=%.1fs hcursor=%p fg=%p \"%ls\"\n", (i + 1) * 0.5, ci.hCursor, fg, ft); }
        fflush(stdout);
    }
    SetCursorPos(save.x, save.y);
    return 0;
}
