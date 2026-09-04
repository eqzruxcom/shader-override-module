// SM5 plumbing around the pinned donor ray and checkerboard/AVG statements.
// Call once per light from a group-uniform boundary, with all 16x16 threads.
// Never call this from the per-pixel native-contribution branch.
#define REDX11_CONTACT_OMIT_ENTRY
#include "RebirthContactShadowKernel_ps.hlsl"
#undef REDX11_CONTACT_OMIT_ENTRY
#include "../../ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl"

groupshared float Redx11ContactQuadRays[256];

float Redx11RemakeSharedContact(uint2 pixel, uint2 localPixel, uint lightIndex)
{
    float visibility=1.0f;
    float4 control=ContactControl.Load(int2(31,0));
    // These values must be group-uniform. Odd viewport origins would split
    // absolute-screen quads across groups; fail neutral until supported.
    bool active=control.x==1.0f && control.z>0.0f && lightIndex<256u;
    active=active && (control.y<0.0f || lightIndex==(uint)control.y);
    active=active && all((asuint(DispatchData[1].xy)&1u)==0u);
    if(active)
    {
        float phase=(float)asint(ViewData[139].z);
        bool traced=Redx11RebirthCheckerboard((int2)pixel,float4(phase,0,0,0));
        bool valid;
        visibility=Redx11RemakeContactPixel(float3((float2)pixel,asfloat(lightIndex)),traced,valid);
        uint lane=localPixel.y*16u+localPixel.x;
        Redx11ContactQuadRays[lane]=visibility;
        GroupMemoryBarrierWithGroupSync();
        if(!traced && valid)
        {
            uint2 basePixel=localPixel&~1u;
            uint baseLane=basePixel.y*16u+basePixel.x;
            float4 rays=float4(Redx11ContactQuadRays[baseLane],Redx11ContactQuadRays[baseLane+1u],
                              Redx11ContactQuadRays[baseLane+16u],Redx11ContactQuadRays[baseLane+17u]);
            visibility=Redx11RebirthQuadAverage(rays);
        }
        // All readers must finish before the next native light reuses storage.
        GroupMemoryBarrierWithGroupSync();
        visibility=lerp(1.0f,visibility,saturate(control.z));
    }
    return visibility;
}
