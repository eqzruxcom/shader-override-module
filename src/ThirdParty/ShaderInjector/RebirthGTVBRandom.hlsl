#ifndef REDX11_REBIRTH_GTVB_RANDOM_HLSL
#define REDX11_REBIRTH_GTVB_RANDOM_HLSL

// Verbatim functions from ShaderInjector's LibraryRandom.hlsl at the commit
// recorded in gtvb-provenance.json. Formatting only was normalized to LF.
uint JenkinsHash(uint x)
{
    x += (x << 10u);
    x ^= (x >>  6u);
    x += (x <<  3u);
    x ^= (x >> 11u);
    x += (x << 15u);
    return x;
}

uint JenkinsHash(uint2 v) { return JenkinsHash(v.x ^ JenkinsHash(v.y)); }
uint JenkinsHash(uint3 v) { return JenkinsHash(v.x ^ JenkinsHash(v.yz)); }
uint JenkinsHash(uint4 v) { return JenkinsHash(v.x ^ JenkinsHash(v.yzw)); }

float ConstructFloat(int m)
{
    const int ieeeMantissa = 0x007FFFFF;
    const int ieeeOne = 0x3F800000;
    m &= ieeeMantissa;
    m |= ieeeOne;
    float f = asfloat(m);
    return f - 1;
}

float ConstructFloat(uint m) { return ConstructFloat(asint(m)); }
float GenerateHashedRandomFloat(uint x) { return ConstructFloat(JenkinsHash(x)); }
float GenerateHashedRandomFloat(uint2 v) { return ConstructFloat(JenkinsHash(v)); }
float GenerateHashedRandomFloat(uint3 v) { return ConstructFloat(JenkinsHash(v)); }
float GenerateHashedRandomFloat(uint4 v) { return ConstructFloat(JenkinsHash(v)); }

#endif
