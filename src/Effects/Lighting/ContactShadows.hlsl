#ifndef REDX11_CONTACT_SHADOWS_HLSL
#define REDX11_CONTACT_SHADOWS_HLSL
// Experimental geometric tracer; source-preserving donor lives separately.
#include "ContactShadowCommon.hlsl"

// Returns visibility for ONE local point/spot light, not a screen-wide mask.
float2 Redx11ContactDepthUV(float2 uv, Redx11ContactView view)
{
    if (view.pointSampledDepth > 0.5f)
        return clamp(floor(uv * view.bufferSize) + 0.5f,
            view.viewportUVBounds.xy * view.bufferSize + 0.5f,
            view.viewportUVBounds.zw * view.bufferSize - 0.5f) * view.invBufferSize;
    return uv;
}

bool Redx11ContactSurfacePosition(float2 uv, float sceneDepth, Redx11ContactView view, out float3 position)
{
    position = 0;
    float2 ndc = (uv - view.ndcToBufferBias) / view.ndcToBufferScale;
    float scale = view.perspective > 0.5f ? sceneDepth : 1.0f;
    float4 h = mul(float4(ndc * scale, sceneDepth, 1), view.screenLinearToWorld);
    if (!all(isfinite(h)) || abs(h.w) <= 1.0e-8f || !isfinite(sceneDepth) || sceneDepth <= 0) return false;
    position = h.xyz / h.w + view.worldToTranslatedWorld;
    return all(isfinite(position));
}

bool Redx11ContactNeighbor(float2 uv, Redx11ContactView view, out float3 position, out float depth)
{
    uv = Redx11ContactDepthUV(uv, view);
    depth = Redx11ContactLinearDepth(Redx11ContactSampleDeviceDepth(uv), view.invDeviceZToWorldZ);
    return Redx11ContactSurfacePosition(uv, depth, view, position);
}

// Fit a local geometric plane from depth, not a normal-mapped shading normal.
// Prefer the closer-depth neighbor on each axis to avoid bridging silhouettes.
bool Redx11ContactSurfacePlane(float2 uv, float depth, Redx11ContactView view, out float3 position, out float3 normal)
{
    normal = 0;
    if (!Redx11ContactSurfacePosition(uv, depth, view, position)) return false;
    float3 left, right, up, down;
    float dl, dr, du, dd;
    bool vl = Redx11ContactNeighbor(uv-float2(view.invBufferSize.x,0), view, left, dl);
    bool vr = Redx11ContactNeighbor(uv+float2(view.invBufferSize.x,0), view, right, dr);
    bool vu = Redx11ContactNeighbor(uv-float2(0,view.invBufferSize.y), view, up, du);
    bool vd = Redx11ContactNeighbor(uv+float2(0,view.invBufferSize.y), view, down, dd);
    if ((!vl && !vr) || (!vu && !vd)) return false;
    float3 dx = vl && (!vr || abs(dl-depth) < abs(dr-depth)) ? position-left : right-position;
    float3 dy = vu && (!vd || abs(du-depth) < abs(dd-depth)) ? position-up : down-position;
    float3 crossNormal = cross(dx,dy);
    float length2 = dot(crossNormal,crossNormal);
    if (!isfinite(length2) || length2 <= 1.0e-16f) return false;
    normal = crossNormal * rsqrt(length2);
    // At a crease the independently selected horizontal/vertical derivatives
    // can belong to different faces. Prefer a quadrant whose fourth depth
    // point agrees with its three-point plane; do not smooth across the fold.
    float bestResidual = 1.0e30f;
    float minDx2=min(dot(right-position,right-position),dot(position-left,position-left));
    float minDy2=min(dot(down-position,down-position),dot(position-up,position-up));
    [unroll]
    for (int quadrant=0;quadrant<4;++quadrant)
    {
        bool useRight=(quadrant&1)!=0, useDown=(quadrant&2)!=0;
        if ((useRight?vr:vl) && (useDown?vd:vu))
        {
            float3 qx=useRight?right-position:position-left;
            float3 qy=useDown?down-position:position-up;
            float3 qn=cross(qx,qy);
            float qnLength2=dot(qn,qn);
            float3 diagonal;float diagonalDepth;
            if (dot(qx,qx)<=256*max(minDx2,1.0e-12f) && dot(qy,qy)<=256*max(minDy2,1.0e-12f) &&
                qnLength2>1.0e-16f && isfinite(qnLength2) &&
                Redx11ContactNeighbor(uv+float2(useRight?1:-1,useDown?1:-1)*view.invBufferSize,view,diagonal,diagonalDepth))
            {
                qn*=rsqrt(qnLength2);
                float residual=abs(dot(diagonal-position,qn));
                if (residual<bestResidual) {bestResidual=residual;normal=qn;}
            }
        }
    }
    // Even the best quadrant may span a silhouette. Require an actual local
    // plane within reconstruction precision before extrapolating it.
    return bestResidual <= max(1.0e-4f,depth*1.0e-5f);
}

bool Redx11ContactProjectSurface(float3 position, Redx11ContactView view, out float2 uv)
{
    uv = 0;
    float4 c = mul(float4(position,1),view.translatedWorldToClip);
    if (!all(isfinite(c)) || c.w <= 1.0e-5f || any(abs(c.xy)>c.w) || c.z<0 || c.z>c.w) return false;
    uv = c.xy/c.w * view.ndcToBufferScale + view.ndcToBufferBias;
    return all(uv>=view.viewportUVBounds.xy) && all(uv<=view.viewportUVBounds.zw);
}

// Intersect a sampled local surface, then independently validate the candidate
// in the depth image. Extending a fitted plane beyond an object's silhouette
// must not invent an occluder. A second local fit handles subpixel reprojection.
bool Redx11ContactGeometricHit(float2 sampleUV, float sampleDepth, float3 receiver, float3 receiverNormal,
    float3 origin, float3 direction, float minimumDistance, float maximumDistance, float depthBias,
    Redx11ContactView view, out float distance, out float2 hitUV, out float hitDepth)
{
    distance = 0; hitUV = sampleUV; hitDepth = sampleDepth;
    float3 surface, normal;
    if (!Redx11ContactSurfacePosition(sampleUV,sampleDepth,view,surface)) return false;
    if (dot(surface-receiver,receiverNormal) <= max(depthBias,sampleDepth*1.0e-5f)) return false;
    if (!Redx11ContactSurfacePlane(sampleUV,sampleDepth,view,surface,normal)) return false;
    float denominator = dot(direction,normal);
    if (abs(denominator)<=1.0e-6f) return false;
    distance = dot(surface-origin,normal)/denominator;
    if (distance<minimumDistance || distance>maximumDistance) return false;
    float2 projectedUV;
    if (!Redx11ContactProjectSurface(origin+direction*distance,view,projectedUV)) return false;
    hitUV = Redx11ContactDepthUV(projectedUV,view);
    hitDepth = Redx11ContactLinearDepth(Redx11ContactSampleDeviceDepth(hitUV),view.invDeviceZToWorldZ);
    if (!Redx11ContactSurfacePlane(hitUV,hitDepth,view,surface,normal)) return false;
    denominator = dot(direction,normal);
    if (abs(denominator)<=1.0e-6f) return false;
    distance = dot(surface-origin,normal)/denominator;
    if (distance<minimumDistance || distance>maximumDistance) return false;
    if (!Redx11ContactProjectSurface(origin+direction*distance,view,projectedUV)) return false;
    if (any(abs(projectedUV-hitUV)*view.bufferSize>1.0f)) return false;
    // Test the final projected texel against the refined plane. A depth jump
    // cannot pass simply because the ray crosses its finite-thickness volume.
    hitUV = Redx11ContactDepthUV(projectedUV,view);
    hitDepth = Redx11ContactLinearDepth(Redx11ContactSampleDeviceDepth(hitUV),view.invDeviceZToWorldZ);
    float3 finalSurface;
    if (!Redx11ContactSurfacePosition(hitUV,hitDepth,view,finalSurface)) return false;
    float residual = abs(dot(finalSurface-(origin+direction*distance),normal));
    return residual <= max(depthBias*.1f,hitDepth*1.0e-5f);
}

// Preserve finite-thickness occlusion, but extrude the local geometric surface
// along its normal rather than along the camera ray. Validate the perpendicular
// footprint in the depth image so the thickness does not grow silhouettes.
bool Redx11ContactExtrudedHit(float2 sampleUV, float sampleDepth, float3 rayPosition, float depthBias,
    Redx11ContactView view, Redx11ContactSettings settings, out float2 hitUV, out float hitDepth)
{
    hitUV=sampleUV;hitDepth=sampleDepth;
    float3 surface,normal;
    if (!Redx11ContactSurfacePlane(sampleUV,sampleDepth,view,surface,normal)) return false;
    float behind=-dot(rayPosition-surface,normal);
    float thickness=Redx11ContactThickness(sampleDepth,depthBias,view,settings);
    if (behind<=depthBias || behind>=thickness) return false;
    float3 footprint=rayPosition+normal*behind;
    float2 projectedUV;
    if (!Redx11ContactProjectSurface(footprint,view,projectedUV)) return false;
    hitUV=Redx11ContactDepthUV(projectedUV,view);
    hitDepth=Redx11ContactLinearDepth(Redx11ContactSampleDeviceDepth(hitUV),view.invDeviceZToWorldZ);
    float3 secondSurface,secondNormal;
    if (!Redx11ContactSurfacePlane(hitUV,hitDepth,view,secondSurface,secondNormal)) return false;
    if (dot(normal,secondNormal)<.99f) return false;
    behind=-dot(rayPosition-secondSurface,secondNormal);
    thickness=Redx11ContactThickness(hitDepth,depthBias,view,settings);
    if (behind<=depthBias || behind>=thickness) return false;
    footprint=rayPosition+secondNormal*behind;
    if (!Redx11ContactProjectSurface(footprint,view,projectedUV)) return false;
    if (any(abs(projectedUV-hitUV)*view.bufferSize>1.0f)) return false;
    hitUV=Redx11ContactDepthUV(projectedUV,view);
    hitDepth=Redx11ContactLinearDepth(Redx11ContactSampleDeviceDepth(hitUV),view.invDeviceZToWorldZ);
    float3 finalSurface;
    if (!Redx11ContactSurfacePosition(hitUV,hitDepth,view,finalSurface)) return false;
    return abs(dot(finalSurface-footprint,secondNormal))<=max(depthBias*.1f,hitDepth*1.0e-5f);
}

// Returns visibility for ONE local point/spot light, not a screen-wide mask.
// Origin is already translated world; normal and direction must be normalized.
// The caller owns material exclusions, sky rejection, light selection and
// applying visibility to the corresponding native contribution exactly once.
float Redx11TraceLocalContactShadow(
    float3 translatedWorldPosition, float3 worldNormal,
    float3 directionToLight, float lightDistance, float lightInverseRadius,
    float sampleJitter, Redx11ContactView view, Redx11ContactSettings settings)
{
    if (settings.rayLength <= 0.0f || lightDistance <= 0.0f
        || lightInverseRadius <= 0.0f || any(view.bufferSize <= 0.0f)
        || any(view.invBufferSize <= 0.0f)
        || any(view.viewportUVBounds.zw <= view.viewportUVBounds.xy))
        return 1.0f;

    float invSamples = rcp((float)REDX11_CONTACT_SAMPLES);
    float jitter = saturate(sampleJitter);
    float pixelSize = max(view.invBufferSize.x, view.invBufferSize.y) * 100.0f;
    float depthBias = pixelSize * max(settings.depthBiasScale, 0.0f);
    float3 origin = translatedWorldPosition
        + worldNormal * (pixelSize * max(settings.normalBiasScale, 0.0f))
        + directionToLight * depthBias;
    float maximumDistance = max(lightDistance - depthBias
        - max(settings.lightExclusionFraction, 0.0f) / lightInverseRadius, 0.0f);
    float traceLength = min(settings.rayLength, maximumDistance);
    if (traceLength <= 1.0e-4f)
        return 1.0f;

    float4 clipStart = mul(float4(origin, 1.0f), view.translatedWorldToClip);
    float4 clipEnd = mul(float4(origin + directionToLight * traceLength, 1.0f),
        view.translatedWorldToClip);
    // Reject invalid starts rather than clamping them onto a screen edge.
    if (!all(isfinite(clipStart)) || !all(isfinite(clipEnd))
        || clipStart.w <= 1.0e-5f || any(abs(clipStart.xy) > clipStart.w)
        || clipStart.z < 0.0f || clipStart.z > clipStart.w)
        return 1.0f;

    float exitT = 1.0f;
    Redx11ContactClipPlane(clipStart.w - 1.0e-5f, clipEnd.w - 1.0e-5f, exitT);
    Redx11ContactClipPlane(clipStart.x + clipStart.w, clipEnd.x + clipEnd.w, exitT);
    Redx11ContactClipPlane(clipStart.w - clipStart.x, clipEnd.w - clipEnd.x, exitT);
    Redx11ContactClipPlane(clipStart.y + clipStart.w, clipEnd.y + clipEnd.w, exitT);
    Redx11ContactClipPlane(clipStart.w - clipStart.y, clipEnd.w - clipEnd.y, exitT);
    // Additional D3D near/far clipping; works for either regular or reversed Z.
    Redx11ContactClipPlane(clipStart.z, clipEnd.z, exitT);
    Redx11ContactClipPlane(clipStart.w - clipStart.z, clipEnd.w - clipEnd.z, exitT);
    if (exitT <= 1.0e-4f)
        return 1.0f;
    clipEnd = lerp(clipStart, clipEnd, saturate(exitT));

    float3 ndcStart = clipStart.xyz / clipStart.w;
    float3 ndcEnd = clipEnd.xyz / clipEnd.w;
    float2 rayDepth = float2(
        Redx11ContactLinearDepth(ndcStart.z, view.invDeviceZToWorldZ),
        Redx11ContactLinearDepth(ndcEnd.z, view.invDeviceZToWorldZ));
    if (!all(isfinite(rayDepth)) || any(rayDepth <= 0.0f))
        return 1.0f;
    float2 inverseW = rcp(float2(clipStart.w, clipEnd.w));
    float2 depthOverW = rayDepth * inverseW;
    float2 uvStart = mad(ndcStart.xy, view.ndcToBufferScale, view.ndcToBufferBias);
    float2 uvEnd = mad(ndcEnd.xy, view.ndcToBufferScale, view.ndcToBufferBias);
    float2 pixelDelta = (uvEnd - uvStart) * view.bufferSize;
    if (dot(pixelDelta, pixelDelta) < 0.25f)
        return 1.0f;

    float2 uvStep = (uvEnd - uvStart) * invSamples;
    float2 uv = mad(uvStep, jitter, uvStart);
    float receiverNoL = saturate(dot(worldNormal, directionToLight));
    float minimumTraceT = saturate((settings.receiverSkipSteps
        + (1.0f - receiverNoL) * settings.grazingExtraSkipSteps) * invSamples);
    float segmentDepth0 = Redx11ContactPerspectiveDepth(minimumTraceT, depthOverW, inverseW);
    float visibility = 1.0f;
    float previousT = minimumTraceT;
    float previousPenetration = 0;
    bool previousValid = false;

    // Explicit LOD sampling works in both SM5 pixel and compute shaders.
    [loop]
    for (int i = 0; i < REDX11_CONTACT_SAMPLES; ++i)
    {
        if (any(uv < view.viewportUVBounds.xy) || any(uv > view.viewportUVBounds.zw))
            break;
        // Include the visible endpoint. Midpoints alone leave the final half
        // cell unobserved, which can hide a blocker at a clipped screen edge.
        float sampleT = i == REDX11_CONTACT_SAMPLES - 1 ? 1.0f : (i + jitter) * invSamples;
        if (i == REDX11_CONTACT_SAMPLES - 1) uv = uvEnd;
        float segmentEndT = i == REDX11_CONTACT_SAMPLES - 1
            ? 1.0f : saturate(sampleT + 0.5f * invSamples);
        if (segmentEndT <= minimumTraceT)
        {
            uv += uvStep;
            continue;
        }
        float segmentDepth1 = Redx11ContactPerspectiveDepth(segmentEndT, depthOverW, inverseW);
        float2 surfaceUV = Redx11ContactDepthUV(uv, view);
        float deviceDepth = Redx11ContactSampleDeviceDepth(surfaceUV);
        float sceneDepth = Redx11ContactLinearDepth(deviceDepth, view.invDeviceZToWorldZ);
        if (isfinite(sceneDepth) && sceneDepth > 0.0f)
        {
            float thickness = Redx11ContactThickness(sceneDepth, depthBias, view, settings);
            // A ray cell's endpoint depth is at a DIFFERENT UV from this
            // surface sample. On a slope, that endpoint can lie behind the
            // sampled depth although the ray is in front of the surface.
            // Require penetration at the matching UV before accepting the
            // finite interval overlap (which still limits thickness).
            float sampleRayDepth = Redx11ContactPerspectiveDepth(sampleT, depthOverW, inverseW);
            float penetration = sampleRayDepth - sceneDepth;
            float hitT = sampleT;
            float2 originalSampleUV = surfaceUV;
            float originalSampleDepth = sceneDepth;
            float geometricProgress = -1;
            bool hit = sampleRayDepth > sceneDepth + depthBias
                && max(segmentDepth0, segmentDepth1) > sceneDepth + depthBias
                && min(segmentDepth0, segmentDepth1) < sceneDepth + thickness;
            if (!hit && previousValid && previousPenetration <= depthBias && penetration > depthBias)
            {
                // A coarse step can jump through a real blocker's entire
                // thickness. Refine a front-to-back crossing, then require a
                // finite matching-UV hit. A foreground depth discontinuity
                // alone is not sufficient evidence of intersection.
                float lowerT = previousT, upperT = sampleT;
                [loop]
                for (int refine = 0; refine < 5; ++refine)
                {
                    float middleT = (lowerT + upperT) * 0.5f;
                    float2 middleUV = Redx11ContactDepthUV(lerp(uvStart, uvEnd, middleT), view);
                    float middleDepth = Redx11ContactLinearDepth(Redx11ContactSampleDeviceDepth(middleUV), view.invDeviceZToWorldZ);
                    float middleRayDepth = Redx11ContactPerspectiveDepth(middleT, depthOverW, inverseW);
                    if (!isfinite(middleDepth) || middleDepth <= 0) break;
                    if (middleRayDepth > middleDepth + depthBias)
                    {
                        upperT = middleT;
                        surfaceUV = middleUV;
                        sceneDepth = middleDepth;
                    }
                    else lowerT = middleT;
                }
                hitT = upperT;
                float refinedRayDepth = Redx11ContactPerspectiveDepth(hitT, depthOverW, inverseW);
                thickness = Redx11ContactThickness(sceneDepth, depthBias, view, settings);
                hit = refinedRayDepth > sceneDepth + depthBias && refinedRayDepth < sceneDepth + thickness;
            }
            previousT = sampleT;
            previousPenetration = penetration;
            previousValid = true;
            if (receiverNoL > 0)
            {
                float minimumWorldT = minimumTraceT * inverseW.y / max(lerp(inverseW.x,inverseW.y,minimumTraceT),1.0e-8f);
                float distance;
                hit = Redx11ContactGeometricHit(originalSampleUV,originalSampleDepth,translatedWorldPosition,worldNormal,
                    origin,directionToLight,minimumWorldT*exitT*traceLength,exitT*traceLength,depthBias,
                    view,distance,surfaceUV,sceneDepth);
                geometricProgress = distance/traceLength;
                if (!hit)
                {
                    float worldT = sampleT * inverseW.y / max(lerp(inverseW.x,inverseW.y,sampleT),1.0e-8f);
                    geometricProgress = worldT*exitT;
                    hit = sampleT>=minimumTraceT && Redx11ContactExtrudedHit(originalSampleUV,originalSampleDepth,
                        origin+directionToLight*(geometricProgress*traceLength),depthBias,view,settings,surfaceUV,sceneDepth);
                }
            }
            if (hit && receiverNoL > 0.0f && geometricProgress < 0.0f)
            {
                // For a lit receiver, the ray stays above its tangent plane.
                // A point on/below that plane cannot block this ray. Rebuild
                // the sampled point at its actual texel center: using the
                // unsnapped ray UV here would invent a height on steep planes.
                float2 surfaceNDC = (surfaceUV - view.ndcToBufferBias) / view.ndcToBufferScale;
                float xyScale = view.perspective > 0.5f ? sceneDepth : 1.0f;
                float4 surfaceH = mul(float4(surfaceNDC * xyScale, sceneDepth, 1), view.screenLinearToWorld);
                hit = all(isfinite(surfaceH)) && abs(surfaceH.w) > 1.0e-8f;
                if (hit)
                {
                    float3 surface = surfaceH.xyz / surfaceH.w + view.worldToTranslatedWorld;
                    float planeDistance = dot(surface - translatedWorldPosition, worldNormal);
                    hit = planeDistance > max(depthBias, sceneDepth * 1.0e-5f);
                }
            }
            if (hit)
            {
                // UV distance is not world-ray distance in perspective.
                // Include clipping so moving the viewport edge cannot stretch
                // a near hit to the end of the falloff range.
                float worldT = hitT * inverseW.y / max(lerp(inverseW.x, inverseW.y, hitT), 1.0e-8f);
                float progress = geometricProgress >= 0 ? saturate(geometricProgress) : saturate(worldT * exitT);
                visibility = min(visibility, progress * progress);
            }
        }
        else previousValid = false;
        segmentDepth0 = segmentDepth1;
        uv += uvStep;
    }
    return pow(saturate(visibility), max(settings.falloffContrast, 1.0e-4f));
}

#endif
