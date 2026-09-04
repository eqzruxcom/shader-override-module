#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

#include <cstdio>
#include <fstream>
#include <string>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d3dcompiler.lib")

using Microsoft::WRL::ComPtr;

static const char kFixtureShader[] = R"hlsl(
Texture2D FamilyTexture : register(t0);
SamplerState FamilySampler : register(s0);

cbuffer FamilyConstants : register(b0)
{
    float4 FamilyTint;
};

float4 main(float2 uv : TEXCOORD0) : SV_Target0
{
    return FamilyTexture.Sample(FamilySampler, uv) * FamilyTint;
}
)hlsl";

static bool WriteBlob(const char* path, ID3DBlob* blob)
{
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output)
        return false;
    output.write(static_cast<const char*>(blob->GetBufferPointer()),
                 static_cast<std::streamsize>(blob->GetBufferSize()));
    return output.good();
}

int main()
{
    wchar_t modulePath[MAX_PATH] = {};
    HMODULE d3d11Module = GetModuleHandleW(L"d3d11.dll");
    if (!d3d11Module || !GetModuleFileNameW(d3d11Module, modulePath, MAX_PATH)) {
        std::fprintf(stderr, "FAIL: d3d11.dll is not loaded\n");
        return 10;
    }
    std::wprintf(L"D3D11_MODULE=%ls\n", modulePath);

    ComPtr<ID3DBlob> shaderBytecode;
    ComPtr<ID3DBlob> compileErrors;
    HRESULT hr = D3DCompile(
        kFixtureShader,
        sizeof(kFixtureShader) - 1,
        "ShaderFamilyFixture.hlsl",
        nullptr,
        nullptr,
        "main",
        "ps_5_0",
        D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_OPTIMIZATION_LEVEL3,
        0,
        &shaderBytecode,
        &compileErrors);
    if (FAILED(hr)) {
        if (compileErrors)
            std::fprintf(stderr, "%.*s\n",
                static_cast<int>(compileErrors->GetBufferSize()),
                static_cast<const char*>(compileErrors->GetBufferPointer()));
        std::fprintf(stderr, "FAIL: D3DCompile returned 0x%08lx\n", hr);
        return 11;
    }

    ComPtr<ID3DBlob> disassembly;
    hr = D3DDisassemble(
        shaderBytecode->GetBufferPointer(),
        shaderBytecode->GetBufferSize(),
        D3D_DISASM_ENABLE_INSTRUCTION_NUMBERING,
        nullptr,
        &disassembly);
    if (FAILED(hr) || !WriteBlob("fixture-ps.asm", disassembly.Get())) {
        std::fprintf(stderr, "FAIL: unable to write fixture disassembly\n");
        return 12;
    }

    const D3D_FEATURE_LEVEL requestedLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0
    };
    D3D_FEATURE_LEVEL createdLevel = D3D_FEATURE_LEVEL_11_0;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    hr = D3D11CreateDevice(
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
        return 13;
    }

    ComPtr<ID3D11PixelShader> pixelShader;
    hr = device->CreatePixelShader(
        shaderBytecode->GetBufferPointer(),
        shaderBytecode->GetBufferSize(),
        nullptr,
        &pixelShader);
    if (FAILED(hr)) {
        std::fprintf(stderr, "FAIL: CreatePixelShader returned 0x%08lx\n", hr);
        return 14;
    }

    std::printf("FEATURE_LEVEL=0x%04x\n", static_cast<unsigned>(createdLevel));
    std::printf("PASS: fixture pixel shader created\n");
    return 0;
}
