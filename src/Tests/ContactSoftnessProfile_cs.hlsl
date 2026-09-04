// Analytic depth-edge profiles through the real donor ray, NOT game rendering.
#pragma warning(disable : 3577)
#include "../Effects/Lighting/RebirthContactSoftness.hlsl"
RWStructuredBuffer<float4> Results : register(u0);
static float BlockerX;
float Redx11ContactSampleDeviceDepth(float2 uv)
{
    float2 xy = (uv-float2(.5f,.5f))*float2(20,-20);
    bool blocker = xy.x >= BlockerX && xy.x <= BlockerX+.6f && xy.y >= 0;
    return blocker ? .08f : .15f;
}
[numthreads(64,1,1)]
void main(uint3 tid:SV_DispatchThreadID)
{
    if (tid.x>=512) return;
    uint profileIndex=tid.x%256;
    BlockerX=tid.x<256?1.0f:3.0f;
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
    s.rayLength=5;s.lightExclusionFraction=0;s.normalBiasScale=0;
    s.minimumThickness=3;s.maximumThickness=3;s.pixelThicknessScale=0;
    float3 p=float3(0,-.5f+(float)profileIndex/255.0f,10);
    float3 n=float3(0,0,1),d=float3(1,0,0);
    float hard=Redx11TraceRebirthContactShadow(p,n,d,100,1,.5f,0,1.5f,v,s);
    float zero=Redx11TraceRebirthSoftContact(p,n,d,100,1,.5f,0,1.5f,v,s,0);
    float soft=Redx11TraceRebirthSoftContact(p,n,d,100,1,.5f,0,1.5f,v,s,5);
    float repeat=Redx11TraceRebirthSoftContact(p,n,d,100,1,.5f,0,1.5f,v,s,5);
    Results[tid.x*4]=float4(hard,.5f,.500001f,1);
    Results[tid.x*4+1]=float4(soft,.5f,.500001f,1);
    Results[tid.x*4+2]=float4(zero-hard,0,0,1);
    Results[tid.x*4+3]=float4(repeat-soft,0,0,1);
}
