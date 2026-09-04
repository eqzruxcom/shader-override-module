#define REDX11_CONTACT_USE_REBIRTH_SOURCE
// This fixture hardcodes finite viewport bounds. Keep production finite checks;
// silence only FXC's redundant-isfinite warning for this synthetic entry point.
#pragma warning(disable : 3577)
#include "ContactShadowsMotion_cs.hlsl"
