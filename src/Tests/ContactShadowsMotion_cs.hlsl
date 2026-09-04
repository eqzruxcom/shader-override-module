// Synthetic continuous-motion fixture. Not FF7 animation or temporal replay.
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
#include "../ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl"
#else
#include "../Effects/Lighting/ContactShadows.hlsl"
#endif
Texture2D<float> MotionDepth : register(t0);
struct MotionReceiver { float4 positionActive; float4 normal; };
StructuredBuffer<MotionReceiver> MotionReceivers : register(t1);
Texture2D<float4> MotionNormals : register(t2);
RWStructuredBuffer<float> MotionResults : register(u0);
cbuffer MotionCamera : register(b13)
{
    float4 MotionDimensions; // width, height, projection x/y
    float4 MotionLight; // camera-space xyz, inverse radius
    float4 MotionParameters; // near, inv near, receiver count, enabled
    uint4 MotionNoise; // x: view-frame bits; y: 0 tracked raw, 1 pixel raw, 2 quad
};
float Redx11ContactSampleDeviceDepth(float2 uv)
{
    int2 pixel=clamp((int2)floor(uv*MotionDimensions.xy),0,(int2)MotionDimensions.xy-1);
    return MotionDepth.Load(int3(pixel,0));
}
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
float Redx11MotionPixelRay(int2 pixel,Redx11ContactView view)
{
    if(any(pixel<0)||any(pixel>=(int2)view.bufferSize)) return 1;
    float device=MotionDepth.Load(int3(pixel,0));
    float depth=Redx11ContactLinearDepth(device,view.invDeviceZToWorldZ);
    float3 normal=MotionNormals.Load(int3(pixel,0)).xyz;
    if(!isfinite(depth)||depth<=0||depth>=1000000||dot(normal,normal)<1e-8) return 1;
    float2 ndc=((float2)pixel+.5f)/view.bufferSize*float2(2,-2)+float2(-1,1);
    float3 position=float3(ndc/view.projectionScale,1)*depth;
    float3 toLight=MotionLight.xyz-position;
    float distance=length(toLight);
    if(distance<=1e-8) return 1;
    float jitter=InterleavedGradientNoise((float2)pixel+.5f,(int)MotionNoise.x);
    return Redx11TraceRebirthContactShadow(position,normalize(normal),toLight/distance,
        distance,MotionLight.w,jitter,0u,1.5f,view,Redx11ContactDonorSettings());
}
#endif
[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if(id.x >= (uint)MotionParameters.z) return;
    MotionReceiver r=MotionReceivers[id.x];
    if(r.positionActive.w==0 || MotionParameters.w==0) {MotionResults[id.x]=1;return;}
    Redx11ContactView v;
    float2 projection=MotionDimensions.zw;
    v.translatedWorldToClip=float4x4(projection.x,0,0,0, 0,projection.y,0,0, 0,0,0,1, 0,0,MotionParameters.x,0);
    v.screenLinearToWorld=float4x4(1/projection.x,0,0,0, 0,1/projection.y,0,0, 0,0,1,0, 0,0,0,1);
    v.invDeviceZToWorldZ=float4(0,0,MotionParameters.y,0);
    v.bufferSize=MotionDimensions.xy;v.invBufferSize=1/v.bufferSize;
    v.projectionScale=projection;v.perspective=1;
    v.ndcToBufferScale=float2(.5f,-.5f);v.ndcToBufferBias=.5f;
    v.viewportUVBounds=float4(0,0,1,1);v.worldToTranslatedWorld=0;v.pointSampledDepth=1;
    float3 toLight=MotionLight.xyz-r.positionActive.xyz;
    float distance=length(toLight);
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
    // Donor IGN with a host-supplied view-frame index. The host can freeze it
    // for a spatial-only comparison. No temporal resolve is implemented here.
    float4 receiverClip=mul(float4(r.positionActive.xyz,1),v.translatedWorldToClip);
    float2 receiverUV=receiverClip.xy/receiverClip.w*v.ndcToBufferScale+v.ndcToBufferBias;
    float2 pixelCenter=floor(receiverUV*v.bufferSize)+.5f;
    if(MotionNoise.y!=0)
    {
        int2 pixel=(int2)pixelCenter;
        float4 phase=float4((float)(MotionNoise.x&7u),0,0,0);
        bool selected=Redx11RebirthCheckerboard(pixel,phase);
        float result=1;
        if(MotionNoise.y==1||selected) result=Redx11MotionPixelRay(pixel,v);
        else
        {
            int2 basePixel=pixel&~1;
            float4 lanes=1;
            [unroll] for(int lane=0;lane<4;++lane)
            {
                int2 neighbor=basePixel+int2(lane&1,lane>>1);
                if(Redx11RebirthCheckerboard(neighbor,phase)) lanes[lane]=Redx11MotionPixelRay(neighbor,v);
            }
            result=Redx11RebirthQuadAverage(lanes);
        }
        MotionResults[id.x]=result;
        return;
    }
    float jitter=InterleavedGradientNoise(pixelCenter,(int)MotionNoise.x);
    MotionResults[id.x]=Redx11TraceRebirthContactShadow(r.positionActive.xyz,normalize(r.normal.xyz),
        toLight/distance,distance,MotionLight.w,jitter,0u,1.5f,v,Redx11ContactDonorSettings());
#else
    MotionResults[id.x]=Redx11TraceLocalContactShadow(r.positionActive.xyz,normalize(r.normal.xyz),
        toLight/distance,distance,MotionLight.w,.5f,v,Redx11ContactDonorSettings());
#endif
}
