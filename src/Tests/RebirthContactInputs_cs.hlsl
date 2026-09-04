// Focused shader-side contract tests. Synthetic inputs, not a frame capture.
#pragma warning(disable : 3577)
#include "../Effects/Lighting/RebirthContactShadows.hlsl"
#include "../Adapters/FF7RemakeIntergrade/RebirthContactInputMapping.hlsl"
RWStructuredBuffer<float> Results : register(u0);
cbuffer DonorInputTiming : register(b13) { uint4 FixtureTiming[8]; };
float Redx11ContactSampleDeviceDepth(float2 uv) { return .08f; }

Redx11ContactView InputFixtureView()
{
    Redx11ContactView v;
    v.translatedWorldToClip=float4x4(.1f,0,0,0, 0,.1f,0,0, 0,0,.01f,0, 0,0,0,1);
    v.invDeviceZToWorldZ=float4(100,-1,0,-1);
    v.bufferSize=128;v.invBufferSize=1/v.bufferSize;
    v.projectionScale=1;v.perspective=0;
    v.ndcToBufferScale=float2(.5f,-.5f);v.ndcToBufferBias=.5f;
    v.viewportUVBounds=float4(0,0,1,1);
    v.screenLinearToWorld=float4x4(10,0,0,0, 0,10,0,0, 0,0,1,0, 0,0,0,1);
    v.worldToTranslatedWorld=0;v.pointSampledDepth=0;
    return v;
}
float InputFixtureVisibility(uint material,float depthBias,float hairBias)
{
    Redx11ContactSettings s=Redx11ContactDonorSettings();
    s.rayLength=5;s.lightExclusionFraction=0;s.normalBiasScale=0;
    s.depthBiasScale=depthBias;s.minimumThickness=3;s.maximumThickness=3;s.pixelThicknessScale=0;
    return Redx11TraceRebirthContactShadow(float3(0,0,10),float3(0,0,1),float3(1,0,0),
        4,1,.5f,material,hairBias,InputFixtureView(),s);
}
float RunInputCase(uint test)
{
    float result=0.0f;
    if(test<16) {
        // Exhaust all 256 encoded bytes, including every high-nibble flag.
        bool matched=true;
        [unroll] for(uint flags=0;flags<16;++flags)
            matched=matched&&(Redx11RemakeContactMaterial((test+flags*16)/255.0f)==test);
        result=matched?1.0f:0.0f;
    }
    else if(test<24) {
        uint material=Redx11RemakeContactMaterial((7+(test-16)*32)/255.0f);
        float hair=InputFixtureVisibility(material,1,8);
        float equivalent=InputFixtureVisibility(1,8,8);
        float other=InputFixtureVisibility(1,1,8);
        // A deliberately large hair-only bias exhausts the short ray. Compare
        // with identical general bias and require the non-hair ray still hits.
        result=(isfinite(hair)&&abs(hair-equivalent)<1e-6f&&hair>.99f&&other<.1f)?1.0f:0.0f;
    }
    else if(test<32) {
        const uint frames[8]={0,1,7,8,31,61,255,12345};
        uint frame=frames[test-24];
        // Real constant-buffer bits, as in the production ViewData load.
        // Avoid relying on compile-time treatment of denormal float literals.
        float4 timing=asfloat(FixtureTiming[test-24]);
        int decoded=Redx11RemakeContactFrameIndex(timing);
        float noise=InterleavedGradientNoise(float2(64.5f,64.5f),decoded);
        float zero=InterleavedGradientNoise(float2(64.5f,64.5f),0);
        result=(decoded==(int)frame&&isfinite(noise)&&noise>=0&&noise<1
            &&(frame==0u||abs(noise-zero)>1e-6f))?1.0f:0.0f;
    }
    else if(test==32) {
        // Only class 7 selects the donor hair bias; adjacent/custom IDs do not.
        bool isolated=true;
        [unroll] for(uint material=0;material<16;++material) {
            float value=InputFixtureVisibility(material,1,8);
            isolated=isolated&&isfinite(value)&&(material==7u?value>=.99f:value<.1f);
        }
        result=isolated?1.0f:0.0f;
    }
    else {
        // Real donor hair bias, not just the exaggerated branch-detection setting.
        float hair=InputFixtureVisibility(7,1,1.5f);
        float equivalent=InputFixtureVisibility(1,1.5f,1.5f);
        result=abs(hair-equivalent)<1e-6f?1.0f:0.0f;
    }
    return result;
}
[numthreads(64,1,1)]
void main(uint3 id:SV_DispatchThreadID) {if(id.x<34) Results[id.x]=RunInputCase(id.x);}
