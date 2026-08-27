#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    POINT p = { atoi(argv[1]), atoi(argv[2]) };
    HWND w = WindowFromPoint(p);
    while (w)
    {
        WCHAR cls[96] = {0};
        GetClassNameW(w, cls, 96);
        printf("hwnd=%p cls=%-34ls classcur=%p style=%lx\n",
               w, cls, (void *)GetClassLongPtrW(w, GCLP_HCURSOR), GetWindowLongW(w, GWL_STYLE));
        if (!(GetWindowLongW(w, GWL_STYLE) & WS_CHILD)) break;
        w = GetParent(w);
    }
    return 0;
}
