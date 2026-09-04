#ifndef REDX11_REBIRTH_CONTACT_SHADOWS_HLSL
#define REDX11_REBIRTH_CONTACT_SHADOWS_HLSL
#include "ContactShadowCommon.hlsl"

// Compatibility wiring only. Ray logic is the generated, source-checked donor
// below. This file does not include the experimental geometric tracer.
struct Redx11RebirthGBuffer { float3 WorldNormal; uint ShadingModelID; };
struct Redx11RebirthPixel { float3 WorldPosition; float3 LightVector; float LightDistance; };
struct Redx11RebirthInput { float4 SvPosition; };
static Redx11ContactView Redx11RebirthView;
static Redx11ContactSettings Redx11RebirthSettings;
static float Redx11RebirthInverseRadius;
static float Redx11RebirthJitter;
static float Redx11RebirthHairBias;

// Kept as a separate unchanged donor function. Callers may supply pixel/frame
// inputs once those engine inputs are verified; fixed jitter is test-only.
#include "../../ThirdParty/ShaderInjector/RebirthContactNoise.hlsl"
float Redx11RebirthLinearize(float deviceDepth)
{
    return Redx11ContactLinearDepth(deviceDepth, Redx11RebirthView.invDeviceZToWorldZ);
}
float4x4 Redx11RebirthProjection()
{
    return float4x4(Redx11RebirthView.projectionScale.x,0,0,0,
        0,Redx11RebirthView.projectionScale.y,0,0, 0,0,1,0,
        0,0,0,Redx11RebirthView.perspective>.5f?0.0f:1.0f);
}

#define FGBufferData Redx11RebirthGBuffer
#define FResolvedPixel Redx11RebirthPixel
#define PSInput Redx11RebirthInput
#define SHADINGMODELID_HAIR 7u
#define CONTACT_SHADOWS_SAMPLES REDX11_CONTACT_SAMPLES
#define CONTACT_SHADOWS_RAY_LENGTH Redx11RebirthSettings.rayLength
#define CONTACT_SHADOWS_LOCAL_LIGHT_SHADOW_EXCLUSION_RADIUS_FACTOR Redx11RebirthSettings.lightExclusionFraction
#define CONTACT_SHADOWS_BIAS Redx11RebirthSettings.depthBiasScale
#define CONTACT_SHADOWS_BIAS_HAIR Redx11RebirthHairBias
#define CONTACT_SHADOWS_NORMAL_BIAS Redx11RebirthSettings.normalBiasScale
#define CONTACT_SHADOWS_MIN_THICKNESS Redx11RebirthSettings.minimumThickness
#define CONTACT_SHADOWS_THICKNESS Redx11RebirthSettings.maximumThickness
#define CONTACT_SHADOWS_PIXEL_THICKNESS_SCALE Redx11RebirthSettings.pixelThicknessScale
#define CONTACT_SHADOWS_SELF_OCCLUSION_SKIP_STEPS Redx11RebirthSettings.receiverSkipSteps
#define CONTACT_SHADOWS_GRAZING_EXTRA_SKIP_STEPS Redx11RebirthSettings.grazingExtraSkipSteps
#define CONTACT_SHADOWS_FALLOFF_CONTRAST Redx11RebirthSettings.falloffContrast
#define CONTACT_SHADOWS_IMPROVED_THICKNESS
#define CONTACT_SHADOWS_FALLOFF
#define RANDOM_INTERLEAVED_GRADIENT_NOISE
#define InterleavedGradientNoise(pixel,frame) Redx11RebirthJitter
#define View_ViewToClip Redx11RebirthProjection()
#define View_BufferSizeAndInvSize float4(Redx11RebirthView.bufferSize,Redx11RebirthView.invBufferSize)
#define View_PreViewTranslation Redx11RebirthView.worldToTranslatedWorld
#define View_TranslatedWorldToClip Redx11RebirthView.translatedWorldToClip
#define View_ScreenPositionScaleBias float4(Redx11RebirthView.ndcToBufferScale,Redx11RebirthView.ndcToBufferBias.yx)
#define DeferredLightUniforms_InvRadius Redx11RebirthInverseRadius
#define LinearizeSceneDepth Redx11RebirthLinearize
#include "../../ThirdParty/ShaderInjector/RebirthContactRay.hlsl"
#undef LinearizeSceneDepth
#undef DeferredLightUniforms_InvRadius
#undef View_ScreenPositionScaleBias
#undef View_TranslatedWorldToClip
#undef View_PreViewTranslation
#undef View_BufferSizeAndInvSize
#undef View_ViewToClip
#undef InterleavedGradientNoise
#undef RANDOM_INTERLEAVED_GRADIENT_NOISE
#undef CONTACT_SHADOWS_FALLOFF
#undef CONTACT_SHADOWS_IMPROVED_THICKNESS
#undef CONTACT_SHADOWS_FALLOFF_CONTRAST
#undef CONTACT_SHADOWS_GRAZING_EXTRA_SKIP_STEPS
#undef CONTACT_SHADOWS_SELF_OCCLUSION_SKIP_STEPS
#undef CONTACT_SHADOWS_PIXEL_THICKNESS_SCALE
#undef CONTACT_SHADOWS_THICKNESS
#undef CONTACT_SHADOWS_MIN_THICKNESS
#undef CONTACT_SHADOWS_NORMAL_BIAS
#undef CONTACT_SHADOWS_BIAS_HAIR
#undef CONTACT_SHADOWS_BIAS
#undef CONTACT_SHADOWS_LOCAL_LIGHT_SHADOW_EXCLUSION_RADIUS_FACTOR
#undef CONTACT_SHADOWS_RAY_LENGTH
#undef CONTACT_SHADOWS_SAMPLES
#undef SHADINGMODELID_HAIR
#undef PSInput
#undef FResolvedPixel
#undef FGBufferData

float Redx11TraceRebirthContactShadow(float3 translatedPosition,float3 normal,
    float3 direction,float lightDistance,float inverseRadius,float jitter,
    uint donorShadingModel,float hairBias,Redx11ContactView view,Redx11ContactSettings settings)
{
    // Adapter contract: the supplied receiver must belong to this viewport.
    // The donor receives renderer-validated inputs; it cannot validate our
    // reconstruction/buffer mapping. Leave its ray and intersection math alone.
    float4 receiverClip=mul(float4(translatedPosition,1.0f),view.translatedWorldToClip);
    if(!all(isfinite(receiverClip)) || receiverClip.w<=1.0e-5f
        || !all(isfinite(view.viewportUVBounds))
        || any(view.viewportUVBounds.zw<=view.viewportUVBounds.xy))
        return 1.0f;
    float2 receiverUV=receiverClip.xy/receiverClip.w*view.ndcToBufferScale+view.ndcToBufferBias;
    if(!all(isfinite(receiverUV)) || any(receiverUV<view.viewportUVBounds.xy)
        || any(receiverUV>=view.viewportUVBounds.zw))
        return 1.0f;
    Redx11RebirthView=view;
    Redx11RebirthSettings=settings;
    Redx11RebirthInverseRadius=inverseRadius;
    Redx11RebirthJitter=jitter;
    Redx11RebirthHairBias=hairBias;
    Redx11RebirthGBuffer gbuffer;
    gbuffer.WorldNormal=normal;
    gbuffer.ShadingModelID=donorShadingModel;
    Redx11RebirthPixel resolved;
    resolved.WorldPosition=translatedPosition-view.worldToTranslatedWorld;
    resolved.LightVector=direction;
    resolved.LightDistance=lightDistance;
    Redx11RebirthInput input;
    input.SvPosition=0; // Donor noise already evaluated by the caller.
    return CalculateContactShadows(gbuffer,resolved,input);
}

// Compatibility for existing numerical fixtures. Not a claim that default-lit
// is the correct material for every game pixel or that fixed jitter is final.
float Redx11TraceLocalContactShadow(float3 translatedPosition,float3 normal,
    float3 direction,float lightDistance,float inverseRadius,float jitter,
    Redx11ContactView view,Redx11ContactSettings settings)
{
    return Redx11TraceRebirthContactShadow(translatedPosition,normal,direction,
        lightDistance,inverseRadius,jitter,0u,1.5f,view,settings);
}
#endif
