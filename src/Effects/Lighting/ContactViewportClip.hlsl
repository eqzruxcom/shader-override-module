#ifndef REDX11_CONTACT_VIEWPORT_CLIP_HLSL
#define REDX11_CONTACT_VIEWPORT_CLIP_HLSL

// Project refinement: clip BOTH ends of a biased contact ray. An on-screen
// receiver does not guarantee its normal/depth-biased ray origin is on screen.
// Homogeneous clipping handles perspective without a fixed pixel-width band.
bool Redx11ContactClipIntervalPlane(float startDistance, float endDistance,
    inout float enterT, inout float exitT)
{
    if (startDistance < 0.0f && endDistance < 0.0f) return false;
    if (startDistance < 0.0f || endDistance < 0.0f)
    {
        float crossing = startDistance / (startDistance - endDistance);
        if (startDistance < 0.0f) enterT = max(enterT, crossing);
        else exitT = min(exitT, crossing);
    }
    return enterT < exitT;
}

bool Redx11ContactClipViewportSegment(float4 start, float4 finish,
    out float enterT, out float exitT)
{
    enterT = 0.0f;
    exitT = 1.0f;
    if (!all(isfinite(start)) || !all(isfinite(finish))) return false;
    if (!Redx11ContactClipIntervalPlane(start.w-1e-5f, finish.w-1e-5f, enterT, exitT)) return false;
    if (!Redx11ContactClipIntervalPlane(start.x+start.w, finish.x+finish.w, enterT, exitT)) return false;
    if (!Redx11ContactClipIntervalPlane(start.w-start.x, finish.w-finish.x, enterT, exitT)) return false;
    if (!Redx11ContactClipIntervalPlane(start.y+start.w, finish.y+finish.w, enterT, exitT)) return false;
    if (!Redx11ContactClipIntervalPlane(start.w-start.y, finish.w-finish.y, enterT, exitT)) return false;
    return enterT < exitT;
}
#endif
