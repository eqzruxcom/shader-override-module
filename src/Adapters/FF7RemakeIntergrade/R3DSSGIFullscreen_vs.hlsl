/*
 * Injector-owned fullscreen triangle for screen-space lighting passes.
 *
 * The shader consumes only SV_VertexID, so it does not depend on the game's
 * input layout, vertex buffers, or vertex count. TEXCOORD0 matches the
 * FullscreenInput contract used by the Remake SSGI pixel shaders:
 *   xy = viewport UV
 *   zw = clip/view ray (2 * U - 1, 1 - 2 * V)
 */

struct FullscreenOutput
{
    float4 uvAndRay : TEXCOORD0;
    float4 position : SV_Position;
};

FullscreenOutput main(uint vertexId : SV_VertexID)
{
    FullscreenOutput output;

    // One oversized triangle covers the viewport. UV values beyond 1.0 are
    // intentional and interpolate to [0,1] across visible pixels.
    float2 uv = float2((vertexId << 1) & 2, vertexId & 2);
    float2 clip = uv * float2(2.0, -2.0) + float2(-1.0, 1.0);

    output.position = float4(clip, 0.0, 1.0);
    output.uvAndRay = float4(uv, clip);
    return output;
}
