#include <windows.h>
#include <stdio.h>
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}
int main(void) {
    WNDCLASSA c = {0};
    c.lpfnWndProc = wp; c.hInstance = GetModuleHandleA(NULL);
    c.lpszClassName = "ProbeWin"; c.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    RegisterClassA(&c);
    HWND h = CreateWindowExA(0, "ProbeWin", "GDI Probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                             100, 100, 400, 300, NULL, NULL, c.hInstance, NULL);
    printf("hwnd=%p\n", h); fflush(stdout);
    DWORD start = GetTickCount();
    int painted = 0;
    MSG msg;
    while (1) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) return 0;
            TranslateMessage(&msg); DispatchMessageA(&msg);
        }
        if (!painted && GetTickCount() - start > 3000) {
            HDC dc = GetDC(h); RECT r; GetClientRect(h, &r);
            HBRUSH b = CreateSolidBrush(RGB(0, 0, 255));
            printf("in-process FillRect=%d\n", FillRect(dc, &r, b)); fflush(stdout);
            DeleteObject(b); ReleaseDC(h, dc); painted = 1;
        }
        Sleep(16);
        if (GetTickCount() - start > 60000) return 0;
    }
}
