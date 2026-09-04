// Diagnostic replacement for FF7 Remake Intergrade ps:e2aa1c8cb39e0a55.
// t11 is proven by frame capture to be the exact o0 handle written by
// ps:b2bc6059f9a39c7f on the immediately preceding draw.
Texture2D<float4> SsrBuffer : register(t11);
SamplerState SsrSampler : register(s9);

float4 main(float4 texcoord : TEXCOORD0) : SV_Target0
{
    float4 ssr = SsrBuffer.SampleLevel(SsrSampler, texcoord.xy, 0.0);
    float luminance = dot(abs(ssr.rgb), float3(0.2126, 0.7152, 0.0722));
    float present = luminance >= 0.00001 ? 1.0 : 0.0;
    return float4(0.0, present, present, 1.0);
}