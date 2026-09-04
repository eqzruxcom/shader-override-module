/*
 * Engine-neutral Shader Model 5 SSGI prototype.
 *
 * This is an altered HLSL adaptation of the horizon-based SSGI pass in R3D:
 * https://github.com/Bigfoot71/r3d
 * Pinned reference commit: 3cb964171a0b90f1d0ec97e061b25021648eec65
 *
 * Copyright (c) 2025-2026 Le Juez Victor
 * Distributed under the Zlib license preserved in licenses/R3D-Zlib.txt.
 *
 * Alterations: GLSL-to-HLSL translation, explicit SM5 bindings, bounded sample
 * loop, D3D depth reconstruction, configurable normal decoding, and a portable
 * fullscreen pixel-shader interface. This is not the original R3D source.
 */

Texture2D<float4> SSGISceneRadiance : register(t0);
Texture2D<float4> SSGIViewNormal : register(t1);
Texture2D<float> SSGISceneDepth : register(t2);
SamplerState SSGILinearClamp : register(s0);

cbuffer SSGIConstants : register(b0)
{
    row_major float4x4 SSGIInverseProjection;
    float4 SSGIOutputSizeAndInverse; // xy = output size, zw = inverse size
    float4 SSGITraceSettings;        // x = max pixel radius, y = distance falloff, z = edge fade UV, w = intensity
    float4 SSGIRejectSettings;       // x = coplanar threshold, y = normal similarity, z = normal rejection, w = depth clear threshold
    float4 SSGINormalDecodeScale;    // xyz applied to encoded normal
    float4 SSGINormalDecodeBias;     // xyz added after scale
    uint SSGISliceCount;             // clamped to [1, 8]
    uint SSGIMaxSteps;               // clamped to [1, 16]
    float SSGIDepthScale;
    float SSGIDepthBias;
};

struct SSGIFullscreenInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

static const float SSGI_PI = 3.14159265358979323846;
static const float SSGI_TAU = 6.28318530717958647692;

float SSGIHashIGN(float2 pixel)
{
    return frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
}

float3 SSGIDecodeNormal(float2 uv)
{
    float3 encoded = SSGIViewNormal.SampleLevel(SSGILinearClamp, uv, 0).xyz;
    return normalize(encoded * SSGINormalDecodeScale.xyz + SSGINormalDecodeBias.xyz);
}

float3 SSGIReconstructViewPosition(float2 uv, float rawDepth)
{
    float deviceDepth = rawDepth * SSGIDepthScale + SSGIDepthBias;
    float2 clipXY = uv * float2(2.0, -2.0) + float2(-1.0, 1.0);
    float4 view = mul(float4(clipXY, deviceDepth, 1.0), SSGIInverseProjection);
    return view.xyz / max(abs(view.w), 1e-6);
}

float SSGIHorizonContribution(float normalDotEye, float normalDotTangent, float h0, float h1)
{
    return 0.25 * normalDotEye * (cos(2.0 * h0) - cos(2.0 * h1))
         + 0.25 * normalDotTangent * (2.0 * (h1 - h0) - sin(2.0 * h1) + sin(2.0 * h0));
}

float3 SSGICompressRadiance(float3 color)
{
    return color / (1.0 + max(color.x, max(color.y, color.z)));
}

float4 main(SSGIFullscreenInput input) : SV_Target0
{
    uint sliceCount = clamp(SSGISliceCount, 1u, 8u);
    uint maxSteps = clamp(SSGIMaxSteps, 1u, 16u);

    float centerDepth = SSGISceneDepth.SampleLevel(SSGILinearClamp, input.uv, 0);
    if (centerDepth >= SSGIRejectSettings.w)
        return 0.0;

    float3 centerPosition = SSGIReconstructViewPosition(input.uv, centerDepth);
    float3 centerNormal = SSGIDecodeNormal(input.uv);
    float3 eyeDirection = normalize(-centerPosition);
    float normalDotEye = dot(centerNormal, eyeDirection);

    float jitter = SSGIHashIGN(input.position.xy);
    float angleOffset = SSGI_TAU * jitter;
    float linearOffset = jitter;
    float sliceStep = SSGI_TAU / float(sliceCount);
    float sliceWeight = 2.0 / float(sliceCount);
    float startStep = max(1.0, SSGIOutputSizeAndInverse.x / 1000.0);
    float stepGrowth = sliceStep + 1.0;
    float pixelDistanceBase = startStep * pow(stepGrowth, linearOffset);
    float pixelDistanceOffset = 1.0 - startStep;

    float3 accumulatedGI = 0.0;

    [loop]
    for (uint slice = 0; slice < sliceCount; ++slice)
    {
        float angle = angleOffset + sliceStep * float(slice);
        float sineAngle;
        float cosineAngle;
        sincos(angle, sineAngle, cosineAngle);
        float2 sliceDirection = float2(cosineAngle, sineAngle);

        float2 tangentUV = input.uv + sliceDirection * SSGIOutputSizeAndInverse.zw * 0.1;
        float3 tangentPosition = SSGIReconstructViewPosition(tangentUV, centerDepth);
        float3 tangent = normalize(normalize(tangentPosition) + eyeDirection);
        float normalDotTangent = dot(centerNormal, tangent);
        float horizonAngle = atan2(normalDotEye, -normalDotTangent);

        float3 sliceGI = 0.0;
        float distanceMultiplier = 1.0;

        [loop]
        for (uint step = 0; step < maxSteps; ++step)
        {
            float pixelDistance = pixelDistanceBase * distanceMultiplier + pixelDistanceOffset;
            distanceMultiplier *= stepGrowth;
            if (pixelDistance > SSGITraceSettings.x)
                break;

            float2 sampleUV = input.uv + sliceDirection * pixelDistance * SSGIOutputSizeAndInverse.zw;
            if (any(sampleUV <= 0.0) || any(sampleUV >= 1.0))
                break;

            float sampleDepth = SSGISceneDepth.SampleLevel(SSGILinearClamp, sampleUV, 0);
            if (sampleDepth >= SSGIRejectSettings.w)
                continue;

            float3 samplePosition = SSGIReconstructViewPosition(sampleUV, sampleDepth);
            float3 sampleNormal = SSGIDecodeNormal(sampleUV);
            float3 delta = samplePosition - centerPosition;

            if (abs(dot(delta, centerNormal)) < SSGIRejectSettings.x &&
                dot(sampleNormal, centerNormal) > SSGIRejectSettings.y)
                continue;

            float sampleAngle = atan2(dot(tangent, delta), dot(eyeDirection, delta));
            if (sampleAngle >= horizonAngle)
                continue;

            float contribution = max(0.0, SSGIHorizonContribution(
                normalDotEye, normalDotTangent, sampleAngle, horizonAngle));
            float2 edgeDistance = min(sampleUV, 1.0 - sampleUV);
            float edgeFade = smoothstep(0.0, SSGITraceSettings.z, min(edgeDistance.x, edgeDistance.y));
            float distanceSquared = max(dot(delta, delta), 1e-8);
            float distanceFade = rcp(1.0 + distanceSquared * SSGITraceSettings.y);
            float facing = -dot(sampleNormal, delta * rsqrt(distanceSquared));
            float normalFade = lerp(
                1.0,
                smoothstep(0.0, 0.1, facing),
                saturate(SSGIRejectSettings.z));
            float3 radiance = max(0.0, SSGISceneRadiance.SampleLevel(SSGILinearClamp, sampleUV, 0).rgb);

            sliceGI += radiance * contribution * edgeFade * distanceFade * normalFade;
            horizonAngle = sampleAngle;
        }

        accumulatedGI += sliceGI * sliceWeight;
    }

    float3 indirectRadiance = max(0.0, accumulatedGI * SSGITraceSettings.w);
    return float4(SSGICompressRadiance(indirectRadiance), 1.0);
}
