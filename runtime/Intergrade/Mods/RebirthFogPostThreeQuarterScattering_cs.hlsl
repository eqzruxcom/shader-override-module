// Temporally compensated three-quarter-scattering post.
// For a pass blending 15% current scattering with 85% history, the scale
// R / (0.15 + 0.85 * R) targets steady-state scattering ratio R.

Texture3D<float4> RebirthFogSource : register(t113);
RWTexture3D<float4> RebirthFogOutput : register(u0);

[numthreads(4, 4, 4)]
void main(uint3 threadID : SV_DispatchThreadID)
{
    uint width, height, depth;
    RebirthFogOutput.GetDimensions(width, height, depth);
    if (any(threadID >= uint3(width, height, depth)))
        return;

    float4 value = RebirthFogSource.Load(int4(threadID, 0));
    static const float THREE_QUARTER_SCATTERING_HISTORY_SCALE = 0.9523809524;
    RebirthFogOutput[threadID] = float4(
        value.xyz * THREE_QUARTER_SCATTERING_HISTORY_SCALE,
        value.w);
}
