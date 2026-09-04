#ifndef REDX11_3DMIGOTO_RUNTIME_SETTINGS_HLSL
#define REDX11_3DMIGOTO_RUNTIME_SETTINGS_HLSL

#include "../../Effects/Post/ImageAdjustments.hlsl"
#include "../../Effects/Post/Tonemaps.hlsl"

#ifndef REDX11_INI_REGISTER
#define REDX11_INI_REGISTER t120
#endif

Texture1D<float4> Redx11IniParams : register(REDX11_INI_REGISTER);

static const int REDX11_INI_ROW_IMAGE_A = 100;
static const int REDX11_INI_ROW_IMAGE_B = 101;
static const int REDX11_INI_ROW_TINT = 102;

struct Redx11RuntimeSettings
{
    bool enabled;
    Redx11ImageAdjustmentSettings image;
    uint tonemapMode;
};

float4 Redx11LoadIniRow(int row)
{
    return Redx11IniParams.Load(int2(row, 0));
}

Redx11RuntimeSettings Redx11LoadRuntimeSettings()
{
    float4 imageA = Redx11LoadIniRow(REDX11_INI_ROW_IMAGE_A);
    float4 imageB = Redx11LoadIniRow(REDX11_INI_ROW_IMAGE_B);
    float4 tint = Redx11LoadIniRow(REDX11_INI_ROW_TINT);

    Redx11RuntimeSettings settings;
    settings.enabled = imageA.x >= 0.5;
    settings.image = Redx11NeutralImageAdjustmentSettings();
    settings.image.brightnessEV = imageA.y;
    settings.image.contrast = imageA.z;
    settings.image.contrastPivot = imageA.w;
    settings.image.saturation = imageB.x;
    settings.image.vibrance = imageB.y;
    settings.image.gamma = imageB.z;
    settings.image.tintColor = tint.xyz;
    settings.image.tintFactor = tint.w;
    settings.tonemapMode = (uint)max(0.0, floor(imageB.w + 0.5));
    return settings;
}

float3 Redx11ApplyRuntimePost(float3 color, Redx11RuntimeSettings settings)
{
    if (!settings.enabled)
    {
        return color;
    }

    float3 adjusted = Redx11ApplyImageAdjustments(color, settings.image);
    return Redx11ApplyTonemap(adjusted, settings.tonemapMode);
}

#endif
