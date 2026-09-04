#include <windows.h>
#include <d3d11.h>
#include <wrl/client.h>

#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#pragma comment(lib, "d3d11.lib")

using Microsoft::WRL::ComPtr;

static bool ReadFile(const wchar_t* path, std::vector<unsigned char>* bytes)
{
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input)
        return false;

    const std::streamoff size = input.tellg();
    if (size <= 0)
        return false;

    bytes->resize(static_cast<size_t>(size));
    input.seekg(0, std::ios::beg);
    input.read(reinterpret_cast<char*>(bytes->data()), size);
    return input.good();
}

int wmain(int argc, wchar_t** argv)
{
    if (argc < 2) {
        std::fprintf(stderr, "Usage: ShaderFamilyComputeHost.exe shader.bin [shader.bin ...]\n");
        return 10;
    }

    wchar_t modulePath[MAX_PATH] = {};
    HMODULE d3d11Module = GetModuleHandleW(L"d3d11.dll");
    if (!d3d11Module || !GetModuleFileNameW(d3d11Module, modulePath, MAX_PATH)) {
        std::fprintf(stderr, "FAIL: d3d11.dll is not loaded\n");
        return 11;
    }
    std::wprintf(L"D3D11_MODULE=%ls\n", modulePath);

    const D3D_FEATURE_LEVEL requestedLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0
    };
    D3D_FEATURE_LEVEL createdLevel = D3D_FEATURE_LEVEL_11_0;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_WARP,
        nullptr,
        0,
        requestedLevels,
        ARRAYSIZE(requestedLevels),
        D3D11_SDK_VERSION,
        &device,
        &createdLevel,
        &context);
    if (FAILED(hr)) {
        std::fprintf(stderr, "FAIL: D3D11CreateDevice returned 0x%08lx\n", hr);
        return 12;
    }

    for (int index = 1; index < argc; ++index) {
        std::vector<unsigned char> bytecode;
        if (!ReadFile(argv[index], &bytecode)) {
            std::fwprintf(stderr, L"FAIL: unable to read %ls\n", argv[index]);
            return 13;
        }

        ComPtr<ID3D11ComputeShader> shader;
        hr = device->CreateComputeShader(
            bytecode.data(),
            bytecode.size(),
            nullptr,
            &shader);
        if (FAILED(hr)) {
            std::fwprintf(stderr, L"FAIL: CreateComputeShader(%ls) returned 0x%08lx\n",
                argv[index], hr);
            return 14;
        }

        context->CSSetShader(shader.Get(), nullptr, 0);
        // 3Dmigoto performs deferred compute ShaderRegex analysis immediately
        // before Dispatch. Zero groups trigger analysis without executing work.
        context->Dispatch(0, 0, 0);
        context->CSSetShader(nullptr, nullptr, 0);
        std::wprintf(L"CREATED=%ls\n", argv[index]);
    }

    std::printf("FEATURE_LEVEL=0x%04x\n", static_cast<unsigned>(createdLevel));
    std::printf("PASS: %d compute shaders created\n", argc - 1);
    return 0;
}
