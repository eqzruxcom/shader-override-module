#ifndef REDX11_MICRO_SHADOWS_HLSL
#define REDX11_MICRO_SHADOWS_HLSL

#include "../Common/Math.hlsl"

float Redx11MicroShadowUncharted4(float ambientOcclusion, float noL, float opacity)
{
    float aperture = 2.0f * ambientOcclusion * ambientOcclusion;
    float visibility = saturate(noL + aperture - 1.0f);
    return lerp(1.0f, visibility, saturate(opacity));
}

float Redx11CombineMicroOcclusion(float screenAO, float materialAO)
{
    float product = screenAO * materialAO;
    float lower = min(screenAO, materialAO);
    float remapped = product + 1.0f - lower;
    float complement = 1.0f - Redx11Pow5(remapped);
    return lower + Redx11Pow5(complement) * (product - lower);
}

float Redx11DiffuseMicroShadow(float noL, float microAO, float attenuation)
{
    float aperture = sqrt(max(0.0f, 1.0f - microAO));
    float visibility = saturate(noL / max(1.0e-3f, aperture));
    return min(attenuation, visibility * visibility);
}

float Redx11SpecularMicroShadow(
    float noL,
    float absNoV,
    float roughness,
    float microAO,
    float attenuation)
{
    float aoRemainder = sqrt(max(0.0f, 1.0f - microAO));
    float roughMask = saturate(roughness * 3.5f - 0.5f);
    float roughWeight = saturate(1.0f - Redx11Pow5(1.0f - roughMask));
    float grazing = Redx11Pow4(1.0f - absNoV) * aoRemainder * roughWeight;
    float visibility = saturate(noL / max(1.0e-3f, grazing));
    return min(attenuation, visibility * visibility);
}

#endif
