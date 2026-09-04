// Generated from ShaderInjector bab25809b375f028b7c0fb603d804426f38c9b8e.
// MIT, Copyright (c) 2026 David Matos. See LICENSE.txt and provenance.json.
// Regenerate/check with tools/import_rebirth_contact_source.py.
bool Redx11RebirthCheckerboard(int2 pixelPos, float4 View_TemporalAAParams)
{
    bool checkerboardTest = ((pixelPos.x + pixelPos.y + (int)View_TemporalAAParams.x) & 1) != 0;
    return checkerboardTest;
}

float Redx11RebirthQuadAverage(float4 lanes)
{
    float lane0=lanes.x, lane1=lanes.y, lane2=lanes.z, lane3=lanes.w;
    float contactShadow;
    contactShadow = saturate((lane0 + lane1 + lane2 + lane3) * 0.5 - 1.0);
    return contactShadow;
}
