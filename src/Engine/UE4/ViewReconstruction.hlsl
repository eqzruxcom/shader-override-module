#ifndef REDX11_UE4_VIEW_RECONSTRUCTION_HLSL
#define REDX11_UE4_VIEW_RECONSTRUCTION_HLSL

// UE4's device-Z conversion supports perspective, orthographic, regular-Z,
// and reversed-Z projections through the view uniform's four coefficients.
float Redx11UE4DeviceZToWorldDepth(float deviceZ, float4 invDeviceZToWorldZ)
{
    return mad(invDeviceZToWorldZ.x, deviceZ, invDeviceZToWorldZ.y)
        + rcp(mad(invDeviceZToWorldZ.z, deviceZ, -invDeviceZToWorldZ.w));
}

float2 Redx11UE4ViewPixelToNDC(
    float2 viewPixel,
    float2 viewRectMin,
    float2 invViewSize)
{
    float2 localPixel = viewPixel - viewRectMin;
    return float2(
        localPixel.x * invViewSize.x * 2.0f - 1.0f,
        1.0f - localPixel.y * invViewSize.y * 2.0f);
}

float2 Redx11UE4ViewPixelToBufferUV(
    float2 viewPixel,
    float2 viewRectMin,
    float2 invBufferSize)
{
    return (viewPixel + viewRectMin) * invBufferSize;
}

float2 Redx11UE4BufferUVToNDC(
    float2 bufferUV,
    float2 screenPositionScale,
    float2 screenPositionBias)
{
    float2 safeScale = float2(
        abs(screenPositionScale.x) > 1.0e-8f ? screenPositionScale.x : 1.0f,
        abs(screenPositionScale.y) > 1.0e-8f ? screenPositionScale.y : 1.0f);
    return (bufferUV - screenPositionBias) / safeScale;
}

float3 Redx11UE4ReconstructTranslatedWorldPosition(
    float2 viewPixel,
    float worldDepth,
    float2 viewRectMin,
    float2 invViewSize,
    float4x4 screenToTranslatedWorld)
{
    float2 ndc = Redx11UE4ViewPixelToNDC(viewPixel, viewRectMin, invViewSize);
    float3 screenPosition = worldDepth * float3(ndc, 1.0f);
    return mul(screenToTranslatedWorld, float4(screenPosition, 1.0f)).xyz;
}

float3 Redx11UE4ReconstructWorldPositionFromDeviceZ(
    float2 svPosition,
    float deviceZ,
    float2 invBufferSize,
    float2 screenPositionScale,
    float2 screenPositionBias,
    float4x4 clipToWorld)
{
    float2 bufferUV = svPosition * invBufferSize;
    float2 ndc = Redx11UE4BufferUVToNDC(
        bufferUV,
        screenPositionScale,
        screenPositionBias);
    float4 homogeneousWorld = mul(clipToWorld, float4(ndc, deviceZ, 1.0f));
    float safeW = abs(homogeneousWorld.w) > 1.0e-8f
        ? homogeneousWorld.w
        : (homogeneousWorld.w < 0.0f ? -1.0e-8f : 1.0e-8f);
    return homogeneousWorld.xyz / safeW;
}

float3 Redx11UE4ScreenPixelToViewRayZ1(
    float2 viewPixel,
    float2 viewRectMin,
    float2 invBufferSize,
    float2 screenPositionScale,
    float2 screenPositionBias,
    float4x4 clipToView)
{
    float2 bufferUV = Redx11UE4ViewPixelToBufferUV(
        viewPixel,
        viewRectMin,
        invBufferSize);
    float2 ndc = Redx11UE4BufferUVToNDC(
        bufferUV,
        screenPositionScale,
        screenPositionBias);
    float4 homogeneousView = mul(clipToView, float4(ndc, 1.0f, 1.0f));
    float safeW = abs(homogeneousView.w) > 1.0e-8f
        ? homogeneousView.w
        : (homogeneousView.w < 0.0f ? -1.0e-8f : 1.0e-8f);
    float3 viewRay = homogeneousView.xyz / safeW;
    float safeZ = abs(viewRay.z) > 1.0e-6f
        ? viewRay.z
        : (viewRay.z < 0.0f ? -1.0e-6f : 1.0e-6f);
    return viewRay / safeZ;
}

float3 Redx11UE4WorldToTranslatedWorld(float3 worldPosition, float3 preViewTranslation)
{
    return worldPosition + preViewTranslation;
}

float3 Redx11UE4TranslatedWorldToView(
    float3 translatedWorldPosition,
    float4x4 translatedWorldToView)
{
    return mul(translatedWorldToView, float4(translatedWorldPosition, 1.0f)).xyz;
}

float3 Redx11UE4WorldDirectionToView(
    float3 worldDirection,
    float3x3 translatedWorldToViewRotation)
{
    return mul(translatedWorldToViewRotation, worldDirection);
}

#endif
