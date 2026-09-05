/*
 * ShaderInjector Maximum Quality GTVB -> FF7 Remake Intergrade DX11 adapter.
 * This file contains compatibility wiring only; the donor algorithm is in
 * ThirdParty/ShaderInjector/RebirthGTVB.hlsl.
 */

Texture2D<float4> RemakeDirectLight : register(t0);
Texture2D<float4> RemakeWorldNormal : register(t1);
Texture2D<float> RemakeSceneDepth : register(t2);
Texture2D<float4> RemakeMaterial : register(t3);
RWTexture2D<float4> RebirthGTVBResult : register(u0); // rgb GI, a AO visibility
RWTexture2D<float4> RebirthGTVBCoverage : register(u1); // x fallback mask

cbuffer RemakeView : register(b0)
{
    float4 RemakeViewData[154];
};

float2 Redx11GTVBViewRectMin() { return RemakeViewData[121].xy; }
float2 REDX11_GTVB_ViewSize() { return RemakeViewData[122].xy; }

float REDX11_GTVB_ConvertFromDeviceZ(float deviceZ)
{
    float4 z = RemakeViewData[57];
    return mad(z.x, deviceZ, z.y) + rcp(mad(z.z, deviceZ, -z.w));
}

uint2 REDX11_GTVB_ScreenPixelToBufferPixel(float2 viewPixel)
{
    return (uint2)(viewPixel + Redx11GTVBViewRectMin());
}

float REDX11_GTVB_LoadDeviceZ(uint2 bufferPixel)
{
    return RemakeSceneDepth.Load(int3(bufferPixel, 0));
}

float3 REDX11_GTVB_LoadWorldNormal(uint2 bufferPixel)
{
    return RemakeWorldNormal.Load(int3(bufferPixel, 0)).rgb * 2.0f - 1.0f;
}

float3 REDX11_GTVB_LoadSceneRadiance(uint2 bufferPixel)
{
    return RemakeDirectLight.Load(int3(bufferPixel, 0)).rgb;
}

float3 Redx11GTVBReconstructWorld(float2 viewPixel, float worldDepth)
{
    float2 ndc = viewPixel / REDX11_GTVB_ViewSize() * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f);
    float4 world = ndc.y * worldDepth * RemakeViewData[41];
    world += ndc.x * worldDepth * RemakeViewData[40];
    world += worldDepth * RemakeViewData[42];
    world += RemakeViewData[43];
    return world.xyz / world.w;
}

// A camera-relative world basis is a rigid rotation of Rebirth's view basis.
// It avoids guessing a world-to-view row layout while preserving every angular
// and distance operation in ComputeGTVBGI.
float3 REDX11_GTVB_ScreenPixelToViewRayZ1(float2 viewPixel)
{
    return Redx11GTVBReconstructWorld(viewPixel, 1.0f) - RemakeViewData[59].xyz;
}

float3 REDX11_GTVB_WorldToViewSpace(float3 worldPosition)
{
    return worldPosition - RemakeViewData[59].xyz;
}

float3 REDX11_GTVB_WorldDirToViewDir(float3 worldDirection) { return worldDirection; }
float3 REDX11_GTVB_ViewDirToWorldDir(float3 viewDirection) { return viewDirection; }
int REDX11_GTVB_FrameIndex() { return asint(RemakeViewData[139].w); }
float REDX11_GTVB_OneOverPreExposure() { return RemakeViewData[128].y; }

#include "../../ThirdParty/ShaderInjector/RebirthGTVB.hlsl"

bool Redx11GTVBSupportedShadingModel(uint shadingModel)
{
    return shadingModel == 1u || shadingModel == 2u || shadingModel == 3u
        || shadingModel == 7u || shadingModel == 8u || shadingModel == 9u;
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    uint2 viewPixel = dispatchThreadId.xy;
    uint2 viewSize = (uint2)REDX11_GTVB_ViewSize();
    if (any(viewPixel >= viewSize))
        return;

    uint2 bufferPixel = REDX11_GTVB_ScreenPixelToBufferPixel(viewPixel);
    float deviceDepth = REDX11_GTVB_LoadDeviceZ(bufferPixel);
    uint shadingModel = (uint)(RemakeMaterial.Load(int3(bufferPixel, 0)).a * 255.0f + 0.5f) & 15u;

    if (deviceDepth <= 1.0e-7f || !Redx11GTVBSupportedShadingModel(shadingModel))
    {
        RebirthGTVBResult[bufferPixel] = float4(0.0f, 0.0f, 0.0f, 1.0f);
        RebirthGTVBCoverage[bufferPixel] = float4(1.0f, 0.0f, 0.0f, 0.0f);
        return;
    }

    float worldDepth = REDX11_GTVB_ConvertFromDeviceZ(deviceDepth);
    float2 viewPixelCenter = (float2)viewPixel + 0.5f;
    float3 worldPosition = Redx11GTVBReconstructWorld(viewPixelCenter, worldDepth);
    float3 worldNormal = normalize(REDX11_GTVB_LoadWorldNormal(bufferPixel));
    float normalBias = shadingModel == 7u ? 0.1f : 0.0005f;
    float3 rayOrigin = worldPosition + worldNormal * normalBias;
    rayOrigin += worldNormal * 0.025f * deviceDepth;

    float fallbackMask;
    float4 gtvb = ComputeGTVBGI(viewPixelCenter, rayOrigin, worldNormal, fallbackMask);
    RebirthGTVBResult[bufferPixel] = gtvb;
    RebirthGTVBCoverage[bufferPixel] = float4(fallbackMask, 0.0f, 0.0f, 0.0f);
}
