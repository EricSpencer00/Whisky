#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

/* Does D3D12 work at all? Reports the feature level and the resource-binding
 * tier, which is what decides whether a modern title will start. */
int main(void) {
    IDXGIFactory4 *factory = NULL;
    HRESULT hr = CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&factory);
    printf("CreateDXGIFactory1 hr=0x%lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;

    hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, NULL);
    printf("D3D12CreateDevice(capability check) hr=0x%lx  (S_FALSE=1 means it could be created)\n",
           (unsigned long)hr);

    ID3D12Device *device = NULL;
    hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
    printf("D3D12CreateDevice(11_0) hr=0x%lx device=%p\n", (unsigned long)hr, device);
    if (FAILED(hr)) return 2;

    D3D12_FEATURE_DATA_D3D12_OPTIONS opts = {0};
    hr = device->lpVtbl->CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS, &opts, sizeof opts);
    printf("Options hr=0x%lx ResourceBindingTier=%d TiledResourcesTier=%d ConservativeRasterTier=%d\n",
           (unsigned long)hr, opts.ResourceBindingTier, opts.TiledResourcesTier,
           opts.ConservativeRasterizationTier);

    D3D12_COMMAND_QUEUE_DESC qd = {0};
    ID3D12CommandQueue *queue = NULL;
    hr = device->lpVtbl->CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue, (void **)&queue);
    printf("CreateCommandQueue hr=0x%lx\n", (unsigned long)hr);

    ID3D12Resource *buffer = NULL;
    D3D12_HEAP_PROPERTIES heap = { .Type = D3D12_HEAP_TYPE_UPLOAD };
    D3D12_RESOURCE_DESC rd = { .Dimension = D3D12_RESOURCE_DIMENSION_BUFFER, .Width = 4096, .Height = 1,
                               .DepthOrArraySize = 1, .MipLevels = 1, .SampleDesc.Count = 1,
                               .Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR };
    hr = device->lpVtbl->CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE, &rd,
                                              D3D12_RESOURCE_STATE_GENERIC_READ, NULL,
                                              &IID_ID3D12Resource, (void **)&buffer);
    printf("CreateCommittedResource hr=0x%lx\n", (unsigned long)hr);
    return 0;
}
