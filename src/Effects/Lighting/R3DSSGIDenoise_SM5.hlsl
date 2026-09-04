/*
 * Altered SM5 port of R3D's A-trous denoiser.
 * Donor commit 3cb964171a0b90f1d0ec97e061b25021648eec65, Zlib.
 * Compile with AGENT2_ATROUS_STEP set to 16, 8, 4, or 2.
 */

#ifndef AGENT2_ATROUS_STEP
#define AGENT2_ATROUS_STEP 16
#endif

static const float AGENT2_UNREAL_UNITS_TO_METERS = 0.01;
static const float AGENT2_DEPTH_CLEAR_EPSILON = 0.0000001;

Texture2D<float4> Agent2DenoiseSource : register(t110);
Texture2D<float4> Agent2DenoiseNormal : register(t111);
Texture2D<float> Agent2DenoiseDepth : register(t112);
SamplerState Agent2DenoiseLinearClamp : register(s0);

cbuffer RemakeView : register(b0)
{
    float4 RemakeViewData[154];
};

struct FullscreenInput
{
    float4 uvAndRay : TEXCOORD0;
    float4 position : SV_Position;
};

float Agent2DenoiseDeviceW(float rawDepth)
{
    return rawDepth * RemakeViewData[57].x + RemakeViewData[57].y
         + rcp(rawDepth * RemakeViewData[57].z - RemakeViewData[57].w);
}

float2 Agent2DenoiseRayAtUV(float2 centerUV, float2 centerRay, float2 sampleUV)
{
    return centerRay + (sampleUV - centerUV) * float2(2.0, -2.0);
}

float3 Agent2DenoiseWorldPosition(float2 ray, float rawDepth)
{
    float deviceW = Agent2DenoiseDeviceW(rawDepth);
    float2 screenXY = ray * deviceW;
    float4 world = RemakeViewData[40] * screenXY.x;
    world += RemakeViewData[41] * screenXY.y;
    world += RemakeViewData[42] * deviceW;
    world += RemakeViewData[43];
    return world.xyz / world.w;
}

int2 Agent2DenoiseCoord(float2 uv, uint width, uint height)
{
    return clamp(int2(uv * float2(width, height)), int2(0, 0), int2(width - 1, height - 1));
}

float Agent2DenoiseLoadDepth(float2 uv)
{
    uint width;
    uint height;
    Agent2DenoiseDepth.GetDimensions(width, height);
    return Agent2DenoiseDepth.Load(int3(Agent2DenoiseCoord(uv, width, height), 0));
}

float3 Agent2DenoiseLoadNormal(float2 uv)
{
    uint width;
    uint height;
    Agent2DenoiseNormal.GetDimensions(width, height);
    float3 encoded = Agent2DenoiseNormal.Load(int3(Agent2DenoiseCoord(uv, width, height), 0)).xyz;
    return normalize(encoded * 2.0 - 1.0);
}

void Agent2AccumulateTap(
    int2 offset,
    float baseWeight,
    float2 centerUV,
    float2 centerRay,
    float2 invOutput,
    float3 centerPosition,
    float3 centerNormal,
    int2 centerPixel,
    int2 sourceResolution,
    float invStepWidthSquared,
    inout float4 result,
    inout float weightSum)
{
    int2 samplePixel = centerPixel + offset * AGENT2_ATROUS_STEP;
    if (any(samplePixel < int2(0, 0)) || any(samplePixel >= sourceResolution))
        return;

    float2 sampleUV = centerUV + float2(offset) * float(AGENT2_ATROUS_STEP) * invOutput;
    float sampleDepth = Agent2DenoiseLoadDepth(sampleUV);
    if (sampleDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return;

    float2 sampleRay = Agent2DenoiseRayAtUV(centerUV, centerRay, sampleUV);
    float3 samplePosition = Agent2DenoiseWorldPosition(sampleRay, sampleDepth);
    float3 sampleNormal = Agent2DenoiseLoadNormal(sampleUV);
    float4 sampleColor = Agent2DenoiseSource.Load(int3(samplePixel, 0));
    float planeDistance = dot(samplePosition - centerPosition, centerNormal) * AGENT2_UNREAL_UNITS_TO_METERS;
    float3 normalDelta = centerNormal - sampleNormal;
    float normalDifference = dot(normalDelta, normalDelta) * invStepWidthSquared;
    float weight = baseWeight * exp(-normalDifference * 20.0 - planeDistance * planeDistance * 100.0);
    result += sampleColor * weight;
    weightSum += weight;
}

float4 main(FullscreenInput input) : SV_Target0
{
    uint width;
    uint height;
    Agent2DenoiseSource.GetDimensions(width, height);
    int2 sourceResolution = int2(width, height);
    float2 invOutput = rcp(float2(sourceResolution));
    int2 centerPixel = int2(input.position.xy);
    if (any(centerPixel < int2(0, 0)) || any(centerPixel >= sourceResolution))
        return 0.0;

    float2 centerUV = input.uvAndRay.xy;
    float centerDepth = Agent2DenoiseLoadDepth(centerUV);
    // Captured resource 00236552 is explicitly cleared to 0.0 (reversed Z).
    if (centerDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return 0.0;

    float3 centerPosition = Agent2DenoiseWorldPosition(input.uvAndRay.zw, centerDepth);
    float3 centerNormal = Agent2DenoiseLoadNormal(centerUV);
    float4 centerColor = Agent2DenoiseSource.Load(int3(centerPixel, 0));

    float4 result = centerColor * 0.25;
    float weightSum = 0.25;
    float invStepWidthSquared = rcp(float(AGENT2_ATROUS_STEP * AGENT2_ATROUS_STEP));

    Agent2AccumulateTap(int2(-1, -1), 0.0625, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2( 0, -1), 0.1250, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2( 1, -1), 0.0625, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2(-1,  0), 0.1250, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2( 1,  0), 0.1250, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2(-1,  1), 0.0625, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2( 0,  1), 0.1250, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);
    Agent2AccumulateTap(int2( 1,  1), 0.0625, centerUV, input.uvAndRay.zw, invOutput, centerPosition, centerNormal, centerPixel, sourceResolution, invStepWidthSquared, result, weightSum);

    return result / max(weightSum, 1e-4);
}
