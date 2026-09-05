#ifndef REDX11_REBIRTH_GTVB_HLSL
#define REDX11_REBIRTH_GTVB_HLSL

// Source-faithful SM5 port of ComputeGTVBGI from ShaderInjector's Maximum
// Quality ReflectionEnvironment shader. The algorithm, constants, loop order,
// masks, noise, AO result, and fallback result are unchanged. The adapter must
// provide the REDX11_GTVB_* compatibility functions documented below.
#include "RebirthGTVBRandom.hlsl"

#define SSGI_RAY_COUNT 1
#define SSGI_RAYMARCHING_STEP_COUNT 16
#define SSGI_RAYMARCHING_WIDTH 512.0f
#define SSGI_THICKNESS 75.0f
#define MATH_PI 3.14159265358979323846f

float4 ComputeGTVBGI(
    float2 PixelXY,
    float3 WorldPos,
    float3 WorldNormal,
    out float FallbackMask)
{
    FallbackMask = 1.0f;

    const uint MASK_ALL = 0xFFFFFFFFu;
    const float inv32 = rcp(32.0f);
    const float InvStepCount = rcp((float)SSGI_RAYMARCHING_STEP_COUNT);
    const float InvSSGISampleCount = rcp((float)SSGI_RAY_COUNT);

    // REDX11 uses a rigidly rotated camera-relative world basis. Dot products,
    // crosses, angular masks, and distances are invariant under that rotation.
    float3 ViewPos = REDX11_GTVB_WorldToViewSpace(WorldPos);
    float3 ViewNormal = normalize(REDX11_GTVB_WorldDirToViewDir(WorldNormal));
    float3 ViewDir = normalize(-ViewPos);
    float2 ViewSize = REDX11_GTVB_ViewSize();

    float3 RayOrigin = REDX11_GTVB_ScreenPixelToViewRayZ1(PixelXY);
    float3 RayDx = REDX11_GTVB_ScreenPixelToViewRayZ1(PixelXY + float2(1.0f, 0.0f)) - RayOrigin;
    float3 RayDy = REDX11_GTVB_ScreenPixelToViewRayZ1(PixelXY + float2(0.0f, 1.0f)) - RayOrigin;

    int frameIndex = REDX11_GTVB_FrameIndex();
    float3 random = float3(
        GenerateHashedRandomFloat(uint4(PixelXY, frameIndex, 0x68bc21ebu)),
        GenerateHashedRandomFloat(uint4(PixelXY, frameIndex, 0x02e5be93u)),
        GenerateHashedRandomFloat(uint4(PixelXY, frameIndex, 0x03e56253u)));

    float3 AccumulatedGI = 0.0f;
    float AccumulatedOcclusion = 0.0f;
    float AccumulatedScreenGICoverage = 0.0f;

    // SM5 rejects Rebirth's [loop] hint when Maximum fixes this to one ray.
    // Removing the hint changes no operation, constant, or iteration count.
    for (uint SSGISampleIndex = 0u; SSGISampleIndex < SSGI_RAY_COUNT; ++SSGISampleIndex)
    {
        float SliceAngle = ((float)SSGISampleIndex + random.x) * InvSSGISampleCount * MATH_PI;
        float SinSlice;
        float CosSlice;
        sincos(SliceAngle, SinSlice, CosSlice);
        float2 ScreenSliceDir2D = float2(CosSlice, SinSlice);
        float3 RayStep = RayDx * ScreenSliceDir2D.x + RayDy * ScreenSliceDir2D.y;

        float3 SlicePlaneNormal = normalize(cross(RayOrigin, -RayStep));
        float ViewNormalPlaneDot = dot(ViewNormal, SlicePlaneNormal);
        float3 ProjViewNormal = ViewNormal - SlicePlaneNormal * ViewNormalPlaneDot;
        float ProjNormalLen2 = max(1.0f - ViewNormalPlaneDot * ViewNormalPlaneDot, 0.0f);
        if (ProjNormalLen2 < 1.0e-8f)
            continue;

        float3 Tangent = cross(SlicePlaneNormal, ViewNormal);
        float3 WorldSlicePlaneNormal = REDX11_GTVB_ViewDirToWorldDir(SlicePlaneNormal);
        float3 WorldProjViewNormal = REDX11_GTVB_ViewDirToWorldDir(ProjViewNormal);
        float3 WorldTangent = REDX11_GTVB_ViewDirToWorldDir(Tangent);

        float InvProjNormalLen = rsqrt(ProjNormalLen2);
        float cosN = dot(ProjViewNormal, ViewDir) * InvProjNormalLen;
        float sinN = dot(Tangent, ViewDir) * InvProjNormalLen;
        float BaseHor = 0.5f + 0.5f * sinN;
        float ArcJitter = frac(random.z + (float)SSGISampleIndex * 0.569840296f) * inv32;
        float DirectionStepJitter = frac(random.y + (float)SSGISampleIndex * 0.754877666f);

        float3 SliceGI = float3(0.0f, 0.0f, 0.0f);
        uint OcclusionBits = 0u;
        uint ResolvedGIBits = 0u;

        [unroll]
        for (int Side = -1; Side <= 1; Side += 2)
        {
            float SideF = (float)Side;
            float2 HorizonDir = ScreenSliceDir2D * SideF;
            float3 HorizonRayStep = RayStep * SideF;
            float StepJitter = frac(DirectionStepJitter + ((Side < 0) ? 0.0f : 0.5f));

            [loop]
            for (uint StepIdx = 0u; StepIdx < SSGI_RAYMARCHING_STEP_COUNT; ++StepIdx)
            {
                float u = ((float)StepIdx + StepJitter) * InvStepCount;
                float SampleT = 1.0f + (SSGI_RAYMARCHING_WIDTH - 1.0f) * (u * u);
                float2 SamplePixel = PixelXY + HorizonDir * SampleT;
                float3 SampleViewRay = RayOrigin + HorizonRayStep * SampleT;

                if (any(SamplePixel < 0.0f) || any(SamplePixel >= ViewSize))
                    break;

                uint2 SampleBufferPixel = REDX11_GTVB_ScreenPixelToBufferPixel(SamplePixel);
                float DeviceZ = REDX11_GTVB_LoadDeviceZ(SampleBufferPixel);
                float SampledDepth = REDX11_GTVB_ConvertFromDeviceZ(DeviceZ);
                float3 FrontDelta = SampleViewRay * SampledDepth - ViewPos;
                float3 BackDelta = FrontDelta + SampleViewRay * SSGI_THICKNESS;

                float2 HorCos = float2(
                    dot(FrontDelta, ViewDir) * rsqrt(max(dot(FrontDelta, FrontDelta), 1.0e-8f)),
                    dot(BackDelta, ViewDir) * rsqrt(max(dot(BackDelta, BackDelta), 1.0e-8f)));
                HorCos = (Side >= 0) ? HorCos.xy : HorCos.yx;

                float d05 = SideF * 0.5f;
                float2 Hor01 = BaseHor + d05 - d05 * HorCos;
                Hor01 = saturate(Hor01 + ArcJitter);
                uint2 HorInt = (uint2)floor(Hor01 * 32.0f);
                uint mX = (HorInt.x < 32u) ? (MASK_ALL << HorInt.x) : 0u;
                uint mY = (HorInt.y != 0u) ? (MASK_ALL >> (32u - HorInt.y)) : 0u;
                uint SampleOccBits = mX & mY;

                uint NewlyVisibleBits = SampleOccBits & (~OcclusionBits);
                if (NewlyVisibleBits != 0u)
                {
                    float3 SampledWorldNormal = normalize(REDX11_GTVB_LoadWorldNormal(SampleBufferPixel));
                    float SampleNormalPlaneDot = dot(SampledWorldNormal, WorldSlicePlaneNormal);
                    float ProjSampledLen2 = max(1.0f - SampleNormalPlaneDot * SampleNormalPlaneDot, 0.0f);

                    if (ProjSampledLen2 > 1.0e-8f)
                    {
                        float InvProjSampledLen = rsqrt(ProjSampledLen2);
                        float n = InvProjNormalLen * InvProjSampledLen;
                        float sinPhi = dot(WorldProjViewNormal, SampledWorldNormal) * n;
                        float cosPhi = dot(WorldTangent, SampledWorldNormal) * n;
                        bool FlipT = (cosPhi < 0.0f);
                        if (!FlipT)
                            sinPhi = -sinPhi;
                        bool c = (sinPhi > sinN);
                        float m0 = c ? 1.0f : 0.0f;
                        float m1 = c ? -0.5f : 0.5f;
                        float Hor01Single = m0 + m1 * (cosN * abs(cosPhi) + sinN * sinPhi) + 0.5f * sinN;
                        Hor01Single = saturate(Hor01Single + ArcJitter);
                        uint HorIntSingle = (uint)floor(Hor01Single * 32.0f);
                        uint VisBitsN = (HorIntSingle < 32u) ? (MASK_ALL << HorIntSingle) : 0u;
                        if (!FlipT)
                            VisBitsN = ~VisBitsN;
                        NewlyVisibleBits &= VisBitsN;
                    }

                    if (NewlyVisibleBits != 0u)
                    {
                        ResolvedGIBits |= NewlyVisibleBits;
                        float Visibility = (float)countbits(NewlyVisibleBits) * inv32;
                        float3 SampledRadiance = REDX11_GTVB_LoadSceneRadiance(SampleBufferPixel);
                        SliceGI += SampledRadiance * Visibility;
                    }
                }

                OcclusionBits |= SampleOccBits;
                if (OcclusionBits == MASK_ALL)
                    break;
            }

            if (OcclusionBits == MASK_ALL)
                break;
        }

        float SliceOcclusion = (float)countbits(OcclusionBits) * inv32;
        float SliceScreenGICoverage = (float)countbits(ResolvedGIBits) * inv32;
        AccumulatedGI += SliceGI;
        AccumulatedOcclusion += SliceOcclusion;
        AccumulatedScreenGICoverage += SliceScreenGICoverage;
    }

    float3 GI = AccumulatedGI * InvSSGISampleCount;
    float Occlusion = AccumulatedOcclusion * InvSSGISampleCount;
    float ScreenGICoverage = AccumulatedScreenGICoverage * InvSSGISampleCount;
    FallbackMask = 1.0f - ScreenGICoverage;
    return float4(GI * REDX11_GTVB_OneOverPreExposure(), 1.0f - Occlusion);
}

#undef MATH_PI
#undef SSGI_THICKNESS
#undef SSGI_RAYMARCHING_WIDTH
#undef SSGI_RAYMARCHING_STEP_COUNT
#undef SSGI_RAY_COUNT
#endif
