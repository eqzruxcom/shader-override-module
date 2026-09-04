// Execute the production adapter against real, synthetic D3D resources.
#define main Redx11AdapterUnderTest
#include "../Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl"
#undef main
cbuffer TestInput : register(b7) { float4 PixelAndLight; };
RWStructuredBuffer<float> TestResults : register(u0);
[numthreads(1,1,1)]
void main() { TestResults[0] = Redx11AdapterUnderTest(PixelAndLight.xyz); }
