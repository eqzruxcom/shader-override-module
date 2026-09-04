// Included after the runner's Check helper. Synthetic resource tests only.
#include <array>
#include <algorithm>
#include <cstring>
#include <vector>
#include <filesystem>
#include <map>

// D3D_COMPILE_STANDARD_FILE_INCLUDE resolves nested files against the entry
// directory. Preserve the including file's directory for the production tree.
class ContactNestedIncludes final : public ID3DInclude {
    using Path=std::filesystem::path;
    Path root;
    std::map<const void*,std::pair<Path,ComPtr<ID3DBlob>>> opened;
public:
    explicit ContactNestedIncludes(const wchar_t* source):root(Path(source).parent_path()) {}
    HRESULT __stdcall Open(D3D_INCLUDE_TYPE, LPCSTR name, LPCVOID parent,
        LPCVOID* data, UINT* bytes) override {
        try {
            auto found=opened.find(parent);
            Path path=(found==opened.end()?root:found->second.first.parent_path())/name;
            ComPtr<ID3DBlob> blob;
            HRESULT result=D3DReadFileToBlob(path.c_str(),&blob);
            if(FAILED(result)) return result;
            if(blob->GetBufferSize()>UINT_MAX) return E_FAIL;
            *data=blob->GetBufferPointer();*bytes=static_cast<UINT>(blob->GetBufferSize());
            opened.emplace(*data,std::make_pair(path,blob));
            return S_OK;
        } catch(...) {return E_FAIL;}
    }
    HRESULT __stdcall Close(LPCVOID data) override {opened.erase(data);return S_OK;}
};

struct ContactFloat4 { float x=0, y=0, z=0, w=0; };
static float ContactBits(UINT value) {
    float result;
    std::memcpy(&result, &value, sizeof(result));
    return result;
}

static int RunContactAdapterTests(const wchar_t* source, const wchar_t* fixture=nullptr,
    UINT fixtureSlot=0,const wchar_t* diffuseMask=nullptr,const wchar_t* specularMask=nullptr,
    UINT frameIndex=0,UINT materialByte=1,bool reconstruction=false,bool shared=false,bool repeated=false) {
    if(shared && (!fixture || !reconstruction)) throw std::runtime_error("Shared test requires full-group fixture and oracle");
    if(repeated&&!shared) throw std::runtime_error("Repeated test requires shared fixture");
    const UINT iterations=repeated?8u:1u;
    UINT alternatingDifferences=0,zeroShadowLanes=0;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    D3D_FEATURE_LEVEL requested=D3D_FEATURE_LEVEL_11_0, obtained;
    Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&requested,1,
        D3D11_SDK_VERSION,&device,&obtained,&context), "Create adapter WARP");
    constexpr UINT size=128;
    std::printf("Input profile: viewFrame=%u packedMaterial=%u\n",frameIndex,materialByte);
    const char* labels[]={"disabled", "all lights hit", "selected light hit",
        "other light bypass", "index out of range", "zero strength", "half strength",
        "negative ray length", "no occluder", "pretranslation cancels",
        "wrong pretranslation rejected", "subviewport hit", "outside viewport",
        "empty viewport", "viewport beyond allocation", "wrong forward XY rejected",
        "wrong forward Z rejected", "zero normal", "zero light radius",
        "nonuniform projection", "light index bitcast", "depth zero sky",
        "viewport exterior ignored", "rotated camera",
        "zero native contributions", "diffuse first lane only", "diffuse second lane only",
        "diffuse third lane only", "specular first lane only", "specular second lane only",
        "specular third lane only", "negative zero native", "negative native contributions",
        "lit blocker receiver plane", "lit receiver no blocker", "translated lit blocker", "rotated lit blocker",
        "odd viewport neutral", "partial group viewport", "mixed invalid group receivers"};
    const UINT count=shared?40u:37u;
    unsigned failed=0;
    for (UINT slot : {4u,5u}) {
        if(fixture && slot!=fixtureSlot) continue;
        D3D_SHADER_MACRO defines[]={{"REDX11_CONTACT_DEPTH_REGISTER",slot==4?"t4":"t5"},
            {"REDX11_GROUP_ITERATIONS",repeated?"8":"1"},{nullptr,nullptr}};
        ComPtr<ID3DBlob> binary,errors;
        if(fixture) Check(D3DReadFileToBlob(fixture,&binary),"Read injected assembly fixture");
        else {
            ContactNestedIncludes includes(source);
            HRESULT compiled=D3DCompileFromFile(source,defines,&includes,
                "main","cs_5_0",D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS|
                D3DCOMPILE_IEEE_STRICTNESS|D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&binary,&errors);
            if(errors) std::fprintf(stderr,"%s",static_cast<const char*>(errors->GetBufferPointer()));
            Check(compiled,"Compile production adapter wrapper");
        }
        ComPtr<ID3D11ComputeShader> shader;
        Check(device->CreateComputeShader(binary->GetBufferPointer(),binary->GetBufferSize(),
            nullptr,&shader),"Create adapter compute");
        ComPtr<ID3D11ComputeShader> oracleShader;
        if(fixture&&reconstruction) {
            ComPtr<ID3DBlob> oracleBinary,oracleErrors;ContactNestedIncludes includes(source);
            HRESULT compiled=D3DCompileFromFile(source,defines,&includes,"main","cs_5_0",
                D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS|D3DCOMPILE_IEEE_STRICTNESS|D3DCOMPILE_OPTIMIZATION_LEVEL3,
                0,&oracleBinary,&oracleErrors);
            if(oracleErrors) std::fprintf(stderr,"%s",static_cast<const char*>(oracleErrors->GetBufferPointer()));
            Check(compiled,"Compile reconstruction reference");
            Check(device->CreateComputeShader(oracleBinary->GetBufferPointer(),oracleBinary->GetBufferSize(),nullptr,&oracleShader),"Create reconstruction reference");
        }
        for(UINT phase=0;phase<(reconstruction?2u:1u);++phase)
        for(UINT quadLane=0;quadLane<(reconstruction&&!shared?4u:1u);++quadLane)
        for(UINT test=0;test<count;++test) {
            if(!fixture && test>=24 && test<=32) continue;
            std::array<ContactFloat4,5> dispatch={};
            std::array<ContactFloat4,140> view={};
            view[139]={ContactBits(899797841u),ContactBits(11283u),ContactBits(frameIndex&7u),ContactBits(frameIndex)};
            if(reconstruction) view[139].z=ContactBits(phase);
            std::array<ContactFloat4,768> lights={};
            std::array<ContactFloat4,32> controls={};
            ContactFloat4 input={64,64,ContactBits(7),0};
            input.x+=static_cast<float>(quadLane&1u);input.y+=static_cast<float>(quadLane>>1u);
            float nativeDiffuse[4]={2,4,6,8},nativeSpecular[4]={10,12,14,16};
            if(fixture && test>=24 && test<=32) {
                for(UINT lane=0;lane<4;++lane) {
                    if(std::wcschr(diffuseMask,L"xyzw"[lane])) nativeDiffuse[lane]=test==31?-0.f:0.f;
                    if(std::wcschr(specularMask,L"xyzw"[lane])) nativeSpecular[lane]=test==31?-0.f:0.f;
                }
                if(test>=25 && test<=30) {
                    UINT channel=(test-25)%3;
                    const wchar_t* mask=test<28?diffuseMask:specularMask;
                    UINT lane=0;while(L"xyzw"[lane]!=mask[channel]) ++lane;
                    (test<28?nativeDiffuse:nativeSpecular)[lane]=2.f;
                }
                if(test==32) {
                    for(UINT lane=0;lane<4;++lane) {
                        if(std::wcschr(diffuseMask,L"xyzw"[lane])) nativeDiffuse[lane]=-2.f-2*lane;
                        if(std::wcschr(specularMask,L"xyzw"[lane])) nativeSpecular[lane]=-10.f-2*lane;
                    }
                }
            }
            UINT minX=0,minY=0,maxX=size,maxY=size;
            if(test==11 || test==22) {minX=16;minY=24;maxX=112;maxY=104;}
            if(test==12) input.x=128;
            if(test==13) maxX=0;
            if(test==14) maxY=size+1;
            if(test==37) minX=1;
            if(test==38) {maxX=72;maxY=75;}
            dispatch[1]={ContactBits(minX),ContactBits(minY),ContactBits(maxX),ContactBits(maxY)};
            view[0]={1,0,0,0};view[1]={0,1,0,0};view[2]={0,0,0,1};view[3]={0,0,.1f,0};
            view[24].x=1;view[25].y=1;view[27].w=0;
            view[40]={1,0,0,0};view[41]={0,1,0,0};view[42]={0,0,1,0};view[43]={0,0,0,1};
            view[57]={0,0,10,0};view[126]={128,128,1.f/128,1.f/128};
            lights[7]={100,0,10,1};
            controls[31]={1,-1,1,5};
            if(test==0) controls[31].x=0;
            if(test==2) controls[31].y=7;
            if(test==3) controls[31].y=8;
            if(test==4) input.z=ContactBits(256);
            if(test==5) controls[31].z=0;
            if(test==6) controls[31].z=.5f;
            if(test==7) controls[31].w=-1;
            if(test==9 || test==10) {
                view[43]={1000,-2000,3000,1};view[62]={-1000,2000,-3000,0};
                lights[7]={1100,-2000,3010,1};
                if(test==10) view[62].x=0;
            }
            if(test==15) view[3].x=10;
            if(test==16) view[3].z=.2f;
            if(test==18) lights[7].w=0;
            if(test==19) {
                view[0].x=2;view[1].y=.5f;view[40].x=.5f;view[41].y=2;
                view[24].x=2;view[25].y=.5f;
            }
            if(test==20) input.z=7.f; // Numeric conversion is deliberately wrong.
            if(test==23) {
                // World Y is view X, world -X is view Y. Not just an identity camera.
                view[0]={0,-1,0,0};view[1]={1,0,0,0};
                view[40]={0,1,0,0};view[41]={-1,0,0,0};lights[7]={0,100,10,1};
            }
            if(test>=33) lights[7]={100,0,5,1};
            if(test==35) {
                view[43]={1000,-2000,3000,1};view[62]={-1000,2000,-3000,0};
                lights[7]={1100,-2000,3005,1};
            }
            if(test==36) {
                view[0]={0,-1,0,0};view[1]={1,0,0,0};
                view[40]={0,1,0,0};view[41]={-1,0,0,0};lights[7]={0,100,5,1};
            }
            // Opposite light direction, with the same camera/translation and
            // radius validity. Both lights are real, not a zero-radius bypass.
            if(repeated) {lights[8]=lights[7];lights[8].x=2*view[43].x-lights[7].x;lights[8].y=2*view[43].y-lights[7].y;}
            std::vector<ContactFloat4> normals(size*size,{.5f,.5f,1,0});
            std::vector<ContactFloat4> depths(size*size,{.1f/8,0,0,0});
            if(test==8 || test==22 || test==34) {
                for(UINT y=0;y<size;++y) for(UINT x=0;x<size;++x)
                    if(test==8 || test==34 || (x>=minX && x<maxX && y>=minY && y<maxY))
                        depths[y*size+x].x=.1f/15;
            }
            const UINT receiverPixel=(64+(quadLane>>1u))*size+64+(quadLane&1u);
            depths[receiverPixel].x=test==21?0:.1f/10;
            if(test==17) normals[receiverPixel]={.5f,.5f,.5f,0};
            if(test>=33) normals[receiverPixel]={.5f,.5f,0,0};
            if(test==39) for(UINT y=64;y<80;++y) for(UINT x=64;x<80;++x) {
                if(x%3==0) normals[y*size+x]={.5f,.5f,.5f,0};
                if(y%5==0) depths[y*size+x].x=0;
            }

            auto constant=[&](const void* data,UINT bytes,UINT binding) {
                D3D11_BUFFER_DESC desc={};desc.ByteWidth=bytes;desc.Usage=D3D11_USAGE_IMMUTABLE;
                desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
                D3D11_SUBRESOURCE_DATA initial={};initial.pSysMem=data;
                ComPtr<ID3D11Buffer> buffer;
                Check(device->CreateBuffer(&desc,&initial,&buffer),"Create adapter CB");
                ID3D11Buffer* p=buffer.Get();context->CSSetConstantBuffers(binding,1,&p);
            };
            constant(dispatch.data(),static_cast<UINT>(sizeof(dispatch)),0);
            constant(view.data(),static_cast<UINT>(sizeof(view)),1);
            constant(lights.data(),static_cast<UINT>(sizeof(lights)),4);
            ContactFloat4 fixtureInput[3]={input,{},{}};
            std::memcpy(&fixtureInput[1],nativeDiffuse,sizeof(nativeDiffuse));
            std::memcpy(&fixtureInput[2],nativeSpecular,sizeof(nativeSpecular));
            constant(fixtureInput,sizeof(fixtureInput),7);
            if(repeated) {
                UINT baseIndex;std::memcpy(&baseIndex,&input.z,sizeof(baseIndex));
                const UINT indices[4]={baseIndex&255u,(baseIndex+1u)&255u,0,0};
                constant(indices,sizeof(indices),8);
            }
            auto texture=[&](const std::vector<ContactFloat4>& data,UINT binding) {
                D3D11_TEXTURE2D_DESC desc={};desc.Width=size;desc.Height=size;desc.MipLevels=1;
                desc.ArraySize=1;desc.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;desc.SampleDesc.Count=1;
                desc.Usage=D3D11_USAGE_IMMUTABLE;desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;
                D3D11_SUBRESOURCE_DATA initial={};initial.pSysMem=data.data();initial.SysMemPitch=size*sizeof(ContactFloat4);
                ComPtr<ID3D11Texture2D> resource;ComPtr<ID3D11ShaderResourceView> srv;
                Check(device->CreateTexture2D(&desc,&initial,&resource),"Create adapter texture");
                Check(device->CreateShaderResourceView(resource.Get(),nullptr,&srv),"Create adapter SRV");
                ID3D11ShaderResourceView* p=srv.Get();context->CSSetShaderResources(binding,1,&p);
            };
            texture(normals,1);texture(depths,slot);
            // Native material alpha carries low-nibble class plus output flags.
            // Baseline class 1; optional profiles exercise hair/flags/frame bits.
            std::vector<ContactFloat4> materials(size*size,{0,0,0,static_cast<float>(materialByte)/255.f});
            if(reconstruction) for(UINT y=0;y<size;++y) for(UINT x=0;x<size;++x)
                materials[y*size+x].w=((x^y)&1u)?231.f/255.f:1.f/255.f;
            texture(materials,2);
            // Poison the OTHER possible depth slot to ensure the intended one is used.
            texture(normals,slot==4?5:4);
            D3D11_TEXTURE1D_DESC controlDesc={};controlDesc.Width=32;controlDesc.MipLevels=1;
            controlDesc.ArraySize=1;controlDesc.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;
            controlDesc.Usage=D3D11_USAGE_IMMUTABLE;controlDesc.BindFlags=D3D11_BIND_SHADER_RESOURCE;
            D3D11_SUBRESOURCE_DATA controlInitial={};controlInitial.pSysMem=controls.data();
            ComPtr<ID3D11Texture1D> controlTexture;ComPtr<ID3D11ShaderResourceView> controlSrv;
            Check(device->CreateTexture1D(&controlDesc,&controlInitial,&controlTexture),"Create control texture");
            Check(device->CreateShaderResourceView(controlTexture.Get(),nullptr,&controlSrv),"Create control SRV");
            ID3D11ShaderResourceView* controlPointer=controlSrv.Get();context->CSSetShaderResources(120,1,&controlPointer);
            const UINT outputCount=shared?iterations*256u*9u:fixture?9u:reconstruction?6u:1u;
            D3D11_BUFFER_DESC resultDesc={};resultDesc.ByteWidth=outputCount*sizeof(float);resultDesc.Usage=D3D11_USAGE_DEFAULT;
            resultDesc.BindFlags=D3D11_BIND_UNORDERED_ACCESS;resultDesc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
            resultDesc.StructureByteStride=sizeof(float);
            ComPtr<ID3D11Buffer> result,staging;ComPtr<ID3D11UnorderedAccessView> uav;
            Check(device->CreateBuffer(&resultDesc,nullptr,&result),"Create adapter result");
            Check(device->CreateUnorderedAccessView(result.Get(),nullptr,&uav),"Create adapter result UAV");
            resultDesc.Usage=D3D11_USAGE_STAGING;resultDesc.BindFlags=0;resultDesc.MiscFlags=0;
            resultDesc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;resultDesc.StructureByteStride=0;
            Check(device->CreateBuffer(&resultDesc,nullptr,&staging),"Create adapter readback");
            const float sentinel[4]={-1000,-1000,-1000,-1000};context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
            ID3D11UnorderedAccessView* target=uav.Get();context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
            context->CSSetShader(shader.Get(),nullptr,0);context->Dispatch(1,1,1);
            target=nullptr;context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
            context->CopyResource(staging.Get(),result.Get());D3D11_MAPPED_SUBRESOURCE mapped={};
            Check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"Read adapter result");
            std::vector<float> values(outputCount);std::memcpy(values.data(),mapped.pData,outputCount*sizeof(float));
            float value=values[0];context->Unmap(staging.Get(),0);
            if(shared) {
                context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
                target=uav.Get();context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                context->CSSetShader(oracleShader.Get(),nullptr,0);context->Dispatch(1,1,iterations);
                target=nullptr;context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                context->CopyResource(staging.Get(),result.Get());
                Check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"Read group recomputation reference");
                std::vector<float> reference(iterations*256u*6u);std::memcpy(reference.data(),mapped.pData,reference.size()*sizeof(float));
                context->Unmap(staging.Get(),0);
                UINT failures=0;
                for(UINT iteration=0;iteration<iterations;++iteration)
                for(UINT thread=0;thread<256;++thread) {
                    const UINT record=iteration*256u+thread;
                    const float* oracle=&reference[record*6];const float* actual=&values[record*9];
                    UINT x=static_cast<UINT>(input.x)+(thread%16u),y=static_cast<UINT>(input.y)+(thread/16u);
                    bool selected=((x+y+phase)&1u)!=0;UINT lane=(x&1u)+2u*(y&1u);
                    float ray=selected?oracle[1+lane]:.5f*(oracle[1+(lane^1u)]+oracle[1+(lane^2u)]);
                    float expected=oracle[5]==0?1.f:1.f+(ray-1.f)*(std::clamp)(controls[31].z,0.f,1.f);
                    if(test==37) expected=1.f; // Explicit unsupported odd-origin neutral contract.
                    bool passed=std::isfinite(actual[0]) && actual[0]>=0 && actual[0]<=1 && std::fabs(actual[0]-expected)<2e-6f;
                    if(test!=37) passed=passed&&std::fabs(actual[0]-oracle[0])<2e-6f;
                    for(UINT j=0;j<6;++j) passed=passed&&std::isfinite(oracle[j])&&oracle[j]>=0&&oracle[j]<=1;
                    if(iteration>0 && std::fabs(actual[0]-values[(record-256u)*9u])>1e-4f) ++alternatingDifferences;
                    if(iteration>=2) passed=passed&&actual[0]==values[(record-512u)*9u];
                    const UINT pattern=(thread%16u+thread/16u+iteration)&3u;
                    if(repeated&&pattern==2&&actual[0]<.999f) ++zeroShadowLanes;
                    for(UINT j=0;j<4;++j) {
                        bool dm=std::wcschr(diffuseMask,L"xyzw"[j])!=nullptr,sm=std::wcschr(specularMask,L"xyzw"[j])!=nullptr;
                        float nd=nativeDiffuse[j],ns=nativeSpecular[j];
                        if(repeated) {
                            if(dm&&pattern==0) nd=0;
                            if(sm&&pattern==1) ns=0;
                            if(pattern==2) {if(dm) nd=-0.f;if(sm) ns=-0.f;}
                        }
                        float d=nd*(dm?actual[0]:1.f),s=ns*(sm?actual[0]:1.f);
                        passed=passed&&std::isfinite(actual[1+j])&&std::isfinite(actual[5+j])&&std::fabs(actual[1+j]-d)<1e-5f&&std::fabs(actual[5+j]-s)<1e-5f;
                        if(nd==0||!dm||actual[0]==1.f) passed=passed&&std::memcmp(&actual[1+j],&nd,4)==0;
                        if(ns==0||!sm||actual[0]==1.f) passed=passed&&std::memcmp(&actual[5+j],&ns,4)==0;
                    }
                    if(!passed) {if(failures<3) std::printf("FAIL group iteration=%u lane=%u expected=%.9g actual=%.9g\n",iteration,thread,expected,actual[0]);++failures;}
                }
                std::printf("%s shared%s t%u phase=%u %02u %-30s lanes=%u/%u\n",failures?"FAIL":"PASS",repeated?"-repeat":"",slot,phase,test,labels[test],256u*iterations-failures,256u*iterations);
                if(failures) ++failed;
                context->ClearState();continue;
            }
            float oracleValues[6]={};
            if(reconstruction) {
                if(fixture) {
                    context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
                    target=uav.Get();context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                    context->CSSetShader(oracleShader.Get(),nullptr,0);context->Dispatch(1,1,1);
                    target=nullptr;context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                    context->CopyResource(staging.Get(),result.Get());
                    Check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"Read reconstruction reference");
                    std::memcpy(oracleValues,mapped.pData,sizeof(oracleValues));context->Unmap(staging.Get(),0);
                } else std::memcpy(oracleValues,values.data(),sizeof(oracleValues));
            }
            bool hit=test==1 || test==2 || test==9 || test==11 || test==19 || test==23
                || (test>=25 && test<=30) || test==32 || test==33 || test==35 || test==36;
            bool passed=std::isfinite(value) && (test==6 ? value>=.5f && value<.55f
                : hit ? value>=0 && value<.1f : std::fabs(value-1)<1e-6f);
            if(reconstruction) {
                // Independent CPU checkerboard/neighbor selection over four
                // raw GPU ray values. Not a geometric shadow-quality oracle.
                bool selected=((static_cast<UINT>(input.x)+static_cast<UINT>(input.y)+phase)&1u)!=0;
                UINT lane=(static_cast<UINT>(input.x)&1u)+2u*(static_cast<UINT>(input.y)&1u);
                float raw=selected?oracleValues[1+lane]:.5f*(oracleValues[1+(lane^1u)]+oracleValues[1+(lane^2u)]);
                float expectedValue=oracleValues[5]==0?1.f:1.f+(raw-1.f)*(std::clamp)(controls[31].z,0.f,1.f);
                bool zeroNative=fixture&&(test==24||test==31);
                if(zeroNative) expectedValue=1.f;
                passed=std::isfinite(value)&&value>=0&&value<=1&&std::fabs(value-expectedValue)<2e-6f;
                for(UINT k=0;k<6;++k) passed=passed&&std::isfinite(oracleValues[k])&&oracleValues[k]>=0&&oracleValues[k]<=1;
                if(!zeroNative) passed=passed&&std::fabs(value-oracleValues[0])<2e-6f;
                if(!passed) std::printf("Reconstruction phase=%u lane=%u: expected %.9g got %.9g\n",phase,quadLane,expectedValue,value);
            }
            if(fixture) {
                for(UINT lane=0;lane<4;++lane) {
                    float expectedDiffuse=nativeDiffuse[lane]*(std::wcschr(diffuseMask,L"xyzw"[lane])?value:1.f);
                    float expectedSpecular=nativeSpecular[lane]*(std::wcschr(specularMask,L"xyzw"[lane])?value:1.f);
                    bool lanesCorrect=std::isfinite(values[lane+1]) && std::isfinite(values[lane+5])
                        && std::fabs(values[lane+1]-expectedDiffuse)<1e-5f
                        && std::fabs(values[lane+5]-expectedSpecular)<1e-5f;
                    if(test==24 || test==31) lanesCorrect=lanesCorrect
                        && std::memcmp(&values[lane+1],&nativeDiffuse[lane],sizeof(float))==0
                        && std::memcmp(&values[lane+5],&nativeSpecular[lane],sizeof(float))==0;
                    if(!lanesCorrect) std::printf("FAIL physical lane %u: diffuse %.9g expected %.9g; specular %.9g expected %.9g\n",
                        lane,values[lane+1],expectedDiffuse,values[lane+5],expectedSpecular);
                    passed=passed && lanesCorrect;
                }
            }
            std::printf("%s t%u %02u %-30s %.9g\n",passed?"PASS":"FAIL",slot,test,labels[test],value);
            if(!passed) ++failed;
            context->ClearState();
        }
    }
    UINT total=(fixture?count:2*(count-9))*(shared?2u:reconstruction?8u:1u);
    if(shared) {
        std::printf("Shared assembly groups: %u/%u passed, each 256 threads, %u light iterations; no full native renderer or live test.\n",total-failed,total,iterations);
        if(repeated) {
            std::printf("Repeated coverage: alternatingDifferences=%u zeroContributionShadowLanes=%u\n",alternatingDifferences,zeroShadowLanes);
            if(!alternatingDifferences||!zeroShadowLanes) {std::printf("FAIL vacuous repeated coverage\n");return 1;}
        }
        return failed?1:0;
    }
    std::printf("%s: %u/%u passed. Synthetic data, not live Remake constants.\n",reconstruction?(fixture?"Reconstruction assembly tests":"Reconstruction adapter tests"):"Adapter resource tests",total-failed,total);
    return failed?1:0;
}
