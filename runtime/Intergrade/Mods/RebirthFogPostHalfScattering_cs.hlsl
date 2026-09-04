// Temporally compensated half-scattering post.
// The source pass blends 15% current scattering with 85% history. Because
// this result feeds the next frame's history, a direct 0.5 multiplier settles
// near 13%. A multiplier of 0.5 / (0.15 + 0.85 * 0.5) targets 50% steady state.

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
    static const float HALF_SCATTERING_HISTORY_SCALE = 0.8695652174;
    RebirthFogOutput[threadID] = float4(
        value.xyz * HALF_SCATTERING_HISTORY_SCALE,
        value.w);
}
