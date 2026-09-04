// Same full-ray fixture compiled against the preserved port and refinement.
// Analytic scene depth, NOT a recreation of FF7's renderer or the user video.
#pragma warning(disable : 3577)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
#ifndef EXPECT_VIEWPORT_REFINEMENT
#define EXPECT_VIEWPORT_REFINEMENT 0
#endif
RWStructuredBuffer<float4> Results : register(u0);
static uint FixtureCase;
static bool PerspectiveFixture;
static float4 FixtureBounds;
static uint OutsideSamples;

float Redx11ContactSampleDeviceDepth(float2 uv)
{
    if (any(uv < FixtureBounds.xy - 1e-7f) || any(uv > FixtureBounds.zw + 1e-7f))
        OutsideSamples++;
    // Match the adapter's clamped fetch: an invalid pre-clamp coordinate is
    // still counted, even though a border texel could supply valid depth.
    float sceneDepth = (FixtureCase == 1 || FixtureCase == 3) ? 15.0f : 8.0f;
    return PerspectiveFixture ? .1f / sceneDepth : sceneDepth / 100.0f;
}

float2 RotateEdge(float2 xy, uint edge)
{
    if (edge == 1) return float2(-xy.y, xy.x);
    if (edge == 2) return -xy;
    if (edge == 3) return float2(xy.y, -xy.x);
    return xy;
}

[numthreads(64,1,1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= 128) return;
    uint c = tid.x % 8;
    uint edge = (tid.x / 8) % 4;
    bool subview = ((tid.x / 32) % 2) != 0;
    bool perspective = tid.x >= 64;
    FixtureCase = c;
    PerspectiveFixture = perspective;
    OutsideSamples = 0;
    Redx11ContactView v;
    v.translatedWorldToClip = perspective
        ? float4x4(1,0,0,0, 0,1,0,0, 0,0,0,1, 0,0,.1f,0)
        : float4x4(.1f,0,0,0, 0,.1f,0,0, 0,0,.01f,0, 0,0,0,1);
    v.invDeviceZToWorldZ = perspective ? float4(0,0,10,0) : float4(100,-1,0,-1);
    v.bufferSize = float2(1024,1024);
    v.invBufferSize = 1.0f / v.bufferSize;
    v.projectionScale = float2(1,1);
    v.perspective = perspective ? 1.0f : 0.0f;
    v.ndcToBufferScale = subview ? float2(.2f,-.3f) : float2(.5f,-.5f);
    v.ndcToBufferBias = subview ? float2(.4f,.5f) : float2(.5f,.5f);
    v.viewportUVBounds = subview ? float4(.2f,.2f,.6f,.8f) : float4(0,0,1,1);
    FixtureBounds = v.viewportUVBounds;
    v.screenLinearToWorld = float4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1);
    v.worldToTranslatedWorld = 0;
    v.pointSampledDepth = 0;
    Redx11ContactSettings s = Redx11ContactDonorSettings();
    s.rayLength = .5f;
    s.lightExclusionFraction = 0;
    s.minimumThickness = 3;
    s.maximumThickness = 3;
    s.pixelThicknessScale = 0;
    float3 p = float3(9.998f,0,10);
    float3 n = float3(1,0,0);
    float3 direction = float3(-.25f,sqrt(.9375f),0);
    if (c == 2 || c == 3) p.x = 9; // Interior hit / clear controls.
    if (c == 4) direction = float3(1,0,0); // Entire biased ray outside.
    if (c == 5) p.x = 10.002f; // Receiver itself outside: remain neutral.
    if (c == 6) s.rayLength = 0;
    if (c == 7) { p.x = 9.7f; direction = float3(1,0,0); } // Valid exiting ray.
    p.xy = RotateEdge(p.xy,edge);
    n.xy = RotateEdge(n.xy,edge);
    direction.xy = RotateEdge(direction.xy,edge);
    float visibility = Redx11TraceRebirthContactShadow(p,n,direction,100,1,.5f,0,1.5f,v,s);
    bool expectHit = c == 0 || c == 2 || c == 7;
    // Reproduce the baseline failure, do not silently bless it as correct.
    // In a subviewport the old code instead samples outside the view because
    // it only checks the full allocation [0,1]. Check that independently.
    if (!EXPECT_VIEWPORT_REFINEMENT && c == 0 && !subview) expectHit = false;
    Results[tid.x*2] = float4(visibility,expectHit?0.0f:1.0f,expectHit?.01f:1e-6f,1);
    bool expectOutside = !EXPECT_VIEWPORT_REFINEMENT && subview && (c == 0 || c == 1);
    Results[tid.x*2+1] = float4(OutsideSamples>0?1.0f:0.0f,expectOutside?1.0f:0.0f,0,1);
}
