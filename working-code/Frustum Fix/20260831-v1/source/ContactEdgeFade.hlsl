//Frustum Fix
#ifndef REDX11_CONTACT_EDGE_FADE_HLSL
#define REDX11_CONTACT_EDGE_FADE_HLSL
// Project refinement, NOT an unchanged part of the Rebirth donor.
// LEFT EDGE ONLY, as requested. Width is a fraction of viewport width.
// Top, right and bottom do not contribute to fading.
// Explicit inner dead zone, independent of the full-strength boundary.
static float Redx11ContactEdgeCutoff = 0.0f;
float Redx11ContactEdgeWidth(float width)
{
    // IEEE exponent test also compiles cleanly when OFF is a literal constant.
    bool finiteWidth = (asuint(width) & 0x7f800000u) != 0x7f800000u;
    return finiteWidth && width > 0.0f ? min(width, .25f) : 0.0f;
}
float Redx11ContactEdgeConfidence(float2 uv, float4 bounds, float width)
{
    if (width <= 0.0f) return 1.0f;
    if (!all(isfinite(uv)) || !all(isfinite(bounds)) || any(bounds.zw <= bounds.xy))
        return 0.0f;
    float leftDistance = (uv.x - bounds.x) / (bounds.z - bounds.x);
    float cutoff = Redx11ContactEdgeWidth(Redx11ContactEdgeCutoff);
    if (cutoff >= width) return 1.0f; // Invalid profile: leave lighting unchanged.
    float t = saturate((leftDistance - cutoff) / (width - cutoff));
    return t * t * (3.0f - 2.0f * t);
}
float Redx11ContactFadeHit(float visibility, float receiverConfidence,
    float2 hitUV, float4 bounds, float width)
{
    // Min avoids applying two attenuation factors to the same border region.
    // Evaluate EACH hit before reducing, so fading an edge blocker cannot
    // discard a different, fully supported blocker farther along the ray.
    float confidence = min(receiverConfidence,
        Redx11ContactEdgeConfidence(hitUV, bounds, width));
    return lerp(1.0f, visibility, confidence);
}
#endif
