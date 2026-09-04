// Headless software-GPU replay; never attaches to or changes the game.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <cstdio>
#include <stdexcept>
#include <fstream>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
using Microsoft::WRL::ComPtr;
static void Check(HRESULT hr,const char* label) {
    if(FAILED(hr)) {std::fprintf(stderr,"%s: 0x%08lX\n",label,(unsigned long)hr);throw std::runtime_error(label);}
}
#include "ContactShadowAdapterTests.h"

static std::vector<char> Read(const std::filesystem::path& path) {
    std::ifstream file(path,std::ios::binary|std::ios::ate);
    if(!file) throw std::runtime_error("Missing input file");
    auto length=file.tellg();
    if(length<=0 || length>256*1024*1024) throw std::runtime_error("Unexpected input size");
    std::vector<char> data(static_cast<size_t>(length));
    file.seekg(0);file.read(data.data(),length);
    if(!file) throw std::runtime_error("Incomplete input file");
    return data;
}
static uint32_t U32(const std::vector<char>& b,size_t offset) {
    if(offset+4>b.size()) throw std::runtime_error("Truncated DDS");
    uint32_t value;std::memcpy(&value,b.data()+offset,4);return value;
}

int wmain(int argc,wchar_t** argv) {
    // source, cb0, cb1, cb4, normalDDS, depthDDS, output directory
    if(argc!=8 && argc!=10) {std::fprintf(stderr,"Expected source cb0 cb1 cb4 normalDDS depthDDS output [materialDDS quads]\n");return 2;}
    try {
        const bool quads=argc==10;
        const bool shared=quads&&std::wstring(argv[9])==L"shared-quads";
        if(quads && !shared && std::wstring(argv[9])!=L"quads") throw std::runtime_error("Unknown replay layout");
        std::filesystem::path output(argv[7]);
        if(!std::filesystem::is_directory(output)) throw std::runtime_error("Output directory missing");
        auto normals=Read(argv[5]),depth=Read(argv[6]);
        if(U32(normals,0)!=0x20534444 || U32(normals,84)!=0x30315844 || U32(normals,128)!=24 ||
           U32(depth,0)!=0x20534444 || U32(depth,84)!=0x30315844 || U32(depth,128)!=21)
            throw std::runtime_error("Expected captured normal/depth DDS formats");
        UINT width=U32(normals,16),height=U32(normals,12),stride=8;
        size_t pixels=static_cast<size_t>(width)*height;
        if(width!=3840 || height!=2160 || U32(depth,16)!=width || U32(depth,12)!=height ||
           normals.size()!=148+pixels*4 || depth.size()!=148+pixels*8 ||
           U32(normals,20)!=width*4 || U32(depth,20)!=width*8)
            throw std::runtime_error("Unexpected captured dimensions/payload");
        std::vector<float> unpackedDepth(pixels);
        for(size_t i=0;i<pixels;i++) std::memcpy(&unpackedDepth[i],depth.data()+148+i*8,4);
        ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL requested=D3D_FEATURE_LEVEL_11_0,actual;
        Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&requested,1,
            D3D11_SDK_VERSION,&device,&actual,&context),"Create WARP");
        ComPtr<ID3DBlob> bytecode,errors;
        ContactNestedIncludes includes(argv[1]);
        HRESULT compiled=D3DCompileFromFile(argv[1],nullptr,&includes,"main","cs_5_0",
            D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS|D3DCOMPILE_IEEE_STRICTNESS|
            D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&bytecode,&errors);
        if(errors) std::fprintf(stderr,"%s",static_cast<const char*>(errors->GetBufferPointer()));
        Check(compiled,"Compile production replay wrapper");
        ComPtr<ID3D11ComputeShader> shader;
        Check(device->CreateComputeShader(bytecode->GetBufferPointer(),bytecode->GetBufferSize(),nullptr,&shader),"Create kernel");
        Check(D3DWriteBlobToFile(bytecode.Get(),(output/L"capture-kernel.cso").c_str(),FALSE),"Save replay kernel");
        auto constant=[&](UINT slot,const void* data,UINT bytes) {
            D3D11_BUFFER_DESC desc={};desc.ByteWidth=bytes;desc.Usage=D3D11_USAGE_IMMUTABLE;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
            D3D11_SUBRESOURCE_DATA initial={};initial.pSysMem=data;ComPtr<ID3D11Buffer> buffer;
            Check(device->CreateBuffer(&desc,&initial,&buffer),"Create capture CB");
            ID3D11Buffer* pointer=buffer.Get();context->CSSetConstantBuffers(slot,1,&pointer);
        };
        for(UINT i=0;i<3;i++) {
            auto bytes=Read(argv[2+i]);UINT slot=i==0?0:i==1?1:4;
            if(bytes.size()!=4096 && bytes.size()!=16384) throw std::runtime_error("Unexpected constant-buffer size");
            constant(slot,bytes.data(),static_cast<UINT>(bytes.size()));
        }
        auto texture=[&](UINT slot,DXGI_FORMAT format,const void* data,UINT pitch) {
            D3D11_TEXTURE2D_DESC desc={};desc.Width=width;desc.Height=height;desc.MipLevels=1;desc.ArraySize=1;
            desc.Format=format;desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_IMMUTABLE;desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;
            D3D11_SUBRESOURCE_DATA initial={};initial.pSysMem=data;initial.SysMemPitch=pitch;
            ComPtr<ID3D11Texture2D> tex;ComPtr<ID3D11ShaderResourceView> srv;
            Check(device->CreateTexture2D(&desc,&initial,&tex),"Create captured texture");
            Check(device->CreateShaderResourceView(tex.Get(),nullptr,&srv),"Create capture SRV");
            ID3D11ShaderResourceView* pointer=srv.Get();context->CSSetShaderResources(slot,1,&pointer);
        };
        texture(1,DXGI_FORMAT_R10G10B10A2_UNORM,normals.data()+148,width*4);
        texture(4,DXGI_FORMAT_R32_FLOAT,unpackedDepth.data(),width*4);
        if(quads) {
            auto material=Read(argv[8]);
            // This capture has legacy (non-DX10) linear BGRA8, including packed
            // shading-model/flag bits in alpha. Never bind as sRGB.
            if(U32(material,0)!=0x20534444 || U32(material,4)!=124 || U32(material,76)!=32 ||
               U32(material,84)!=0 || U32(material,88)!=32 || U32(material,92)!=0x00ff0000 ||
               U32(material,96)!=0x0000ff00 || U32(material,100)!=0x000000ff || U32(material,104)!=0xff000000 ||
               U32(material,16)!=width || U32(material,12)!=height || material.size()!=128+pixels*4)
                throw std::runtime_error("Expected captured legacy BGRA8 material DDS");
            texture(2,DXGI_FORMAT_B8G8R8A8_UNORM,material.data()+128,width*4);
        }
        UINT gridX=(width+stride-1)/stride,gridY=(height+stride-1)/stride,count=gridX*gridY;
        if(quads) {gridX*=2;gridY*=2;count=gridX*gridY;}
        const UINT channels=quads?2:1;
        D3D11_BUFFER_DESC desc={};desc.ByteWidth=count*4*channels;desc.Usage=D3D11_USAGE_DEFAULT;
        desc.BindFlags=D3D11_BIND_UNORDERED_ACCESS;desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=4;
        ComPtr<ID3D11Buffer> result,readback;Check(device->CreateBuffer(&desc,nullptr,&result),"Create replay output");
        ComPtr<ID3D11UnorderedAccessView> uav;Check(device->CreateUnorderedAccessView(result.Get(),nullptr,&uav),"Create replay UAV");
        desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.MiscFlags=0;desc.StructureByteStride=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        Check(device->CreateBuffer(&desc,nullptr,&readback),"Create readback");
        context->CSSetShader(shader.Get(),nullptr,0);
        std::ofstream report(output/L"results.csv");report<<"light,enabled,rayLength,count,finite,changed,min,mean\n";
        for(UINT light:{50u,38u,54u,20u,52u}) for(UINT mode=0;mode<2;mode++) {
            std::array<ContactFloat4,32> controls={};controls[31]={static_cast<float>(mode),static_cast<float>(light),1,100};
            D3D11_TEXTURE1D_DESC c={};c.Width=32;c.MipLevels=1;c.ArraySize=1;c.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;
            c.Usage=D3D11_USAGE_IMMUTABLE;c.BindFlags=D3D11_BIND_SHADER_RESOURCE;
            D3D11_SUBRESOURCE_DATA initial={};initial.pSysMem=controls.data();
            ComPtr<ID3D11Texture1D> tex;ComPtr<ID3D11ShaderResourceView> srv;
            Check(device->CreateTexture1D(&c,&initial,&tex),"Create controls");Check(device->CreateShaderResourceView(tex.Get(),nullptr,&srv),"Control SRV");
            ID3D11ShaderResourceView* pointer=srv.Get();context->CSSetShaderResources(120,1,&pointer);
            UINT replay[]={width,height,stride,light};constant(13,replay,sizeof(replay));
            ID3D11UnorderedAccessView* target=uav.Get();context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
            const float sentinel[]={-1000,-1000,-1000,-1000};context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
            const UINT groupWidth=shared?16u:8u;
            context->Dispatch((gridX+groupWidth-1)/groupWidth,(gridY+groupWidth-1)/groupWidth,1);
            target=nullptr;context->CSSetUnorderedAccessViews(0,1,&target,nullptr);context->CopyResource(readback.Get(),result.Get());
            D3D11_MAPPED_SUBRESOURCE mapped={};Check(context->Map(readback.Get(),0,D3D11_MAP_READ,0,&mapped),"Read replay output");
            const float* packed=static_cast<const float*>(mapped.pData);UINT finite=0,changed=0,nonNeutral=0,badFlags=0;float minimum=1;double sum=0;
            std::vector<float> values(count);std::vector<uint8_t> valid(count);
            for(UINT i=0;i<count;i++) {
                values[i]=packed[i*channels];finite+=std::isfinite(values[i]) && values[i]>=0 && values[i]<=1;
                changed+=values[i]<.999f;nonNeutral+=values[i]!=1.0f;minimum=(std::min)(minimum,values[i]);sum+=values[i];
                if(quads) {float flag=packed[i*channels+1];badFlags+=flag!=0.0f && flag!=1.0f;valid[i]=flag==1.0f?1:0;}
            }
            std::wstring name=L"light-"+std::to_wstring(light)+L"-"+std::to_wstring(mode)+L".f32";
            std::ofstream binary(output/name,std::ios::binary);binary.write(reinterpret_cast<const char*>(values.data()),count*4);
            context->Unmap(readback.Get(),0);
            if(!binary) throw std::runtime_error("Replay output write failed");
            if(quads) {
                auto validity=output/(L"light-"+std::to_wstring(light)+L"-"+std::to_wstring(mode)+L".valid.u8");
                std::ofstream flags(validity,std::ios::binary);flags.write(reinterpret_cast<const char*>(valid.data()),count);
                if(!flags) throw std::runtime_error("Replay validity write failed");
            }
            report<<light<<','<<mode<<",100,"<<count<<','<<finite<<','<<changed<<','<<minimum<<','<<sum/count<<'\n';report.flush();
            std::printf("light=%u enabled=%u valid=%u/%u changed=%u min=%.6g mean=%.6g\n",light,mode,finite,count,changed,minimum,sum/count);std::fflush(stdout);
            if(finite!=count || badFlags || (!mode && nonNeutral!=0)) throw std::runtime_error("Invalid output or OFF not exactly neutral");
        }
        std::puts("Replay complete: actual production kernel with captured resources, NOT native full-dispatch shading or live performance.");
        return 0;
    } catch(const std::exception& e) {std::fprintf(stderr,"%s\n",e.what());return 1;}
}
