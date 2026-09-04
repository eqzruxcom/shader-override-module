/*
 * Depth-aware additive composite for the offline Agent 2 R3D SSGI candidate.
 * R3D donor commit 3cb964171a0b90f1d0ec97e061b25021648eec65, Zlib.
 */

Texture2D<float4> Agent2FilteredSSGI : register(t110);
Texture2D<float4> Agent2CompositeNormal : register(t111);
Texture2D<float> Agent2CompositeDepth : register(t112);
Texture2D<float4> Agent2CompositeMaterial : register(t113);
Texture2D<float4> Agent2CompositeAlbedo : register(t114);

cbuffer RemakeView : register(b0)
{
    float4 RemakeViewData[154];
};

struct FullscreenInput
{
    float4 uvAndRay : TEXCOORD0;
    float4 position : SV_Position;
};

static const float AGENT2_UNREAL_UNITS_TO_METERS = 0.01;
static const float AGENT2_DEPTH_CLEAR_EPSILON = 0.0000001;
static const float AGENT2_UPSAMPLE_DEPTH_TOLERANCE_METERS = 0.05;
static const float AGENT2_UPSAMPLE_MIN_NORMAL_DOT_VIEW = 0.05;
static const float AGENT2_DIAGNOSTIC_STRENGTH = 1.25;
static const float AGENT2_INV_PI = 0.31830988618;

float Agent2CompositeDeviceW(float rawDepth)
{
    return rawDepth * RemakeViewData[57].x + RemakeViewData[57].y
         + rcp(rawDepth * RemakeViewData[57].z - RemakeViewData[57].w);
}

float2 Agent2CompositeRayAtUV(float2 centerUV, float2 centerRay, float2 sampleUV)
{
    return centerRay + (sampleUV - centerUV) * float2(2.0, -2.0);
}

float3 Agent2CompositeWorldPosition(float2 ray, float rawDepth)
{
    float deviceW = Agent2CompositeDeviceW(rawDepth);
    float2 screenXY = ray * deviceW;
    float4 world = RemakeViewData[40] * screenXY.x;
    world += RemakeViewData[41] * screenXY.y;
    world += RemakeViewData[42] * deviceW;
    world += RemakeViewData[43];
    return world.xyz / world.w;
}

int2 Agent2CompositeCoord(float2 uv, uint width, uint height)
{
    return clamp(int2(uv * float2(width, height)), int2(0, 0), int2(width - 1, height - 1));
}

float Agent2CompositeLoadDepth(float2 uv)
{
    uint width;
    uint height;
    Agent2CompositeDepth.GetDimensions(width, height);
    return Agent2CompositeDepth.Load(int3(Agent2CompositeCoord(uv, width, height), 0));
}

float3 Agent2CompositeLoadNormal(float2 uv)
{
    uint width;
    uint height;
    Agent2CompositeNormal.GetDimensions(width, height);
    float3 encoded = Agent2CompositeNormal.Load(int3(Agent2CompositeCoord(uv, width, height), 0)).xyz;
    return normalize(encoded * 2.0 - 1.0);
}

float3 Agent2UncompressRadiance(float3 color)
{
    float maximum = max(color.x, max(color.y, color.z));
    return color / max(1.0 - maximum, 1e-4);
}

void Agent2AccumulateUpsampleTap(
    int2 sourceCoord,
    float spatialWeight,
    float2 centerUV,
    float2 centerRay,
    int2 sourceResolution,
    float3 centerPosition,
    float3 eyeDirection,
    float depthSharpness,
    inout float3 filtered,
    inout float weightSum)
{
    float2 sampleUV = (float2(sourceCoord) + 0.5) / float2(sourceResolution);
    float sampleDepth = Agent2CompositeLoadDepth(sampleUV);
    if (sampleDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return;

    float2 sampleRay = Agent2CompositeRayAtUV(centerUV, centerRay, sampleUV);
    float3 samplePosition = Agent2CompositeWorldPosition(sampleRay, sampleDepth);
    float depthDifferenceMeters = abs(dot(samplePosition - centerPosition, eyeDirection)) * AGENT2_UNREAL_UNITS_TO_METERS;
    float weight = spatialWeight * exp(-depthDifferenceMeters * depthSharpness);
    filtered += Agent2FilteredSSGI.Load(int3(sourceCoord, 0)).rgb * weight;
    weightSum += weight;
}

float4 main(FullscreenInput input) : SV_Target0
{
    float2 centerUV = input.uvAndRay.xy;
    float centerDepth = Agent2CompositeLoadDepth(centerUV);
    if (centerDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return 0.0;

    float3 centerPosition = Agent2CompositeWorldPosition(input.uvAndRay.zw, centerDepth);
    float3 centerNormal = Agent2CompositeLoadNormal(centerUV);
    float3 eyeDirection = normalize(RemakeViewData[59].xyz - centerPosition);
    float normalDotView = max(dot(centerNormal, eyeDirection), 0.0);
    float depthSharpness = max(normalDotView, AGENT2_UPSAMPLE_MIN_NORMAL_DOT_VIEW)
        / AGENT2_UPSAMPLE_DEPTH_TOLERANCE_METERS;

    uint sourceWidth;
    uint sourceHeight;
    Agent2FilteredSSGI.GetDimensions(sourceWidth, sourceHeight);
    int2 sourceResolution = int2(sourceWidth, sourceHeight);
    float2 lowPixel = centerUV * float2(sourceResolution) - 0.5;
    int2 baseCoord = int2(floor(lowPixel));
    float2 fraction = frac(lowPixel);
    int2 maxCoord = sourceResolution - int2(1, 1);
    int2 p00 = clamp(baseCoord, int2(0, 0), maxCoord);
    int2 p10 = clamp(baseCoord + int2(1, 0), int2(0, 0), maxCoord);
    int2 p01 = clamp(baseCoord + int2(0, 1), int2(0, 0), maxCoord);
    int2 p11 = clamp(baseCoord + int2(1, 1), int2(0, 0), maxCoord);

    float3 compressed = 0.0;
    float weightSum = 0.0;
    Agent2AccumulateUpsampleTap(p00, (1.0 - fraction.x) * (1.0 - fraction.y), centerUV, input.uvAndRay.zw, sourceResolution, centerPosition, eyeDirection, depthSharpness, compressed, weightSum);
    Agent2AccumulateUpsampleTap(p10, fraction.x * (1.0 - fraction.y), centerUV, input.uvAndRay.zw, sourceResolution, centerPosition, eyeDirection, depthSharpness, compressed, weightSum);
    Agent2AccumulateUpsampleTap(p01, (1.0 - fraction.x) * fraction.y, centerUV, input.uvAndRay.zw, sourceResolution, centerPosition, eyeDirection, depthSharpness, compressed, weightSum);
    Agent2AccumulateUpsampleTap(p11, fraction.x * fraction.y, centerUV, input.uvAndRay.zw, sourceResolution, centerPosition, eyeDirection, depthSharpness, compressed, weightSum);
    compressed = saturate(compressed / max(weightSum, 1e-5));

    uint materialWidth;
    uint materialHeight;
    uint albedoWidth;
    uint albedoHeight;
    Agent2CompositeMaterial.GetDimensions(materialWidth, materialHeight);
    Agent2CompositeAlbedo.GetDimensions(albedoWidth, albedoHeight);
    float metallic = saturate(Agent2CompositeMaterial.Load(int3(Agent2CompositeCoord(centerUV, materialWidth, materialHeight), 0)).x);
    float3 albedo = saturate(Agent2CompositeAlbedo.Load(int3(Agent2CompositeCoord(centerUV, albedoWidth, albedoHeight), 0)).rgb);
    // The horizon trace estimates incoming diffuse irradiance. Convert that
    // irradiance to outgoing Lambertian radiance before the additive composite.
    // Omitting 1/pi over-brightens pale receivers and makes emissive fixtures
    // appear to surge even though they should only illuminate nearby surfaces.
    float3 receiverDiffuse = albedo * (1.0 - metallic) * AGENT2_INV_PI;

    // F2 ON remains an intentionally visible diagnostic until live exposure,
    // motion/disocclusion, and GPU timing captures support a promoted strength.
    float3 indirectRadiance = Agent2UncompressRadiance(compressed)
        * receiverDiffuse * AGENT2_DIAGNOSTIC_STRENGTH;
    return float4(indirectRadiance, 0.0);
}
