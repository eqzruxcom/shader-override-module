# Remake bloom/downsample VS-PS pair evidence

## Verified live pair

- Vertex shader: `56528003870d00b3-vs`
- Pixel shader: `c58358673087aaf8-ps`
- `ShaderUsage.txt` records `c58358673087aaf8` with exactly one peer VS: `56528003870d00b3`.
- The VS has two peer PS hashes: `c58358673087aaf8` and `4170b0f1040d507f`.

The vertex shader constructs a fullscreen rectangle and emits `TEXCOORD0` and
`SV_POSITION`. The `c583` pixel shader ignores `TEXCOORD0` and derives its
downsample coordinates from `SV_POSITION.xy`. Therefore this pair does not pass
custom bloom or lighting values from VS to PS; the VS is a shared fullscreen
producer used by more than one downstream pixel shader.

## Rebirth Shader Injector comparison

Shader Injector v2.2.1 Maximum Quality fingerprints identify the lighting
families by individual shader stage:

- Pixel: DirectionalLight, LocalLight, LocalLightIES, SSR, PostProcessFinal.
- Compute: ReflectionEnvironment, SampleGI.

The package contains no corresponding replacement vertex-shader families for
those effects. Its replacement pixel shaders consume the engine's existing VS
outputs and preserve the declared interface. VS/PS peer relationships remain
valuable for identifying and validating a complete draw, but the Rebirth donor
does not inject custom values through a paired replacement VS.
