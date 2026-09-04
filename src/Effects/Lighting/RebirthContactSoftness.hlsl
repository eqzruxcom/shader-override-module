#ifndef REDX11_REBIRTH_CONTACT_SOFTNESS_HLSL
#define REDX11_REBIRTH_CONTACT_SOFTNESS_HLSL
#include "RebirthContactShadows.hlsl"

// Project experiment, not an unchanged donor function. Reuses the complete
// donor tracer for eight deterministic points on a virtual disk emitter.
// Radius is an explicit caller parameter in world units. It MUST NOT be
// populated with attenuation radius; Remake's emitter-size binding is unverified.
// No temporal accumulation, native penumbra matching, or cost claim is made.
float Redx11TraceRebirthSoftContactPositiveRadius(float3 translatedPosition, float3 normal,
    float3 direction, float lightDistance, float inverseRadius, float jitter,
    uint material, float hairBias, Redx11ContactView view,
    Redx11ContactSettings settings, float emitterRadius)
{
    if (!isfinite(emitterRadius) || emitterRadius <= 0.0f)
        return 1.0f;
    if (!all(isfinite(direction)) || !isfinite(lightDistance) || lightDistance <= 1e-5f)
        return 1.0f;
    float length2 = dot(direction,direction);
    if (length2 <= 1e-8f) return 1.0f;
    direction *= rsqrt(length2);
    float3 referenceAxis = abs(direction.z) < .99f ? float3(0,0,1) : float3(0,1,0);
    float3 tangent = normalize(cross(referenceAxis,direction));
    float3 bitangent = cross(direction,tangent);
    // Equal-area radial strata (r^2=.25,.75), symmetric, no frame rotation.
    static const float2 offsets[8] = {
        float2(.5f,0),float2(0,.5f),float2(-.5f,0),float2(0,-.5f),
        float2(.612372436f,.612372436f),float2(-.612372436f,.612372436f),
        float2(-.612372436f,-.612372436f),float2(.612372436f,-.612372436f)
    };
    float visibility = 0;
    [unroll] for (uint i=0;i<8;i++)
    {
        float3 toSample = direction*lightDistance
            + emitterRadius*(tangent*offsets[i].x+bitangent*offsets[i].y);
        float sampleDistance = length(toSample);
        visibility += Redx11TraceRebirthContactShadow(translatedPosition,normal,
            toSample/sampleDistance,sampleDistance,inverseRadius,jitter,
            material,hairBias,view,settings);
    }
    return saturate(visibility*.125f);
}

// Compatibility wrapper for numerical fixtures and callers that intentionally
// use radius zero as an exact request for the existing hard path.
float Redx11TraceRebirthSoftContact(float3 translatedPosition, float3 normal,
    float3 direction, float lightDistance, float inverseRadius, float jitter,
    uint material, float hairBias, Redx11ContactView view,
    Redx11ContactSettings settings, float emitterRadius)
{
    if (!isfinite(emitterRadius) || emitterRadius <= 0.0f)
        return Redx11TraceRebirthContactShadow(translatedPosition,normal,direction,
            lightDistance,inverseRadius,jitter,material,hairBias,view,settings);
    return Redx11TraceRebirthSoftContactPositiveRadius(translatedPosition,normal,
        direction,lightDistance,inverseRadius,jitter,material,hairBias,view,
        settings,emitterRadius);
}
#endif
