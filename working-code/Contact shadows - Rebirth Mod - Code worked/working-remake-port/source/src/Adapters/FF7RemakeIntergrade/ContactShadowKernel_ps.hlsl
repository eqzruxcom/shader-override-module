// Standalone kernel compiled to SM5 instructions and inserted into native CS
// light loops. This is NOT a replacement for the full native lighting shader.
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
#include "../../Effects/Lighting/RebirthContactShadows.hlsl"
#include "RebirthContactInputMapping.hlsl"
#else
#include "../../Effects/Lighting/ContactShadows.hlsl"
#endif

#ifndef REDX11_CONTACT_DEPTH_REGISTER
#define REDX11_CONTACT_DEPTH_REGISTER t4
#endif
cbuffer NativeDispatch : register(b0) { float4 DispatchData[5]; };
cbuffer NativeView : register(b1) { float4 ViewData[140]; };
cbuffer NativeLights : register(b4) { float4 LightData[768]; };
Texture2D<float4> NativeNormal : register(t1);
#if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
Texture2D<float4> NativeMaterial : register(t2);
#endif
Texture2D<float4> NativeDepth : register(REDX11_CONTACT_DEPTH_REGISTER);
Texture1D<float4> ContactControl : register(t120);

float Redx11ContactSampleDeviceDepth(float2 uv)
{
    // Integer Load is point sampling without depending on a native sampler's
    // unknown filtering. Clamp to the verified dispatch viewport, not padding.
    int2 minimumPixel = (int2)asuint(DispatchData[1].xy);
    int2 maximumPixel = (int2)asuint(DispatchData[1].zw) - 1;
    int2 pixel = clamp((int2)floor(uv * ViewData[126].xy), minimumPixel, maximumPixel);
    return NativeDepth.Load(int3(pixel, 0)).x;
}

// xy = absolute pixel indices as floats; z = native uint light index bit-cast
// to float, not numerically converted. There are at most 256 indexed lights.
float Redx11RemakeContactPixel(float3 input, bool traceEnabled, out bool receiverValid)
{
    receiverValid=false;
    float4 control = ContactControl.Load(int2(31, 0));
    uint lightIndex = asuint(input.z);
    if (control.x != 1.0f || control.z <= 0.0f || lightIndex >= 256u)
        return 1.0f;
    if (control.y >= 0.0f && lightIndex != (uint)control.y)
        return 1.0f;

    uint2 pixel = (uint2)input.xy;
    uint2 rectMin = asuint(DispatchData[1].xy);
    uint2 rectMax = asuint(DispatchData[1].zw);
    float2 bufferSize = ViewData[126].xy;
    if (any(rectMax <= rectMin) || any(pixel < rectMin) || any(pixel >= rectMax)
        || any(bufferSize <= 0) || any((float2)rectMax > bufferSize))
        return 1.0f;

    float2 viewSize = (float2)(rectMax - rectMin);
    float2 localPixel = (float2)(pixel - rectMin) + .5f;
    float2 ndc = localPixel / viewSize * float2(2,-2) + float2(-1,1);
    float deviceDepth = NativeDepth.Load(int3(pixel, 0)).x;
    float linearDepth = Redx11ContactLinearDepth(deviceDepth, ViewData[57]);
    if (!isfinite(linearDepth) || linearDepth <= 0.0f)
        return 1.0f;
    #if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
    // Donor caller CONTACT_SHADOW_EARLY_SKY_OUT.
    if(linearDepth>=1000000.0f) return 1.0f;
    #endif

    // Exact row-combination convention of native lighting cb1[40..43].
    float4 homogeneousWorld = ndc.y * linearDepth * ViewData[41];
    homogeneousWorld += ndc.x * linearDepth * ViewData[40];
    homogeneousWorld += linearDepth * ViewData[42];
    homogeneousWorld += ViewData[43];
    if (abs(homogeneousWorld.w) <= 1.0e-8f)
        return 1.0f;
    float3 world = homogeneousWorld.xyz / homogeneousWorld.w;
    float3 translated = world + ViewData[62].xyz;
    Redx11ContactView view;
    // Geometry VS f2f65b9971c21bde adds [62] then combines rows [0..3].
    view.translatedWorldToClip = float4x4(ViewData[0], ViewData[1], ViewData[2], ViewData[3]);
    view.invDeviceZToWorldZ = ViewData[57];
    view.bufferSize = bufferSize;
    view.invBufferSize = ViewData[126].zw;
    view.projectionScale = float2(ViewData[24].x, ViewData[25].y);
    view.perspective = ViewData[27].w < 1.0f ? 1.0f : 0.0f;
    view.viewportUVBounds = float4((float2)rectMin / bufferSize, (float2)rectMax / bufferSize);
    view.ndcToBufferScale = .5f * viewSize / bufferSize * float2(1,-1);
    view.ndcToBufferBias = ((float2)rectMin + .5f * viewSize) / bufferSize;
    view.screenLinearToWorld = float4x4(ViewData[40], ViewData[41], ViewData[42], ViewData[43]);
    view.worldToTranslatedWorld = ViewData[62].xyz;
    view.pointSampledDepth = 1;

    // Validate the mapping at the receiver before ANY ray lookup. This checks
    // the convention, subrect, and translation, not every matrix coefficient.
    float4 receiverClip = mul(float4(translated,1), view.translatedWorldToClip);
    if (!all(isfinite(receiverClip)) || receiverClip.w <= 1.0e-5f)
        return 1.0f;
    float2 receiverUV = receiverClip.xy / receiverClip.w * view.ndcToBufferScale + view.ndcToBufferBias;
    float2 pixelError = receiverUV * bufferSize - ((float2)pixel + .5f);
    float projectedDepth = Redx11ContactLinearDepth(receiverClip.z / receiverClip.w, ViewData[57]);
    if (any(abs(pixelError) > .75f) || !isfinite(projectedDepth)
        || abs(projectedDepth-linearDepth) > max(.01f,linearDepth*.002f))
        return 1.0f;

    float3 normal = NativeNormal.Load(int3(pixel,0)).xyz * 2.0f - 1.0f;
    float normalLength2 = dot(normal,normal);
    float3 toLight = LightData[lightIndex].xyz - world;
    float distance2 = dot(toLight,toLight);
    if (normalLength2 <= 1.0e-8f || distance2 <= 1.0e-8f)
        return 1.0f;
    normal *= rsqrt(normalLength2);
    float lightDistance = sqrt(distance2);
    float3 direction = toLight / lightDistance;
    float inverseRadius = LightData[lightIndex].w;
    Redx11ContactSettings settings = Redx11ContactDonorSettings();
    settings.rayLength = max(control.w,0.0f);
    receiverValid=true;
    if(!traceEnabled) return 1.0f;
    #if defined(REDX11_CONTACT_USE_REBIRTH_SOURCE)
    // Native material/noise inputs traced in the source-reuse binding audit.
    // Keep the donor's IGN and hair bias, not a new sampling/shading algorithm.
    int frameIndex=Redx11RemakeContactFrameIndex(ViewData[139]);
    uint material=Redx11RemakeContactMaterial(NativeMaterial.Load(int3(pixel,0)).w);
    float jitter=InterleavedGradientNoise((float2)pixel+.5f,frameIndex);
    float visibility=Redx11TraceRebirthContactShadow(translated,normal,direction,
        lightDistance,inverseRadius,jitter,material,1.5f,view,settings);
    #else
    // Fixed midpoint sampling for the first integration, without relying on an
    // unverified temporal-noise binding. Motion quality still needs a live test.
    float visibility = Redx11TraceLocalContactShadow(translated, normal, direction,
        lightDistance, inverseRadius, .5f, view, settings);
    #endif
    return visibility;
}

#if !defined(REDX11_CONTACT_OMIT_ENTRY)
float main(float3 input : TEXCOORD0) : SV_Target0
{
    bool valid;
    float visibility=Redx11RemakeContactPixel(input,true,valid);
    return lerp(1.0f,visibility,saturate(ContactControl.Load(int2(31,0)).z));
}
#endif
