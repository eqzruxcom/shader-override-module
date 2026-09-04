// Finite literal test endpoints trigger FXC's redundant-isfinite warning.
// Keep finite validation in the helper; suppress only in this analytic fixture.
#pragma warning(disable : 3577)
#include "../Effects/Lighting/ContactViewportClip.hlsl"
RWStructuredBuffer<float4> Results : register(u0);

// 16 interval cases, mirrored/rotated over all four viewport sides.
// actual enterT, expected enterT, tolerance, remaining-contract pass flag.
[numthreads(64,1,1)]
void main(uint3 thread : SV_DispatchThreadID)
{
    uint test = thread.x % 16u;
    uint edge = thread.x / 16u;
    float4 a=float4(0,0,.5f,1), b=float4(.5f,0,.5f,1);
    float expectedEnter=0, expectedExit=1;
    bool expectedVisible=true;
    if(test==1) { a.x=0; b.x=2; expectedExit=.5f; }
    if(test==2) { a.x=-1.1f; b.x=-.5f; expectedEnter=1.0f/6.0f; }
    if(test==3) { a.x=-1.1f; b.x=-2; expectedVisible=false; }
    if(test==4) { a.x=-2; b.x=2; expectedEnter=.25f; expectedExit=.75f; }
    if(test==5) { a=float4(-2,0,.5f,1); b=float4(0,0,.5f,2); expectedEnter=1.0f/3.0f; }
    if(test==6) { b=a; }
    if(test==7) { a.x=-2; b=a; expectedVisible=false; }
    if(test==8) { a.x=-1.0001f; b.x=-.9f; expectedEnter=(-1-a.x)/(b.x-a.x); }
    if(test==9) { b.x=1; }
    if(test==10) { a.x=-1; b.x=-2; expectedVisible=false; }
    if(test==11) { a.x=2; b.x=0; expectedEnter=.5f; }
    if(test==12) { a=float4(0,0,.5f,1); b=float4(0,0,.5f,-1); expectedExit=(1-1e-5f)/2; }
    if(test==13) { a.x=asfloat(0x7fc00000); expectedVisible=false; }
    if(test==14) { a=float4(-2,-3,.5f,1); b=float4(0,0,.5f,1); expectedEnter=2.0f/3.0f; }
    if(test==15) { a.w=-1; b.w=-2; expectedVisible=false; }
    if(edge==1) { a.x=-a.x; b.x=-b.x; }
    if(edge==2) { a.xy=a.yx; b.xy=b.yx; }
    if(edge==3) { a.xy=-a.yx; b.xy=-b.yx; }
    float first,last;
    bool visible=Redx11ContactClipViewportSegment(a,b,first,last);
    bool correct=visible==expectedVisible;
    if(expectedVisible) correct=correct && abs(last-expectedExit)<2e-5f;
    // An outside-to-inside start is the specific regression: the former
    // endpoint-only clipping leaves its first UV outside and the ray loop stops.
    if(test==2) correct=correct && first>0 && first<1;
    Results[thread.x]=float4(expectedVisible?first:0,expectedVisible?expectedEnter:0,2e-5f,correct?1:0);
}
