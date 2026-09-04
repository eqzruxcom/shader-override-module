#include "../Effects/Lighting/DiffuseBRDF.hlsl"
#include "../Effects/Lighting/MicroShadows.hlsl"
#include "../Engine/UE4/ShadingModels.hlsl"

struct Redx11LightingSmokeInput
{
    float4 position : SV_Position;
    float3 normal : TEXCOORD0;
    float3 viewDirection : TEXCOORD1;
    float encodedShadingModel : TEXCOORD2;
};

float4 main(Redx11LightingSmokeInput input) : SV_Target0
{
    float3 normal = Redx11SafeNormalize(input.normal);
    float3 viewDirection = Redx11SafeNormalize(input.viewDirection);
    float3 lightDirection = Redx11SafeNormalize(float3(0.4f, 0.6f, 0.7f));
    float noL = saturate(dot(normal, lightDirection));
    float noV = saturate(dot(normal, viewDirection));
    float3 diffuse = Redx11DiffuseEnergyPreservingOrenNayar(
        float3(0.8f, 0.7f, 0.6f),
        0.5f,
        lightDirection,
        viewDirection,
        noL,
        noV);
    float visibility = Redx11DiffuseMicroShadow(noL, 0.75f, 1.0f);
    uint shadingModel = Redx11DecodeUE4ShadingModel(input.encodedShadingModel);
    float supported = shadingModel == REDX11_UE4_SHADINGMODEL_DEFAULT_LIT ? 1.0f : 0.5f;
    return float4(diffuse * visibility * supported, 1.0f);
}
