#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdio.h>

/* Device, swapchain, clear, present on its own window. Reports the feature
 * level actually granted, which is the number that decides whether a D3D11
 * title will start. */
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }

int main(void) {
    WNDCLASSA c = {0};
    c.lpfnWndProc = wp; c.hInstance = GetModuleHandleA(NULL); c.lpszClassName = "D3D11Probe";
    RegisterClassA(&c);
    HWND hwnd = CreateWindowExA(0, "D3D11Probe", "D3D11 Probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                                140, 140, 640, 480, NULL, NULL, c.hInstance, NULL);

    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 2; sd.BufferDesc.Width = 640; sd.BufferDesc.Height = 480;
    sd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    IDXGISwapChain *sc = NULL; ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL got = 0;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                               D3D11_SDK_VERSION, &sd, &sc, &dev, &got, &ctx);
    printf("D3D11CreateDeviceAndSwapChain hr=0x%lx featurelevel=0x%x\n", (unsigned long)hr, got);
    fflush(stdout);
    if (FAILED(hr)) return 1;

    ID3D11Texture2D *bb = NULL; ID3D11RenderTargetView *rtv = NULL;
    sc->lpVtbl->GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
    dev->lpVtbl->CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);

    const FLOAT teal[4] = {0.05f, 0.7f, 0.65f, 1.0f};
    for (int i = 0; i < 900; i++) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        ctx->lpVtbl->ClearRenderTargetView(ctx, rtv, teal);
        hr = sc->lpVtbl->Present(sc, 1, 0);
        if (i == 0) { printf("Present hr=0x%lx\n", (unsigned long)hr); fflush(stdout); }
    }
    printf("done\n");
    return 0;
}
