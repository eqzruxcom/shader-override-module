// Non-amplifying diagnostic using an explicitly bound IniParams SRV.
// The wrapper binds 3Dmigoto's IniParams resource at t114, independently of
// the globally pinned register. Green means all expected constants arrived;
// red means one or more did not.

Texture3D<float4> RebirthFogSource : register(t113);
Texture1D<float4> RebirthIniParams : register(t114);
RWTexture3D<float4> RebirthFogOutput : register(u0);

[numthreads(4, 4, 4)]
void main(uint3 threadID : SV_DispatchThreadID)
{
    uint width, height, depth;
    RebirthFogOutput.GetDimensions(width, height, depth);
    if (any(threadID >= uint3(width, height, depth)))
        return;

    float enabled = RebirthIniParams.Load(100).x;
    float4 controls = RebirthIniParams.Load(103);
    bool expected =
        abs(enabled - 1.0) < 0.001 &&
        abs(controls.x - 0.0) < 0.001 &&
        abs(controls.y - 1.0) < 0.001 &&
        abs(controls.z - 0.85) < 0.001;

    float4 original = RebirthFogSource.Load(int4(threadID, 0));
    float scatteringMagnitude = max(original.x, max(original.y, original.z));
    float3 marker = expected
        ? float3(0.0, scatteringMagnitude, 0.0)
        : float3(scatteringMagnitude, 0.0, 0.0);
    RebirthFogOutput[threadID] = float4(marker, original.w);
}