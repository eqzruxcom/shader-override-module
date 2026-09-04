#ifndef REDX11_CONTACT_SHADOW_COMMON_HLSL
#define REDX11_CONTACT_SHADOW_COMMON_HLSL

// Adapted from David Matos' ShaderInjector, MIT, Copyright (c) 2026 David Matos.
// Pinned source and complete license: THIRD_PARTY_NOTICES.md and
// licenses/ShaderInjector-MIT.txt. See docs/contact-shadow-port.md for changes.
// No game register bindings, material IDs, or temporal/checkerboard assumptions.
#ifndef REDX11_CONTACT_SAMPLES
#define REDX11_CONTACT_SAMPLES 16
#endif
#if REDX11_CONTACT_SAMPLES < 1 || REDX11_CONTACT_SAMPLES > 64
#error REDX11_CONTACT_SAMPLES must be between 1 and 64
#endif

// The adapter supplies an explicit-LOD, point-sampled device-depth lookup.
float Redx11ContactSampleDeviceDepth(float2 bufferUV);

struct Redx11ContactView
{
    // Row-vector convention: mul(float4(translatedWorld, 1), matrix).
    float4x4 translatedWorldToClip;
    float4 invDeviceZToWorldZ;
    float2 bufferSize;
    float2 invBufferSize;
    float2 projectionScale;
    float perspective; // 1 for perspective, 0 for orthographic.
    float2 ndcToBufferScale;
    float2 ndcToBufferBias; // Already unswizzled; UE4 callers pass .wz.
    float4 viewportUVBounds; // min.xy, max.zw, in the allocated depth texture.
    // Row-vector native reconstruction from (ndc.xy * linearZ, linearZ, 1)
    // for perspective; orthographic uses unscaled ndc.xy instead.
    float4x4 screenLinearToWorld;
    float3 worldToTranslatedWorld;
    float pointSampledDepth; // Depth texels describe their centers, not input UV.
};

struct Redx11ContactSettings
{
    float rayLength;
    float lightExclusionFraction;
    float depthBiasScale;
    float normalBiasScale;
    float minimumThickness;
    float maximumThickness;
    float pixelThicknessScale;
    float receiverSkipSteps;
    float grazingExtraSkipSteps;
    float falloffContrast;
};

// Donor local-light defaults, not a validated Remake preset. Lengths must use
// the same units as the adapter's positions and linear view depth.
Redx11ContactSettings Redx11ContactDonorSettings()
{
    Redx11ContactSettings s;
    s.rayLength = 100.0f;
    s.lightExclusionFraction = 0.175f;
    s.depthBiasScale = 1.0f; // Hair's donor 1.5 is an adapter/material decision.
    s.normalBiasScale = 0.5f;
    s.minimumThickness = 5.0f;
    s.maximumThickness = 25.0f;
    s.pixelThicknessScale = 32.0f;
    s.receiverSkipSteps = 0.5f;
    s.grazingExtraSkipSteps = 1.0f;
    s.falloffContrast = 3.0f;
    return s;
}

float Redx11ContactLinearDepth(float deviceZ, float4 coefficients)
{
    return mad(deviceZ, coefficients.x, coefficients.y)
        + rcp(mad(deviceZ, coefficients.z, -coefficients.w));
}

float Redx11ContactPerspectiveDepth(
    float t, float2 depthOverW, float2 inverseW)
{
    return lerp(depthOverW.x, depthOverW.y, t)
        / max(lerp(inverseW.x, inverseW.y, t), 1.0e-8f);
}

void Redx11ContactClipPlane(float startDistance, float endDistance, inout float exitT)
{
    if (endDistance < 0.0f)
    {
        float denominator = startDistance - endDistance;
        if (denominator > 1.0e-6f)
            exitT = min(exitT, startDistance / denominator);
    }
}

float Redx11ContactThickness(
    float sceneDepth, float depthBias,
    Redx11ContactView view, Redx11ContactSettings settings)
{
    float depthScale = view.perspective > 0.5f ? sceneDepth : 1.0f;
    // NDC spans two units across the VIEW, not necessarily the allocation.
    float2 viewPixels = (view.viewportUVBounds.zw - view.viewportUVBounds.xy)
        * view.bufferSize;
    float2 footprint = 2.0f * depthScale
        / (max(abs(view.projectionScale), 1.0e-6f) * max(viewPixels, 1.0f));
    float minimumThickness = max(settings.minimumThickness, depthBias + 1.0e-4f);
    float maximumThickness = max(settings.maximumThickness, minimumThickness);
    return clamp(settings.minimumThickness
        + max(footprint.x, footprint.y) * settings.pixelThicknessScale,
        minimumThickness, maximumThickness);
}

#endif
