/*
 * d3d11-probe.c
 *
 * Minimal D3D11 feature-level probe. Creates a hardware device, prints the
 * feature level that came back and the DXGI adapter behind it. Build with
 * mingw-w64 (see Scripts/run-d3d11-probe.sh) and run inside a bottle.
 *
 * This exists so "what D3D level does this bundle actually expose?" can be
 * answered in two seconds without launching a game. BeamNG reporting
 * "Highest DX version supported: 9" is the same measurement, 40 GB later.
 *
 * Known outputs on Apple Silicon / macOS 26:
 *
 *   featurelevel=0x9300  adapter=Apple M1 Max   stock Wine 11 -> wined3d-vulkan
 *                                               -> MoltenVK. No geometry
 *                                               shaders, so wined3d caps at 9_3.
 *
 *   hr=0x887a0004                               DXVK 3.x: refuses the device
 *                                               ('geometryShader' unsupported).
 *
 * A pass is featurelevel=0xb000 (11_0) or better.
 */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <d3d11.h>
#include <dxgi.h>

int main(void)
{
    D3D_FEATURE_LEVEL want[] = {
        D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
        D3D_FEATURE_LEVEL_9_3,  D3D_FEATURE_LEVEL_9_1 };
    D3D_FEATURE_LEVEL got = 0;
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
                                   want, ARRAYSIZE(want), D3D11_SDK_VERSION,
                                   &dev, &got, &ctx);
    printf("D3D11CreateDevice hr=0x%08lx featurelevel=0x%04x\n",
           (unsigned long)hr, (unsigned)got);
    if (FAILED(hr)) return 1;

    IDXGIDevice *dxdev = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void**)&dxdev))) {
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

    ID3D11DeviceContext_Release(ctx);
    ID3D11Device_Release(dev);
    return got >= D3D_FEATURE_LEVEL_11_0 ? 0 : 2;
}
