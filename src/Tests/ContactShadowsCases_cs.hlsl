// Fixtures contain compile-time finite matrices. FXC warns about the library's
// intentionally redundant finite checks; keep them in production, silence only
// this constant-fixture warning here. The parameterized smoke builds use /WX.
#pragma warning(disable : 3577)
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
#else
#include "../Effects/Lighting/ContactShadows.hlsl"
#endif

RWStructuredBuffer<float> Results : register(u0);
static uint TestCase;

float Redx11ContactSampleDeviceDepth(float2 uv)
{
    float depth = 15.0f; // Behind the ray: no occluder.
    if (TestCase == 7 || TestCase == 15 || TestCase == 21 || TestCase == 24)
        depth = 8.0f;
    if (TestCase == 8) depth = 1.0f; // Too far in front for finite thickness.
    if (TestCase == 9) depth = 10.0f; // The receiver itself.
    if (TestCase == 10) return 0.0f; // Invalid/zero linear depth.
    if (TestCase == 22) return asfloat(0x7f800000); // Infinite sky depth.
    if (TestCase == 23) return asfloat(0x7fc00000); // Invalid sample.
    if (TestCase == 26 || TestCase == 28)
        depth = uv.x >= .6f && uv.x <= .64f ? 8.0f : 15.0f;
    if (TestCase == 27) depth = uv.x >= .9f ? 8.0f : 15.0f;
    if (TestCase == 29) depth = uv.x >= .72f && uv.x <= .73f ? 8.0f : 15.0f;
    if (TestCase == 30) depth = uv.y >= .36f && uv.y <= .4f ? 8.0f : 15.0f;
    if (TestCase == 31 || TestCase == 32) depth = 8.0f;
    if (TestCase == 33) depth = uv.x >= .72f && uv.x <= .74f ? 8.0f : 15.0f;
    if (TestCase == 16 || TestCase == 17)
        return 0.1f / 8.0f; // Reversed-Z perspective, n=0.1.
    if (TestCase == 18)
        return (1.0f - 0.1f / 8.0f) / 0.999f; // Regular-Z, n=.1, f=100.
    return depth / 100.0f;
}

Redx11ContactView FixtureView()
{
    Redx11ContactView v;
    v.translatedWorldToClip = float4x4(
        .1f, 0, 0, 0, 0, .1f, 0, 0, 0, 0, .01f, 0, 0, 0, 0, 1);
    v.invDeviceZToWorldZ = float4(100, -1, 0, -1); // Orthographic depth=100*z.
    v.bufferSize = float2(1024, 1024);
    v.invBufferSize = 1.0f / v.bufferSize;
    v.projectionScale = float2(1, 1);
    v.perspective = 1; // Individual thickness tests select the projection.
    v.ndcToBufferScale = float2(.5f, -.5f);
    v.ndcToBufferBias = float2(.5f, .5f);
    v.viewportUVBounds = float4(0, 0, 1, 1);
    v.screenLinearToWorld = float4x4(10,0,0,0, 0,10,0,0, 0,0,1,0, 0,0,0,1);
    v.worldToTranslatedWorld = 0;
    v.pointSampledDepth = 0;
    return v;
}

float RunCase(uint test)
{
    Redx11ContactView v = FixtureView();
    Redx11ContactSettings s = Redx11ContactDonorSettings();
    if (test == 0)
        return Redx11ContactPerspectiveDepth(.5f, float2(1, 1), float2(.1f, .05f));
    if (test == 1) return Redx11ContactThickness(10, .1f, v, s);
    if (test == 2) return Redx11ContactThickness(100, .1f, v, s);
    if (test == 3)
    {
        v.perspective = 0;
        return Redx11ContactThickness(100, .1f, v, s);
    }
    if (test == 4)
    {
        v.viewportUVBounds = float4(.25f, .25f, .75f, .75f);
        return Redx11ContactThickness(100, .1f, v, s);
    }
    if (test == 5)
    {
        float t = 1;
        Redx11ContactClipPlane(1, -3, t);
        return t;
    }
    s.rayLength = 5;
    s.lightExclusionFraction = 0;
    s.depthBiasScale = 1;
    s.normalBiasScale = 0;
    s.minimumThickness = 3;
    s.maximumThickness = 3;
    s.pixelThicknessScale = 0;
    s.receiverSkipSteps = .5f;
    s.grazingExtraSkipSteps = 1;
    v.perspective = 0;
    float3 p = float3(0, 0, 10);
    float3 direction = float3(1, 0, 0);
    float distance = 100;
    float inverseRadius = 1;
    float jitter = .5f;
    if (test == 11) s.rayLength = 0;
    if (test == 12) inverseRadius = 0;
    if (test == 13)
    {
        distance = 1;
        inverseRadius = .1f;
        s.lightExclusionFraction = .175f;
    }
    if (test == 14) p.x = 20; // Start outside the view.
    if (test == 15) p.x = 8; // End exits view: clipped ray still hits.
    if (test == 16 || test == 17 || test == 18)
    {
        v.perspective = 1;
        v.translatedWorldToClip = float4x4(
            1,0,0,0, 0,1,0,0, 0,0,0,1, 0,0,.1f,0);
        v.invDeviceZToWorldZ = float4(0,0,10,0);
        v.screenLinearToWorld = float4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1);
        if (test == 17) p.z = -10; // Behind the camera.
        if (test == 18)
        {
            v.translatedWorldToClip[2][2] = 1.0f / .999f;
            v.translatedWorldToClip[3][2] = -.1f / .999f;
            v.invDeviceZToWorldZ = float4(0,0,-9.99f,-10);
        }
    }
    if (test == 19) s.rayLength = .001f; // Sub-half-pixel projected ray.
    if (test == 20) v.viewportUVBounds.zw = 0;
    if (test == 21)
    {
        v.viewportUVBounds = float4(.25f,.25f,.75f,.75f);
        v.ndcToBufferScale *= .5f; // Offset subviewport inside allocation.
    }
    if (test == 24) jitter = 1.0f;
    if (test == 25) p.z = 110; // Beyond orthographic far clip.
    if (test == 28) distance = 1; // Occluder is beyond the light itself.
    if (test == 29)
    {
        v.viewportUVBounds = float4(.5f,.25f,.9f,.75f);
        v.ndcToBufferScale = float2(.2f,-.25f);
        v.ndcToBufferBias = float2(.7f,.5f);
    }
    if (test == 30) direction = float3(0,1,0);
    if (test == 31)
    {
        v.viewportUVBounds = float4(.25f,.25f,.75f,.75f);
        v.ndcToBufferBias.x = .95f; // Invalid mapping must not sample the border.
    }
    if (test == 32) s.receiverSkipSteps = REDX11_CONTACT_SAMPLES;
    return Redx11TraceLocalContactShadow(p, float3(0,0,1), direction,
        distance, inverseRadius, jitter, v, s);
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= 34) return;
    TestCase = tid.x;
    Results[tid.x] = RunCase(tid.x);
}
