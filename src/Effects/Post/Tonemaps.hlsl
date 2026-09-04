#ifndef REDX11_TONEMAPS_HLSL
#define REDX11_TONEMAPS_HLSL

// Initial SM5-safe subset of the MIT-licensed Rebirth tonemap library. More
// expensive operators will be added only after the Intergrade final pass is
// captured and its color domain is verified.

#define REDX11_TONEMAP_NONE             0u
#define REDX11_TONEMAP_REINHARD         1u
#define REDX11_TONEMAP_REINHARD2        2u
#define REDX11_TONEMAP_ACES_2015        3u
#define REDX11_TONEMAP_ACES_FITTED      4u
#define REDX11_TONEMAP_FILMIC           5u
#define REDX11_TONEMAP_UNCHARTED2       6u
#define REDX11_TONEMAP_UNREAL3          7u
#define REDX11_TONEMAP_KHRONOS_NEUTRAL  8u

float3 Redx11TonemapReinhard(float3 color)
{
    return color / (1.0f + color);
}

float3 Redx11TonemapReinhard2(float3 color, float whitePoint)
{
    float whiteSquared = max(whitePoint * whitePoint, 1.0e-6f);
    return color * (1.0f + color / whiteSquared) / (1.0f + color);
}

float3 Redx11TonemapAces2015(float3 color)
{
    const float a = 2.51f;
    const float b = 0.03f;
    const float c = 2.43f;
    const float d = 0.59f;
    const float e = 0.14f;
    return saturate(color * (a * color + b) / (color * (c * color + d) + e));
}

static const float3x3 Redx11AcesInputMatrix = float3x3(
    0.59719f, 0.35458f, 0.04823f,
    0.07600f, 0.90834f, 0.01566f,
    0.02840f, 0.13383f, 0.83777f
);

static const float3x3 Redx11AcesOutputMatrix = float3x3(
     1.60475f, -0.53108f, -0.07367f,
    -0.10208f,  1.10813f, -0.00605f,
    -0.00327f, -0.07276f,  1.07602f
);

float3 Redx11AcesRrtOdtFit(float3 value)
{
    float3 numerator = value * (value + 0.0245786f) - 0.000090537f;
    float3 denominator = value * (0.983729f * value + 0.4329510f) + 0.238081f;
    return numerator / denominator;
}

float3 Redx11TonemapAcesFitted(float3 color)
{
    color = mul(Redx11AcesInputMatrix, color);
    color = Redx11AcesRrtOdtFit(color);
    color = mul(Redx11AcesOutputMatrix, color);
    return saturate(color);
}

float3 Redx11TonemapFilmic(float3 color)
{
    float3 x = max(0.0f, color - 0.004f);
    float3 mapped = x * (6.2f * x + 0.5f) / (x * (6.2f * x + 1.7f) + 0.06f);
    return pow(mapped, 2.2f);
}

float3 Redx11Uncharted2Curve(float3 color)
{
    const float a = 0.15f;
    const float b = 0.50f;
    const float c = 0.10f;
    const float d = 0.20f;
    const float e = 0.02f;
    const float f = 0.30f;
    return ((color * (a * color + c * b) + d * e) /
            (color * (a * color + b) + d * f)) - e / f;
}

float3 Redx11TonemapUncharted2(float3 color)
{
    const float exposureBias = 2.0f;
    const float whitePoint = 11.2f;
    float3 white = Redx11Uncharted2Curve(whitePoint.xxx);
    return Redx11Uncharted2Curve(exposureBias * color) / max(white, 1.0e-6f);
}

float3 Redx11TonemapUnreal3(float3 color)
{
    return color / (color + 0.155f) * 1.019f;
}

float3 Redx11TonemapKhronosNeutral(float3 color)
{
    const float compressionStart = 0.76f;
    const float desaturation = 0.15f;

    float minimumChannel = min(color.r, min(color.g, color.b));
    float offset = minimumChannel < 0.08f
        ? minimumChannel - 6.25f * minimumChannel * minimumChannel
        : 0.04f;
    color -= offset;

    float peak = max(color.r, max(color.g, color.b));
    if (peak < compressionStart)
        return color;

    const float distanceToWhite = 1.0f - compressionStart;
    float newPeak = 1.0f - distanceToWhite * distanceToWhite /
        (peak + distanceToWhite - compressionStart);
    color *= newPeak / max(peak, 1.0e-6f);

    float desaturationAmount = 1.0f - 1.0f /
        (desaturation * (peak - newPeak) + 1.0f);
    return lerp(color, newPeak.xxx, desaturationAmount);
}

float3 Redx11ApplyTonemap(float3 color, uint mode)
{
    color = max(color, 0.0f);

    if (mode == REDX11_TONEMAP_REINHARD)
        return Redx11TonemapReinhard(color);
    if (mode == REDX11_TONEMAP_REINHARD2)
        return Redx11TonemapReinhard2(color, 4.0f);
    if (mode == REDX11_TONEMAP_ACES_2015)
        return Redx11TonemapAces2015(color);
    if (mode == REDX11_TONEMAP_ACES_FITTED)
        return Redx11TonemapAcesFitted(color);
    if (mode == REDX11_TONEMAP_FILMIC)
        return Redx11TonemapFilmic(color);
    if (mode == REDX11_TONEMAP_UNCHARTED2)
        return Redx11TonemapUncharted2(color);
    if (mode == REDX11_TONEMAP_UNREAL3)
        return Redx11TonemapUnreal3(color);
    if (mode == REDX11_TONEMAP_KHRONOS_NEUTRAL)
        return Redx11TonemapKhronosNeutral(color);

    return color;
}

#endif

