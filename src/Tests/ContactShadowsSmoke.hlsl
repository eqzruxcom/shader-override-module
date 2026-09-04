#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
#else
#include "../Effects/Lighting/ContactShadows.hlsl"
#endif

Texture2D<float> TestDepth : register(t0);
SamplerState TestPointClamp : register(s0);
cbuffer TestParameters : register(b0)
{
    Redx11ContactView TestView;
    Redx11ContactSettings TestSettings;
    float4 TestWorldPositionAndLightDistance;
    float4 TestLightDirectionAndInverseRadius;
    float4 TestNormalAndJitter;
};

float Redx11ContactSampleDeviceDepth(float2 uv)
{
    return TestDepth.SampleLevel(TestPointClamp, uv, 0.0f);
}

float CalculateTestVisibility()
{
    return Redx11TraceLocalContactShadow(
        TestWorldPositionAndLightDistance.xyz, TestNormalAndJitter.xyz,
        TestLightDirectionAndInverseRadius.xyz, TestWorldPositionAndLightDistance.w,
        TestLightDirectionAndInverseRadius.w, TestNormalAndJitter.w, TestView, TestSettings);
}

float4 mainPS(float4 position : SV_Position) : SV_Target0
{
    return CalculateTestVisibility().xxxx;
}

RWStructuredBuffer<float> TestOutput : register(u0);
[numthreads(1, 1, 1)]
void mainCS(uint3 tid : SV_DispatchThreadID)
{
    TestOutput[tid.x] = CalculateTestVisibility();
}
