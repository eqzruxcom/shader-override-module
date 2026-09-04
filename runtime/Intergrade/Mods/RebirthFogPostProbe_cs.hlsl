// Diagnostic-only post marker for the original ef7fe8d9c4e9ad15 dispatch.
// The original pass runs first and is snapshotted at t113. This shader writes
// unmistakable magenta scattering while preserving the original extinction.

Texture3D<float4> RebirthFogSource : register(t113);
RWTexture3D<float4> RebirthFogOutput : register(u0);

[numthreads(4, 4, 4)]
void main(uint3 threadID : SV_DispatchThreadID)
{
    uint width, height, depth;
    RebirthFogOutput.GetDimensions(width, height, depth);
    if (any(threadID >= uint3(width, height, depth)))
        return;

    float4 original = RebirthFogSource.Load(int4(threadID, 0));
    RebirthFogOutput[threadID] = float4(1.0, 0.0, 1.0, original.w);
}
