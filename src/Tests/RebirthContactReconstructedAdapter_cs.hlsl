#define main Redx11ReconstructedUnderTest
#include "../Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl"
#undef main
cbuffer TestInput : register(b7) { float4 PixelAndLight; };
RWStructuredBuffer<float> TestResults : register(u0);
[numthreads(1,1,1)]
void main()
{
    TestResults[0]=Redx11ReconstructedUnderTest(PixelAndLight.xyz);
    int2 basePixel=(int2)PixelAndLight.xy&~1;
    [unroll] for(int lane=0;lane<4;++lane)
    {
        bool valid;
        TestResults[1+lane]=Redx11RemakeContactPixel(
            float3((float2)(basePixel+int2(lane&1,lane>>1)),PixelAndLight.z),true,valid);
    }
    bool centerValid;
    Redx11RemakeContactPixel(PixelAndLight.xyz,false,centerValid);
    TestResults[5]=centerValid?1.0f:0.0f;
}
