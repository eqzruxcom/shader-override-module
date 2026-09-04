#ifndef REDX11_IMAGE_ADJUSTMENTS_HLSL
#define REDX11_IMAGE_ADJUSTMENTS_HLSL

#include "../Common/Color.hlsl"

struct Redx11ImageAdjustmentSettings
{
    float brightnessEV;
    float contrast;
    float contrastPivot;
    float saturation;
    float vibrance;
    float gamma;
    float3 lift;
    float3 gain;
    float3 tintColor;
    float tintFactor;
};

Redx11ImageAdjustmentSettings Redx11NeutralImageAdjustmentSettings()
{
    Redx11ImageAdjustmentSettings settings;
    settings.brightnessEV = 0.0f;
    settings.contrast = 1.0f;
    settings.contrastPivot = 0.18f;
    settings.saturation = 1.0f;
    settings.vibrance = 0.0f;
    settings.gamma = 1.0f;
    settings.lift = 0.0f;
    settings.gain = 1.0f;
    settings.tintColor = 1.0f;
    settings.tintFactor = 0.0f;
    return settings;
}

float3 Redx11ApplyImageAdjustments(
    float3 inputColor,
    Redx11ImageAdjustmentSettings settings)
{
    float3 color = inputColor + settings.lift;
    color *= exp2(settings.brightnessEV);
    color *= settings.gain;
    color = (color - settings.contrastPivot) * settings.contrast + settings.contrastPivot;
    color = max(color, 0.0f);

    float luminance = Redx11LuminanceRec709(color);
    color = lerp(luminance.xxx, color, settings.saturation);

    luminance = Redx11LuminanceRec709(color);
    float channelMax = max(color.r, max(color.g, color.b));
    float channelMin = min(color.r, min(color.g, color.b));
    float chroma = channelMax - channelMin;
    float vibranceAmount = settings.vibrance * (1.0f - saturate(chroma));
    color = lerp(luminance.xxx, color, max(0.0f, 1.0f + vibranceAmount));

    float3 tintMultiplier = lerp(
        1.0f.xxx,
        max(settings.tintColor, 0.0f),
        saturate(settings.tintFactor)
    );
    color *= tintMultiplier;

    float safeGamma = max(settings.gamma, 1.0e-4f);
    return pow(max(color, 0.0f), rcp(safeGamma));
}

#endif

