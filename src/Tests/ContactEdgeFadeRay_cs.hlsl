// Full donor tracing against analytic depth. NOT a reconstruction of FF7.
#pragma warning(disable : 3577)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
RWStructuredBuffer<float4> Results : register(u0);
static float BlockerU;
float Redx11ContactSampleDeviceDepth(float2 uv)
{
    return abs(uv.x-BlockerU)<.012f ? .08f : .15f;
}
[numthreads(64,1,1)]
void main(uint3 tid:SV_DispatchThreadID)
{
    if(tid.x>=5120) return;
    uint preset=tid.x%10, rayIndex=tid.x/10, profile=rayIndex/128, sampleIndex=rayIndex%128;
    float q=(float)sampleIndex/127.0f;
    float2 receiverUV;
    float3 direction;
    if(profile==0) {receiverUV=float2(.0001f+.12f*q,.5f);BlockerU=receiverUV.x+.025f;direction=float3(1,0,0);}
    else if(profile==1) {receiverUV=float2(.12f,.5f);BlockerU=-.015f+.165f*q;direction=float3(-1,0,0);}
    else if(profile==2) {receiverUV=float2(.6f,.0001f+.9998f*q);BlockerU=.625f;direction=float3(1,0,0);}
    else {receiverUV=float2(.88f+.1198f*q,.5f);BlockerU=receiverUV.x-.03f;direction=float3(-1,0,0);}
    Redx11ContactView v;
    v.translatedWorldToClip=float4x4(.1f,0,0,0, 0,.1f,0,0, 0,0,.01f,0, 0,0,0,1);
    v.invDeviceZToWorldZ=float4(100,-1,0,-1);
    v.bufferSize=float2(1280,720);v.invBufferSize=1.0f/v.bufferSize;
    v.projectionScale=1;v.perspective=0;
    v.ndcToBufferScale=float2(.5f,-.5f);v.ndcToBufferBias=.5f;
    v.viewportUVBounds=float4(0,0,1,1);
    v.screenLinearToWorld=float4x4(10,0,0,0, 0,10,0,0, 0,0,1,0, 0,0,0,1);
    v.worldToTranslatedWorld=0;v.pointSampledDepth=0;
    Redx11ContactSettings s=Redx11ContactDonorSettings();
    s.rayLength=3;s.lightExclusionFraction=0;s.normalBiasScale=0;
    s.minimumThickness=3;s.maximumThickness=3;s.pixelThicknessScale=0;
    float3 p=float3((receiverUV-float2(.5f,.5f))*float2(20,-20),10);
    #if EXPECT_EDGE_FADE
    Redx11RebirthEdgeFadeWidth=(float)preset*.01f;
    #endif
    float visibility=Redx11TraceRebirthContactShadow(p,float3(0,0,1),direction,100,1,.5f,0,1.5f,v,s);
    Results[tid.x]=float4(visibility,.5f,.500001f,1);
}
