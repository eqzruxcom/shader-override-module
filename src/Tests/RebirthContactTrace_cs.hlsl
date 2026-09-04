// Offline-only logger. TraceIncludes inserts one observer call into the donor
// in memory; the checked-in donor and all its arithmetic remain unchanged.
RWStructuredBuffer<float4> TraceResults : register(u1);
static uint TraceReceiver;
static uint TraceCalls;
void Redx11ObserveContact(uint index,float2 uv,float sampleT,float segmentEndT,
    float depth0,float depth1,float sceneDepth,float thickness,float bias,bool hit,
    float minimumT,float3 origin,float3 direction,float length,float3 normal,
    float random,float2 uvStart,float2 uvEnd,float3 receiver,float distance)
{
    uint base=TraceReceiver*54u;
    TraceResults[base+1u]=float4(origin,length);
    TraceResults[base+2u]=float4(direction,minimumT);
    TraceResults[base+3u]=float4(normal,random);
    TraceResults[base+4u]=float4(uvStart,uvEnd);
    TraceResults[base+5u]=float4(receiver,distance);
    uint row=base+6u+index*3u;
    TraceResults[row]=float4(uv,sceneDepth,sampleT);
    TraceResults[row+1u]=float4(depth0,depth1,thickness,bias);
    TraceResults[row+2u]=float4((float)index,hit?1.0f:0.0f,minimumT,segmentEndT);
    ++TraceCalls;
}
#define main Redx11MotionUnchangedEntry
#include "RebirthContactMotion_cs.hlsl"
#undef main
[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if(id.x >= (uint)MotionParameters.z) return;
    TraceReceiver=id.x;
    TraceCalls=0;
    // Explicit per-record initialization: skipped observer slots must not
    // retain allocation contents or a previous frame's sample metadata.
    [unroll] for(uint row=0;row<54u;++row)
        TraceResults[id.x*54u+row]=float4(-1000,-1000,-1000,-1000);
    Redx11MotionUnchangedEntry(id);
    TraceResults[id.x*54u]=float4(MotionResults[id.x],(float)TraceCalls,0,0);
}
