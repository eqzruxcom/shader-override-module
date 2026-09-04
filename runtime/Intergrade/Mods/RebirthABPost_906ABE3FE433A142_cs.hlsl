// Hardcoded half-scattering post used behind a 3Dmigoto command-list gate.
// Runtime enable/bypass is evaluated by 3Dmigoto, so this shader does not
// depend on IniParams being visible inside the nested dispatch.

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
    RebirthFogOutput[threadID] = float4(value.xyz * 0.5, value.w);
}
