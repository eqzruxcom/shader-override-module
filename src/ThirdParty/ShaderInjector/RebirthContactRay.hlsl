// Generated from ShaderInjector bab25809b375f028b7c0fb603d804426f38c9b8e.
// MIT, Copyright (c) 2026 David Matos. See LICENSE.txt and provenance.json.
// Regenerate/check with tools/import_rebirth_contact_source.py.
#if defined(CONTACT_SHADOWS_IMPROVED_THICKNESS)
    float PerspectiveCorrectDepth(
        float t,
        float depthOverWStart,
        float depthOverWEnd,
        float inverseWStart,
        float inverseWEnd)
    {
        float inverseW = lerp(inverseWStart, inverseWEnd, t);
        float depthOverW = lerp(depthOverWStart, depthOverWEnd, t);
        return depthOverW * rcp(max(inverseW, 1e-8f));
    }

    float CalculateAdaptiveContactShadowThickness(float sceneDepth, float contactShadowBias)
    {
        // A perspective pixel footprint grows linearly with depth; an
        // orthographic pixel footprint remains constant.
        float projectionDepthScale = (View_ViewToClip[3].w < 1.0f) ? sceneDepth : 1.0f;

        float inverseProjectionScaleX = rcp(max(abs(View_ViewToClip[0][0]), 1e-6f));
        float inverseProjectionScaleY = rcp(max(abs(View_ViewToClip[1][1]), 1e-6f));

        float pixelFootprintX = 2.0f * projectionDepthScale * inverseProjectionScaleX * View_BufferSizeAndInvSize.z;
        float pixelFootprintY = 2.0f * projectionDepthScale * inverseProjectionScaleY * View_BufferSizeAndInvSize.w;
        float pixelFootprint = max(pixelFootprintX, pixelFootprintY);

        float minimumThickness = max(CONTACT_SHADOWS_MIN_THICKNESS, contactShadowBias + 1e-4f);
        float maximumThickness = max(CONTACT_SHADOWS_THICKNESS, minimumThickness);

        return clamp(
            CONTACT_SHADOWS_MIN_THICKNESS + pixelFootprint * CONTACT_SHADOWS_PIXEL_THICKNESS_SCALE,
            minimumThickness,
            maximumThickness);
    }
#else
    // Original helper retained verbatim for the legacy macro path.
    float PerspectiveCorrectDepth(
        float t,
        float depthStart,
        float depthEnd,
        float clipWStart,
        float clipWEnd)
    {
        float inverseW = lerp(rcp(clipWStart), rcp(clipWEnd), t);
        float depthOverW = lerp(
            depthStart * rcp(clipWStart),
            depthEnd   * rcp(clipWEnd),
            t);

        return depthOverW / inverseW;
    }
#endif

void ClipAgainstPlane(float startDistance, float endDistance, inout float exitT)
{
    if (endDistance < 0.0)
    {
        float denominator = startDistance - endDistance;

        if (denominator > 1e-6)
            exitT = min(exitT, startDistance / denominator);
    }
}

float CalculateContactShadows(FGBufferData gbufferData, FResolvedPixel resolvedPixel, PSInput input)
{
    const float invSamples = rcp((float)CONTACT_SHADOWS_SAMPLES);

	#if defined(RANDOM_INTERLEAVED_GRADIENT_NOISE)
		float random = InterleavedGradientNoise(input.SvPosition.xy, View_StateFrameIndex);
	#elif defined(RANDOM_BLUE_NOISE)
		float random = LoadSpatiotemporalBlueNoise(input);
	#else
		float random = 1.0f;
	#endif
	
    //approximation of how big a pixel is
    //this is because at low resolutions biasing / noise issues get really bad
    //but intrestingly at higher and higher resolutions the biasing/noise issues go away
    //so this means that for the most part we should factor in the pixel scale of the render target
    //for inv size, natrually lower resolutions will have a larger number (higher res lower)
    //so we can use this to scale our set bias factor
    float pixelSize = max(View_BufferSizeAndInvSize.z, View_BufferSizeAndInvSize.w);
    pixelSize *= 100.0f; //this 100 is arbitrary

    float contactShadowBias = pixelSize * CONTACT_SHADOWS_BIAS;

    if(gbufferData.ShadingModelID == SHADINGMODELID_HAIR)
		contactShadowBias = pixelSize * CONTACT_SHADOWS_BIAS_HAIR;

	//FIX: apparently we use "pre" translation? seems like there is an extra necessary offset to get an accurate world position vector
    float3 worldPosition = resolvedPixel.WorldPosition + View_PreViewTranslation;

	//apply normal bias to help mitigate self-shadowing issues
    worldPosition += gbufferData.WorldNormal * (pixelSize * CONTACT_SHADOWS_NORMAL_BIAS);

    //assumed normalized and pointing from the surface toward the light.
    float3 rayDirection = resolvedPixel.LightVector;

    float3 rayOrigin = worldPosition + rayDirection * contactShadowBias;

    float traceLength = CONTACT_SHADOWS_RAY_LENGTH;

    // lightDistance is assumed to have been calculated before
    // the origin was moved forward by contactShadowBias.
    float remainingLightDistance = max(resolvedPixel.LightDistance - contactShadowBias, 0.0f);

    float lightExclusionRadius = rcp(DeferredLightUniforms_InvRadius) * CONTACT_SHADOWS_LOCAL_LIGHT_SHADOW_EXCLUSION_RADIUS_FACTOR;

    // Stop at the outside of the light's exclusion sphere.
    float maximumShadowDistance = max(remainingLightDistance - lightExclusionRadius, 0.0f);

    traceLength = min(traceLength, maximumShadowDistance);

    float3 rayEnd    = rayOrigin + rayDirection * traceLength;

    // Nothing useful remains to trace.
    if (traceLength <= 1e-4f)
        return 1.0f;

	//FIX: apparently we use translated world to clip, which supposedly is more accurate?
    float4 clipStart = mul(float4(rayOrigin, 1.0), View_TranslatedWorldToClip);
    float4 clipEnd   = mul(float4(rayEnd, 1.0), View_TranslatedWorldToClip);

    //FIX: do not trace rays behind camera
    if (clipStart.w <= 1e-5)
        return 1.0;

    //FIX: stop rays from tracing outside of the camera viewports visible region
    //this is to reduce wierd funky self shadowing artifacts when we get too close to light sources
    float rayExitT = 1.0;
    ClipAgainstPlane(clipStart.w - 1e-5, clipEnd.w - 1e-5, rayExitT); //in front of the camera.
    ClipAgainstPlane(clipStart.x + clipStart.w, clipEnd.x + clipEnd.w, rayExitT); //left: x >= -w.
    ClipAgainstPlane(clipStart.w - clipStart.x, clipEnd.w - clipEnd.x, rayExitT); //right: x <= w.
    ClipAgainstPlane(clipStart.y + clipStart.w, clipEnd.y + clipEnd.w, rayExitT); //bottom: y >= -w.
    ClipAgainstPlane(clipStart.w - clipStart.y, clipEnd.w - clipEnd.y, rayExitT); //top: y <= w.

    if (rayExitT <= 1e-4)
        return 1.0;

    clipEnd = lerp(clipStart, clipEnd, saturate(rayExitT));

    float3 ndcStart = clipStart.xyz / clipStart.w;
    float3 ndcEnd = clipEnd.xyz / clipEnd.w;

    float rayStartDepth = LinearizeSceneDepth(ndcStart.z);
    float rayEndDepth = LinearizeSceneDepth(ndcEnd.z);

    #if defined(CONTACT_SHADOWS_IMPROVED_THICKNESS)
        // UV is stepped linearly after perspective division, so view depth must
        // be interpolated perspective-correctly at the same screen-space t.
        float inverseWStart = rcp(clipStart.w);
        float inverseWEnd = rcp(clipEnd.w);
        float depthOverWStart = rayStartDepth * inverseWStart;
        float depthOverWEnd = rayEndDepth * inverseWEnd;
    #else
        float rayDepth = lerp(rayStartDepth, rayEndDepth, random * invSamples);
        float rayDepthStep = (rayEndDepth - rayStartDepth) * invSamples;
    #endif

	//IMPORTANT NOTE: make sure we use View_ScreenPositionScaleBias instead of hardcoded constants.
	// xy = scale (0.5, -0.5 on D3D), zw = bias (0.5, 0.5 + viewport offset + TAA jitter)
	// if we don't we can (and have) end up in a case where due to some resolution mismatching
	// contact shadows can have a lot of artifacts and seemingly appear "offset" or behind for some user graphics configs
    //IMPORTANT NOTE 2: WATCH THAT SWIZZLE! it needs to be wz not zw... otherwise we get scaling issues at non standard resolutions
	float2 uvStart = mad(ndcStart.xy, View_ScreenPositionScaleBias.xy, View_ScreenPositionScaleBias.wz);
	float2 uvEnd   = mad(ndcEnd.xy,   View_ScreenPositionScaleBias.xy, View_ScreenPositionScaleBias.wz);

    //NEW: reject super tiny rays
    float2 rayPixelDelta = (uvEnd - uvStart) * View_BufferSizeAndInvSize.xy;
    if (dot(rayPixelDelta, rayPixelDelta) < 0.25)
        return 1.0;

	float2 uvStep  = (uvEnd - uvStart) * invSamples;
	float2 uv      = mad(uvStep, random, uvStart);

	float occlusion = 1.0f;

    #if defined(CONTACT_SHADOWS_IMPROVED_THICKNESS)
        // Exclude the receiver before interval tests. Grazing rays receive a
        // larger exclusion because they remain near the receiver plane longer.
        float receiverNoL = saturate(dot(gbufferData.WorldNormal, rayDirection));
        float grazingFactor = 1.0f - receiverNoL;
        float receiverSkipSteps =
            CONTACT_SHADOWS_SELF_OCCLUSION_SKIP_STEPS +
            grazingFactor * CONTACT_SHADOWS_GRAZING_EXTRA_SKIP_STEPS;
        float minimumTraceT = saturate(receiverSkipSteps * invSamples);

        // Adjacent samples share an interval boundary, so only one new
        // perspective-correct depth is required per tested sample.
        float segmentDepth0 = PerspectiveCorrectDepth(
            minimumTraceT,
            depthOverWStart,
            depthOverWEnd,
            inverseWStart,
            inverseWEnd);
    #else
        float thickness = CONTACT_SHADOWS_THICKNESS;
    #endif

    [unroll]
    for (int i = 0; i < CONTACT_SHADOWS_SAMPLES; ++i)
    {
		//OPTIMIZATION: early out when our sample UV goes past screen edges
        if (any(uv < 0.0) || any(uv > 1.0))
            break;

        float deviceDepth = Redx11ContactSampleDeviceDepth(uv);
        float sceneDepth = LinearizeSceneDepth(deviceDepth);

        #if defined(CONTACT_SHADOWS_IMPROVED_THICKNESS)
            // Test a finite ray-depth segment rather than an infinitely thin
            // point, then overlap it with the visible surface's depth interval.
            float sampleT = (i + random) * invSamples;
            float halfStepT = 0.5f * invSamples;
            float segmentEndT = (i == CONTACT_SHADOWS_SAMPLES - 1)
                ? 1.0f
                : saturate(sampleT + halfStepT);

            // This complete sample cell is inside the receiver exclusion zone.
            if (segmentEndT <= minimumTraceT)
            {
                uv += uvStep;
                continue;
            }

            float segmentDepth1 = PerspectiveCorrectDepth(
                segmentEndT,
                depthOverWStart,
                depthOverWEnd,
                inverseWStart,
                inverseWEnd);

            float rayDepthMin = min(segmentDepth0, segmentDepth1);
            float rayDepthMax = max(segmentDepth0, segmentDepth1);

            float thickness = CalculateAdaptiveContactShadowThickness(sceneDepth, contactShadowBias);
            float sceneDepthFront = sceneDepth + contactShadowBias;
            float sceneDepthBack = sceneDepth + thickness;

            bool intersectsDepthInterval =
                rayDepthMax > sceneDepthFront &&
                rayDepthMin < sceneDepthBack;

            // Nearest penetrated depth gives a stable thickness fade when a
            // segment crosses the front of the surface interval.
            float penetration = max(rayDepthMin - sceneDepth, contactShadowBias);

			#if defined(CONTACT_SHADOWS_FALLOFF)
				if (intersectsDepthInterval)
				{
					float rayProgress = saturate(sampleT);
					float distanceFade = 1.0f - rayProgress;
					float sampleShadow = 1.0f - distanceFade;
					sampleShadow *= sampleShadow;

					occlusion = min(occlusion, sampleShadow);
				}
			#else
				if (intersectsDepthInterval)
					return 0.0f;
			#endif

            segmentDepth0 = segmentDepth1;
        #else
            // Original point-depth thickness test.
            float penetration = rayDepth - sceneDepth;

			#if defined(CONTACT_SHADOWS_FALLOFF)
				if (penetration > contactShadowBias && penetration < thickness)
				{
					//how far along the ray are we? (we are going from point towards the light)
					float rayProgress = i * invSamples;
					float distanceFade = 1.0 - saturate(rayProgress);
					float sampleShadow = 1.0 - distanceFade;
					sampleShadow *= sampleShadow;

					occlusion = min(occlusion, sampleShadow);
				}
			#else
				//NOTE TO SELF: while this is simple and fast, leaves a harsh cutoff
				//for thickness we can calculate a "weight" to do a smoother falloff out from shadow
				if (penetration > contactShadowBias && penetration < thickness)
					return 0.0;
			#endif

            rayDepth += rayDepthStep;
        #endif

        uv += uvStep;
    }

	//when introducing the falloff shadows can appear a little too light
	//to compensate especially near contacts we have a contrast factor here
	#if defined(CONTACT_SHADOWS_FALLOFF)
		occlusion = pow(occlusion, CONTACT_SHADOWS_FALLOFF_CONTRAST);
	#endif

    return occlusion;
}
