#ifndef REMAKE_TEMPORAL_AO_POWER_HLSL
#define REMAKE_TEMPORAL_AO_POWER_HLSL

// Remake stores AO as visibility: 1.0 is neutral and smaller values occlude.
// Apply this only to the newly computed current-frame scalar, before the
// shader chooses current versus reprojected history. Applying it at the packed
// output would power an already-shaped history sample a second time.
float RemakeTemporalAOApplyCurrentPower(float currentVisibility, float power)
{
    return saturate(pow(saturate(currentVisibility), power));
}

#endif
