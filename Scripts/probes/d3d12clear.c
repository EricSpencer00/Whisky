#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

/* Creating a device says nothing about whether anything draws. This makes a
 * swapchain, clears it to a known colour and presents, which is the smallest
 * thing a D3D12 title does. */
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }

static HRESULT last_hr;
#define CHECK(what, call) do { last_hr = (call); \
                               printf("%s hr=0x%lx\n", what, (unsigned long)last_hr); fflush(stdout); \
                               if (FAILED(last_hr)) return __LINE__; } while (0)

int main(void) {
    WNDCLASSA c = {0};
    c.lpfnWndProc = wp; c.hInstance = GetModuleHandleA(NULL); c.lpszClassName = "D3D12Clear";
    RegisterClassA(&c);
    HWND hwnd = CreateWindowExA(0, "D3D12Clear", "D3D12 Clear", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                                120, 120, 640, 480, NULL, NULL, c.hInstance, NULL);

    IDXGIFactory4 *factory = NULL;
    CHECK("CreateDXGIFactory1", CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&factory));
    ID3D12Device *device = NULL;
    CHECK("D3D12CreateDevice", D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device));

    D3D12_COMMAND_QUEUE_DESC qd = {0};
    ID3D12CommandQueue *queue = NULL;
    CHECK("CreateCommandQueue", device->lpVtbl->CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue, (void **)&queue));

    DXGI_SWAP_CHAIN_DESC1 sd = {0};
    sd.BufferCount = 2; sd.Width = 640; sd.Height = 480;
    sd.Format = DXGI_FORMAT_R8G8B8A8_UNORM; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD; sd.SampleDesc.Count = 1;
    IDXGISwapChain1 *sc1 = NULL;
    CHECK("CreateSwapChainForHwnd", factory->lpVtbl->CreateSwapChainForHwnd(factory, (IUnknown *)queue, hwnd, &sd, NULL, NULL, &sc1));
    IDXGISwapChain3 *sc = NULL;
    CHECK("QI IDXGISwapChain3", sc1->lpVtbl->QueryInterface(sc1, &IID_IDXGISwapChain3, (void **)&sc));

    D3D12_DESCRIPTOR_HEAP_DESC hd = { .Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV, .NumDescriptors = 2 };
    ID3D12DescriptorHeap *heap = NULL;
    CHECK("CreateDescriptorHeap", device->lpVtbl->CreateDescriptorHeap(device, &hd, &IID_ID3D12DescriptorHeap, (void **)&heap));
    UINT stride = device->lpVtbl->GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

    D3D12_CPU_DESCRIPTOR_HANDLE rtv;
    heap->lpVtbl->GetCPUDescriptorHandleForHeapStart(heap, &rtv);
    ID3D12Resource *targets[2] = {0};
    for (UINT i = 0; i < 2; i++) {
        CHECK("GetBuffer", sc->lpVtbl->GetBuffer(sc, i, &IID_ID3D12Resource, (void **)&targets[i]));
        D3D12_CPU_DESCRIPTOR_HANDLE h = { rtv.ptr + (SIZE_T)i * stride };
        device->lpVtbl->CreateRenderTargetView(device, targets[i], NULL, h);
    }

    ID3D12CommandAllocator *alloc = NULL;
    CHECK("CreateCommandAllocator", device->lpVtbl->CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&alloc));
    ID3D12GraphicsCommandList *list = NULL;
    CHECK("CreateCommandList", device->lpVtbl->CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, NULL, &IID_ID3D12GraphicsCommandList, (void **)&list));
    printf("before Close\n"); fflush(stdout);
    list->lpVtbl->Close(list);
    printf("after Close\n"); fflush(stdout);

    ID3D12Fence *fence = NULL;
    CHECK("CreateFence", device->lpVtbl->CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence));
    printf("after CreateFence\n"); fflush(stdout);
    HANDLE event = CreateEventA(NULL, FALSE, FALSE, NULL);
    UINT64 value = 0;

    const FLOAT orange[4] = {0.95f, 0.45f, 0.1f, 1.0f};
    for (int frame = 0; frame < 900; frame++) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        if (frame == 0) { printf("loop start\n"); fflush(stdout); }
        UINT index = sc->lpVtbl->GetCurrentBackBufferIndex(sc);
        if (frame == 0) { printf("got index %u\n", index); fflush(stdout); }
        alloc->lpVtbl->Reset(alloc);
        list->lpVtbl->Reset(list, alloc, NULL);
        D3D12_RESOURCE_BARRIER to_rt = { .Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
            .Transition = { .pResource = targets[index], .StateBefore = D3D12_RESOURCE_STATE_PRESENT,
                            .StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET,
                            .Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES } };
        list->lpVtbl->ResourceBarrier(list, 1, &to_rt);
        D3D12_CPU_DESCRIPTOR_HANDLE h = { rtv.ptr + (SIZE_T)index * stride };
        list->lpVtbl->ClearRenderTargetView(list, h, orange, 0, NULL);
        D3D12_RESOURCE_BARRIER to_present = to_rt;
        to_present.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
        to_present.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        list->lpVtbl->ResourceBarrier(list, 1, &to_present);
        list->lpVtbl->Close(list);
        ID3D12CommandList *lists[] = { (ID3D12CommandList *)list };
        queue->lpVtbl->ExecuteCommandLists(queue, 1, lists);
        HRESULT hr = sc->lpVtbl->Present(sc, 1, 0);
        if (frame == 0) { printf("Present hr=0x%lx\n", (unsigned long)hr); fflush(stdout); }
        queue->lpVtbl->Signal(queue, fence, ++value);
        if (fence->lpVtbl->GetCompletedValue(fence) < value) {
            fence->lpVtbl->SetEventOnCompletion(fence, value, event);
            WaitForSingleObject(event, 1000);
        }
    }
    printf("done\n");
    return 0;
}
