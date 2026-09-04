#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

#include <cstdio>

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

int main()
{
    wchar_t modulePath[MAX_PATH] = {};
    HMODULE d3d11Module = GetModuleHandleW(L"d3d11.dll");
    if (!d3d11Module || !GetModuleFileNameW(d3d11Module, modulePath, MAX_PATH))
        return 10;
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
        return 11;
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
    if (FAILED(hr))
        return 12;

    ComPtr<ID3D11PixelShader> pixelShader;
    hr = device->CreatePixelShader(
        shaderBytecode->GetBufferPointer(),
        shaderBytecode->GetBufferSize(),
        nullptr,
        &pixelShader);
    if (FAILED(hr))
        return 13;

    // ShaderRegex is intentionally deferred until the shader reaches a draw.
    // A render target and vertex shader are unnecessary for this classifier
    // test; the wrapper evaluates the bound shader before forwarding Draw.
    context->PSSetShader(pixelShader.Get(), nullptr, 0);
    context->Draw(3, 0);
    context->Flush();

    std::wprintf(L"FEATURE_LEVEL=0x%04x\n", static_cast<unsigned>(createdLevel));
    std::wprintf(L"PASS: fixture shader reached a draw\n");
    return 0;
}
