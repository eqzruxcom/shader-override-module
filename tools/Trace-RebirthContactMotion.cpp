// Reuse the exact existing analytic scene functions without changing its test.
#define wmain Redx11UnusedMotionAuditEntry
#include "Audit-ContactShadowMotion.cpp"
#undef wmain
#include <memory>

class TraceIncludes final : public ID3DInclude {
    ContactNestedIncludes original;
    std::map<const void*,std::unique_ptr<std::string>> injected;
public:
    std::string donorText;
    std::string fixtureText;
    unsigned injections=0,fixtureEdits=0;
    explicit TraceIncludes(const wchar_t* source):original(source) {}
    HRESULT __stdcall Open(D3D_INCLUDE_TYPE kind,LPCSTR name,LPCVOID parent,LPCVOID* data,UINT* bytes) override {
        HRESULT hr=original.Open(kind,name,parent,data,bytes);
        if(FAILED(hr)) return hr;
        auto leaf=std::filesystem::path(name).filename();
        if(leaf!="RebirthContactRay.hlsl"&&leaf!="ContactShadowsMotion_cs.hlsl") return hr;
        std::string source(static_cast<const char*>(*data),*bytes);
        original.Close(*data);
        if(leaf=="ContactShadowsMotion_cs.hlsl") {
            const std::string attribute="[numthreads(64,1,1)]";
            auto position=source.find(attribute);
            if(position==std::string::npos||source.find(attribute,position+1)!=std::string::npos) return E_FAIL;
            source.erase(position,attribute.size());fixtureText=source;
            auto text=std::make_unique<std::string>(source);
            *data=text->data();*bytes=static_cast<UINT>(text->size());
            injected.emplace(*data,std::move(text));++fixtureEdits;
            return S_OK;
        }
        const std::string anchor="            float penetration = max(rayDepthMin - sceneDepth, contactShadowBias);";
        const std::string observer=
            "            Redx11ObserveContact((uint)i,uv,sampleT,segmentEndT,segmentDepth0,segmentDepth1,\n"
            "                sceneDepth,thickness,contactShadowBias,intersectsDepthInterval,minimumTraceT,\n"
            "                rayOrigin,rayDirection,traceLength,gbufferData.WorldNormal,random,uvStart,uvEnd,\n"
            "                resolvedPixel.WorldPosition,resolvedPixel.LightDistance);\n";
        auto position=source.find(anchor);
        if(position==std::string::npos||source.find(anchor,position+1)!=std::string::npos) return E_FAIL;
        donorText=source;donorText.insert(position,observer);
        std::string restored=donorText;restored.erase(position,observer.size());
        if(restored!=source) return E_FAIL;
        auto text=std::make_unique<std::string>(donorText);
        *data=text->data();*bytes=static_cast<UINT>(text->size());
        injected.emplace(*data,std::move(text));++injections;
        return S_OK;
    }
    HRESULT __stdcall Close(LPCVOID data) override {
        if(injected.erase(data)) return S_OK;
        return original.Close(data);
    }
};

int wmain(int argc,wchar_t** argv) {
    if(argc!=4) return 2;
    try {
        const std::filesystem::path repo(argv[1]),output(argv[2]);
        std::ifstream prior(argv[3],std::ios::binary);
        std::vector<float> saved(4u*Frames*Count);
        prior.read(reinterpret_cast<char*>(saved.data()),static_cast<std::streamsize>(saved.size()*4));
        if(!prior||prior.peek()!=EOF) throw std::runtime_error("Wrong saved readback size");
        ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL level=D3D_FEATURE_LEVEL_11_0;
        Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&level,1,D3D11_SDK_VERSION,&device,nullptr,&context),"Create WARP");
        ComPtr<ID3D11ComputeShader> shaders[2];
        for(unsigned mode=0;mode<2;++mode) {
            auto path=repo/(mode?L"src/Tests/RebirthContactTrace_cs.hlsl":L"src/Tests/RebirthContactMotion_cs.hlsl");
            ContactNestedIncludes plain(path.c_str());TraceIncludes traced(path.c_str());
            ComPtr<ID3DBlob> binary,errors;
            D3D_SHADER_MACRO macros[]={{"REDX11_CONTACT_SAMPLES","16"},{nullptr,nullptr}};
            HRESULT hr=D3DCompileFromFile(path.c_str(),macros,mode?static_cast<ID3DInclude*>(&traced):static_cast<ID3DInclude*>(&plain),
                "main","cs_5_0",D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS|D3DCOMPILE_IEEE_STRICTNESS|D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&binary,&errors);
            if(errors) std::fprintf(stderr,"%s",static_cast<const char*>(errors->GetBufferPointer()));
            Check(hr,"Compile logger/reference");
            Check(D3DWriteBlobToFile(binary.Get(),(output/(mode?L"trace.cso":L"reference.cso")).c_str(),FALSE),"Save shader");
            Check(device->CreateComputeShader(binary->GetBufferPointer(),binary->GetBufferSize(),nullptr,&shaders[mode]),"Create shader");
            if(mode) {
                if(traced.injections!=1||traced.fixtureEdits!=1) throw std::runtime_error("Observer insertion count mismatch");
                std::ofstream text(output/L"instrumented-donor.hlsl",std::ios::binary);text<<traced.donorText;
                if(!text) throw std::runtime_error("Save observed donor");
                std::ofstream fixture(output/L"instrumented-motion.hlsl",std::ios::binary);fixture<<traced.fixtureText;
                if(!fixture) throw std::runtime_error("Save observed fixture");
            }
        }
        auto texture=[&](DXGI_FORMAT format,UINT slot,ComPtr<ID3D11Texture2D>& resource) {
            D3D11_TEXTURE2D_DESC td={};td.Width=Width;td.Height=Height;td.MipLevels=1;td.ArraySize=1;td.Format=format;
            td.SampleDesc.Count=1;td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_SHADER_RESOURCE;
            Check(device->CreateTexture2D(&td,nullptr,&resource),"Create texture");
            ComPtr<ID3D11ShaderResourceView> srv;Check(device->CreateShaderResourceView(resource.Get(),nullptr,&srv),"Create texture SRV");
            ID3D11ShaderResourceView* p=srv.Get();context->CSSetShaderResources(slot,1,&p);
        };
        ComPtr<ID3D11Texture2D> depth,normals;texture(DXGI_FORMAT_R32_FLOAT,0,depth);texture(DXGI_FORMAT_R32G32B32A32_FLOAT,2,normals);
        D3D11_BUFFER_DESC desc={};desc.ByteWidth=Count*sizeof(Receiver);desc.Usage=D3D11_USAGE_DEFAULT;
        desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=sizeof(Receiver);
        ComPtr<ID3D11Buffer> receivers;ComPtr<ID3D11ShaderResourceView> receiverSRV;
        Check(device->CreateBuffer(&desc,nullptr,&receivers),"Receiver buffer");
        Check(device->CreateShaderResourceView(receivers.Get(),nullptr,&receiverSRV),"Receiver SRV");
        ID3D11ShaderResourceView* srv=receiverSRV.Get();context->CSSetShaderResources(1,1,&srv);
        desc={};desc.ByteWidth=64;desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        ComPtr<ID3D11Buffer> constants;Check(device->CreateBuffer(&desc,nullptr,&constants),"Constants");
        ID3D11Buffer* cb=constants.Get();context->CSSetConstantBuffers(13,1,&cb);
        ComPtr<ID3D11Buffer> buffers[2],staging[2];ComPtr<ID3D11UnorderedAccessView> uavs[2];
        const UINT bytes[]={Count*4,Count*54*16};
        for(unsigned i=0;i<2;++i) {
            desc={};desc.ByteWidth=bytes[i];desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_UNORDERED_ACCESS;
            desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=i?16:4;
            Check(device->CreateBuffer(&desc,nullptr,&buffers[i]),"Output buffer");
            Check(device->CreateUnorderedAccessView(buffers[i].Get(),nullptr,&uavs[i]),"Output UAV");
            desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.MiscFlags=0;desc.StructureByteStride=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
            Check(device->CreateBuffer(&desc,nullptr,&staging[i]),"Staging");
        }
        std::ofstream traceFile(output/L"trace.f32",std::ios::binary),valueFile(output/L"visibility.f32",std::ios::binary);
        if(!traceFile||!valueFile) throw std::runtime_error("Open trace output");
        std::vector<float> depthValues(Width*Height),traceValues(Count*54*4);
        std::vector<ContactFloat4> normalValues(Width*Height);
        std::array<Receiver,Count> samples;std::array<float,Count> reference,values;
        unsigned logged=0,bitDifferences=0;float maximumDifference=0;
        for(unsigned frame=0;frame<Frames;++frame) {
            double phase=frame==Frames-1?0:6.283185307179586*frame/(Frames-1);
            double yaw=.14*std::sin(phase);
            Camera camera={{18*std::sin(phase),3*std::sin(2*phase),-8*std::cos(phase)},
                {std::cos(yaw),0,-std::sin(yaw)},{std::sin(yaw),0,std::cos(yaw)}};
            V box={35*std::sin(phase),10,130};
            for(UINT y=0;y<Height;++y) for(UINT x=0;x<Width;++x) {
                V ray={(2*(x+.5)/Width-1)/ProjectionX,(1-2*(y+.5)/Height)/ProjectionY,1};
                V worldRay=camera.WorldVector(ray);double z=Scene(2,camera.origin,worldRay,box);
                depthValues[y*Width+x]=static_cast<float>(.1/z);
                V normal=Unit({.35,-.18,-1}),p=camera.origin+worldRay*z;
                if(std::fabs(Box(camera.origin,worldRay,box)-z)<1e-5) {
                    V d=p-box;double dx=std::fabs(std::fabs(d.x)-8),dy=std::fabs(std::fabs(d.y)-10),dz=std::fabs(std::fabs(d.z)-8);
                    normal=dx<=dy&&dx<=dz?V{std::copysign(1.0,d.x),0,0}:dy<=dz?V{0,std::copysign(1.0,d.y),0}:V{0,0,std::copysign(1.0,d.z)};
                }
                normalValues[y*Width+x]=Float4(camera.ViewVector(normal));
            }
            for(UINT i=0;i<Count;++i) {
                double u=(i%32+.5)/32,v=(i/32+.5)/16;
                V p={(u-.5)*65,(v-.5)*45,0};p.z=160+.35*p.x-.18*p.y;
                V n=Unit({.35,-.18,-1}),vp=camera.ViewPoint(p),direction=Unit(Light-p);
                double us=vp.x/vp.z*ProjectionX*.5+.5,vs=.5-vp.y/vp.z*ProjectionY*.5;
                bool active=vp.z>1&&us>2.0/Width&&us<1-2.0/Width&&vs>2.0/Height&&vs<1-2.0/Height&&
                    std::fabs(Scene(2,camera.origin,p-camera.origin,box)-1)<1e-5&&Dot(n,direction)>.05;
                samples[i]={Float4(vp,active?1.f:0.f),Float4(camera.ViewVector(n))};
            }
            context->UpdateSubresource(depth.Get(),0,nullptr,depthValues.data(),Width*4,0);
            context->UpdateSubresource(normals.Get(),0,nullptr,normalValues.data(),Width*sizeof(ContactFloat4),0);
            context->UpdateSubresource(receivers.Get(),0,nullptr,samples.data(),0,0);
            ContactFloat4 params[4]={{static_cast<float>(Width),static_cast<float>(Height),static_cast<float>(ProjectionX),static_cast<float>(ProjectionY)},
                Float4(camera.ViewPoint(Light),1.f/150),{.1f,10,static_cast<float>(Count),1},
                {ContactBits(frame==Frames-1?0:frame),ContactBits(1),0,0}};
            context->UpdateSubresource(constants.Get(),0,nullptr,params,0,0);
            for(unsigned mode=0;mode<2;++mode) {
                const float sentinel[]={-1000,-1000,-1000,-1000};
                context->ClearUnorderedAccessViewFloat(uavs[0].Get(),sentinel);context->ClearUnorderedAccessViewFloat(uavs[1].Get(),sentinel);
                ID3D11UnorderedAccessView* targets[]={uavs[0].Get(),mode?uavs[1].Get():nullptr};
                context->CSSetUnorderedAccessViews(0,2,targets,nullptr);context->CSSetShader(shaders[mode].Get(),nullptr,0);context->Dispatch(Count/64,1,1);
                targets[0]=targets[1]=nullptr;context->CSSetUnorderedAccessViews(0,2,targets,nullptr);
                for(unsigned slot=0;slot<=mode;++slot) {
                    context->CopyResource(staging[slot].Get(),buffers[slot].Get());D3D11_MAPPED_SUBRESOURCE mapped={};
                    Check(context->Map(staging[slot].Get(),0,D3D11_MAP_READ,0,&mapped),"Read trace");
                    void* destination=slot?static_cast<void*>(traceValues.data()):mode?static_cast<void*>(values.data()):static_cast<void*>(reference.data());
                    std::memcpy(destination,mapped.pData,bytes[slot]);context->Unmap(staging[slot].Get(),0);
                }
            }
            for(UINT i=0;i<Count;++i) {
                if(std::memcmp(&reference[i],&saved[(2*Frames+frame)*Count+i],4)) throw std::runtime_error("Reference differs from prior motion readback");
                float difference=std::fabs(reference[i]-values[i]);maximumDifference=(std::max)(maximumDifference,difference);
                bitDifferences+=std::memcmp(&reference[i],&values[i],4)!=0;
                if(!std::isfinite(values[i])||difference>2e-6f||traceValues[i*216]!=values[i]) throw std::runtime_error("Instrumentation changes output");
                logged+=static_cast<unsigned>(traceValues[i*216+1]);
            }
            traceFile.write(reinterpret_cast<const char*>(traceValues.data()),bytes[1]);valueFile.write(reinterpret_cast<const char*>(values.data()),bytes[0]);
            if(frame%16==15){std::printf("PASS traced frame %u/96; saved reference bit-exact\n",frame+1);std::fflush(stdout);}
        }
        if(!traceFile||!valueFile||!logged) throw std::runtime_error("Incomplete trace output");
        std::printf("Trace complete: cases=%u loggedSteps=%u instrumentedBitDifferences=%u maximumDifference=%.9g; diagnostic only\n",Frames*Count,logged,bitDifferences,maximumDifference);
        return 0;
    } catch(const std::exception& e) {std::fprintf(stderr,"%s\n",e.what());return 2;}
}
