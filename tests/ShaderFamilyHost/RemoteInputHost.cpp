#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <cstdio>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

using Microsoft::WRL::ComPtr;

static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

int main()
{
    wchar_t modulePath[MAX_PATH] = {};
    HMODULE d3d11Module = GetModuleHandleW(L"d3d11.dll");
    if (!d3d11Module || !GetModuleFileNameW(d3d11Module, modulePath, MAX_PATH))
        return 10;
    std::wprintf(L"D3D11_MODULE=%ls\n", modulePath);

    WNDCLASSW windowClass = {};
    windowClass.lpfnWndProc = WindowProc;
    windowClass.hInstance = GetModuleHandleW(NULL);
    windowClass.lpszClassName = L"ThreeDMigotoRemoteInputHost";
    if (!RegisterClassW(&windowClass))
        return 11;

    HWND window = CreateWindowExW(
        WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
        windowClass.lpszClassName,
        L"3Dmigoto Remote Input Offline Host",
        WS_OVERLAPPED | WS_CAPTION,
        32, 32, 360, 100,
        NULL, NULL, windowClass.hInstance, NULL);
    if (!window)
        return 12;
    ShowWindow(window, SW_SHOWNOACTIVATE);

    const D3D_FEATURE_LEVEL requestedLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0
    };
    D3D_FEATURE_LEVEL createdLevel = D3D_FEATURE_LEVEL_11_0;

    DXGI_SWAP_CHAIN_DESC swapChainDescription = {};
    swapChainDescription.BufferDesc.Width = 360;
    swapChainDescription.BufferDesc.Height = 100;
    swapChainDescription.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swapChainDescription.SampleDesc.Count = 1;
    swapChainDescription.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapChainDescription.BufferCount = 1;
    swapChainDescription.OutputWindow = window;
    swapChainDescription.Windowed = TRUE;
    swapChainDescription.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    ComPtr<IDXGISwapChain> swapChain;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr,
        D3D_DRIVER_TYPE_WARP,
        nullptr,
        0,
        requestedLevels,
        ARRAYSIZE(requestedLevels),
        D3D11_SDK_VERSION,
        &swapChainDescription,
        &swapChain,
        &device,
        &createdLevel,
        &context);
    if (FAILED(hr))
        return 13;

    // 3Dmigoto dispatches input actions from its Present path. The host remains
    // deliberately unfocused while it pumps Presents for external IPC testing.
    context->Draw(3, 0);
    context->Flush();
    hr = swapChain->Present(0, 0);
    if (FAILED(hr))
        return 14;

    HANDLE ready = CreateFileW(L"ready.flag", GENERIC_WRITE, FILE_SHARE_READ,
        NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (ready == INVALID_HANDLE_VALUE)
        return 15;
    CloseHandle(ready);

    ULONGLONG endTime = GetTickCount64() + 20000;
    MSG message = {};
    while (GetTickCount64() < endTime) {
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        context->Draw(3, 0);
        context->Flush();
        swapChain->Present(0, 0);
        Sleep(10);
    }

    DestroyWindow(window);
    std::wprintf(L"PASS: remote input host completed background Present loop\n");
    return 0;
}
