// ---- Created with 3Dmigoto v1.3.16 on Sat Aug 29 14:06:42 2026
Texture2D<float4> t2 : register(t2);

Texture2D<float4> t1 : register(t1);

Texture2D<float4> t0 : register(t0);

cbuffer cb1 : register(b1)
{
  float4 cb1[123];
}

cbuffer cb0 : register(b0)
{
  float4 cb0[19];
}




// 3Dmigoto declarations
#define cmp -
Texture1D<float4> IniParams : register(t120);
Texture2D<float4> StereoParams : register(t125);


void main(
  float4 v0 : TEXCOORD0,
  float4 v1 : SV_Position0,
  out float4 o0 : SV_Target0)
{
  float4 r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10;
  uint4 bitmask, uiDest;
  float4 fDest;

  r0.xyzw = floor(v1.xyxy);
  r1.xy = (int2)r0.zw;
  r2.x = dot(r0.zw, float2(0.0671105608,0.00583714992));
  r2.x = frac(r2.x);
  r2.x = 52.9829178 * r2.x;
  r2.xz = frac(r2.xx);
  r0.xyzw = float4(32.6650009,11.8149996,0.5,0.5) + r0.xyzw;
  r0.x = dot(r0.xy, float2(0.0671105608,0.00583714992));
  r0.x = frac(r0.x);
  r0.x = 52.9829178 * r0.x;
  r2.yw = frac(r0.xx);
  r0.xy = r2.zw * float2(0.5,0.5) + float2(-0.25,-0.25);
  r3.xy = -cb1[121].xy + r0.zw;
  r0.xy = r3.xy * float2(0.0625,0.0625) + r0.xy;
  r0.xy = floor(r0.xy);
  r0.xy = (int2)r0.xy;
  r3.xy = float2(15,15) + cb1[122].xy;
  r3.xy = float2(0.0625,0.0625) * r3.xy;
  r3.xy = (int2)r3.xy;
  r0.xy = max(int2(0,0), (int2)r0.xy);
  r3.xy = min((int2)r0.xy, (int2)r3.xy);
  r3.zw = float2(0,0);
  r3.xyzw = t2.Load(r3.xyz).xyzw;
  r4.xyzw = cb0[18].yyyy * r3.zwzw;
  r0.x = dot(r4.zw, r4.zw);
  r1.zw = float2(0,0);
  r5.xyz = t0.Load(r1.xyw).xyz;
  r0.y = cmp(r0.x < 0.25);
  if (r0.y == 0) {
    r3.xy = cb0[18].yy * r3.xy;
    r0.y = dot(r3.xy, r3.xy);
    r3.xy = cb1[122].xy + cb1[121].xy;
    r3.xy = float2(-1,-1) + r3.xy;
    r3.zw = (int2)cb1[121].xy;
    r3.xy = (int2)r3.xy;
    r5.w = 0.5 * r0.x;
    r0.y = cmp(r5.w < r0.y);
    if (r0.y != 0) {
      r6.xyzw = float4(1,1,2,2) + -r2.zwzw;
      r6.xyzw = float4(0.0250000004,0.0250000004,0.0250000004,0.0250000004) * r6.xyzw;
      r7.xy = r6.xx * r4.zw + r0.zw;
      r7.xy = floor(r7.xy);
      r7.xy = (int2)r7.xy;
      r7.xy = max((int2)r7.xy, (int2)r3.zw);
      r7.xy = min((int2)r7.xy, (int2)r3.xy);
      r6.xy = -r6.yy * r4.zw + r0.zw;
      r6.xy = floor(r6.xy);
      r6.xy = (int2)r6.xy;
      r6.xy = max((int2)r6.xy, (int2)r3.zw);
      r8.xy = min((int2)r6.xy, (int2)r3.xy);
      r7.zw = float2(0,0);
      r7.xyz = t0.Load(r7.xyz).xyz;
      r8.zw = float2(0,0);
      r8.xyz = t0.Load(r8.xyz).xyz;
      r7.xyz = r8.xyz + r7.xyz;
      r6.xy = r6.zz * r4.zw + r0.zw;
      r6.xy = floor(r6.xy);
      r6.xy = (int2)r6.xy;
      r6.xy = max((int2)r6.xy, (int2)r3.zw);
      r8.xy = min((int2)r6.xy, (int2)r3.xy);
      r6.xy = -r6.ww * r4.zw + r0.zw;
      r6.xy = floor(r6.xy);
      r6.xy = (int2)r6.xy;
      r6.xy = max((int2)r6.xy, (int2)r3.zw);
      r6.xy = min((int2)r6.xy, (int2)r3.xy);
      r8.zw = float2(0,0);
      r8.xyz = t0.Load(r8.xyz).xyz;
      r7.xyz = r8.xyz + r7.xyz;
      r6.zw = float2(0,0);
      r6.xyz = t0.Load(r6.xyz).xyz;
      r6.xyz = r7.xyz + r6.xyz;
      r7.xyzw = float4(3,3,4,4) + -r2.zwzw;
      r7.xyzw = float4(0.0250000004,0.0250000004,0.0250000004,0.0250000004) * r7.xyzw;
      r8.xy = r7.xx * r4.zw + r0.zw;
      r8.xy = floor(r8.xy);
      r8.xy = (int2)r8.xy;
      r8.xy = max((int2)r8.xy, (int2)r3.zw);
      r8.xy = min((int2)r8.xy, (int2)r3.xy);
      r7.xy = -r7.yy * r4.zw + r0.zw;
      r7.xy = floor(r7.xy);
      r7.xy = (int2)r7.xy;
      r7.xy = max((int2)r7.xy, (int2)r3.zw);
      r9.xy = min((int2)r7.xy, (int2)r3.xy);
      r8.zw = float2(0,0);
      r8.xyz = t0.Load(r8.xyz).xyz;
      r6.xyz = r8.xyz + r6.xyz;
      r9.zw = float2(0,0);
      r8.xyz = t0.Load(r9.xyz).xyz;
      r6.xyz = r8.xyz + r6.xyz;
      r7.xy = r7.zz * r4.zw + r0.zw;
      r7.xy = floor(r7.xy);
      r7.xy = (int2)r7.xy;
      r7.xy = max((int2)r7.xy, (int2)r3.zw);
      r8.xy = min((int2)r7.xy, (int2)r3.xy);
      r7.xy = -r7.ww * r4.zw + r0.zw;
      r7.xy = floor(r7.xy);
      r7.xy = (int2)r7.xy;
      r7.xy = max((int2)r7.xy, (int2)r3.zw);
      r7.xy = min((int2)r7.xy, (int2)r3.xy);
      r8.zw = float2(0,0);
      r8.xyz = t0.Load(r8.xyz).xyz;
      r6.xyz = r8.xyz + r6.xyz;
      r7.zw = float2(0,0);
      r7.xyz = t0.Load(r7.xyz).xyz;
      r6.xyz = r7.xyz + r6.xyz;
      r5.xyz = float3(0.125,0.125,0.125) * r6.xyz;
    } else {
      r0.x = rsqrt(r0.x);
      r0.x = 4 * r0.x;
      r1.xy = t1.Load(r1.xyz).xy;
      r0.y = cb0[18].y * r1.x;
      r6.y = min(cb0[18].w, r0.y);
      r7.xyzw = float4(1,1,2,2) + -r2.zwzw;
      r8.xyzw = float4(0.0250000004,0.0250000004,0.0250000004,0.0250000004) * r7.xyzw;
      r1.xz = r8.xx * r4.zw + r0.zw;
      r1.xz = floor(r1.xz);
      r1.xz = (int2)r1.xz;
      r1.xz = max((int2)r1.xz, (int2)r3.zw);
      r9.xy = min((int2)r1.xz, (int2)r3.xy);
      r1.xz = -r8.yy * r4.zw + r0.zw;
      r1.xz = floor(r1.xz);
      r1.xz = (int2)r1.xz;
      r1.xz = max((int2)r1.xz, (int2)r3.zw);
      r10.xy = min((int2)r1.xz, (int2)r3.xy);
      r9.zw = float2(0,0);
      r1.xz = t1.Load(r9.xyw).xy;
      r9.xyz = t0.Load(r9.xyz).xyz;
      r0.y = cb0[18].y * r1.x;
      r6.x = min(cb0[18].w, r0.y);
      r0.y = r1.z + -r1.y;
      r1.xw = saturate(r0.yy * float2(1,-1) + float2(0.5,0.5));
      r7.yw = saturate(r6.yx * r0.xx);
      r0.y = dot(r1.xw, r7.yw);
      r10.zw = float2(0,0);
      r1.xw = t1.Load(r10.xyw).xy;
      r10.xyz = t0.Load(r10.xyz).xyz;
      r1.x = cb0[18].y * r1.x;
      r6.z = min(cb0[18].w, r1.x);
      r1.x = r1.w + -r1.y;
      r7.yw = saturate(r1.xx * float2(1,-1) + float2(0.5,0.5));
      r8.xy = saturate(r6.yz * r0.xx);
      r1.x = dot(r7.yw, r8.xy);
      r1.z = cmp(r1.w < r1.z);
      r1.w = cmp(r6.x < r6.z);
      r5.w = r1.w ? r1.z : 0;
      r5.w = r5.w ? r1.x : r0.y;
      r1.z = (int)r1.w | (int)r1.z;
      r0.y = r1.z ? r1.x : r0.y;
      r1.xzw = r0.yyy * r10.xyz;
      r1.xzw = r5.www * r9.xyz + r1.xzw;
      r0.y = r5.w + r0.y;
      r7.yw = r8.zz * r4.zw + r0.zw;
      r7.yw = floor(r7.yw);
      r7.yw = (int2)r7.yw;
      r7.yw = max((int2)r7.yw, (int2)r3.zw);
      r9.xy = min((int2)r7.yw, (int2)r3.xy);
      r7.yw = -r8.ww * r4.zw + r0.zw;
      r7.yw = floor(r7.yw);
      r7.yw = (int2)r7.yw;
      r7.yw = max((int2)r7.yw, (int2)r3.zw);
      r8.xy = min((int2)r7.yw, (int2)r3.xy);
      r9.zw = float2(0,0);
      r7.yw = t1.Load(r9.xyw).xy;
      r9.xyz = t0.Load(r9.xyz).xyz;
      r5.w = cb0[18].y * r7.y;
      r6.w = min(cb0[18].w, r5.w);
      r5.w = r7.w + -r1.y;
      r10.xy = saturate(r5.ww * float2(1,-1) + float2(0.5,0.5));
      r10.zw = saturate(r0.xx * r6.yw + -r7.xx);
      r5.w = dot(r10.xy, r10.zw);
      r8.zw = float2(0,0);
      r10.xy = t1.Load(r8.xyw).xy;
      r8.xyz = t0.Load(r8.xyz).xyz;
      r7.y = cb0[18].y * r10.x;
      r6.x = min(cb0[18].w, r7.y);
      r7.y = r10.y + -r1.y;
      r10.xz = saturate(r7.yy * float2(1,-1) + float2(0.5,0.5));
      r7.xy = saturate(r0.xx * r6.yx + -r7.xx);
      r7.x = dot(r10.xz, r7.xy);
      r7.y = cmp(r10.y < r7.w);
      r7.w = cmp(r6.w < r6.x);
      r8.w = r7.w ? r7.y : 0;
      r8.w = r8.w ? r7.x : r5.w;
      r7.y = (int)r7.w | (int)r7.y;
      r5.w = r7.y ? r7.x : r5.w;
      r1.xzw = r8.www * r9.xyz + r1.xzw;
      r1.xzw = r5.www * r8.xyz + r1.xzw;
      r0.y = r8.w + r0.y;
      r0.y = r0.y + r5.w;
      r2.xyzw = float4(3,3,4,4) + -r2.xyzw;
      r8.xyzw = float4(0.0250000004,0.0250000004,0.0250000004,0.0250000004) * r2.xyzw;
      r2.yz = r8.xx * r4.zw + r0.zw;
      r2.yz = floor(r2.yz);
      r2.yz = (int2)r2.yz;
      r2.yz = max((int2)r2.yz, (int2)r3.zw);
      r9.xy = min((int2)r2.yz, (int2)r3.xy);
      r2.yz = -r8.yy * r4.zw + r0.zw;
      r2.yz = floor(r2.yz);
      r2.yz = (int2)r2.yz;
      r2.yz = max((int2)r2.yz, (int2)r3.zw);
      r10.xy = min((int2)r2.yz, (int2)r3.xy);
      r9.zw = float2(0,0);
      r2.yz = t1.Load(r9.xyw).xy;
      r7.xyw = t0.Load(r9.xyz).xyz;
      r2.y = cb0[18].y * r2.y;
      r6.z = min(cb0[18].w, r2.y);
      r2.y = r2.z + -r1.y;
      r2.yw = saturate(r2.yy * float2(1,-1) + float2(0.5,0.5));
      r8.xy = saturate(r0.xx * r6.yz + -r7.zz);
      r2.y = dot(r2.yw, r8.xy);
      r10.zw = float2(0,0);
      r8.xy = t1.Load(r10.xyw).xy;
      r9.xyz = t0.Load(r10.xyz).xyz;
      r2.w = cb0[18].y * r8.x;
      r6.w = min(cb0[18].w, r2.w);
      r2.w = r8.y + -r1.y;
      r10.xy = saturate(r2.ww * float2(1,-1) + float2(0.5,0.5));
      r10.zw = saturate(r0.xx * r6.yw + -r7.zz);
      r2.w = dot(r10.xy, r10.zw);
      r2.z = cmp(r8.y < r2.z);
      r5.w = cmp(r6.z < r6.w);
      r6.w = r2.z ? r5.w : 0;
      r6.w = r6.w ? r2.w : r2.y;
      r2.z = (int)r2.z | (int)r5.w;
      r2.y = r2.z ? r2.w : r2.y;
      r1.xzw = r6.www * r7.xyw + r1.xzw;
      r1.xzw = r2.yyy * r9.xyz + r1.xzw;
      r0.y = r6.w + r0.y;
      r0.y = r0.y + r2.y;
      r2.yz = r8.zz * r4.xy + r0.zw;
      r2.yz = floor(r2.yz);
      r2.yz = (int2)r2.yz;
      r2.yz = max((int2)r2.yz, (int2)r3.zw);
      r7.xy = min((int2)r2.yz, (int2)r3.xy);
      r0.zw = -r8.ww * r4.zw + r0.zw;
      r0.zw = floor(r0.zw);
      r0.zw = (int2)r0.zw;
      r0.zw = max((int2)r0.zw, (int2)r3.zw);
      r3.xy = min((int2)r0.zw, (int2)r3.xy);
      r7.zw = float2(0,0);
      r0.zw = t1.Load(r7.xyw).xy;
      r2.yzw = t0.Load(r7.xyz).xyz;
      r0.z = cb0[18].y * r0.z;
      r6.x = min(cb0[18].w, r0.z);
      r0.z = r0.w + -r1.y;
      r4.xy = saturate(r0.zz * float2(1,-1) + float2(0.5,0.5));
      r4.zw = saturate(r0.xx * r6.yx + -r2.xx);
      r0.z = dot(r4.xy, r4.zw);
      r3.zw = float2(0,0);
      r4.xy = t1.Load(r3.xyw).xy;
      r3.xyz = t0.Load(r3.xyz).xyz;
      r3.w = cb0[18].y * r4.x;
      r6.z = min(cb0[18].w, r3.w);
      r1.y = r4.y + -r1.y;
      r4.xz = saturate(r1.yy * float2(1,-1) + float2(0.5,0.5));
      r6.yw = saturate(r0.xx * r6.yz + -r2.xx);
      r0.x = dot(r4.xz, r6.yw);
      r0.w = cmp(r4.y < r0.w);
      r1.y = cmp(r6.x < r6.z);
      r2.x = r0.w ? r1.y : 0;
      r2.x = r2.x ? r0.x : r0.z;
      r0.w = (int)r0.w | (int)r1.y;
      r0.x = r0.w ? r0.x : r0.z;
      r1.xyz = r2.xxx * r2.yzw + r1.xzw;
      r1.xyz = r0.xxx * r3.xyz + r1.xyz;
      r0.y = r2.x + r0.y;
      r0.x = r0.y + r0.x;
      r0.x = -r0.x * 0.125 + 1;
      r0.x = max(0, r0.x);
      r0.yzw = float3(0.125,0.125,0.125) * r1.xyz;
      r5.xyz = r0.xxx * r5.xyz + r0.yzw;
    }
  }
  // Generated scene-only saturation control. The HUD is composed after this pass.
  float sceneLuma = dot(r5.xyz, float3(0.2126, 0.7152, 0.0722));
  o0.xyz = lerp(sceneLuma.xxx, r5.xyz, 0.75);
  o0.w = 0;
  return;
}

/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Original ASM ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//
// Generated by Microsoft (R) D3D Shader Disassembler
//
//   using 3Dmigoto v1.3.16 on Sat Aug 29 14:06:42 2026
//
//
// Input signature:
//
// Name                 Index   Mask Register SysValue  Format   Used
// -------------------- ----- ------ -------- -------- ------- ------
// TEXCOORD                 0   xyzw        0     NONE   float
// SV_Position              0   xyzw        1      POS   float   xy
//
//
// Output signature:
//
// Name                 Index   Mask Register SysValue  Format   Used
// -------------------- ----- ------ -------- -------- ------- ------
// SV_Target                0   xyzw        0   TARGET   float   xyzw
//
ps_5_0
dcl_globalFlags refactoringAllowed
dcl_constantbuffer cb0[19], immediateIndexed
dcl_constantbuffer cb1[123], immediateIndexed
dcl_resource_texture2d (float,float,float,float) t0
dcl_resource_texture2d (float,float,float,float) t1
dcl_resource_texture2d (float,float,float,float) t2
dcl_input_ps_siv linear noperspective v1.xy, position
dcl_output o0.xyzw
dcl_temps 11
round_ni r0.xyzw, v1.xyxy
ftoi r1.xy, r0.zwzz
dp2 r2.x, r0.zwzz, l(0.0671105608, 0.00583714992, 0.000000, 0.000000)
frc r2.x, r2.x
mul r2.x, r2.x, l(52.982918)
frc r2.xz, r2.xxxx
add r0.xyzw, r0.xyzw, l(32.665001, 11.815000, 0.500000, 0.500000)
dp2 r0.x, r0.xyxx, l(0.0671105608, 0.00583714992, 0.000000, 0.000000)
frc r0.x, r0.x
mul r0.x, r0.x, l(52.982918)
frc r2.yw, r0.xxxx
mad r0.xy, r2.zwzz, l(0.500000, 0.500000, 0.000000, 0.000000), l(-0.250000, -0.250000, 0.000000, 0.000000)
add r3.xy, r0.zwzz, -cb1[121].xyxx
mad r0.xy, r3.xyxx, l(0.062500, 0.062500, 0.000000, 0.000000), r0.xyxx
round_ni r0.xy, r0.xyxx
ftoi r0.xy, r0.xyxx
add r3.xy, cb1[122].xyxx, l(15.000000, 15.000000, 0.000000, 0.000000)
mul r3.xy, r3.xyxx, l(0.062500, 0.062500, 0.000000, 0.000000)
ftoi r3.xy, r3.xyxx
imax r0.xy, r0.xyxx, l(0, 0, 0, 0)
imin r3.xy, r3.xyxx, r0.xyxx
mov r3.zw, l(0,0,0,0)
ld_indexable(texture2d)(float,float,float,float) r3.xyzw, r3.xyzw, t2.xyzw
mul r4.xyzw, r3.zwzw, cb0[18].yyyy
dp2 r0.x, r4.zwzz, r4.zwzz
mov r1.zw, l(0,0,0,0)
ld_indexable(texture2d)(float,float,float,float) r5.xyz, r1.xyww, t0.xyzw
lt r0.y, r0.x, l(0.250000)
if_z r0.y
  mul r3.xy, r3.xyxx, cb0[18].yyyy
  dp2 r0.y, r3.xyxx, r3.xyxx
  add r3.xy, cb1[121].xyxx, cb1[122].xyxx
  add r3.xy, r3.xyxx, l(-1.000000, -1.000000, 0.000000, 0.000000)
  ftoi r3.zw, cb1[121].xxxy
  ftoi r3.xy, r3.xyxx
  mul r5.w, r0.x, l(0.500000)
  lt r0.y, r5.w, r0.y
  if_nz r0.y
    add r6.xyzw, -r2.zwzw, l(1.000000, 1.000000, 2.000000, 2.000000)
    mul r6.xyzw, r6.xyzw, l(0.025000, 0.025000, 0.025000, 0.025000)
    mad r7.xy, r6.xxxx, r4.zwzz, r0.zwzz
    round_ni r7.xy, r7.xyxx
    ftoi r7.xy, r7.xyxx
    imax r7.xy, r3.zwzz, r7.xyxx
    imin r7.xy, r3.xyxx, r7.xyxx
    mad r6.xy, -r6.yyyy, r4.zwzz, r0.zwzz
    round_ni r6.xy, r6.xyxx
    ftoi r6.xy, r6.xyxx
    imax r6.xy, r3.zwzz, r6.xyxx
    imin r8.xy, r3.xyxx, r6.xyxx
    mov r7.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r7.xyz, r7.xyzw, t0.xyzw
    mov r8.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r8.xyz, r8.xyzw, t0.xyzw
    add r7.xyz, r7.xyzx, r8.xyzx
    mad r6.xy, r6.zzzz, r4.zwzz, r0.zwzz
    round_ni r6.xy, r6.xyxx
    ftoi r6.xy, r6.xyxx
    imax r6.xy, r3.zwzz, r6.xyxx
    imin r8.xy, r3.xyxx, r6.xyxx
    mad r6.xy, -r6.wwww, r4.zwzz, r0.zwzz
    round_ni r6.xy, r6.xyxx
    ftoi r6.xy, r6.xyxx
    imax r6.xy, r3.zwzz, r6.xyxx
    imin r6.xy, r3.xyxx, r6.xyxx
    mov r8.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r8.xyz, r8.xyzw, t0.xyzw
    add r7.xyz, r7.xyzx, r8.xyzx
    mov r6.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r6.xyz, r6.xyzw, t0.xyzw
    add r6.xyz, r6.xyzx, r7.xyzx
    add r7.xyzw, -r2.zwzw, l(3.000000, 3.000000, 4.000000, 4.000000)
    mul r7.xyzw, r7.xyzw, l(0.025000, 0.025000, 0.025000, 0.025000)
    mad r8.xy, r7.xxxx, r4.zwzz, r0.zwzz
    round_ni r8.xy, r8.xyxx
    ftoi r8.xy, r8.xyxx
    imax r8.xy, r3.zwzz, r8.xyxx
    imin r8.xy, r3.xyxx, r8.xyxx
    mad r7.xy, -r7.yyyy, r4.zwzz, r0.zwzz
    round_ni r7.xy, r7.xyxx
    ftoi r7.xy, r7.xyxx
    imax r7.xy, r3.zwzz, r7.xyxx
    imin r9.xy, r3.xyxx, r7.xyxx
    mov r8.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r8.xyz, r8.xyzw, t0.xyzw
    add r6.xyz, r6.xyzx, r8.xyzx
    mov r9.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r8.xyz, r9.xyzw, t0.xyzw
    add r6.xyz, r6.xyzx, r8.xyzx
    mad r7.xy, r7.zzzz, r4.zwzz, r0.zwzz
    round_ni r7.xy, r7.xyxx
    ftoi r7.xy, r7.xyxx
    imax r7.xy, r3.zwzz, r7.xyxx
    imin r8.xy, r3.xyxx, r7.xyxx
    mad r7.xy, -r7.wwww, r4.zwzz, r0.zwzz
    round_ni r7.xy, r7.xyxx
    ftoi r7.xy, r7.xyxx
    imax r7.xy, r3.zwzz, r7.xyxx
    imin r7.xy, r3.xyxx, r7.xyxx
    mov r8.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r8.xyz, r8.xyzw, t0.xyzw
    add r6.xyz, r6.xyzx, r8.xyzx
    mov r7.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r7.xyz, r7.xyzw, t0.xyzw
    add r6.xyz, r6.xyzx, r7.xyzx
    mul r5.xyz, r6.xyzx, l(0.125000, 0.125000, 0.125000, 0.000000)
  else
    rsq r0.x, r0.x
    mul r0.x, r0.x, l(4.000000)
    ld_indexable(texture2d)(float,float,float,float) r1.xy, r1.xyzw, t1.xyzw
    mul r0.y, r1.x, cb0[18].y
    min r6.y, r0.y, cb0[18].w
    add r7.xyzw, -r2.zwzw, l(1.000000, 1.000000, 2.000000, 2.000000)
    mul r8.xyzw, r7.xyzw, l(0.025000, 0.025000, 0.025000, 0.025000)
    mad r1.xz, r8.xxxx, r4.zzwz, r0.zzwz
    round_ni r1.xz, r1.xxzx
    ftoi r1.xz, r1.xxzx
    imax r1.xz, r3.zzwz, r1.xxzx
    imin r9.xy, r3.xyxx, r1.xzxx
    mad r1.xz, -r8.yyyy, r4.zzwz, r0.zzwz
    round_ni r1.xz, r1.xxzx
    ftoi r1.xz, r1.xxzx
    imax r1.xz, r3.zzwz, r1.xxzx
    imin r10.xy, r3.xyxx, r1.xzxx
    mov r9.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r1.xz, r9.xyww, t1.xzyw
    ld_indexable(texture2d)(float,float,float,float) r9.xyz, r9.xyzw, t0.xyzw
    mul r0.y, r1.x, cb0[18].y
    min r6.x, r0.y, cb0[18].w
    add r0.y, -r1.y, r1.z
    mad_sat r1.xw, r0.yyyy, l(1.000000, 0.000000, 0.000000, -1.000000), l(0.500000, 0.000000, 0.000000, 0.500000)
    mul_sat r7.yw, r0.xxxx, r6.yyyx
    dp2 r0.y, r1.xwxx, r7.ywyy
    mov r10.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r1.xw, r10.xyww, t1.xzwy
    ld_indexable(texture2d)(float,float,float,float) r10.xyz, r10.xyzw, t0.xyzw
    mul r1.x, r1.x, cb0[18].y
    min r6.z, r1.x, cb0[18].w
    add r1.x, -r1.y, r1.w
    mad_sat r7.yw, r1.xxxx, l(0.000000, 1.000000, 0.000000, -1.000000), l(0.000000, 0.500000, 0.000000, 0.500000)
    mul_sat r8.xy, r0.xxxx, r6.yzyy
    dp2 r1.x, r7.ywyy, r8.xyxx
    lt r1.z, r1.w, r1.z
    lt r1.w, r6.x, r6.z
    and r5.w, r1.w, r1.z
    movc r5.w, r5.w, r1.x, r0.y
    or r1.z, r1.w, r1.z
    movc r0.y, r1.z, r1.x, r0.y
    mul r1.xzw, r10.xxyz, r0.yyyy
    mad r1.xzw, r5.wwww, r9.xxyz, r1.xxzw
    add r0.y, r0.y, r5.w
    mad r7.yw, r8.zzzz, r4.zzzw, r0.zzzw
    round_ni r7.yw, r7.yyyw
    ftoi r7.yw, r7.yyyw
    imax r7.yw, r3.zzzw, r7.yyyw
    imin r9.xy, r3.xyxx, r7.ywyy
    mad r7.yw, -r8.wwww, r4.zzzw, r0.zzzw
    round_ni r7.yw, r7.yyyw
    ftoi r7.yw, r7.yyyw
    imax r7.yw, r3.zzzw, r7.yyyw
    imin r8.xy, r3.xyxx, r7.ywyy
    mov r9.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r7.yw, r9.xyww, t1.zxwy
    ld_indexable(texture2d)(float,float,float,float) r9.xyz, r9.xyzw, t0.xyzw
    mul r5.w, r7.y, cb0[18].y
    min r6.w, r5.w, cb0[18].w
    add r5.w, -r1.y, r7.w
    mad_sat r10.xy, r5.wwww, l(1.000000, -1.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
    mad_sat r10.zw, r0.xxxx, r6.yyyw, -r7.xxxx
    dp2 r5.w, r10.xyxx, r10.zwzz
    mov r8.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r10.xy, r8.xyww, t1.xyzw
    ld_indexable(texture2d)(float,float,float,float) r8.xyz, r8.xyzw, t0.xyzw
    mul r7.y, r10.x, cb0[18].y
    min r6.x, r7.y, cb0[18].w
    add r7.y, -r1.y, r10.y
    mad_sat r10.xz, r7.yyyy, l(1.000000, 0.000000, -1.000000, 0.000000), l(0.500000, 0.000000, 0.500000, 0.000000)
    mad_sat r7.xy, r0.xxxx, r6.yxyy, -r7.xxxx
    dp2 r7.x, r10.xzxx, r7.xyxx
    lt r7.y, r10.y, r7.w
    lt r7.w, r6.w, r6.x
    and r8.w, r7.w, r7.y
    movc r8.w, r8.w, r7.x, r5.w
    or r7.y, r7.w, r7.y
    movc r5.w, r7.y, r7.x, r5.w
    mad r1.xzw, r8.wwww, r9.xxyz, r1.xxzw
    mad r1.xzw, r5.wwww, r8.xxyz, r1.xxzw
    add r0.y, r0.y, r8.w
    add r0.y, r5.w, r0.y
    add r2.xyzw, -r2.xyzw, l(3.000000, 3.000000, 4.000000, 4.000000)
    mul r8.xyzw, r2.xyzw, l(0.025000, 0.025000, 0.025000, 0.025000)
    mad r2.yz, r8.xxxx, r4.zzwz, r0.zzwz
    round_ni r2.yz, r2.yyzy
    ftoi r2.yz, r2.yyzy
    imax r2.yz, r3.zzwz, r2.yyzy
    imin r9.xy, r3.xyxx, r2.yzyy
    mad r2.yz, -r8.yyyy, r4.zzwz, r0.zzwz
    round_ni r2.yz, r2.yyzy
    ftoi r2.yz, r2.yyzy
    imax r2.yz, r3.zzwz, r2.yyzy
    imin r10.xy, r3.xyxx, r2.yzyy
    mov r9.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r2.yz, r9.xyww, t1.zxyw
    ld_indexable(texture2d)(float,float,float,float) r7.xyw, r9.xyzw, t0.xywz
    mul r2.y, r2.y, cb0[18].y
    min r6.z, r2.y, cb0[18].w
    add r2.y, -r1.y, r2.z
    mad_sat r2.yw, r2.yyyy, l(0.000000, 1.000000, 0.000000, -1.000000), l(0.000000, 0.500000, 0.000000, 0.500000)
    mad_sat r8.xy, r0.xxxx, r6.yzyy, -r7.zzzz
    dp2 r2.y, r2.ywyy, r8.xyxx
    mov r10.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r8.xy, r10.xyww, t1.xyzw
    ld_indexable(texture2d)(float,float,float,float) r9.xyz, r10.xyzw, t0.xyzw
    mul r2.w, r8.x, cb0[18].y
    min r6.w, r2.w, cb0[18].w
    add r2.w, -r1.y, r8.y
    mad_sat r10.xy, r2.wwww, l(1.000000, -1.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
    mad_sat r10.zw, r0.xxxx, r6.yyyw, -r7.zzzz
    dp2 r2.w, r10.xyxx, r10.zwzz
    lt r2.z, r8.y, r2.z
    lt r5.w, r6.z, r6.w
    and r6.w, r2.z, r5.w
    movc r6.w, r6.w, r2.w, r2.y
    or r2.z, r2.z, r5.w
    movc r2.y, r2.z, r2.w, r2.y
    mad r1.xzw, r6.wwww, r7.xxyw, r1.xxzw
    mad r1.xzw, r2.yyyy, r9.xxyz, r1.xxzw
    add r0.y, r0.y, r6.w
    add r0.y, r2.y, r0.y
    mad r2.yz, r8.zzzz, r4.xxyx, r0.zzwz
    round_ni r2.yz, r2.yyzy
    ftoi r2.yz, r2.yyzy
    imax r2.yz, r3.zzwz, r2.yyzy
    imin r7.xy, r3.xyxx, r2.yzyy
    mad r0.zw, -r8.wwww, r4.zzzw, r0.zzzw
    round_ni r0.zw, r0.zzzw
    ftoi r0.zw, r0.zzzw
    imax r0.zw, r3.zzzw, r0.zzzw
    imin r3.xy, r3.xyxx, r0.zwzz
    mov r7.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r0.zw, r7.xyww, t1.zwxy
    ld_indexable(texture2d)(float,float,float,float) r2.yzw, r7.xyzw, t0.wxyz
    mul r0.z, r0.z, cb0[18].y
    min r6.x, r0.z, cb0[18].w
    add r0.z, -r1.y, r0.w
    mad_sat r4.xy, r0.zzzz, l(1.000000, -1.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
    mad_sat r4.zw, r0.xxxx, r6.yyyx, -r2.xxxx
    dp2 r0.z, r4.xyxx, r4.zwzz
    mov r3.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r4.xy, r3.xyww, t1.xyzw
    ld_indexable(texture2d)(float,float,float,float) r3.xyz, r3.xyzw, t0.xyzw
    mul r3.w, r4.x, cb0[18].y
    min r6.z, r3.w, cb0[18].w
    add r1.y, -r1.y, r4.y
    mad_sat r4.xz, r1.yyyy, l(1.000000, 0.000000, -1.000000, 0.000000), l(0.500000, 0.000000, 0.500000, 0.000000)
    mad_sat r6.yw, r0.xxxx, r6.yyyz, -r2.xxxx
    dp2 r0.x, r4.xzxx, r6.ywyy
    lt r0.w, r4.y, r0.w
    lt r1.y, r6.x, r6.z
    and r2.x, r0.w, r1.y
    movc r2.x, r2.x, r0.x, r0.z
    or r0.w, r0.w, r1.y
    movc r0.x, r0.w, r0.x, r0.z
    mad r1.xyz, r2.xxxx, r2.yzwy, r1.xzwx
    mad r1.xyz, r0.xxxx, r3.xyzx, r1.xyzx
    add r0.y, r0.y, r2.x
    add r0.x, r0.x, r0.y
    mad r0.x, -r0.x, l(0.125000), l(1.000000)
    max r0.x, r0.x, l(0.000000)
    mul r0.yzw, r1.xxyz, l(0.000000, 0.125000, 0.125000, 0.125000)
    mad r5.xyz, r0.xxxx, r5.xyzx, r0.yzwy
  endif
endif
mov o0.xyz, r5.xyzx
mov o0.w, l(0)
ret
// Approximately 0 instruction slots used

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
