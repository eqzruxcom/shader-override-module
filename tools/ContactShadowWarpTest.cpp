// Headless, offline execution of the actual HLSL on Microsoft's D3D11 WARP.
// Does not open the game, inject a DLL, create a window, or use the hardware GPU.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <cmath>
#include <cstdio>
#include <cwchar>
#include <stdexcept>
using Microsoft::WRL::ComPtr;

static void Check(HRESULT result, const char* operation) {
    if (FAILED(result)) {
        std::fprintf(stderr, "%s failed: 0x%08lX\n", operation, (unsigned long)result);
        throw std::runtime_error(operation);
    }
}

#include "ContactShadowAdapterTests.h"

int wmain(int argc, wchar_t** argv) {
    if(argc==9 && (std::wcscmp(argv[1],L"--adapter-assembly-shared")==0 || std::wcscmp(argv[1],L"--adapter-assembly-shared-repeat")==0)) {
        try {
            UINT slot=static_cast<UINT>(std::wcstoul(argv[3],nullptr,10));
            UINT frame=static_cast<UINT>(std::wcstoul(argv[6],nullptr,10));
            UINT material=static_cast<UINT>(std::wcstoul(argv[7],nullptr,10));
            if((slot!=4&&slot!=5)||std::wcslen(argv[4])!=3||std::wcslen(argv[5])!=3||material>255) throw std::runtime_error("Invalid shared assembly inputs");
            return RunContactAdapterTests(argv[8],argv[2],slot,argv[4],argv[5],frame,material,true,true,
                std::wcscmp(argv[1],L"--adapter-assembly-shared-repeat")==0);
        }catch(const std::exception& e){std::fprintf(stderr,"%s\n",e.what());return 1;}
    }
    if(argc==9 && std::wcscmp(argv[1],L"--adapter-assembly-reconstruction")==0) {
        try {
            UINT slot=static_cast<UINT>(std::wcstoul(argv[3],nullptr,10));
            UINT frame=static_cast<UINT>(std::wcstoul(argv[6],nullptr,10));
            UINT material=static_cast<UINT>(std::wcstoul(argv[7],nullptr,10));
            if((slot!=4&&slot!=5)||std::wcslen(argv[4])!=3||std::wcslen(argv[5])!=3||material>255)
                throw std::runtime_error("Invalid reconstruction assembly inputs");
            return RunContactAdapterTests(argv[8],argv[2],slot,argv[4],argv[5],frame,material,true);
        } catch(const std::exception& e){std::fprintf(stderr,"%s\n",e.what());return 1;}
    }
    if ((argc == 6 || argc == 8) && std::wcscmp(argv[1], L"--adapter-assembly") == 0) {
        try {
            UINT slot=static_cast<UINT>(std::wcstoul(argv[3],nullptr,10));
            if((slot!=4 && slot!=5) || std::wcslen(argv[4])!=3 || std::wcslen(argv[5])!=3)
                throw std::runtime_error("Invalid assembly fixture depth slot or lane masks");
            UINT frame=argc==8?static_cast<UINT>(std::wcstoul(argv[6],nullptr,10)):0;
            UINT material=argc==8?static_cast<UINT>(std::wcstoul(argv[7],nullptr,10)):1;
            if(material>255) throw std::runtime_error("Invalid packed material byte");
            return RunContactAdapterTests(nullptr,argv[2],slot,argv[4],argv[5],frame,material);
        } catch (const std::exception& e) { std::fprintf(stderr,"%s\n",e.what()); return 1; }
    }
    if (argc == 3 && (std::wcscmp(argv[1], L"--adapter") == 0 || std::wcscmp(argv[1],L"--adapter-reconstruction")==0)) {
        try { return RunContactAdapterTests(argv[2],nullptr,0,nullptr,nullptr,0,1,std::wcscmp(argv[1],L"--adapter-reconstruction")==0); }
        catch (const std::exception& e) { std::fprintf(stderr,"%s\n",e.what()); return 1; }
    }
    if (argc >= 3 && std::wcscmp(argv[1], L"--validate-cs") == 0) {
        try {
            ComPtr<ID3D11Device> device;
            D3D_FEATURE_LEVEL requested = D3D_FEATURE_LEVEL_11_0, obtained;
            Check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0,
                &requested, 1, D3D11_SDK_VERSION, &device, &obtained, nullptr), "Create WARP");
            for (int i = 2; i < argc; ++i) {
                ComPtr<ID3DBlob> binary;
                ComPtr<ID3D11ComputeShader> shader;
                Check(D3DReadFileToBlob(argv[i], &binary), "Read compute binary");
                Check(device->CreateComputeShader(binary->GetBufferPointer(),
                    binary->GetBufferSize(), nullptr, &shader), "Validate native compute shader");
                std::printf("PASS CreateComputeShader: %ls\n", argv[i]);
            }
            std::printf("Validated %d compute shaders. Creation only; no native dispatch or live game test.\n", argc-2);
            return 0;
        } catch (const std::exception& e) {
            std::fprintf(stderr, "%s\n", e.what());
            return 1;
        }
    }
    const bool donorInputs=argc==3 && std::wcscmp(argv[1],L"--donor-inputs")==0;
    const bool reconstruction=argc==3 && std::wcscmp(argv[1],L"--reconstruction")==0;
    if (argc != 2 && !donorInputs && !reconstruction) { std::fprintf(stderr, "Expected HLSL test source path\n"); return 2; }
    const wchar_t* caseSource=argv[(donorInputs||reconstruction)?2:1];
    try {
        ComPtr<ID3DBlob> bytecode, errors;
        ContactNestedIncludes includes(caseSource);
        HRESULT compiled = D3DCompileFromFile(caseSource, nullptr,
            &includes, "main", "cs_5_0",
            D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_WARNINGS_ARE_ERRORS | D3DCOMPILE_IEEE_STRICTNESS |
            D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &bytecode, &errors);
        if (errors) std::fprintf(stderr, "%s", (const char*)errors->GetBufferPointer());
        Check(compiled, "D3DCompileFromFile");
        ComPtr<ID3D11Device> device;
        ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL requested = D3D_FEATURE_LEVEL_11_0, obtained;
        Check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0,
            &requested, 1, D3D11_SDK_VERSION, &device, &obtained, &context), "Create WARP");
        ComPtr<ID3D11ComputeShader> shader;
        Check(device->CreateComputeShader(bytecode->GetBufferPointer(),
            bytecode->GetBufferSize(), nullptr, &shader), "CreateComputeShader");
        constexpr UINT count = 34;
        D3D11_BUFFER_DESC desc = {};
        desc.ByteWidth = count * sizeof(float);
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
        desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
        desc.StructureByteStride = sizeof(float);
        ComPtr<ID3D11Buffer> output, staging;
        Check(device->CreateBuffer(&desc, nullptr, &output), "Create output buffer");
        D3D11_UNORDERED_ACCESS_VIEW_DESC view = {};
        view.Format = DXGI_FORMAT_UNKNOWN;
        view.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
        view.Buffer.NumElements = count;
        ComPtr<ID3D11UnorderedAccessView> uav;
        Check(device->CreateUnorderedAccessView(output.Get(), &view, &uav), "Create UAV");
        desc.Usage = D3D11_USAGE_STAGING;
        desc.BindFlags = 0;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        desc.MiscFlags = 0;
        desc.StructureByteStride = 0;
        Check(device->CreateBuffer(&desc, nullptr, &staging), "Create readback buffer");
        const float sentinel[4] = {-1000,-1000,-1000,-1000};
        context->ClearUnorderedAccessViewFloat(uav.Get(), sentinel);
        context->CSSetShader(shader.Get(), nullptr, 0);
        if(donorInputs) {
            const UINT frames[8]={0,1,7,8,31,61,255,12345};
            UINT timing[8][4]={};
            for(UINT row=0;row<8;++row) {
                timing[row][0]=899797841u;timing[row][1]=11283u;
                timing[row][2]=frames[row]&7u;timing[row][3]=frames[row];
            }
            D3D11_BUFFER_DESC timingDesc={};timingDesc.ByteWidth=sizeof(timing);
            timingDesc.Usage=D3D11_USAGE_IMMUTABLE;timingDesc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
            D3D11_SUBRESOURCE_DATA initial={};initial.pSysMem=timing;
            ComPtr<ID3D11Buffer> timingBuffer;
            Check(device->CreateBuffer(&timingDesc,&initial,&timingBuffer),"Create donor frame bits");
            ID3D11Buffer* timingPointer=timingBuffer.Get();context->CSSetConstantBuffers(13,1,&timingPointer);
        }
        ID3D11UnorderedAccessView* target = uav.Get();
        context->CSSetUnorderedAccessViews(0, 1, &target, nullptr);
        context->Dispatch(1, 1, 1);
        target = nullptr;
        context->CSSetUnorderedAccessViews(0, 1, &target, nullptr);
        context->CopyResource(staging.Get(), output.Get());
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        Check(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped), "Readback");
        const float* values = static_cast<const float*>(mapped.pData);
        const char* labels[count] = {
            "perspective midpoint", "thickness near", "thickness far",
            "orthographic footprint", "subviewport footprint", "clip plane exit",
            "surface behind ray", "occluder hit", "outside thickness", "receiver rejection",
            "zero depth rejection", "zero ray length", "invalid light radius", "light exclusion",
            "outside view start", "clipped ray hit", "reversed Z hit", "behind camera",
            "regular Z hit", "subpixel ray", "empty viewport", "subviewport hit",
            "infinite sky sample", "NaN sample", "jitter endpoint hit", "beyond far clip",
            "UV occluder stripe", "outside ray length", "beyond light endpoint", "offset viewport stripe",
            "D3D vertical UV flip", "outside viewport UV", "whole receiver excluded", "late hit falloff"};
        const float exact[6] = {40.0f/3.0f, 5.625f, 11.25f, 5.0625f, 17.5f, .25f};
        unsigned failed = 0;
        for (UINT i = 0; i < count; ++i) {
            bool hitCase = i==7 || i==15 || i==16 || i==18 || i==21 || i==24 || i==26 || i==29 || i==30;
            bool passed = std::isfinite(values[i]) && (i < 6
                ? std::fabs(values[i] - exact[i]) < 2e-4f
                : i==33 ? values[i] > .4f && values[i] < .8f
                : hitCase ? values[i] >= 0 && values[i] < .1f
                : std::fabs(values[i] - 1.0f) < 1e-6f);
            if(donorInputs||reconstruction) passed=std::isfinite(values[i])&&values[i]==1.f;
            const char* label=donorInputs?(i<16?"material decode all flags":i<24?"hair bias with flags":i<32?"frame bits and noise":i==32?"hair branch isolation":"donor hair default parity"):labels[i];
            if(reconstruction) label=i<32?"quad lane and phase":i==32?"neutral/edge averages":"absolute pixel parity";
            std::printf("%s %02u %-26s %.9g\n", passed ? "PASS" : "FAIL", i, label, values[i]);
            if (!passed) ++failed;
        }
        context->Unmap(staging.Get(), 0);
        std::printf("%s: %u/%u passed. Not a live Remake or performance test.\n",reconstruction?"Donor reconstruction tests":donorInputs?"Donor input tests":"WARP HLSL tests", count-failed, count);
        return failed ? 1 : 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "%s\n", e.what());
        return 1;
    }
}
