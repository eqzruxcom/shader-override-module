// Offline WARP diagnostic. Never opens, attaches to, or modifies the game.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <cmath>
#include <cstdio>
#include <cwchar>
#include <fstream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
static void Check(HRESULT hr,const char* what) {if(FAILED(hr)) throw std::runtime_error(what);}
#include "ContactShadowAdapterTests.h"
int wmain(int argc,wchar_t** argv) {
    if(argc!=3) return 2;
    try {
        ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL level=D3D_FEATURE_LEVEL_11_0;
        Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&level,1,D3D11_SDK_VERSION,&device,nullptr,&context),"Create WARP");
        ComPtr<ID3DBlob> binary,errors;ContactNestedIncludes includes(argv[1]);
        HRESULT compiled=D3DCompileFromFile(argv[1],nullptr,&includes,"main","cs_5_0",
            D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS|D3DCOMPILE_IEEE_STRICTNESS|D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&binary,&errors);
        if(errors) std::fprintf(stderr,"%s",static_cast<const char*>(errors->GetBufferPointer()));
        Check(compiled,"Compile plane audit");
        ComPtr<ID3D11ComputeShader> shader;Check(device->CreateComputeShader(binary->GetBufferPointer(),binary->GetBufferSize(),nullptr,&shader),"Create shader");
        D3D11_BUFFER_DESC cameraDesc={};cameraDesc.ByteWidth=16;cameraDesc.Usage=D3D11_USAGE_IMMUTABLE;cameraDesc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        const float camera[4]={1.7320509f,3.079202f,.1f,10.f};
        D3D11_SUBRESOURCE_DATA cameraData={};cameraData.pSysMem=camera;
        ComPtr<ID3D11Buffer> cameraBuffer;Check(device->CreateBuffer(&cameraDesc,&cameraData,&cameraBuffer),"Camera constants");
        ID3D11Buffer* cameraPointer=cameraBuffer.Get();context->CSSetConstantBuffers(13,1,&cameraPointer);
        constexpr unsigned count=20480;
        D3D11_BUFFER_DESC desc={};desc.ByteWidth=count*16;desc.Usage=D3D11_USAGE_DEFAULT;
        desc.BindFlags=D3D11_BIND_UNORDERED_ACCESS;desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=16;
        ComPtr<ID3D11Buffer> output,staging;ComPtr<ID3D11UnorderedAccessView> uav;
        Check(device->CreateBuffer(&desc,nullptr,&output),"Create output");
        Check(device->CreateUnorderedAccessView(output.Get(),nullptr,&uav),"Create UAV");
        desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.MiscFlags=0;desc.StructureByteStride=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        Check(device->CreateBuffer(&desc,nullptr,&staging),"Create staging");
        const float sentinel[4]={-1000,-1000,-1000,-1000};context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
        ID3D11UnorderedAccessView* target=uav.Get();context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
        context->CSSetShader(shader.Get(),nullptr,0);context->Dispatch(count/64,1,1);
        target=nullptr;context->CSSetUnorderedAccessViews(0,1,&target,nullptr);context->CopyResource(staging.Get(),output.Get());
        D3D11_MAPPED_SUBRESOURCE mapped={};Check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"Readback");
        const auto* values=static_cast<const ContactFloat4*>(mapped.pData);
        std::ofstream csv(argv[2]);if(!csv) throw std::runtime_error("Open CSV");
        csv<<"case,orientation,subpixelPhase,pointQuantized,receiverDepth,slope,lightSlopeGap,NoL,visibility,hasBlocker,boxRayEntry,visibleRayExit,expectedShadow\n";
        unsigned rejected[2]={},missed[2]={},visibleBoxes[2]={},outsideBoxes[2]={},outsideFalseHits[2]={},invalid=0;
        for(unsigned i=0;i<count;++i) {
            const auto& v=values[i];unsigned mode=(i%320)>=160;
            invalid+=!std::isfinite(v.x) || v.x<0 || v.x>1 || !(v.w>0);
            const bool hasBox=i%640>=320;
            const unsigned orientation=(i/640)%8,phase=i/5120;
            const double receiverDepth=(i/80)%2==0?100:1000;
            const double theta=orientation*0.78539816339;
            const double zSlope=static_cast<double>(v.y)-v.z;
            const double length=std::sqrt(1+zSlope*zSlope);
            const double dx=std::cos(theta)/length,dy=std::sin(theta)/length,dz=zSlope/length;
            // Independent analytic oracle: world-ray entry into a box centered
            // 40 units along it, versus intersection with each frustum side.
            const double maxDirection=(std::max)(std::fabs(dx),(std::max)(std::fabs(dy),std::fabs(dz)));
            const double boxEntry=40-8/maxDirection;
            const double shiftX=2*(-.4+phase*.29)/3840,shiftY=-2*(-.4+phase*.29)/2160;
            const double vx=camera[0]*dx+shiftX*dz,vy=camera[1]*dy+shiftY*dz;
            const double starts[]={receiverDepth*(1+shiftX),receiverDepth*(1-shiftX),receiverDepth*(1+shiftY),receiverDepth*(1-shiftY)};
            const double slopes[]={dz+vx,dz-vx,dz+vy,dz-vy};
            double visibleExit=100;
            for(unsigned side=0;side<4;++side) if(slopes[side]<0) visibleExit=(std::min)(visibleExit,-starts[side]/slopes[side]);
            const bool visibleBox=hasBox && boxEntry<visibleExit;
            if(!hasBox) rejected[mode]+=v.x<.99999f;
            else if(visibleBox) {++visibleBoxes[mode];missed[mode]+=v.x>=.5f;}
            else {++outsideBoxes[mode];outsideFalseHits[mode]+=v.x<.99999f;}
            csv<<i<<','<<orientation<<','<<phase<<','<<mode<<','<<receiverDepth<<','<<v.y<<','<<v.z<<','<<v.w<<','<<v.x<<','<<hasBox<<','<<boxEntry<<','<<visibleExit<<','<<visibleBox<<'\n';
        }
        context->Unmap(staging.Get(),0);
        std::printf("Plane audit: invalid=%u; false shadow hits exact=%u/5120 point-quantized=%u/5120. Expected visibility=1; single lit plane, no occluder.\n",invalid,rejected[0],rejected[1]);
        std::printf("Visible box blockers: missed exact=%u/%u point-quantized=%u/%u. Expected visibility<0.5.\n",missed[0],visibleBoxes[0],missed[1],visibleBoxes[1]);
        std::printf("Box beyond visible ray: false hits exact=%u/%u point-quantized=%u/%u. Expected visibility=1; no offscreen geometry is available.\n",outsideFalseHits[0],outsideBoxes[0],outsideFalseHits[1],outsideBoxes[1]);
        // Nonzero denotes a reproduced regression, not failure to run the test.
        return invalid?2:(rejected[0]||rejected[1]||missed[0]||missed[1]||outsideFalseHits[0]||outsideFalseHits[1]?1:0);
    } catch(const std::exception& e) {std::fprintf(stderr,"%s\n",e.what());return 2;}
}
