/*
 * d3d11-probe.c
 *
 * Minimal D3D11 feature-level probe. Reports what a Wine bundle actually
 * exposes, in two seconds, without launching a game.
 *
 * Two measurements, because they are not the same test:
 *
 *   device   D3D11CreateDevice with no output window.
 *   swapchain  D3D11CreateDeviceAndSwapChain against a real HWND, then a
 *              clear and a Present. This is the path games take, and the only
 *              one that exercises the swapchain/Metal-layer handshake.
 *
 * Build with mingw-w64 — see Scripts/run-d3d11-probe.sh.
 *
 * Reference results on Apple Silicon / macOS 26:
 *
 *   0xb100  feature level 11_1, adapter "AMD Compatibility Mode"
 *           D3DMetal from CrossOver 26.1.0. Matches CrossOver itself.
 *   0x9300  feature level 9_3, adapter "Apple M1 Max"
 *           stock Wine 11 -> wined3d-vulkan -> MoltenVK. wined3d caps here
 *           because Metal has no geometry shaders. This is the same fact as
 *           BeamNG's "Highest DX version supported: 9".
 *   hr=0x887a0004
 *           DXVK 3.x refuses the device: 'geometryShader' unsupported.
 *
 * Exit status: 0 if the swapchain path reached 11_0 or better, else 2.
 */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <d3d11.h>
#include <dxgi.h>

static D3D_FEATURE_LEVEL want[] = {
    D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
    D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
    D3D_FEATURE_LEVEL_9_3,  D3D_FEATURE_LEVEL_9_1 };

static void print_adapter(ID3D11Device *dev)
{
    IDXGIDevice *dxdev = NULL;
    if (FAILED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void**)&dxdev))) return;
    IDXGIAdapter *ad = NULL;
    if (SUCCEEDED(IDXGIDevice_GetAdapter(dxdev, &ad))) {
        DXGI_ADAPTER_DESC d;
        if (SUCCEEDED(IDXGIAdapter_GetDesc(ad, &d)))
            printf("adapter=%ls vendor=0x%04x device=0x%04x vram=%lluMB\n",
                   d.Description, d.VendorId, d.DeviceId,
                   (unsigned long long)(d.DedicatedVideoMemory >> 20));
        IDXGIAdapter_Release(ad);
    }
    IDXGIDevice_Release(dxdev);
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{ return DefWindowProcW(h, m, w, l); }

int main(void)
{
    D3D_FEATURE_LEVEL got = 0;
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;

    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
                                   want, ARRAYSIZE(want), D3D11_SDK_VERSION,
                                   &dev, &got, &ctx);
    printf("device    hr=0x%08lx featurelevel=0x%04x\n", (unsigned long)hr, (unsigned)got);
    fflush(stdout);
    if (SUCCEEDED(hr)) {
        print_adapter(dev);
        ID3D11DeviceContext_Release(ctx);
        ID3D11Device_Release(dev);
        dev = NULL; ctx = NULL;
    }

    WNDCLASSEXW wc = { sizeof(wc) };
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"d3d11probe";
    RegisterClassExW(&wc);
    HWND hwnd = CreateWindowExW(0, L"d3d11probe", L"d3d11probe", WS_OVERLAPPEDWINDOW,
                                CW_USEDEFAULT, CW_USEDEFAULT, 640, 480,
                                NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("swapchain SKIPPED: no window\n"); return 2; }
    ShowWindow(hwnd, SW_SHOW);

    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 640; sd.BufferDesc.Height = 480;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd; sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    IDXGISwapChain *sc = NULL;
    got = 0;
    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
                                       want, ARRAYSIZE(want), D3D11_SDK_VERSION,
                                       &sd, &sc, &dev, &got, &ctx);
    printf("swapchain hr=0x%08lx featurelevel=0x%04x\n", (unsigned long)hr, (unsigned)got);
    fflush(stdout);
    if (FAILED(hr)) return 1;
    print_adapter(dev);

    ID3D11Texture2D *bb = NULL;
    if (SUCCEEDED(IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void**)&bb))) {
        ID3D11RenderTargetView *rtv = NULL;
        if (SUCCEEDED(ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource*)bb, NULL, &rtv))) {
            const float clear[4] = { 0.1f, 0.4f, 0.8f, 1.0f };
            ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
            printf("present   hr=0x%08lx\n", (unsigned long)IDXGISwapChain_Present(sc, 0, 0));
            ID3D11RenderTargetView_Release(rtv);
        }
        ID3D11Texture2D_Release(bb);
    }
    fflush(stdout);
    return got >= D3D_FEATURE_LEVEL_11_0 ? 0 : 2;
}
