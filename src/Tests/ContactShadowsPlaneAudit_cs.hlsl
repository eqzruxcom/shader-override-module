// Diagnostic only: a single infinite plane, no separate occluder. Every ray
// points into the plane's lit hemisphere and therefore should remain visible.
// This executes the unchanged production tracer, not a copied CPU algorithm.
// Constant fixture matrices make finite guards redundant; production unchanged.
#pragma warning(disable : 3577)
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
#else
#include "../Effects/Lighting/ContactShadows.hlsl"
#endif
RWStructuredBuffer<float4> Results : register(u0);
// Runtime parameters keep the audit on FXC's parameterized camera path.
cbuffer AuditCameraConstants : register(b13) { float4 AuditCamera; };
static float PlaneSlope;
static float ReceiverDepth;
static bool QuantizedDepth;
static bool HasBlocker;
static float3 BlockerCenter;
static float2 PlaneAxis;
static float2 ProjectionScale;
static float2 ProjectionShift;

bool AuditSlab(float direction, float lower, float upper, inout float nearZ, inout float farZ)
{
    if (abs(direction)<1.0e-8f) return lower<=0 && upper>=0;
    float a=lower/direction, b=upper/direction;
    nearZ=max(nearZ,min(a,b));farZ=min(farZ,max(a,b));
    return farZ>=nearZ;
}

float Redx11ContactSampleDeviceDepth(float2 uv)
{
    if (QuantizedDepth) uv=(floor(uv*float2(3840,2160))+.5f)/float2(3840,2160);
    float2 ndc=(uv*float2(2,-2)+float2(-1,1)-ProjectionShift)/ProjectionScale;
    // Plane z = receiverDepth + slope*x; perspective x = z*ndcX.
    float z=ReceiverDepth/(1-PlaneSlope*dot(PlaneAxis,ndc));
    if (HasBlocker)
    {
        // Exact camera-ray/AABB slab intersection; the box is centered on
        // the light ray, 40 world units away from the receiver.
        float3 cameraRay=float3(ndc,1);
        float nearZ=0,farZ=1.0e20f;
        bool hit=AuditSlab(cameraRay.x,BlockerCenter.x-8,BlockerCenter.x+8,nearZ,farZ);
        hit=AuditSlab(cameraRay.y,BlockerCenter.y-8,BlockerCenter.y+8,nearZ,farZ) && hit;
        hit=AuditSlab(cameraRay.z,BlockerCenter.z-8,BlockerCenter.z+8,nearZ,farZ) && hit;
        if (hit && nearZ>0) z=min(z,nearZ);
    }
    // No forward plane intersection: finite far background, beyond all rays.
    // Avoid a compile-time zero-device-depth reciprocal in this constant fixture.
    return AuditCamera.z/(z>0 ? z : 1.0e20f);
}

[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint test=id.x;
    if(test>=20480) return;
    uint orientation=(test/640)%8;
    uint phase=test/5120;
    float theta=orientation*0.78539816339f;
    PlaneAxis=float2(cos(theta),sin(theta));
    ProjectionScale=AuditCamera.xy;
    float pixelPhase=-.4f+phase*.29f;
    ProjectionShift=float2(2*pixelPhase/3840,-2*pixelPhase/2160);
    HasBlocker=(test%640)>=320;
    test=test%320;
    uint slopeCase=test%8;
    uint angleCase=(test/8)%10;
    QuantizedDepth=test>=160;
    ReceiverDepth=((test/80)%2)==0 ? 100.0f : 1000.0f;
    PlaneSlope=-1.5f + slopeCase*.5f;
    float gap=.01f+angleCase*.1f;
    float3 normal=normalize(float3(PlaneSlope*PlaneAxis,-1));
    float3 direction=normalize(float3(PlaneAxis,PlaneSlope-gap));
    BlockerCenter=float3(0,0,ReceiverDepth)+direction*40;
    Redx11ContactView v;
    v.translatedWorldToClip=float4x4(ProjectionScale.x,0,0,0, 0,ProjectionScale.y,0,0, ProjectionShift,0,1, 0,0,AuditCamera.z,0);
    v.invDeviceZToWorldZ=float4(0,0,AuditCamera.w,0);
    v.bufferSize=float2(3840,2160);v.invBufferSize=1/v.bufferSize;
    v.projectionScale=ProjectionScale;v.perspective=1;
    v.ndcToBufferScale=float2(.5f,-.5f);v.ndcToBufferBias=.5f;
    v.viewportUVBounds=float4(0,0,1,1);
    v.screenLinearToWorld=float4x4(1/ProjectionScale.x,0,0,0, 0,1/ProjectionScale.y,0,0, -ProjectionShift/ProjectionScale,1,0, 0,0,0,1);
    v.worldToTranslatedWorld=0;v.pointSampledDepth=QuantizedDepth?1:0;
    Redx11ContactSettings s=Redx11ContactDonorSettings();
    float visibility=Redx11TraceLocalContactShadow(float3(0,0,ReceiverDepth),normal,
        direction,10000,1,.5f,v,s);
    Results[id.x]=float4(visibility,PlaneSlope,gap,dot(normal,direction));
}
