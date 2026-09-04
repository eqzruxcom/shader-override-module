// Offline compilation interface. The generator replaces b13 with an isolated
// native register (uint group pixel origin and captured uint light index), and
// the sole u7 store with a register move. Neither extra binding reaches runtime.
#include "RebirthContactShared.hlsl"
cbuffer ContactSharedInput : register(b13) { uint4 SharedInput; };
RWStructuredBuffer<float> SharedResult : register(u7);
[numthreads(16,16,1)]
void main(uint3 local : SV_GroupThreadID)
{
    uint2 pixel=SharedInput.xy+local.xy;
    SharedResult[local.y*16u+local.x]=Redx11RemakeSharedContact(pixel,local.xy,SharedInput.z);
}
