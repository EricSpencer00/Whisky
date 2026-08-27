#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

/* Does D3D9 work at all? Creates a device on its own window, clears green and
 * presents. A game that fails here fails for reasons nothing above D3D9 can fix. */
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }

int main(void) {
    WNDCLASSA c = {0};
    c.lpfnWndProc = wp; c.hInstance = GetModuleHandleA(NULL); c.lpszClassName = "D3D9Probe";
    RegisterClassA(&c);
    HWND h = CreateWindowExA(0, "D3D9Probe", "D3D9 Probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                             100, 100, 640, 480, NULL, NULL, c.hInstance, NULL);
    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    printf("Direct3DCreate9 = %p\n", d3d); fflush(stdout);
    if (!d3d) return 1;

    D3DCAPS9 caps;
    HRESULT hr = IDirect3D9_GetDeviceCaps(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, &caps);
    printf("GetDeviceCaps hr=0x%lx vs=%lx ps=%lx\n", (unsigned long)hr,
           (unsigned long)caps.VertexShaderVersion, (unsigned long)caps.PixelShaderVersion);
    fflush(stdout);

    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_UNKNOWN; pp.hDeviceWindow = h;
    IDirect3DDevice9 *dev = NULL;
    hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, h,
                                 D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    printf("CreateDevice hr=0x%lx dev=%p\n", (unsigned long)hr, dev); fflush(stdout);
    if (FAILED(hr)) return 2;

    for (int i = 0; i < 200; i++) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0, 200, 60), 1.0f, 0);
        hr = IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
        if (i == 0) { printf("Present hr=0x%lx\n", (unsigned long)hr); fflush(stdout); }
        Sleep(33);
    }
    return 0;
}
