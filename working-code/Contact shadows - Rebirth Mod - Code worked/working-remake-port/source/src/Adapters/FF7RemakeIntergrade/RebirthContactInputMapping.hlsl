#ifndef REDX11_INTERGRADE_REBIRTH_CONTACT_INPUTS_HLSL
#define REDX11_INTERGRADE_REBIRTH_CONTACT_INPUTS_HLSL

// Native tiled-lighting loads t2.w, converts alpha*255+.5 to uint, masks 15.
// General variant ID 7 uses the same strand tangent/anisotropic construction
// as the donor's ShadeHair. High-nibble output flags are not material IDs.
uint Redx11RemakeContactMaterial(float packedAlpha)
{
    return (uint)(packedAlpha*255.0f+.5f)&15u;
}

// Input is native ViewData[139]: random, frame number, view phase mod8,
// view state frame index. Native PS 7101fdc4c25fb2bd/a77b589dce5822d6 use
// .w for noise; tiled lights use .z for an 8-phase slice. Captured .w=61,
// .z=5 corroborate this layout. It is integer bits, not a numeric float.
// Do not substitute [140].x or assume this is an unbounded application counter.
int Redx11RemakeContactFrameIndex(float4 nativeTiming)
{
    return asint(nativeTiming.w);
}
#endif
