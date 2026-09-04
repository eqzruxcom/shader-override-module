// Headless synthetic scene + actual production HLSL on WARP. Never touches FF7.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <cwchar>
using Microsoft::WRL::ComPtr;
static void Check(HRESULT hr,const char* what) {if(FAILED(hr)) throw std::runtime_error(what);}
#include "ContactShadowAdapterTests.h"
struct V {double x=0,y=0,z=0;};
static V operator+(V a,V b) {return {a.x+b.x,a.y+b.y,a.z+b.z};}
static V operator-(V a,V b) {return {a.x-b.x,a.y-b.y,a.z-b.z};}
static V operator*(V a,double t) {return {a.x*t,a.y*t,a.z*t};}
static double Dot(V a,V b) {return a.x*b.x+a.y*b.y+a.z*b.z;}
static double Length(V a) {return std::sqrt(Dot(a,a));}
static V Unit(V a) {return a*(1/Length(a));}
struct Camera {
    V origin,right,forward;
    V ViewVector(V p) const {return {Dot(p,right),p.y,Dot(p,forward)};}
    V ViewPoint(V p) const {return ViewVector(p-origin);}
    V WorldVector(V p) const {return right*p.x+V{0,1,0}*p.y+forward*p.z;}
};
static constexpr UINT Width=1280,Height=720,Count=512,Frames=96;
static constexpr double ProjectionX=1.7320509,ProjectionY=3.079202;
static constexpr V SphereCenter={0,0,130};
static constexpr double Radius=25;
static constexpr V Light={80,45,40};
static constexpr double Infinity=1e20;
static bool Slab(double o,double d,double lo,double hi,double& nearT,double& farT) {
    if(std::fabs(d)<1e-12) return o>=lo && o<=hi;
    double a=(lo-o)/d,b=(hi-o)/d;
    nearT=(std::max)(nearT,(std::min)(a,b));farT=(std::min)(farT,(std::max)(a,b));
    return farT>=nearT;
}
static double Box(V o,V d,V center) {
    double a=0,b=Infinity;
    if(!Slab(o.x,d.x,center.x-8,center.x+8,a,b) || !Slab(o.y,d.y,center.y-10,center.y+10,a,b) ||
       !Slab(o.z,d.z,center.z-8,center.z+8,a,b)) return Infinity;
    return a>1e-5?a:(b>1e-5?b:Infinity);
}
static double Scene(unsigned scene,V o,V d,V box) {
    if(scene==1 || scene==3) {
        V q=o-SphereCenter;double a=Dot(d,d),b=Dot(q,d),c=Dot(q,q)-Radius*Radius;
        double discriminant=b*b-a*c;
        if(discriminant<0) return Infinity;
        double t=(-b-std::sqrt(discriminant))/a;
        if(t<=1e-5) t=(-b+std::sqrt(discriminant))/a;
        return t>1e-5?t:Infinity;
    }
    double denominator=d.z-.35*d.x+.18*d.y;
    double t=std::fabs(denominator)<1e-12?Infinity:(160+.35*o.x-.18*o.y-o.z)/denominator;
    if(t<=1e-5) t=Infinity;
    return scene==2?(std::min)(t,Box(o,d,box)):t;
}
static ContactFloat4 Float4(V p,float w=0) {return {static_cast<float>(p.x),static_cast<float>(p.y),static_cast<float>(p.z),w};}
struct Receiver {ContactFloat4 position,normal;};
static V QuantizeNormal(V n) {
    auto q=[](double v) {return std::round((v*.5+.5)*1023)/1023*2-1;};
    return Unit({q(n.x),q(n.y),q(n.z)});
}
int wmain(int argc,wchar_t** argv) {
    if(argc<4 || argc>6) return 2;
    const bool animatedNoise=argc>=5 && std::wcscmp(argv[4],L"animated")==0;
    if(argc>=5 && !animatedNoise && std::wcscmp(argv[4],L"fixed")!=0) return 2;
    UINT reconstruction=0;
    if(argc==6) {
        if(std::wcscmp(argv[5],L"pixel")==0) reconstruction=1;
        else if(std::wcscmp(argv[5],L"quad")==0) reconstruction=2;
        else if(std::wcscmp(argv[5],L"raw")!=0) return 2;
    }
    try {
        std::filesystem::path output(argv[2]);
        ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL level=D3D_FEATURE_LEVEL_11_0;
        Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,&level,1,D3D11_SDK_VERSION,&device,nullptr,&context),"Create WARP");
        ComPtr<ID3DBlob> binary,errors;ContactNestedIncludes includes(argv[1]);
        unsigned sampleCount=static_cast<unsigned>(std::wcstoul(argv[3],nullptr,10));
        if(sampleCount!=16 && sampleCount!=32 && sampleCount!=64) throw std::runtime_error("Unexpected sample count");
        std::string sampleDefine=std::to_string(sampleCount);
        D3D_SHADER_MACRO definitions[]={{"REDX11_CONTACT_SAMPLES",sampleDefine.c_str()},{nullptr,nullptr}};
        HRESULT compiled=D3DCompileFromFile(argv[1],definitions,&includes,"main","cs_5_0",
            D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS|D3DCOMPILE_IEEE_STRICTNESS|D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&binary,&errors);
        if(errors) std::fprintf(stderr,"%s",static_cast<const char*>(errors->GetBufferPointer()));
        Check(compiled,"Compile motion wrapper");
        Check(D3DWriteBlobToFile(binary.Get(),(output/L"motion-kernel.cso").c_str(),FALSE),"Save kernel");
        ComPtr<ID3D11ComputeShader> shader;Check(device->CreateComputeShader(binary->GetBufferPointer(),binary->GetBufferSize(),nullptr,&shader),"Create shader");
        D3D11_TEXTURE2D_DESC td={};td.Width=Width;td.Height=Height;td.MipLevels=1;td.ArraySize=1;td.Format=DXGI_FORMAT_R32_FLOAT;
        td.SampleDesc.Count=1;td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        ComPtr<ID3D11Texture2D> depth;ComPtr<ID3D11ShaderResourceView> depthSRV;
        Check(device->CreateTexture2D(&td,nullptr,&depth),"Create depth");Check(device->CreateShaderResourceView(depth.Get(),nullptr,&depthSRV),"Depth SRV");
        ComPtr<ID3D11Texture2D> normals;ComPtr<ID3D11ShaderResourceView> normalSRV;
        if(reconstruction) {
            td.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;
            Check(device->CreateTexture2D(&td,nullptr,&normals),"Create motion normals");
            Check(device->CreateShaderResourceView(normals.Get(),nullptr,&normalSRV),"Motion normal SRV");
            ID3D11ShaderResourceView* p=normalSRV.Get();context->CSSetShaderResources(2,1,&p);
        }
        D3D11_BUFFER_DESC desc={};desc.ByteWidth=Count*sizeof(Receiver);desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        desc.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;desc.StructureByteStride=sizeof(Receiver);
        ComPtr<ID3D11Buffer> receivers;ComPtr<ID3D11ShaderResourceView> receiverSRV;
        Check(device->CreateBuffer(&desc,nullptr,&receivers),"Receiver buffer");Check(device->CreateShaderResourceView(receivers.Get(),nullptr,&receiverSRV),"Receiver SRV");
        desc.ByteWidth=Count*4;desc.BindFlags=D3D11_BIND_UNORDERED_ACCESS;desc.StructureByteStride=4;
        ComPtr<ID3D11Buffer> result,readback;ComPtr<ID3D11UnorderedAccessView> uav;
        Check(device->CreateBuffer(&desc,nullptr,&result),"Result");Check(device->CreateUnorderedAccessView(result.Get(),nullptr,&uav),"Result UAV");
        desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;desc.MiscFlags=0;desc.StructureByteStride=0;
        Check(device->CreateBuffer(&desc,nullptr,&readback),"Readback");
        desc={};desc.ByteWidth=64;desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        ComPtr<ID3D11Buffer> constants;Check(device->CreateBuffer(&desc,nullptr,&constants),"Constants");
        ID3D11ShaderResourceView* srvs[]={depthSRV.Get(),receiverSRV.Get()};context->CSSetShaderResources(0,2,srvs);
        ID3D11Buffer* cb=constants.Get();context->CSSetConstantBuffers(13,1,&cb);context->CSSetShader(shader.Get(),nullptr,0);
        std::vector<float> depthValues(Width*Height);
        std::vector<ContactFloat4> normalValues(reconstruction?Width*Height:0);
        std::array<Receiver,Count> samples={};
        std::array<int,Count> active={},expected={},eligible={},previousActive={},previousExpected={};
        std::array<float,Count> previousVisibility={},firstVisibility={};
        std::ofstream csv(output/L"results.csv"),frames(output/L"frames.csv"),readbacks(output/L"visibility.f32",std::ios::binary);
        if(!csv || !frames || !readbacks) throw std::runtime_error("Open result files");
        csv<<"scene,frame,receiver,active,expectedShadow,screenVisibleBlocker,visibility,worldX,worldY,worldZ,normalX,normalY,normalZ\n";
        frames<<"scene,frame,active,falseHits,visibleBlockers,missedVisibleBlockers,stableTruthLargeChanges,repeatMaxDifference\n";
        const char* names[]={"plane","convex-sphere","moving-box","perturbed-quantized-sphere"};
        unsigned invalid=0,totalFalse=0,totalMiss=0,totalTransitions=0;
        for(unsigned scene=0;scene<4;scene++) {
            unsigned sceneActive=0,sceneFalse=0,sceneMiss=0,sceneTransitions=0,sceneBlockers=0;
            previousActive.fill(0);
            for(unsigned frame=0;frame<Frames;frame++) {
                // Continuous closed camera sweep; last input exactly repeats first.
                double phase=frame==Frames-1?0:6.283185307179586*frame/(Frames-1);
                double yaw=.14*std::sin(phase);
                Camera camera={{18*std::sin(phase),3*std::sin(2*phase),-8*std::cos(phase)},
                    {std::cos(yaw),0,-std::sin(yaw)},{std::sin(yaw),0,std::cos(yaw)}};
                V box={35*std::sin(phase),10,130};
                for(UINT y=0;y<Height;y++) for(UINT x=0;x<Width;x++) {
                    V viewRay={(2*(x+.5)/Width-1)/ProjectionX,(1-2*(y+.5)/Height)/ProjectionY,1};
                    double z=Scene(scene,camera.origin,camera.WorldVector(viewRay),box);
                    depthValues[y*Width+x]=static_cast<float>(.1/z);
                    if(reconstruction) {
                        V normal={};
                        if(z<Infinity*.5) {
                            V p=camera.origin+camera.WorldVector(viewRay)*z;
                            if(scene==1 || scene==3) {
                                normal=Unit(p-SphereCenter);
                                if(scene==3) {
                                    double u=std::atan2(normal.x,-normal.z)/2.2+.5;
                                    double v=std::asin((std::clamp)(normal.y,-1.0,1.0))/1.8+.5;
                                    normal=Unit(normal+V{.18*std::sin(u*45),.18*std::cos(v*39),0});
                                }
                            } else {
                                normal=Unit({.35,-.18,-1});
                                if(scene==2 && std::fabs(Box(camera.origin,camera.WorldVector(viewRay),box)-z)<1e-5) {
                                    V d=p-box;
                                    double dx=std::fabs(std::fabs(d.x)-8),dy=std::fabs(std::fabs(d.y)-10),dz=std::fabs(std::fabs(d.z)-8);
                                    normal=dx<=dy&&dx<=dz?V{std::copysign(1.0,d.x),0,0}:dy<=dz?V{0,std::copysign(1.0,d.y),0}:V{0,0,std::copysign(1.0,d.z)};
                                }
                            }
                            normal=camera.ViewVector(normal);
                            if(scene==3) normal=QuantizeNormal(normal);
                        }
                        normalValues[y*Width+x]=Float4(normal);
                    }
                }
                context->UpdateSubresource(depth.Get(),0,nullptr,depthValues.data(),Width*4,0);
                if(reconstruction) context->UpdateSubresource(normals.Get(),0,nullptr,normalValues.data(),Width*sizeof(ContactFloat4),0);
                std::array<V,Count> worldPoints={},worldNormals={};
                for(UINT i=0;i<Count;i++) {
                    double u=(i%32+.5)/32,v=(i/32+.5)/16;
                    V p,n;
                    if(scene==1 || scene==3) {
                        double azimuth=(u-.5)*2.2,elevation=(v-.5)*1.8;
                        n={std::sin(azimuth)*std::cos(elevation),std::sin(elevation),-std::cos(azimuth)*std::cos(elevation)};
                        p=SphereCenter+n*Radius;
                    } else {p={(u-.5)*65,(v-.5)*45,0};p.z=160+.35*p.x-.18*p.y;n=Unit({.35,-.18,-1});}
                    V geomNormal=n;
                    if(scene==3) n=Unit(n+V{.18*std::sin(u*45),.18*std::cos(v*39),0});
                    V vp=camera.ViewPoint(p),vn=camera.ViewVector(n),direction=Unit(Light-p);
                    if(scene==3) vn=QuantizeNormal(vn);
                    worldPoints[i]=p;worldNormals[i]=n;
                    double uScreen=vp.x/vp.z*ProjectionX*.5+.5,vScreen=.5-vp.y/vp.z*ProjectionY*.5;
                    bool visible=vp.z>1 && uScreen>2.0/Width && uScreen<1-2.0/Width && vScreen>2.0/Height && vScreen<1-2.0/Height &&
                        std::fabs(Scene(scene,camera.origin,p-camera.origin,box)-1)<1e-5;
                    active[i]=visible && Dot(geomNormal,direction)>.05 && Dot(n,direction)>.05;
                    samples[i]={Float4(vp,active[i]?1.f:0.f),Float4(vn)};
                    double hit=Scene(scene,p+direction*.001,direction,box);
                    double maxDistance=(std::min)(100.0,Length(Light-p)-26.25);
                    expected[i]=hit<maxDistance;
                    eligible[i]=0;
                    if(expected[i]) {
                        V hitPoint=p+direction*hit,hp=camera.ViewPoint(hitPoint);
                        double hu=hp.x/hp.z*ProjectionX*.5+.5,hv=.5-hp.y/hp.z*ProjectionY*.5;
                        // Separately report all world hits. Strict blocker coverage
                        // only concerns visible, non-immediate, short-range hits.
                        eligible[i]=hit>12 && hit<70 && hp.z>0 && hu>.01 && hu<.99 && hv>.01 && hv<.99 &&
                            std::fabs(Scene(scene,camera.origin,hitPoint-camera.origin,box)-1)<.002;
                    }
                }
                context->UpdateSubresource(receivers.Get(),0,nullptr,samples.data(),0,0);
                // Endpoint repeats ALL inputs, including stochastic phase;
                // otherwise the deterministic repeat check would be invalid.
                UINT noiseFrame=animatedNoise && frame!=Frames-1?frame:0;
                ContactFloat4 params[4]={{static_cast<float>(Width),static_cast<float>(Height),static_cast<float>(ProjectionX),static_cast<float>(ProjectionY)},
                    Float4(camera.ViewPoint(Light),1.f/150),{.1f,10,static_cast<float>(Count),1},
                    {ContactBits(noiseFrame),ContactBits(reconstruction),0,0}};
                context->UpdateSubresource(constants.Get(),0,nullptr,params,0,0);
                ID3D11UnorderedAccessView* target=uav.Get();context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                const float sentinel[]={-1000,-1000,-1000,-1000};context->ClearUnorderedAccessViewFloat(uav.Get(),sentinel);
                context->Dispatch(Count/64,1,1);target=nullptr;context->CSSetUnorderedAccessViews(0,1,&target,nullptr);
                context->CopyResource(readback.Get(),result.Get());D3D11_MAPPED_SUBRESOURCE mapped={};
                Check(context->Map(readback.Get(),0,D3D11_MAP_READ,0,&mapped),"Read motion frame");
                const float* values=static_cast<const float*>(mapped.pData);
                unsigned activeCount=0,falseHits=0,blockers=0,misses=0,changes=0;float repeatDifference=0;
                for(UINT i=0;i<Count;i++) {
                    float value=values[i];invalid+=!std::isfinite(value)||value<0||value>1;
                    if(active[i]) {
                        ++activeCount;
                        falseHits+=!expected[i] && value<.999f;
                        blockers+=eligible[i]!=0;misses+=eligible[i] && value>=.5f;
                        changes+=frame>0 && previousActive[i] && expected[i]==previousExpected[i] && std::fabs(value-previousVisibility[i])>.5f;
                    }
                    if(frame==0) firstVisibility[i]=value;
                    if(frame==Frames-1) repeatDifference=(std::max)(repeatDifference,std::fabs(value-firstVisibility[i]));
                    V p=worldPoints[i],n=worldNormals[i];
                    csv<<scene<<','<<frame<<','<<i<<','<<active[i]<<','<<expected[i]<<','<<eligible[i]<<','<<value<<','<<p.x<<','<<p.y<<','<<p.z<<','<<n.x<<','<<n.y<<','<<n.z<<'\n';
                    previousVisibility[i]=value;previousActive[i]=active[i];previousExpected[i]=expected[i];
                }
                readbacks.write(static_cast<const char*>(mapped.pData),Count*4);context->Unmap(readback.Get(),0);
                frames<<scene<<','<<frame<<','<<activeCount<<','<<falseHits<<','<<blockers<<','<<misses<<','<<changes<<','<<repeatDifference<<'\n';
                invalid+=repeatDifference>1e-5f;
                sceneActive+=activeCount;sceneFalse+=falseHits;sceneMiss+=misses;sceneTransitions+=changes;sceneBlockers+=blockers;
            }
            std::printf("%s: frames=%u active=%u falseHits=%u eligibleVisibleBlockers=%u missed=%u stableTruthLargeChanges=%u\n",
                names[scene],Frames,sceneActive,sceneFalse,sceneBlockers,sceneMiss,sceneTransitions);std::fflush(stdout);
            totalFalse+=sceneFalse;totalMiss+=sceneMiss;totalTransitions+=sceneTransitions;
        }
        std::printf("Motion audit: invalid=%u falseHits=%u missedVisible=%u stableTruthLargeChanges=%u. Synthetic geometry only, no engine history.\n",invalid,totalFalse,totalMiss,totalTransitions);
        if(!csv || !frames || !readbacks) throw std::runtime_error("Result write failed");
        return invalid?2:(totalFalse||totalMiss||totalTransitions?1:0);
    } catch(const std::exception& e) {std::fprintf(stderr,"%s\n",e.what());return 2;}
}
