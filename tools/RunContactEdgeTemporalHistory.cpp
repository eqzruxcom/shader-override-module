// Headless D3D11 ping-pong test. Synthetic moving correspondences, NOT FF7.
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
static void Check(HRESULT hr,const char* label){if(FAILED(hr))throw std::runtime_error(label);}
struct Input{float target,dt;uint32_t edge,allowed,index,receiver,light,pad;};
struct History{float darkness;uint32_t receiver,light,flags;};
static_assert(sizeof(Input)==32 && sizeof(History)==16,"Buffer layout");
int wmain(int argc,wchar_t** argv){
    if(argc!=2)return 2;
    try{
        ComPtr<ID3DBlob> code;Check(D3DReadFileToBlob(argv[1],&code),"Read shader");
        ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL level=D3D_FEATURE_LEVEL_11_0;
        Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&level,1,D3D11_SDK_VERSION,&device,nullptr,&context),"WARP device");
        ComPtr<ID3D11ComputeShader> shader;
        Check(device->CreateComputeShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&shader),"Create shader");
        std::array<History,64> zero{};
        ComPtr<ID3D11Buffer> history[2],inputs,readback;
        ComPtr<ID3D11ShaderResourceView> historySRV[2],inputSRV;
        ComPtr<ID3D11UnorderedAccessView> historyUAV[2];
        D3D11_BUFFER_DESC desc{};
        desc.ByteWidth=sizeof(History)*64;desc.Usage=D3D11_USAGE_DEFAULT;
        desc.BindFlags=D3D11_BIND_SHADER_RESOURCE|D3D11_BIND_UNORDERED_ACCESS;
        desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=sizeof(History);
        D3D11_SUBRESOURCE_DATA initial{};initial.pSysMem=zero.data();
        for(unsigned j=0;j<2;++j){
            Check(device->CreateBuffer(&desc,&initial,&history[j]),"History buffer");
            Check(device->CreateShaderResourceView(history[j].Get(),nullptr,&historySRV[j]),"History SRV");
            Check(device->CreateUnorderedAccessView(history[j].Get(),nullptr,&historyUAV[j]),"History UAV");
        }
        desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        desc.MiscFlags=0;desc.StructureByteStride=0;
        Check(device->CreateBuffer(&desc,nullptr,&readback),"Readback");
        desc.ByteWidth=sizeof(Input)*64;desc.Usage=D3D11_USAGE_DEFAULT;desc.CPUAccessFlags=0;
        desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=sizeof(Input);
        Check(device->CreateBuffer(&desc,nullptr,&inputs),"Inputs");
        Check(device->CreateShaderResourceView(inputs.Get(),nullptr,&inputSRV),"Input SRV");
        const unsigned rates[]={30,60,90,120,144,240};
        unsigned checks=0,dispatches=0,identityRejects=0,releaseChecks=0,carryChecks=0;
        for(unsigned fps:rates)for(unsigned scenario=0;scenario<5;++scenario){
            context->UpdateSubresource(history[0].Get(),0,nullptr,zero.data(),0,0);
            context->UpdateSubresource(history[1].Get(),0,nullptr,zero.data(),0,0);
            std::array<History,64> cpu=zero;
            unsigned previous=0;
            const unsigned frames=fps/2+1;
            for(unsigned frame=0;frame<frames;++frame){
                std::array<Input,64> current{};
                std::array<History,64> expected{};
                for(unsigned pixel=0;pixel<64;++pixel){
                    const unsigned surface=(pixel+frame)%64;
                    Input in{surface<32?1.0f:.37f,1.0f/static_cast<float>(fps),surface<32?1u:0u,
                        frame?1u:0u,(pixel+1)%64,surface+1,100,0};
                    // 0 stationary target, translated receiver history.
                    // 1 edge sample leaves band while its fade is pending.
                    if(scenario==1 && frame>=2)in.edge=0;
                    // 2 obsolete hit disappears; history must not retain it.
                    if(scenario==2 && frame>=fps/10 && surface<32)in.target=0;
                    // 3 surface replacement, light change, camera cut, OOB reprojection.
                    if(scenario==3 && frame==fps/10){
                        if(surface%4==0)in.receiver+=1000;
                        if(surface%4==1)in.light+=1;
                        if(surface%4==2)in.allowed=0;
                        if(surface%4==3)in.index=64;
                    }
                    // 4 long stall: restart rather than instant full darkness.
                    if(scenario==4 && frame==fps/10)in.dt=.5f;
                    current[pixel]=in;
                    History old{};
                    if(in.allowed && in.index<64)old=cpu[in.index];
                    const bool valid=(old.flags&1)!=0 && old.receiver==in.receiver && old.light==in.light && in.allowed;
                    const bool edge=in.edge || (valid && (old.flags&2));
                    const float target=std::clamp(in.target,0.0f,1.0f);
                    float value=target;
                    if(edge){
                        if(!valid || in.dt>.1f)value=0;
                        else value=std::min(target,old.darkness+in.dt*5.0f);
                    }
                    const uint32_t pending=(edge && value<target)?2u:0u;
                    expected[pixel]={value,in.receiver,in.light,1u|pending};
                    if(!valid && edge)++identityRejects;
                    if(target==0)++releaseChecks;
                    if(!in.edge && valid && (old.flags&2))++carryChecks;
                }
                context->UpdateSubresource(inputs.Get(),0,nullptr,current.data(),0,0);
                const unsigned next=1-previous;
                ID3D11ShaderResourceView* srvs[]={inputSRV.Get(),historySRV[previous].Get()};
                ID3D11UnorderedAccessView* target=historyUAV[next].Get();
                context->CSSetShader(shader.Get(),nullptr,0);context->CSSetShaderResources(0,2,srvs);
                context->CSSetUnorderedAccessViews(0,1,&target,nullptr);context->Dispatch(1,1,1);
                srvs[0]=nullptr;srvs[1]=nullptr;target=nullptr;
                context->CSSetShaderResources(0,2,srvs);context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                context->CopyResource(readback.Get(),history[next].Get());
                D3D11_MAPPED_SUBRESOURCE mapped{};Check(context->Map(readback.Get(),0,D3D11_MAP_READ,0,&mapped),"Readback map");
                const History* actual=static_cast<const History*>(mapped.pData);
                bool failed=false;
                for(unsigned pixel=0;pixel<64;++pixel){
                    const auto& a=actual[pixel];const auto& e=expected[pixel];
                    if(!std::isfinite(a.darkness)||std::fabs(a.darkness-e.darkness)>2e-5f
                        ||a.receiver!=e.receiver||a.light!=e.light||a.flags!=e.flags){
                        std::printf("FAIL fps=%u scenario=%u frame=%u pixel=%u actual=%.9g expected=%.9g flags=%u/%u\n",fps,scenario,frame,pixel,a.darkness,e.darkness,a.flags,e.flags);
                        failed=true;break;
                    }
                    ++checks;
                }
                context->Unmap(readback.Get(),0);
                if(failed)return 1;
                cpu=expected;previous=next;++dispatches;
            }
            std::printf("PASS fps=%u scenario=%u frames=%u receivers=64\n",fps,scenario,frames);
        }
        if(!identityRejects||!releaseChecks||!carryChecks)throw std::runtime_error("Vacuous history coverage");
        std::printf("PASS history checks=%u dispatches=%u rejected=%u releases=%u pendingCarry=%u\n",checks,dispatches,identityRejects,releaseChecks,carryChecks);
        return 0;
    }catch(const std::exception& e){std::fprintf(stderr,"%s\n",e.what());return 1;}
}
