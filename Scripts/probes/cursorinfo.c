#include <windows.h>
#include <stdio.h>

static void sample(const char *tag)
{
    CURSORINFO ci = { .cbSize = sizeof(ci) };
    POINT pt;
    HWND w;
    WCHAR cls[128] = {0};
    DWORD pid = 0;

    GetCursorPos(&pt);
    GetCursorInfo(&ci);
    w = WindowFromPoint(pt);
    if (w) { GetClassNameW(w, cls, 128); GetWindowThreadProcessId(w, &pid); }

    printf("%-8s pos=(%ld,%ld) flags=%lx hcursor=%p under=%p pid=%lu cls=%ls\n",
           tag, pt.x, pt.y, ci.flags, ci.hCursor, w, pid, cls);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    POINT save;
    GetCursorPos(&save);
    sample("before");

    if (argc >= 3)
    {
        int x = atoi(argv[1]), y = atoi(argv[2]);
        SetCursorPos(x, y);
        Sleep(300);
        sample("moved");
        SetCursorPos(x + 3, y + 3);
        Sleep(300);
        sample("jiggle");
        SetCursorPos(save.x, save.y);
    }
    return 0;
}
