#include "../Adapters/3Dmigoto/RuntimeSettings.hlsl"

Texture2D<float4> Redx11Input : register(t0);
SamplerState Redx11LinearClamp : register(s0);

struct Redx11PixelInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

float4 main(Redx11PixelInput input) : SV_Target0
{
    float4 source = Redx11Input.SampleLevel(Redx11LinearClamp, input.uv, 0.0);
    Redx11RuntimeSettings settings = Redx11LoadRuntimeSettings();
    source.rgb = Redx11ApplyRuntimePost(source.rgb, settings);
    return source;
}
