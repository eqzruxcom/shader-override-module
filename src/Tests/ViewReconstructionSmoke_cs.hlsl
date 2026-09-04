#include "../Engine/UE4/ViewReconstruction.hlsl"

cbuffer Redx11ViewSmokeConstants : register(b0)
{
    float4 Redx11InvDeviceZToWorldZ;
    float4 Redx11ViewRectAndInvSize;
    float4 Redx11BufferInvSizeAndScreenScale;
    float4 Redx11ScreenBiasAndDeviceZ;
    float4x4 Redx11ClipToWorld;
};

RWTexture2D<float4> Redx11ViewSmokeOutput : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    float2 pixel = float2(dispatchThreadId.xy) + 0.5f;
    float worldDepth = Redx11UE4DeviceZToWorldDepth(
        Redx11ScreenBiasAndDeviceZ.z,
        Redx11InvDeviceZToWorldZ);
    float3 worldPosition = Redx11UE4ReconstructWorldPositionFromDeviceZ(
        pixel,
        Redx11ScreenBiasAndDeviceZ.z,
        Redx11BufferInvSizeAndScreenScale.xy,
        Redx11BufferInvSizeAndScreenScale.zw,
        Redx11ScreenBiasAndDeviceZ.xy,
        Redx11ClipToWorld);
    Redx11ViewSmokeOutput[dispatchThreadId.xy] = float4(worldPosition, worldDepth);
}
