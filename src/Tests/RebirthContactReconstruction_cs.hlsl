#include "../ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl"
RWStructuredBuffer<float> TestResults : register(u0);
[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if(id.x>=34) return;
    bool passed=true;
    // 32 cases: every lane at each phase, all binary shadow combinations,
    // plus nonbinary values. Independent expected average uses XOR neighbors.
    if(id.x<32)
    {
        int phase=(int)(id.x/4u),lane=(int)(id.x%4u);
        int2 pixel=int2(24+(lane&1),40+(lane>>1));
        bool traced=Redx11RebirthCheckerboard(pixel,float4(phase,0,0,0));
        passed=traced==(((uint)((lane&1)+(lane>>1)+phase))%2u!=0);
        [loop] for(int pattern=0;pattern<17;++pattern)
        {
            float4 raw=pattern==16?float4(.125,.375,.625,.875):
                float4(pattern&1,(pattern>>1)&1,(pattern>>2)&1,(pattern>>3)&1);
            float4 masked=1;
            int selected=0;
            [unroll] for(int k=0;k<4;++k)
            {
                if(Redx11RebirthCheckerboard(int2(24+(k&1),40+(k>>1)),float4(phase,0,0,0)))
                {masked[k]=raw[k];selected++;}
            }
            float result=traced?raw[lane]:Redx11RebirthQuadAverage(masked);
            float expected=traced?raw[lane]:(raw[lane^1]+raw[lane^2])*.5;
            passed=passed&&selected==2&&abs(result-expected)<1e-6;
        }
    }
    else if(id.x==32)
    {
        // Neutral lanes, one valid shadow at an uncovered viewport edge,
        // and an all-shadow pair retain donor AVG behavior.
        passed=Redx11RebirthQuadAverage(1)==1
            &&Redx11RebirthQuadAverage(float4(1,0,1,1))==.5
            &&Redx11RebirthQuadAverage(float4(1,0,0,1))==0;
    }
    else
    {
        // Translation by a whole quad preserves parity; odd viewport origins
        // must not rebase the screen-space quad lattice.
        [unroll] for(int lane=0;lane<4;++lane)
        {
            int2 p=int2(17+(lane&1),25+(lane>>1));
            passed=passed&&Redx11RebirthCheckerboard(p,0)==Redx11RebirthCheckerboard(p+int2(2,4),0)
                &&Redx11RebirthCheckerboard(p,0)!=Redx11RebirthCheckerboard(p,float4(1,0,0,0));
        }
    }
    TestResults[id.x]=passed?1:0;
}
