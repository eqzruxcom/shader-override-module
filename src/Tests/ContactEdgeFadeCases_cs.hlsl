// Constant analytic fixtures trigger FXC's redundant-finite-check warning.
// Keep finite guards and warnings-as-errors in parameterized production code.
#pragma warning(disable : 3577)
#include "../Effects/Lighting/ContactEdgeFade.hlsl"
RWStructuredBuffer<float4> Results : register(u0);
[numthreads(64,1,1)]
void main(uint3 tid:SV_DispatchThreadID)
{
    if(tid.x>=288) return;
    uint preset=tid.x%9+1, shape=(tid.x/9)%2, test=tid.x/18;
    float width=(float)preset*.01f;
    float4 bounds=shape==0?float4(0,0,1,1):float4(.2f,.15f,.8f,.9f);
    float2 uv=.5f;
    float expected=1;
    // Known smoothstep values, plus unaffected right/top/bottom controls.
    if(test<=6) {
        const float positions[7]={0,.25f,.5f,.75f,1,1.5f,-.5f};
        const float values[7]={0,.15625f,.5f,.84375f,1,1,0};
        uv.x=width*positions[test];expected=values[test];
    }
    if(test==7) uv.y=0;
    if(test==8) uv.y=1;
    if(test==9) uv.x=1;
    uv=lerp(bounds.xy,bounds.zw,uv);
    float receiver=1;
    if(test==10) {width=0;uv.x=bounds.x-1;} // Disabled means exact passthrough.
    if(test==11) width=Redx11ContactEdgeWidth(-1);
    if(test==12) width=Redx11ContactEdgeWidth(asfloat(0x7fc00000));
    if(test==13) width=Redx11ContactEdgeWidth(asfloat(0x7f800000));
    if(test==14) {receiver=.5f;expected=1;}
    if(test==15) {bounds.z=bounds.x;expected=0;}
    float confidence=Redx11ContactEdgeConfidence(uv,bounds,width);
    Results[tid.x*2]=float4(confidence,expected,2e-5f,1);
    float hit=Redx11ContactFadeHit(.25f,receiver,uv,bounds,width);
    Results[tid.x*2+1]=float4(hit,1-.75f*min(receiver,expected),2e-5f,1);
}
