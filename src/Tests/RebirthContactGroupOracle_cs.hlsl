// Barrier-free recomputation reference for the exact native shared block.
#define main Redx11ReconstructedUnderTest
#include "../Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl"
#undef main
cbuffer TestInput : register(b7) { float4 PixelAndLight; };
RWStructuredBuffer<float> TestResults : register(u0);
#ifndef REDX11_GROUP_ITERATIONS
#define REDX11_GROUP_ITERATIONS 1
#endif
#if REDX11_GROUP_ITERATIONS > 1
// Host-decoded native indices, independently uploaded without the float
// denormal folding caused by asfloat((index+phase)&255) in this wrapper.
cbuffer ReferenceIndices : register(b8) { uint4 TestLightIndices; };
#endif
[numthreads(16,16,1)]
void main(uint3 local : SV_GroupThreadID, uint3 group : SV_GroupID)
{
    // Each light reference is an independent group. Only the assembly fixture
    // under test loops through lights in one group and reuses shared storage.
    uint iteration=group.z;
    float light=PixelAndLight.z;
#if REDX11_GROUP_ITERATIONS > 1
    light=asfloat(TestLightIndices[iteration&1u]);
#endif
    float3 input=float3(PixelAndLight.xy+(float2)local.xy,light);
    uint offset=(iteration*256u+local.y*16u+local.x)*6u;
    TestResults[offset]=Redx11ReconstructedUnderTest(input);
    int2 basePixel=(int2)input.xy&~1;
    [unroll] for(int lane=0;lane<4;++lane)
    {
        bool valid;
        TestResults[offset+1u+(uint)lane]=Redx11RemakeContactPixel(
            float3((float2)(basePixel+int2(lane&1,lane>>1)),input.z),true,valid);
    }
    bool centerValid;
    Redx11RemakeContactPixel(input,false,centerValid);
    TestResults[offset+5u]=centerValid?1.0f:0.0f;
}
