/*
 * FF7 Remake Intergrade private temporal history for the R3D SSGI candidate.
 *
 * This pass stores only filtered indirect lighting plus a logarithmic depth
 * validity key. It must never ingest the finished scene render target: doing
 * so creates recursive previous-frame feedback and causes lighting to become
 * stuck until a shader reload.
 *
 * The motion decode and static-surface fallback match c473ab75b7519f7e's
 * native history reprojection. Moving pixels use encoded t4.zx motion. A zero
 * motion sentinel uses depth plus CB1[114..117] to reconstruct previous clip
 * position; returning the current UV here would lose wall history on camera
 * movement.
 */

Texture2D<float4> RemakeCurrentIndirect : register(t110);
Texture2D<float4> RemakePreviousIndirectDepth : register(t111);
Texture2D<float> RemakeSceneDepth : register(t112);
Texture2D<float4> RemakeEncodedMotion : register(t113);
SamplerState RemakeTemporalLinearClamp : register(s0);

cbuffer RemakeView : register(b1)
{
    float4 RemakeViewData[140];
};

struct FullscreenInput
{
    float4 uvAndRay : TEXCOORD0;
    float4 position : SV_Position;
};

static const float REMAKE_DEPTH_CLEAR_EPSILON = 0.0000001;
static const float REMAKE_MOTION_CENTER = 0.499992371;
static const float REMAKE_MOTION_SCALE = 4.008016;
static const float REMAKE_HISTORY_DEPTH_THRESHOLD = 0.12;
static const float REMAKE_HISTORY_DECAY = 0.985;
static const float REMAKE_HISTORY_REFRESH_FAST = 0.35;
static const float REMAKE_HISTORY_REFRESH_SLOW = 0.015;
static const float REMAKE_HISTORY_RISE_BIAS = 0.95;

int2 RemakeTemporalCoord(float2 uv, uint width, uint height)
{
    return clamp(
        int2(uv * float2(width, height)),
        int2(0, 0),
        int2(width - 1, height - 1));
}

float RemakeTemporalDeviceW(float rawDepth)
{
    float linearTerm = rawDepth * RemakeViewData[57].x + RemakeViewData[57].y;
    float reciprocalTerm = rawDepth * RemakeViewData[57].z - RemakeViewData[57].w;
    return linearTerm + rcp(reciprocalTerm);
}

float RemakeTemporalDepthKey(float rawDepth)
{
    if (rawDepth <= REMAKE_DEPTH_CLEAR_EPSILON)
        return 0.0;

    float deviceW = RemakeTemporalDeviceW(rawDepth);
    if (!isfinite(deviceW))
        return 0.0;

    // Zero remains the unambiguous invalid/cleared history marker.
    return log2(1.0 + abs(deviceW)) + 1.0;
}

float2 RemakeTemporalPreviousUV(float2 uv, float rawDepth, float4 encodedMotion)
{
    // c473 reads t4.zx, checks the encoded pair for a zero sentinel, then
    // subtracts 0.499992371 and multiplies by 4.008016.
    float2 encoded = encodedMotion.zx;
    if (dot(encoded, encoded) > 0.0)
    {
        float2 velocity = (encoded - REMAKE_MOTION_CENTER) * REMAKE_MOTION_SCALE;
        return uv + float2(-0.5 * velocity.x, 0.5 * velocity.y);
    }

    // Native c473 fallback (assembly lines 85..90 and 164): reproject static
    // geometry with the previous-view transform carried in CB1[114..117].
    float2 currentNDC = uv * 2.0 - 1.0;
    float currentClipY = -currentNDC.y;
    float3 previousClipXYW = currentNDC.x * RemakeViewData[114].xyw
        + currentClipY * RemakeViewData[115].xyw
        + rawDepth * RemakeViewData[116].xyw
        + RemakeViewData[117].xyw;
    if (!all(isfinite(previousClipXYW)) || abs(previousClipXYW.z) <= 1.0e-8)
        return float2(-1.0, -1.0);

    float2 previousNDC = previousClipXYW.xy / previousClipXYW.z;
    return float2(previousNDC.x * 0.5 + 0.5, 0.5 - previousNDC.y * 0.5);
}

float RemakeTemporalPeak(float3 value)
{
    return max(value.x, max(value.y, value.z));
}

float4 main(FullscreenInput input) : SV_Target0
{
    float2 uv = input.uvAndRay.xy;

    uint currentWidth;
    uint currentHeight;
    uint depthWidth;
    uint depthHeight;
    uint motionWidth;
    uint motionHeight;
    RemakeCurrentIndirect.GetDimensions(currentWidth, currentHeight);
    RemakeSceneDepth.GetDimensions(depthWidth, depthHeight);
    RemakeEncodedMotion.GetDimensions(motionWidth, motionHeight);

    float3 currentIndirect = saturate(RemakeCurrentIndirect.Load(int3(
        RemakeTemporalCoord(uv, currentWidth, currentHeight), 0)).rgb);
    float rawDepth = RemakeSceneDepth.Load(int3(
        RemakeTemporalCoord(uv, depthWidth, depthHeight), 0));
    float currentDepthKey = RemakeTemporalDepthKey(rawDepth);
    if (currentDepthKey <= 0.0)
        return 0.0;

    float4 encodedMotion = RemakeEncodedMotion.Load(int3(
        RemakeTemporalCoord(uv, motionWidth, motionHeight), 0));
    float2 previousUV = RemakeTemporalPreviousUV(uv, rawDepth, encodedMotion);
    bool insideHistory = all(previousUV > 0.0) && all(previousUV < 1.0);

    float4 previous = 0.0;
    if (insideHistory)
        previous = RemakePreviousIndirectDepth.SampleLevel(
            RemakeTemporalLinearClamp, previousUV, 0);

    bool historyValid = insideHistory
        && previous.a > 0.0
        && abs(previous.a - currentDepthKey) <= REMAKE_HISTORY_DEPTH_THRESHOLD;
    if (!historyValid)
        return float4(currentIndirect, currentDepthKey);

    // Fast rise responds promptly when a newly visible source is brighter.
    // Slow refresh plus decay retains a recently observed off-screen source
    // for a short bounded interval instead of popping off at one view angle.
    float3 decayedHistory = saturate(previous.rgb) * REMAKE_HISTORY_DECAY;
    float refresh = RemakeTemporalPeak(currentIndirect)
            >= RemakeTemporalPeak(decayedHistory) * REMAKE_HISTORY_RISE_BIAS
        ? REMAKE_HISTORY_REFRESH_FAST
        : REMAKE_HISTORY_REFRESH_SLOW;
    float3 resolvedIndirect = lerp(decayedHistory, currentIndirect, refresh);

    return float4(saturate(resolvedIndirect), currentDepthKey);
}
