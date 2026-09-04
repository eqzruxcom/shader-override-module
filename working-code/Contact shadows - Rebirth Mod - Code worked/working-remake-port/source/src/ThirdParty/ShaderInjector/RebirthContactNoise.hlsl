// Generated from ShaderInjector bab25809b375f028b7c0fb603d804426f38c9b8e.
// MIT, Copyright (c) 2026 David Matos. See LICENSE.txt and provenance.json.
// Regenerate/check with tools/import_rebirth_contact_source.py.
float InterleavedGradientNoise(float2 pixCoord, int frameCount)
{
	const float3 magic = float3(0.06711056f, 0.00583715f, 52.9829189f);
	const float2 frameMagicScale = float2(2.083f, 4.867f);
    pixCoord += frameCount * frameMagicScale;
    
	return frac(magic.z * frac(dot(pixCoord, magic.xy)));
}
