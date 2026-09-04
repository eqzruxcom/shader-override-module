#include "../Effects/Post/ImageAdjustments.hlsl"
#include "../Effects/Post/Tonemaps.hlsl"

Texture2D<float4> Redx11SourceColor : register(t0);
SamplerState Redx11LinearClamp : register(s0);

cbuffer Redx11TestParameters : register(b0)
{
    // x: brightness EV, y: contrast, z: pivot, w: saturation
    float4 Redx11Adjustment0;
    // x: vibrance, y: gamma, z: tint factor, w: tonemap mode
    float4 Redx11Adjustment1;
    float4 Redx11Lift;
    float4 Redx11Gain;
    float4 Redx11Tint;
};

struct Redx11PixelInput
{
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float4 main(Redx11PixelInput input) : SV_TARGET
{
    float3 color = Redx11SourceColor.SampleLevel(Redx11LinearClamp, input.uv, 0.0f).rgb;

    Redx11ImageAdjustmentSettings settings = Redx11NeutralImageAdjustmentSettings();
    settings.brightnessEV = Redx11Adjustment0.x;
    settings.contrast = Redx11Adjustment0.y;
    settings.contrastPivot = Redx11Adjustment0.z;
    settings.saturation = Redx11Adjustment0.w;
    settings.vibrance = Redx11Adjustment1.x;
    settings.gamma = Redx11Adjustment1.y;
    settings.tintFactor = Redx11Adjustment1.z;
    settings.lift = Redx11Lift.rgb;
    settings.gain = Redx11Gain.rgb;
    settings.tintColor = Redx11Tint.rgb;

    color = Redx11ApplyImageAdjustments(color, settings);
    color = Redx11ApplyTonemap(color, (uint)Redx11Adjustment1.w);
    return float4(color, 1.0f);
}

