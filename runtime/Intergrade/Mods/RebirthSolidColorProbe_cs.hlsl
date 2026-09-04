RWTexture3D<float4> OutputVolume : register(u0);

[numthreads(4, 4, 4)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    OutputVolume[dispatchThreadId] = float4(1.0, 0.0, 1.0, 1.0);
}
