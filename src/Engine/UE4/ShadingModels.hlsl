#ifndef REDX11_UE4_SHADING_MODELS_HLSL
#define REDX11_UE4_SHADING_MODELS_HLSL

// UE4 shading-model identifiers observed in the Rebirth integration. A game
// adapter must verify the encoded GBuffer channel and mask for its own build.
static const uint REDX11_UE4_SHADINGMODEL_UNLIT = 0u;
static const uint REDX11_UE4_SHADINGMODEL_DEFAULT_LIT = 1u;
static const uint REDX11_UE4_SHADINGMODEL_SUBSURFACE = 2u;
static const uint REDX11_UE4_SHADINGMODEL_PREINTEGRATED_SKIN = 3u;
static const uint REDX11_UE4_SHADINGMODEL_CLEAR_COAT = 4u;
static const uint REDX11_UE4_SHADINGMODEL_SUBSURFACE_PROFILE = 5u;
static const uint REDX11_UE4_SHADINGMODEL_TWOSIDED_FOLIAGE = 6u;
static const uint REDX11_UE4_SHADINGMODEL_HAIR = 7u;
static const uint REDX11_UE4_SHADINGMODEL_CLOTH = 8u;
static const uint REDX11_UE4_SHADINGMODEL_EYE = 9u;
static const uint REDX11_UE4_SHADINGMODEL_MASK = 0xFu;

uint Redx11DecodeUE4ShadingModel(float encodedValue)
{
    return ((uint)round(saturate(encodedValue) * 255.0f)) & REDX11_UE4_SHADINGMODEL_MASK;
}

#endif
