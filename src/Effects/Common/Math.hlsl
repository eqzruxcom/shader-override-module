#ifndef REDX11_MATH_HLSL
#define REDX11_MATH_HLSL

// Portable SM5 helpers derived from the MIT-licensed Shader Injector math
// library. Names are prefixed to avoid collisions with captured game shaders.

float Redx11PositivePow(float baseValue, float exponentValue)
{
    return pow(abs(baseValue), exponentValue);
}

float3 Redx11PositivePow(float3 baseValue, float exponentValue)
{
    return pow(abs(baseValue), float3(exponentValue, exponentValue, exponentValue));
}

float Redx11Pow2(float value)
{
    return value * value;
}

float Redx11Pow4(float value)
{
    float squared = value * value;
    return squared * squared;
}

float Redx11Pow5(float value)
{
    return Redx11Pow4(value) * value;
}

float3 Redx11SafeNormalize(float3 value)
{
    float lengthSquared = dot(value, value);
    return lengthSquared > 1.0e-12f ? value * rsqrt(lengthSquared) : float3(0.0f, 0.0f, 1.0f);
}

#endif
