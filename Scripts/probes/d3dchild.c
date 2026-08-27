#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    HWND target = (HWND)(uintptr_t)strtoull(argv[1], NULL, 0);
    printf("target=%p pid_of_target=", target);
    DWORD tpid = 0; GetWindowThreadProcessId(target, &tpid);
    printf("%lu self=%lu\n", (unsigned long)tpid, (unsigned long)GetCurrentProcessId());
    fflush(stdout);

    RECT r; GetClientRect(target, &r);
    UINT w = r.right - r.left, h = r.bottom - r.top;

    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL got;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                   D3D11_SDK_VERSION, &dev, &got, &ctx);
    printf("D3D11CreateDevice hr=0x%lx fl=0x%x\n", (unsigned long)hr, got); fflush(stdout);
    if (FAILED(hr)) return 1;

    IDXGIDevice *dxgi = NULL; IDXGIAdapter *ad = NULL; IDXGIFactory2 *fac = NULL;
    dev->lpVtbl->QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgi);
    dxgi->lpVtbl->GetAdapter(dxgi, &ad);
    ad->lpVtbl->GetParent(ad, &IID_IDXGIFactory2, (void **)&fac);

    DXGI_SWAP_CHAIN_DESC1 sd = {0};
    sd.Width = w; sd.Height = h; sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 2; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    IDXGISwapChain1 *sc = NULL;
    hr = fac->lpVtbl->CreateSwapChainForHwnd(fac, (IUnknown *)dev, target, &sd, NULL, NULL, &sc);
    printf("CreateSwapChainForHwnd hr=0x%lx size=%ux%u\n", (unsigned long)hr, w, h); fflush(stdout);
    if (FAILED(hr)) return 2;

    ID3D11Texture2D *bb = NULL; ID3D11RenderTargetView *rtv = NULL;
    sc->lpVtbl->GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
    dev->lpVtbl->CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);

    const FLOAT green[4] = {0.0f, 0.8f, 0.2f, 1.0f};
    for (int i = 0; i < 200; i++) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        ctx->lpVtbl->ClearRenderTargetView(ctx, rtv, green);
        hr = sc->lpVtbl->Present(sc, 1, 0);
        if (i == 0) { printf("Present hr=0x%lx\n", (unsigned long)hr); fflush(stdout); }
        Sleep(33);
    }
    return 0;
}
