#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static int g_transparent;
static int g_clicks;

static LRESULT CALLBACK parent_proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_LBUTTONDOWN || m == WM_NCLBUTTONDOWN)
    {
        WCHAR t[64];
        wsprintfW(t, L"clicks=%d", ++g_clicks);
        SetWindowTextW(h, t);
    }
    return DefWindowProcW(h, m, w, l);
}

static LRESULT CALLBACK child_proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_NCHITTEST && g_transparent) return HTTRANSPARENT;
    if (m == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    return DefWindowProcW(h, m, w, l);
}

static void pump(int ms)
{
    for (int i = 0; i < ms / 20; i++) { MSG msg; while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); } Sleep(20); }
}

int main(int argc, char **argv)
{
    WNDCLASSEXW c = { .cbSize = sizeof(c) };
    HINSTANCE hi = GetModuleHandleW(NULL);

    if (argc > 1 && !strcmp(argv[1], "parent"))
    {
        c.lpfnWndProc = parent_proc;
        c.hInstance = hi;
        c.hCursor = LoadCursorW(NULL, (LPCWSTR)IDC_ARROW);
        c.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        c.lpszClassName = L"CursorParent";
        RegisterClassExW(&c);
        HWND w = CreateWindowExW(0, L"CursorParent", L"cursor parent",
                                 WS_OVERLAPPEDWINDOW | WS_VISIBLE, 40, 500, 300, 240, NULL, NULL, hi, NULL);
        printf("parent=%p\n", w); fflush(stdout);
        pump(60000);
        return 0;
    }

    /* child <parent-hwnd-hex> <flags>
     *   flags: t = HTTRANSPARENT, x = WS_EX_TRANSPARENT, d = WS_DISABLED,
     *          n = WS_EX_NOACTIVATE, c = class cursor */
    HWND parent = (HWND)(ULONG_PTR)strtoull(argv[2], NULL, 16);
    const char *f = argv[3];
    DWORD ex = 0, style = WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS;
    g_transparent = !!strchr(f, 't');
    if (strchr(f, 'x')) ex |= WS_EX_TRANSPARENT;
    if (strchr(f, 'n')) ex |= WS_EX_NOACTIVATE;
    if (strchr(f, 'd')) style |= WS_DISABLED;

    c.lpfnWndProc = child_proc;
    c.hInstance = hi;
    c.hCursor = strchr(f, 'c') ? LoadCursorW(NULL, (LPCWSTR)IDC_ARROW) : NULL;
    c.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    c.lpszClassName = L"CursorChildProbe";
    RegisterClassExW(&c);

    RECT r;
    GetClientRect(parent, &r);
    MapWindowPoints(parent, GetAncestor(parent, GA_ROOT), (POINT *)&r, 2);
    HWND w = CreateWindowExW(ex, L"CursorChildProbe", L"", style,
                             r.left, r.top, r.right - r.left, r.bottom - r.top,
                             GetAncestor(parent, GA_ROOT), NULL, hi, NULL);
    printf("child=%p ex=%lx style=%lx\n", w, ex, style); fflush(stdout);
    pump(60000);
    return 0;
}
