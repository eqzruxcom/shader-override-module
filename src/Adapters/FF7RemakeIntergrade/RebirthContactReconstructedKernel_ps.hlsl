// Offline SM5 reconstruction prototype. Not selected by the runtime stager.
// Recompute donor-selected neighbors instead of unsafe cross-thread barriers
// inside the native divergent per-light loop. Approximately 1.5 rays/pixel,
// versus donor checkerboarding's 0.5; not a performance-equivalent port.
#define REDX11_CONTACT_OMIT_ENTRY
#include "RebirthContactShadowKernel_ps.hlsl"
#undef REDX11_CONTACT_OMIT_ENTRY
#include "../../ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl"

float main(float3 input : TEXCOORD0) : SV_Target0
{
    int2 pixel=(int2)input.xy;
    // Explicit provisional phase adapter: captured native eight-phase index
    // equals the apparent TAA sample index (5). Reset/cut equivalence to the
    // donor's TemporalAAParams.x has NOT been observed across native frames.
    float phase=(float)asint(ViewData[139].z);
    bool traced=Redx11RebirthCheckerboard(pixel,float4(phase,0,0,0));
    bool receiverValid;
    float visibility=Redx11RemakeContactPixel(input,traced,receiverValid);
    if(!receiverValid) return 1.0f;
    if(!traced)
    {
        int2 basePixel=pixel&~1;
        float4 lanes=1.0f;
        // Quad lane order: upper-left, upper-right, lower-left, lower-right.
        // Both selected pixels belong to this exact 2x2 quad, not arbitrary
        // adjacent native CS lanes. Each reconstructs its own surface/normal.
        [unroll] for(int lane=0;lane<4;++lane)
        {
            int2 neighbor=basePixel+int2(lane&1,lane>>1);
            if(Redx11RebirthCheckerboard(neighbor,float4(phase,0,0,0)))
            {
                bool neighborValid;
                lanes[lane]=Redx11RemakeContactPixel(float3((float2)neighbor,input.z),true,neighborValid);
            }
        }
        visibility=Redx11RebirthQuadAverage(lanes);
    }
    return lerp(1.0f,visibility,saturate(ContactControl.Load(int2(31,0)).z));
}
