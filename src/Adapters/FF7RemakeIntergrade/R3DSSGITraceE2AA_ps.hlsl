/*
 * FF7 Remake Intergrade adapter for the altered R3D horizon SSGI core.
 *
 * Donor: https://github.com/Bigfoot71/r3d
 * Commit: 3cb964171a0b90f1d0ec97e061b25021648eec65
 * License: Zlib (licenses/R3D-Zlib.txt)
 *
 * This adapter deliberately reuses e2aa1c8cb39e0a55's native b0 world-position
 * reconstruction. It is an offline candidate; the neighbor-ray mapping and
 * custom-pass formats still require a live capture before runtime promotion.
 */

Texture2D<float4> Agent2SceneRadiance : register(t110);
Texture2D<float4> Agent2WorldNormal : register(t111);
Texture2D<float> Agent2SceneDepth : register(t112);
SamplerState Agent2LinearClamp : register(s0);

cbuffer RemakeView : register(b0)
{
    float4 RemakeViewData[154];
};

struct FullscreenInput
{
    float4 uvAndRay : TEXCOORD0;
    float4 position : SV_Position;
};

static const float AGENT2_PI = 3.14159265358979323846;
static const float AGENT2_TAU = 6.28318530717958647692;
static const uint AGENT2_SLICE_COUNT = 4;
static const uint AGENT2_MAX_STEPS = 16;
static const float AGENT2_EDGE_FADE = 0.10;
static const float AGENT2_DISTANCE_FALLOFF = 1.0;
static const float AGENT2_NORMAL_REJECTION = 0.0;
static const float AGENT2_DEPTH_CLEAR_EPSILON = 0.0000001;
// UE4 reconstructs world positions in centimeters; R3D's distance-domain
// defaults are preserved in meters.
static const float AGENT2_UNREAL_UNITS_TO_METERS = 0.01;

float Agent2HashIGN(float2 pixel)
{
    return frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
}

float Agent2DeviceW(float rawDepth)
{
    float linearTerm = rawDepth * RemakeViewData[57].x + RemakeViewData[57].y;
    float reciprocalTerm = rawDepth * RemakeViewData[57].z - RemakeViewData[57].w;
    return linearTerm + rcp(reciprocalTerm);
}

float2 Agent2RayAtUV(float2 centerUV, float2 centerRay, float2 sampleUV)
{
    // The active 1bf99472af1427ba VS writes clip XY to TEXCOORD0.zw.
    // Clip XY varies linearly with UV; D3D screen Y has the opposite sign.
    return centerRay + (sampleUV - centerUV) * float2(2.0, -2.0);
}

float3 Agent2WorldPosition(float2 screenRay, float rawDepth)
{
    float deviceW = Agent2DeviceW(rawDepth);
    float2 screenXY = screenRay * deviceW;
    float4 world = RemakeViewData[40] * screenXY.x;
    world += RemakeViewData[41] * screenXY.y;
    world += RemakeViewData[42] * deviceW;
    world += RemakeViewData[43];
    return world.xyz / world.w;
}

float3 Agent2DecodeNormal(float2 uv)
{
    return normalize(Agent2WorldNormal.SampleLevel(Agent2LinearClamp, uv, 0).xyz * 2.0 - 1.0);
}

float Agent2LoadCenterDepth(float2 uv)
{
    uint width;
    uint height;
    Agent2SceneDepth.GetDimensions(width, height);
    int2 coord = clamp(int2(uv * float2(width, height)), int2(0, 0), int2(width - 1, height - 1));
    return Agent2SceneDepth.Load(int3(coord, 0));
}

float Agent2HorizonContribution(float normalDotEye, float normalDotTangent, float h0, float h1)
{
    return 0.25 * normalDotEye * (cos(2.0 * h0) - cos(2.0 * h1))
         + 0.25 * normalDotTangent * (2.0 * (h1 - h0) - sin(2.0 * h1) + sin(2.0 * h0));
}

float3 Agent2CompressRadiance(float3 color)
{
    return color / (1.0 + max(color.x, max(color.y, color.z)));
}

float4 main(FullscreenInput input) : SV_Target0
{
    uint width;
    uint height;
    Agent2SceneRadiance.GetDimensions(width, height);
    float2 viewport = float2(width, height);
    float2 invViewport = rcp(viewport);

    // Match R3D's texelFetch for receiver depth. Neighbor trace samples remain
    // linearly filtered, as in the donor's UV-based sampling path.
    float centerDepth = Agent2LoadCenterDepth(input.uvAndRay.xy);
    // Captured resource 00236552 is explicitly cleared to 0.0 (reversed Z).
    if (centerDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return 0.0;

    float3 centerPosition = Agent2WorldPosition(input.uvAndRay.zw, centerDepth);
    float3 centerNormal = Agent2DecodeNormal(input.uvAndRay.xy);
    float3 eyeDirection = normalize(RemakeViewData[59].xyz - centerPosition);
    float normalDotEye = dot(centerNormal, eyeDirection);

    float jitter = Agent2HashIGN(input.position.xy);
    float angleOffset = AGENT2_TAU * jitter;
    float sliceStep = AGENT2_TAU / float(AGENT2_SLICE_COUNT);
    float sliceWeight = 2.0 / float(AGENT2_SLICE_COUNT);
    float startStep = max(1.0, viewport.x / 1000.0);
    float stepGrowth = sliceStep + 1.0;
    float pixelDistanceBase = startStep * pow(stepGrowth, jitter);
    float pixelDistanceOffset = 1.0 - startStep;
    float3 accumulatedGI = 0.0;

    [loop]
    for (uint slice = 0; slice < AGENT2_SLICE_COUNT; ++slice)
    {
        float sineAngle;
        float cosineAngle;
        sincos(angleOffset + sliceStep * float(slice), sineAngle, cosineAngle);
        float2 sliceDirection = float2(cosineAngle, sineAngle);

        float2 tangentUV = input.uvAndRay.xy + sliceDirection * invViewport * 0.1;
        float2 tangentRay = Agent2RayAtUV(input.uvAndRay.xy, input.uvAndRay.zw, tangentUV);
        float3 tangentPosition = Agent2WorldPosition(tangentRay, centerDepth);
        float3 tangent = normalize(normalize(tangentPosition - RemakeViewData[59].xyz) + eyeDirection);
        float normalDotTangent = dot(centerNormal, tangent);
        float horizonAngle = atan2(normalDotEye, -normalDotTangent);
        float3 sliceGI = 0.0;
        float distanceMultiplier = 1.0;

        [loop]
        for (uint step = 0; step < AGENT2_MAX_STEPS; ++step)
        {
            float pixelDistance = pixelDistanceBase * distanceMultiplier + pixelDistanceOffset;
            distanceMultiplier *= stepGrowth;
            float2 sampleUV = input.uvAndRay.xy + sliceDirection * pixelDistance * invViewport;
            if (any(sampleUV <= 0.0) || any(sampleUV >= 1.0))
                break;

            float sampleDepth = Agent2SceneDepth.SampleLevel(Agent2LinearClamp, sampleUV, 0);
            if (sampleDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
                continue;

            float2 sampleRay = Agent2RayAtUV(input.uvAndRay.xy, input.uvAndRay.zw, sampleUV);
            float3 samplePosition = Agent2WorldPosition(sampleRay, sampleDepth);
            float3 sampleNormal = Agent2DecodeNormal(sampleUV);
            float3 delta = samplePosition - centerPosition;
            float3 deltaMeters = delta * AGENT2_UNREAL_UNITS_TO_METERS;

            if (abs(dot(deltaMeters, centerNormal)) < 0.03 && dot(sampleNormal, centerNormal) > 0.95)
                continue;

            float sampleAngle = atan2(dot(tangent, delta), dot(eyeDirection, delta));
            if (sampleAngle >= horizonAngle)
                continue;

            float contribution = max(0.0, Agent2HorizonContribution(
                normalDotEye, normalDotTangent, sampleAngle, horizonAngle));
            float2 edgeDistance = min(sampleUV, 1.0 - sampleUV);
            float edgeFade = smoothstep(0.0, AGENT2_EDGE_FADE, min(edgeDistance.x, edgeDistance.y));
            float distanceSquaredMeters = max(dot(deltaMeters, deltaMeters), 1e-8);
            float distanceFade = rcp(1.0 + distanceSquaredMeters * AGENT2_DISTANCE_FALLOFF);
            float facing = -dot(sampleNormal, deltaMeters * rsqrt(distanceSquaredMeters));
            float normalFade = lerp(1.0, smoothstep(0.0, 0.1, facing), AGENT2_NORMAL_REJECTION);
            float3 radiance = max(0.0, Agent2SceneRadiance.SampleLevel(Agent2LinearClamp, sampleUV, 0).rgb);

            sliceGI += radiance * contribution * edgeFade * distanceFade * normalFade;
            horizonAngle = sampleAngle;
        }

        accumulatedGI += sliceGI * sliceWeight;
    }

    return float4(Agent2CompressRadiance(max(0.0, accumulatedGI)), 1.0);
}
