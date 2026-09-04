// Diagnostic replacement for FF7 Remake Intergrade ps:e2aa1c8cb39e0a55.
// t11 is proven by frame capture to be the exact o0 handle written by
// ps:b2bc6059f9a39c7f on the immediately preceding draw.
Texture2D<float4> SsrBuffer : register(t11);
SamplerState SsrSampler : register(s9);

float4 main(float4 texcoord : TEXCOORD0) : SV_Target0
{
    float4 ssr = SsrBuffer.SampleLevel(SsrSampler, texcoord.xy, 0.0);
    float hit = saturate(ssr.a);
    return float4(hit, hit, hit, 1.0);
}