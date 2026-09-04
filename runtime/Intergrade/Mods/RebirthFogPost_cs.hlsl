// Post-control for Intergrade's original volumetric scattering/history dispatch.
// The original ef7fe8d9c4e9ad15 compute shader runs first. At neutral values this
// shader returns without writing, preserving the game's UAV output bit-for-bit.

Texture3D<float4> RebirthFogSource : register(t113);
// The wrapper explicitly binds 3Dmigoto's IniParams SRV here. Do not rely on
// the globally pinned register inside a nested custom-shader dispatch.
Texture1D<float4> IniParams : register(t114);
RWTexture3D<float4> RebirthFogOutput : register(u0);

[numthreads(4, 4, 4)]
void main(uint3 threadID : SV_DispatchThreadID)
{
    uint width, height, depth;
    RebirthFogOutput.GetDimensions(width, height, depth);
    if (any(threadID >= uint3(width, height, depth)))
        return;

    float enabled = saturate(IniParams.Load(100).x);
    float4 controls = IniParams.Load(103);
    float scatteringScale = lerp(1.0, max(0.0, controls.x), enabled);
    float extinctionScale = lerp(1.0, max(0.0, controls.y), enabled);

    // Do not even rewrite the UAV in neutral/bypassed mode.
    if (scatteringScale == 1.0 && extinctionScale == 1.0)
        return;

    float4 value = RebirthFogSource.Load(int4(threadID, 0));
    value.xyz *= scatteringScale;
    value.w *= extinctionScale;
    RebirthFogOutput[threadID] = value;
}
