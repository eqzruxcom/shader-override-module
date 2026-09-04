#ifndef REDX11_COLOR_HLSL
#define REDX11_COLOR_HLSL

#include "Math.hlsl"

float Redx11LuminanceRec709(float3 linearColor)
{
    return dot(linearColor, float3(0.212639f, 0.715169f, 0.072192f));
}

float3 Redx11SRGBToLinear(float3 color)
{
    float3 low = color / 12.92f;
    float3 high = Redx11PositivePow((color + 0.055f) / 1.055f, 2.4f);

    return float3(
        color.r <= 0.04045f ? low.r : high.r,
        color.g <= 0.04045f ? low.g : high.g,
        color.b <= 0.04045f ? low.b : high.b
    );
}

float3 Redx11LinearToSRGB(float3 color)
{
    color = max(color, 0.0f);
    float3 low = color * 12.92f;
    float3 high = Redx11PositivePow(color, 1.0f / 2.4f) * 1.055f - 0.055f;

    return float3(
        color.r <= 0.0031308f ? low.r : high.r,
        color.g <= 0.0031308f ? low.g : high.g,
        color.b <= 0.0031308f ? low.b : high.b
    );
}

#endif

