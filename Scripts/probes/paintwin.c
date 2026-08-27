#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    HWND h = (HWND)(uintptr_t)strtoull(argv[1], NULL, 0);
    HDC dc = GetDC(h);
    if (!dc) { printf("GetDC failed %lu\n", GetLastError()); return 1; }
    RECT r; GetClientRect(h, &r);
    HBRUSH b = CreateSolidBrush(RGB(255, 0, 0));
    int n = FillRect(dc, &r, b);
    printf("FillRect=%d rect=%ld,%ld,%ld,%ld\n", n, r.left, r.top, r.right, r.bottom);
    DeleteObject(b);
    ReleaseDC(h, dc);
    return 0;
}
