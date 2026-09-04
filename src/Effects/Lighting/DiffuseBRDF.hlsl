#ifndef REDX11_DIFFUSE_BRDF_HLSL
#define REDX11_DIFFUSE_BRDF_HLSL

#include "../Common/Math.hlsl"

static const float REDX11_PI_INV = 0.3183098861837907f;
static const float REDX11_FON_COEFFICIENT = 0.287793409210806f;

float3 Redx11DiffuseLambert(float3 diffuseColor)
{
    return diffuseColor * REDX11_PI_INV;
}

float3 Redx11DiffuseBurley(
    float3 diffuseColor,
    float roughness,
    float noV,
    float noL,
    float voH)
{
    float fd90 = 0.5f + 2.0f * voH * voH * roughness;
    float fdV = 1.0f + (fd90 - 1.0f) * Redx11Pow5(1.0f - noV);
    float fdL = 1.0f + (fd90 - 1.0f) * Redx11Pow5(1.0f - noL);
    return diffuseColor * (REDX11_PI_INV * fdV * fdL);
}

float3 Redx11DiffuseOrenNayar(
    float3 diffuseColor,
    float roughness,
    float noV,
    float noL,
    float voH)
{
    float variance = roughness * roughness;
    float varianceSquared = variance * variance;
    float voL = 2.0f * voH * voH - 1.0f;
    float cosRelativeAzimuth = voL - noV * noL;
    float c1 = 1.0f - 0.5f * varianceSquared / (varianceSquared + 0.33f);
    float c2 = 0.45f * varianceSquared / (varianceSquared + 0.09f);
    c2 *= cosRelativeAzimuth;
    c2 *= cosRelativeAzimuth >= 0.0f ? rcp(max(noL, noV)) : 1.0f;
    return diffuseColor * REDX11_PI_INV * (c1 + c2) * (1.0f + roughness * 0.5f);
}

// Energy-preserving Oren-Nayar approximation used by the Rebirth injector,
// adapted to a portable isotropic SM5 interface.
float3 Redx11DiffuseEnergyPreservingOrenNayar(
    float3 diffuseColor,
    float roughness,
    float3 lightDirection,
    float3 viewDirection,
    float noL,
    float noV)
{
    float projectedCorrelation = dot(lightDirection, viewDirection) - noL * noV;
    float denominator = max(max(noL, noV), 1.0e-4f);
    float correlation = projectedCorrelation > 0.0f
        ? projectedCorrelation / denominator
        : projectedCorrelation;
    float energyScale = (1.0f - REDX11_FON_COEFFICIENT * roughness)
        * (1.0f + roughness * correlation);
    return diffuseColor * (energyScale * noL * REDX11_PI_INV);
}

#endif
