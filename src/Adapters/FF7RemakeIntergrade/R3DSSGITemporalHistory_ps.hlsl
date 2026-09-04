/*
 * FF7 Remake Intergrade private temporal history for the R3D SSGI candidate.
 *
 * This pass stores only filtered indirect lighting plus a logarithmic depth
 * validity key. It must never ingest the finished scene render target: doing
 * so creates recursive previous-frame feedback and causes lighting to become
 * stuck until a shader reload.
 *
 * The motion decode matches c473ab75b7519f7e's observed t4 constants. The
 * sign/UV conversion remains a live-validation item and is deliberately kept
 * in this adapter rather than the reusable R3D effect source.
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

float2 RemakeTemporalDecodePreviousUV(float2 uv, float4 encodedMotion)
{
    // c473 reads t4.zx, checks the encoded pair for a zero sentinel, then
    // subtracts 0.499992371 and multiplies by 4.008016.
    float2 encoded = encodedMotion.zx;
    if (dot(encoded, encoded) <= 0.0)
        return uv;

    float2 velocity = (encoded - REMAKE_MOTION_CENTER) * REMAKE_MOTION_SCALE;
    return uv + float2(-0.5 * velocity.x, 0.5 * velocity.y);
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
    float2 previousUV = RemakeTemporalDecodePreviousUV(uv, encodedMotion);
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
