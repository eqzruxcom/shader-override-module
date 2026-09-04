// Offline replay of the production kernel against captured game resources.
#define main ContactVisibilityMain
#if defined(REDX11_REPLAY_SHARED)
#include "../Adapters/FF7RemakeIntergrade/RebirthContactShared.hlsl"
#elif defined(REDX11_REPLAY_QUAD_RECONSTRUCTION)
#include "../Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl"
#elif defined(REDX11_REPLAY_REBIRTH)
#include "../Adapters/FF7RemakeIntergrade/RebirthContactShadowKernel_ps.hlsl"
#else
#include "../Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl"
#endif
#undef main
cbuffer ReplayDispatch : register(b13) { uint4 Replay; }; // width,height,stride,light
RWStructuredBuffer<float> ReplayOutput : register(u0);
#if defined(REDX11_REPLAY_SHARED)
[numthreads(16,16,1)]
#else
[numthreads(8,8,1)]
#endif
void main(uint3 id : SV_DispatchThreadID, uint3 local : SV_GroupThreadID)
{
    uint2 grid = (Replay.xy + Replay.zz - 1) / Replay.zz;
#if defined(REDX11_REPLAY_REBIRTH)
    // Every lane of sparse absolute-screen quads, not just one parity.
    grid *= 2;
#endif
#if !defined(REDX11_REPLAY_SHARED)
    if (any(id.xy >= grid)) return;
#endif
#if defined(REDX11_REPLAY_REBIRTH)
    uint2 pixel = (id.xy >> 1) * Replay.z + (id.xy & 1);
    float3 input = float3((float2)pixel, asfloat(Replay.w));
    uint offset = (id.y * grid.x + id.x) * 2;
#if defined(REDX11_REPLAY_SHARED)
    // Sparse complete 2x2 quads retain exact neighbor/parity mapping within
    // local 2x2 quads. This is not the native contiguous tile dispatch layout.
    // Partial final groups MUST synchronize before out-of-grid threads leave.
    float visibility=Redx11RemakeSharedContact(pixel,local.xy,Replay.w);
    if(any(id.xy>=grid)) return;
    ReplayOutput[offset]=visibility;
#else
    ReplayOutput[offset] = ContactVisibilityMain(input);
#endif
    bool valid;
    Redx11RemakeContactPixel(input, false, valid);
    ReplayOutput[offset + 1] = valid ? 1.0f : 0.0f;
#else
    float3 input = float3((float2)(id.xy * Replay.z), asfloat(Replay.w));
    ReplayOutput[id.y * grid.x + id.x] = ContactVisibilityMain(input);
#endif
}
