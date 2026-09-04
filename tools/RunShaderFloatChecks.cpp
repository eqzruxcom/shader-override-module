// Generic headless D3D11 WARP float4 checks; not a game renderer.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <vector>
#include <cmath>
#include <cstdio>
#include <cwchar>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
static void Check(HRESULT hr,const char* label) { if(FAILED(hr)) throw std::runtime_error(label); }
int wmain(int argc,wchar_t** argv) {
    if(argc!=3) return 2;
    wchar_t* end=nullptr;
    const unsigned long parsed=std::wcstoul(argv[2],&end,10);
    if(!end||*end||parsed==0||parsed>65536) return 2;
    const UINT count=static_cast<UINT>(parsed);
    try {
        ComPtr<ID3DBlob> code; Check(D3DReadFileToBlob(argv[1],&code),"Read bytecode");
        ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL level=D3D_FEATURE_LEVEL_11_0,obtained;
        Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&level,1,D3D11_SDK_VERSION,&device,&obtained,&context),"WARP device");
        ComPtr<ID3D11ComputeShader> shader;
        Check(device->CreateComputeShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&shader),"Compute shader");
        D3D11_BUFFER_DESC desc={}; desc.ByteWidth=count*16; desc.Usage=D3D11_USAGE_DEFAULT;
        desc.BindFlags=D3D11_BIND_UNORDERED_ACCESS; desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED; desc.StructureByteStride=16;
        ComPtr<ID3D11Buffer> result,readback; Check(device->CreateBuffer(&desc,nullptr,&result),"Output buffer");
        D3D11_UNORDERED_ACCESS_VIEW_DESC udesc={}; udesc.ViewDimension=D3D11_UAV_DIMENSION_BUFFER; udesc.Buffer.NumElements=count;
        ComPtr<ID3D11UnorderedAccessView> uav; Check(device->CreateUnorderedAccessView(result.Get(),&udesc,&uav),"UAV");
        desc.Usage=D3D11_USAGE_STAGING; desc.BindFlags=0; desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ; desc.MiscFlags=0; desc.StructureByteStride=0;
        Check(device->CreateBuffer(&desc,nullptr,&readback),"Readback buffer");
        const float sentinel[4]={-1000,-1000,-1000,-1000}; context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
        context->CSSetShader(shader.Get(),nullptr,0); ID3D11UnorderedAccessView* target=uav.Get();
        context->CSSetUnorderedAccessViews(0,1,&target,nullptr); context->Dispatch((count+63)/64,1,1);
        target=nullptr; context->CSSetUnorderedAccessViews(0,1,&target,nullptr); context->CopyResource(readback.Get(),result.Get());
        D3D11_MAPPED_SUBRESOURCE mapped={}; Check(context->Map(readback.Get(),0,D3D11_MAP_READ,0,&mapped),"Readback map");
        const float* values=static_cast<const float*>(mapped.pData); UINT failed=0;
        for(UINT i=0;i<count;++i) {
            const float* v=values+i*4;
            bool pass=std::isfinite(v[0])&&std::isfinite(v[1])&&std::isfinite(v[2])&&v[2]>=0&&v[3]==1&&std::fabs(v[0]-v[1])<=v[2];
            if(!pass) ++failed;
            std::printf("%s %u actual=%.9g expected=%.9g tolerance=%.9g contract=%.0f\n",pass?"PASS":"FAIL",i,v[0],v[1],v[2],v[3]);
        }
        context->Unmap(readback.Get(),0);
        std::printf("Shader float checks: %u/%u passed. Offline WARP only.\n",count-failed,count);
        return failed?1:0;
    } catch(const std::exception& e) { std::fprintf(stderr,"%s\n",e.what()); return 1; }
}
