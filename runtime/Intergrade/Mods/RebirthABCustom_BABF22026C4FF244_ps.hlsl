// ---- Created with 3Dmigoto v1.3.16 on Sat Aug 29 14:06:43 2026
Texture2D<float4> t8 : register(t8);

Texture2D<float4> t7 : register(t7);

Texture2D<float4> t6 : register(t6);

Texture2D<float4> t5 : register(t5);

Texture2D<float4> t4 : register(t4);

Texture2D<float4> t3 : register(t3);

Texture2D<float4> t2 : register(t2);

Texture2D<float4> t1 : register(t1);

Texture3D<float4> t0 : register(t0);

cbuffer cb1 : register(b1)
{
  float4 cb1[140];
}

cbuffer cb0 : register(b0)
{
  float4 cb0[21];
}




// 3Dmigoto declarations
#define cmp -
Texture1D<float4> IniParams : register(t120);
Texture2D<float4> StereoParams : register(t125);


void main(
  float4 v0 : TEXCOORD0,
  float4 v1 : SV_POSITION0,
  out float4 o0 : SV_Target0)
{
  float4 r0,r1,r2,r3,r4,r5,r6,r7,r8;
  uint4 bitmask, uiDest;
  float4 fDest;

  r0.xy = cb1[121].xy + v1.xy;
  r0.xy = (uint2)r0.xy;
  r0.zw = float2(0,0);
  r1.xy = t2.Load(r0.xyw).zw;
  r1.y = r1.y * 255 + 0.5;
  r1.y = (uint)r1.y;
  r1.y = (int)r1.y & 15;
  if (r1.y != 0) {
    r2.xyzw = t1.Load(r0.xyw).xyzw;
    r2.xyz = r2.xyz * float3(2,2,2) + float3(-1,-1,-1);
    r1.z = dot(r2.xyz, r2.xyz);
    r1.z = rsqrt(r1.z);
    r3.xyz = r2.xyz * r1.zzz;
    r4.xy = float2(1,0.577000022) * r1.xx;
    r1.w = dot(float2(0.850000024,0.150000006), r4.xy);
    r4.xyzw = cmp((int4)r1.yyyy == int4(3,7,8,1));
    r1.x = r4.z ? 1 : r1.x;
    r1.x = r4.y ? 0.479999989 : r1.x;
    r1.x = r4.x ? r1.w : r1.x;
    r1.w = t4.Load(r0.xyw).x;
    r3.w = r1.w * cb1[57].x + cb1[57].y;
    r1.w = r1.w * cb1[57].z + -cb1[57].w;
    r1.w = rcp(r1.w);
    r1.w = r3.w + r1.w;
    r4.xy = -cb1[121].xy + v1.xy;
    r4.xy = cb1[122].zw * r4.xy;
    r4.xy = r4.xy * float2(2,-2) + float2(-1,1);
    r5.xy = r4.xy * r1.ww;
    r5.yzw = cb1[45].xyz * r5.yyy;
    r5.xyz = r5.xxx * cb1[44].xyz + r5.yzw;
    r5.xyz = r1.www * cb1[46].xyz + r5.xyz;
    r5.xyz = cb1[47].xyz + r5.xyz;
    r6.xyz = cb1[60].xyz + -r5.xyz;
    r3.w = dot(r6.xyz, r6.xyz);
    r3.w = rsqrt(r3.w);
    r6.xyz = r6.xyz * r3.www;
    r7.xyz = r3.xyz + r3.xyz;
    r3.x = dot(r3.xyz, r6.xyz);
    r3.xyz = r7.xyz * r3.xxx + -r6.xyz;
    r3.w = dot(r3.xyz, r3.xyz);
    r3.w = rsqrt(r3.w);
    r3.xyz = r3.xyz * r3.www;
    r3.w = r1.x * r1.x;
    r1.x = r3.w * r1.x;
    r2.xyz = r2.xyz * r1.zzz + -r3.xyz;
    r2.xyz = r1.xxx * r2.xyz + r3.xyz;
    r1.x = dot(r2.xyz, r2.xyz);
    r1.x = rsqrt(r1.x);
    r2.xyz = r2.xyz * r1.xxx;
    r1.x = cmp((int)r1.y == 5);
    r1.x = (int)r1.x | (int)r4.w;
    if (r1.x != 0) {
      r0.xyz = t3.Load(r0.xyz).xyz;
      r0.xyz = r0.xyz * float3(2,2,2) + float3(-1,-1,-1);
      r0.w = dot(r0.xyz, r0.xyz);
      r0.w = rsqrt(r0.w);
      r0.xyz = r0.xyz * r0.www;
      r0.w = dot(r0.xyz, r2.xyz);
      r0.w = abs(r0.w) + -r0.w;
      r0.xyz = r0.www * r0.xyz + r2.xyz;
      r0.w = dot(r0.xyz, r0.xyz);
      r0.w = rsqrt(r0.w);
      r2.xyz = r0.xyz * r0.www;
    }
    r0.z = asuint(cb1[139].z) << 3;
    r0.xy = (int2)v1.xy;
    r0.xyz = (int3)r0.xyz & int3(63,63,63);
    r0.w = 0;
    r0.x = t0.Load(r0.xyzw).x;
    r0.y = max(9.99999975e-006, r3.w);
    r0.y = rcp(r0.y);
    r0.y = 10 * r0.y;
    r6.xyzw = cb1[1].xyzw * r5.yyyy;
    r6.xyzw = r5.xxxx * cb1[0].xyzw + r6.xyzw;
    r6.xyzw = r5.zzzz * cb1[2].xyzw + r6.xyzw;
    r6.xyzw = cb1[3].xyzw + r6.xyzw;
    r1.xyz = r2.xyz * r1.www;
    r7.xyzw = cb1[1].xyzw * r1.yyyy;
    r7.xyzw = r1.xxxx * cb1[0].xyzw + r7.xyzw;
    r7.xyzw = r1.zzzz * cb1[2].xyzw + r7.xyzw;
    r7.xyzw = r7.xyzw + r6.xyzw;
    r0.yzw = r0.yyy * cb1[24].xyw + r6.xyw;
    r1.xy = r1.ww * cb1[26].zw + r6.zw;
    r2.xyz = r6.xyz / r6.www;
    r3.xyz = r7.xyz / r7.www;
    r0.yz = r0.yz / r0.ww;
    r0.w = r1.x / r1.y;
    r1.xyz = r3.xyz + -r2.xyz;
    r0.yz = r0.yz + -r2.xy;
    r1.w = dot(r1.xy, r1.xy);
    r1.w = sqrt(r1.w);
    r3.x = 0.5 * r1.w;
    r3.yz = r2.xy * r3.xx + r1.xy;
    r3.yz = -r1.ww * float2(0.5,0.5) + abs(r3.yz);
    r3.yz = max(float2(0,0), r3.yz);
    r3.yz = -r3.yz + abs(r1.xy);
    r3.yz = r3.yz / abs(r1.xy);
    r1.w = min(r3.y, r3.z);
    r1.xyz = r1.www * r1.xyz;
    r1.xyz = r1.xyz / r3.xxx;
    r0.y = dot(r0.yz, r0.yz);
    r0.z = dot(r1.xy, r1.xy);
    r0.yz = sqrt(r0.yz);
    r0.z = max(9.99999975e-005, r0.z);
    r0.z = rcp(r0.z);
    r0.y = r0.y * r0.z;
    r0.y = min(1, r0.y);
    r0.y = r0.y * 8 + r0.x;
    r0.y = ceil(r0.y);
    r0.y = (uint)r0.y;
    r0.y = min(8, (uint)r0.y);
    r0.y = max(1, (uint)r0.y);
    r3.xy = r2.xy * float2(0.5,-0.5) + float2(0.5,0.5);
    r2.xy = cb0[18].xy * r3.xy;
    r1.xy = cb0[18].xy * r1.xy;
    r1.xyw = float3(0.0625,-0.0625,0.125) * r1.xyz;
    r0.z = r2.z + -r0.w;
    r0.z = max(abs(r1.z), r0.z);
    r0.w = 0.125 * r0.z;
    t5.GetDimensions(0, fDest.x, fDest.y, fDest.z);
    r3.xy = fDest.xy;
    r4.zw = float2(-1,-1) + r3.xy;
    r6.zw = float2(0,0);
    r3.z = 0;
    r5.w = 0;
    r7.xyzw = float4(0,0,0,0);
    while (true) {
      r8.x = cmp((uint)r7.w >= (uint)r0.y);
      if (r8.x != 0) break;
      r8.x = (uint)r7.w;
      r8.x = r8.x + r0.x;
      r8.yzw = r1.xyw * r8.xxx + r2.xyz;
      r8.yz = r8.yz * r3.xy;
      r8.yz = max(float2(0,0), r8.yz);
      r8.yz = min(r8.yz, r4.zw);
      r6.xy = (uint2)r8.yz;
      r6.x = t5.Load(r6.xyz).x;
      r6.x = r8.w + -r6.x;
      r6.y = -r0.z * 0.125 + -r6.x;
      r6.y = cmp(abs(r6.y) < r0.w);
      if (r6.y != 0) {
        r6.y = -r1.z * 0.125 + r6.x;
        r6.y = r7.w ? r5.w : r6.y;
        r8.x = -1 + r8.x;
        r8.y = r6.y + -r6.x;
        r6.y = saturate(r6.y / r8.y);
        r6.y = r8.x + r6.y;
        r7.xyz = r1.xyw * abs(r6.yyy) + r2.xyz;
        r6.y = 0.125 * abs(r6.y);
        r6.y = min(1, r6.y);
        r3.z = -r6.y * r6.y + 1;
        break;
      }
      r5.w = r6.x;
      r7.w = (int)r7.w + 1;
      r7.xyz = float3(0,0,0);
      r3.z = 0;
    }
    r0.xy = cb0[18].zw * r7.xy;
    r0.xy = r0.xy * float2(2,-2) + float2(-1,1);
    r0.z = cmp(0 < r3.z);
    if (r0.z != 0) {
      r0.z = r2.w * 3 + 0.5;
      r0.z = (uint)r0.z;
      r0.w = r7.z * cb1[57].x + cb1[57].y;
      r1.x = r7.z * cb1[57].z + -cb1[57].w;
      r1.x = rcp(r1.x);
      r0.w = r1.x + r0.w;
      r1.xy = r0.xy * r0.ww;
      r1.yzw = cb1[45].xyz * r1.yyy;
      r1.xyz = r1.xxx * cb1[44].xyz + r1.yzw;
      r1.xyz = r0.www * cb1[46].xyz + r1.xyz;
      r1.xyz = cb1[47].xyz + r1.xyz;
      r2.xyz = r1.xyz + -r5.xyz;
      r0.w = dot(r2.xyz, r2.xyz);
      r0.w = sqrt(r0.w);
      r2.xyz = cb1[115].xyw * r0.yyy;
      r2.xyz = r0.xxx * cb1[114].xyw + r2.xyz;
      r2.xyz = r7.zzz * cb1[116].xyw + r2.xyz;
      r2.xyz = cb1[117].xyw + r2.xyz;
      r2.xy = r2.xy / r2.zz;
      r2.zw = r0.xy * cb1[58].xy + cb1[58].wz;
      r2.zw = r2.zw * cb1[126].xy + float2(0.5,0.5);
      r2.zw = (int2)r2.zw;
      r3.xy = cb1[122].xy + cb1[121].xy;
      r3.xy = float2(-1,-1) + r3.xy;
      r4.zw = (int2)cb1[121].xy;
      r3.xy = (int2)r3.xy;
      r2.zw = max((int2)r4.zw, (int2)r2.zw);
      r5.xy = min((int2)r2.zw, (int2)r3.xy);
      r5.zw = float2(0,0);
      r2.zw = t6.Load(r5.xyz).xy;
      r1.w = dot(r2.zw, r2.zw);
      r1.w = cmp(0 < r1.w);
      r2.zw = float2(-0.499992371,-0.499992371) + r2.zw;
      r0.xy = -r2.zw * float2(4.00801611,4.00801611) + r0.xy;
      r0.xy = r1.ww ? r0.xy : r2.xy;
      r2.xy = r0.xy * cb1[123].xy + cb1[123].wz;
      r2.xy = r2.xy * cb1[126].xy + float2(0.5,0.5);
      r2.zw = cb1[125].xy + cb1[124].xy;
      r2.zw = float2(-1,-1) + r2.zw;
      r3.xy = (int2)cb1[124].xy;
      r2.xyzw = (int4)r2.xyzw;
      r2.xy = max((int2)r2.xy, (int2)r3.xy);
      r2.xy = min((int2)r2.xy, (int2)r2.zw);
      r2.zw = float2(0,0);
      r5.xyz = t7.Load(r2.xyw).xyz;
      r5.xyz = min(float3(65504,65504,65504), r5.xyz);
      r2.xyz = t8.Load(r2.xyz).xyz;
      r2.xyz = min(float3(65504,65504,65504), r2.xyz);
      r2.xyz = cb0[20].yyy * r2.xyz;
      r1.x = dot(r1.xyz, r1.xyz);
      r1.x = sqrt(r1.x);
      r1.x = rcp(r1.x);
      r1.x = saturate(r1.x * r0.w);
      r1.yzw = r5.xyz * cb0[20].yyy + -r2.xyz;
      r1.xyz = r1.xxx * r1.yzw + r2.xyz;
      r1.w = 1;
      r1.xyzw = r1.xyzw * r3.zzzz;
      r0.xy = r0.xy + -r4.xy;
      r0.xy = float2(0.5,0.5) * r0.xy;
      r0.xy = saturate(abs(r0.xy) * float2(5,5) + float2(-4,-4));
      r0.x = dot(r0.xy, r0.xy);
      r0.x = 1 + -r0.x;
      r0.x = max(0, r0.x);
      r1.xyzw = r1.xyzw * r0.xxxx;
      r0.x = r0.w * r3.w;
      r0.x = r0.x * r0.x;
      r0.x = max(9.99999975e-006, r0.x);
      r0.x = rcp(r0.x);
      r0.x = min(1, r0.x);
      r1.xyzw = r1.xyzw * r0.xxxx;
      r0.x = (int)r0.z & 2;
      r0.x = r0.x ? cb0[19].y : cb0[19].z;
      r0.x = cb0[19].x * r0.x;
      r0.xyzw = r1.xyzw * r0.xxxx;
      // Control: attenuate reflection radiance only; preserve hit/confidence alpha.
      float ssrStrength = 0.0;
      o0.xyz = cb1[128].xxx * r0.xyz * ssrStrength;
      o0.w = r0.w;
    } else {
      o0.xyzw = float4(0,0,0,0);
    }
  } else {
    o0.xyzw = float4(0,0,0,0);
  }
  return;
}

/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Original ASM ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//
// Generated by Microsoft (R) D3D Shader Disassembler
//
//   using 3Dmigoto v1.3.16 on Sat Aug 29 14:06:43 2026
//
//
// Input signature:
//
// Name                 Index   Mask Register SysValue  Format   Used
// -------------------- ----- ------ -------- -------- ------- ------
// TEXCOORD                 0   xyzw        0     NONE   float
// SV_POSITION              0   xyzw        1      POS   float   xy
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
dcl_constantbuffer cb0[21], immediateIndexed
dcl_constantbuffer cb1[140], immediateIndexed
dcl_resource_texture3d (float,float,float,float) t0
dcl_resource_texture2d (float,float,float,float) t1
dcl_resource_texture2d (float,float,float,float) t2
dcl_resource_texture2d (float,float,float,float) t3
dcl_resource_texture2d (float,float,float,float) t4
dcl_resource_texture2d (float,float,float,float) t5
dcl_resource_texture2d (float,float,float,float) t6
dcl_resource_texture2d (float,float,float,float) t7
dcl_resource_texture2d (float,float,float,float) t8
dcl_input_ps_siv linear noperspective v1.xy, position
dcl_output o0.xyzw
dcl_temps 9
add r0.xy, v1.xyxx, cb1[121].xyxx
ftou r0.xy, r0.xyxx
mov r0.zw, l(0,0,0,0)
ld_indexable(texture2d)(float,float,float,float) r1.xy, r0.xyww, t2.zwxy
mad r1.y, r1.y, l(255.000000), l(0.500000)
ftou r1.y, r1.y
and r1.y, r1.y, l(15)
if_nz r1.y
  ld_indexable(texture2d)(float,float,float,float) r2.xyzw, r0.xyww, t1.xyzw
  mad r2.xyz, r2.xyzx, l(2.000000, 2.000000, 2.000000, 0.000000), l(-1.000000, -1.000000, -1.000000, 0.000000)
  dp3 r1.z, r2.xyzx, r2.xyzx
  rsq r1.z, r1.z
  mul r3.xyz, r1.zzzz, r2.xyzx
  mul r4.xy, r1.xxxx, l(1.000000, 0.577000, 0.000000, 0.000000)
  dp2 r1.w, l(0.850000, 0.150000, 0.000000, 0.000000), r4.xyxx
  ieq r4.xyzw, r1.yyyy, l(3, 7, 8, 1)
  movc r1.x, r4.z, l(1.000000), r1.x
  movc r1.x, r4.y, l(0.480000), r1.x
  movc r1.x, r4.x, r1.w, r1.x
  ld_indexable(texture2d)(float,float,float,float) r1.w, r0.xyww, t4.yzwx
  mad r3.w, r1.w, cb1[57].x, cb1[57].y
  mad r1.w, r1.w, cb1[57].z, -cb1[57].w
  rcp r1.w, r1.w
  add r1.w, r1.w, r3.w
  add r4.xy, v1.xyxx, -cb1[121].xyxx
  mul r4.xy, r4.xyxx, cb1[122].zwzz
  mad r4.xy, r4.xyxx, l(2.000000, -2.000000, 0.000000, 0.000000), l(-1.000000, 1.000000, 0.000000, 0.000000)
  mul r5.xy, r1.wwww, r4.xyxx
  mul r5.yzw, r5.yyyy, cb1[45].xxyz
  mad r5.xyz, r5.xxxx, cb1[44].xyzx, r5.yzwy
  mad r5.xyz, r1.wwww, cb1[46].xyzx, r5.xyzx
  add r5.xyz, r5.xyzx, cb1[47].xyzx
  add r6.xyz, -r5.xyzx, cb1[60].xyzx
  dp3 r3.w, r6.xyzx, r6.xyzx
  rsq r3.w, r3.w
  mul r6.xyz, r3.wwww, r6.xyzx
  add r7.xyz, r3.xyzx, r3.xyzx
  dp3 r3.x, r3.xyzx, r6.xyzx
  mad r3.xyz, r7.xyzx, r3.xxxx, -r6.xyzx
  dp3 r3.w, r3.xyzx, r3.xyzx
  rsq r3.w, r3.w
  mul r3.xyz, r3.wwww, r3.xyzx
  mul r3.w, r1.x, r1.x
  mul r1.x, r1.x, r3.w
  mad r2.xyz, r2.xyzx, r1.zzzz, -r3.xyzx
  mad r2.xyz, r1.xxxx, r2.xyzx, r3.xyzx
  dp3 r1.x, r2.xyzx, r2.xyzx
  rsq r1.x, r1.x
  mul r2.xyz, r1.xxxx, r2.xyzx
  ieq r1.x, r1.y, l(5)
  or r1.x, r1.x, r4.w
  if_nz r1.x
    ld_indexable(texture2d)(float,float,float,float) r0.xyz, r0.xyzw, t3.xyzw
    mad r0.xyz, r0.xyzx, l(2.000000, 2.000000, 2.000000, 0.000000), l(-1.000000, -1.000000, -1.000000, 0.000000)
    dp3 r0.w, r0.xyzx, r0.xyzx
    rsq r0.w, r0.w
    mul r0.xyz, r0.wwww, r0.xyzx
    dp3 r0.w, r0.xyzx, r2.xyzx
    add r0.w, -r0.w, |r0.w|
    mad r0.xyz, r0.wwww, r0.xyzx, r2.xyzx
    dp3 r0.w, r0.xyzx, r0.xyzx
    rsq r0.w, r0.w
    mul r2.xyz, r0.wwww, r0.xyzx
  endif
  ishl r0.z, cb1[139].z, l(3)
  ftoi r0.xy, v1.xyxx
  and r0.xyz, r0.xyzx, l(63, 63, 63, 0)
  mov r0.w, l(0)
  ld_indexable(texture3d)(float,float,float,float) r0.x, r0.xyzw, t0.xyzw
  max r0.y, r3.w, l(0.000010)
  rcp r0.y, r0.y
  mul r0.y, r0.y, l(10.000000)
  mul r6.xyzw, r5.yyyy, cb1[1].xyzw
  mad r6.xyzw, r5.xxxx, cb1[0].xyzw, r6.xyzw
  mad r6.xyzw, r5.zzzz, cb1[2].xyzw, r6.xyzw
  add r6.xyzw, r6.xyzw, cb1[3].xyzw
  mul r1.xyz, r1.wwww, r2.xyzx
  mul r7.xyzw, r1.yyyy, cb1[1].xyzw
  mad r7.xyzw, r1.xxxx, cb1[0].xyzw, r7.xyzw
  mad r7.xyzw, r1.zzzz, cb1[2].xyzw, r7.xyzw
  add r7.xyzw, r6.xyzw, r7.xyzw
  mad r0.yzw, r0.yyyy, cb1[24].xxyw, r6.xxyw
  mad r1.xy, r1.wwww, cb1[26].zwzz, r6.zwzz
  div r2.xyz, r6.xyzx, r6.wwww
  div r3.xyz, r7.xyzx, r7.wwww
  div r0.yz, r0.yyzy, r0.wwww
  div r0.w, r1.x, r1.y
  add r1.xyz, -r2.xyzx, r3.xyzx
  add r0.yz, -r2.xxyx, r0.yyzy
  dp2 r1.w, r1.xyxx, r1.xyxx
  sqrt r1.w, r1.w
  mul r3.x, r1.w, l(0.500000)
  mad r3.yz, r2.xxyx, r3.xxxx, r1.xxyx
  mad r3.yz, -r1.wwww, l(0.000000, 0.500000, 0.500000, 0.000000), |r3.yyzy|
  max r3.yz, r3.yyzy, l(0.000000, 0.000000, 0.000000, 0.000000)
  add r3.yz, |r1.xxyx|, -r3.yyzy
  div r3.yz, r3.yyzy, |r1.xxyx|
  min r1.w, r3.z, r3.y
  mul r1.xyz, r1.xyzx, r1.wwww
  div r1.xyz, r1.xyzx, r3.xxxx
  dp2 r0.y, r0.yzyy, r0.yzyy
  dp2 r0.z, r1.xyxx, r1.xyxx
  sqrt r0.yz, r0.yyzy
  max r0.z, r0.z, l(0.000100)
  rcp r0.z, r0.z
  mul r0.y, r0.z, r0.y
  min r0.y, r0.y, l(1.000000)
  mad r0.y, r0.y, l(8.000000), r0.x
  round_pi r0.y, r0.y
  ftou r0.y, r0.y
  umin r0.y, r0.y, l(8)
  umax r0.y, r0.y, l(1)
  mad r3.xy, r2.xyxx, l(0.500000, -0.500000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
  mul r2.xy, r3.xyxx, cb0[18].xyxx
  mul r1.xy, r1.xyxx, cb0[18].xyxx
  mul r1.xyw, r1.xyxz, l(0.062500, -0.062500, 0.000000, 0.125000)
  add r0.z, -r0.w, r2.z
  max r0.z, r0.z, |r1.z|
  mul r0.w, r0.z, l(0.125000)
  resinfo_indexable(texture2d)(float,float,float,float) r3.xy, l(0), t5.xyzw
  add r4.zw, r3.xxxy, l(0.000000, 0.000000, -1.000000, -1.000000)
  mov r6.zw, l(0,0,0,0)
  mov r3.z, l(0)
  mov r5.w, l(0)
  mov r7.xyzw, l(0,0,0,0)
  loop
    uge r8.x, r7.w, r0.y
    breakc_nz r8.x
    utof r8.x, r7.w
    add r8.x, r0.x, r8.x
    mad r8.yzw, r1.xxyw, r8.xxxx, r2.xxyz
    mul r8.yz, r3.xxyx, r8.yyzy
    max r8.yz, r8.yyzy, l(0.000000, 0.000000, 0.000000, 0.000000)
    min r8.yz, r4.zzwz, r8.yyzy
    ftou r6.xy, r8.yzyy
    ld_indexable(texture2d)(float,float,float,float) r6.x, r6.xyzw, t5.xyzw
    add r6.x, -r6.x, r8.w
    mad r6.y, -r0.z, l(0.125000), -r6.x
    lt r6.y, |r6.y|, r0.w
    if_nz r6.y
      mad r6.y, -r1.z, l(0.125000), r6.x
      movc r6.y, r7.w, r5.w, r6.y
      add r8.x, r8.x, l(-1.000000)
      add r8.y, -r6.x, r6.y
      div_sat r6.y, r6.y, r8.y
      add r6.y, r6.y, r8.x
      mad r7.xyz, r1.xywx, |r6.yyyy|, r2.xyzx
      mul r6.y, |r6.y|, l(0.125000)
      min r6.y, r6.y, l(1.000000)
      mad r3.z, -r6.y, r6.y, l(1.000000)
      break
    endif
    mov r5.w, r6.x
    iadd r7.w, r7.w, l(1)
    mov r7.xyz, l(0,0,0,0)
    mov r3.z, l(0)
  endloop
  mul r0.xy, r7.xyxx, cb0[18].zwzz
  mad r0.xy, r0.xyxx, l(2.000000, -2.000000, 0.000000, 0.000000), l(-1.000000, 1.000000, 0.000000, 0.000000)
  lt r0.z, l(0.000000), r3.z
  if_nz r0.z
    mad r0.z, r2.w, l(3.000000), l(0.500000)
    ftou r0.z, r0.z
    mad r0.w, r7.z, cb1[57].x, cb1[57].y
    mad r1.x, r7.z, cb1[57].z, -cb1[57].w
    rcp r1.x, r1.x
    add r0.w, r0.w, r1.x
    mul r1.xy, r0.wwww, r0.xyxx
    mul r1.yzw, r1.yyyy, cb1[45].xxyz
    mad r1.xyz, r1.xxxx, cb1[44].xyzx, r1.yzwy
    mad r1.xyz, r0.wwww, cb1[46].xyzx, r1.xyzx
    add r1.xyz, r1.xyzx, cb1[47].xyzx
    add r2.xyz, -r5.xyzx, r1.xyzx
    dp3 r0.w, r2.xyzx, r2.xyzx
    sqrt r0.w, r0.w
    mul r2.xyz, r0.yyyy, cb1[115].xywx
    mad r2.xyz, r0.xxxx, cb1[114].xywx, r2.xyzx
    mad r2.xyz, r7.zzzz, cb1[116].xywx, r2.xyzx
    add r2.xyz, r2.xyzx, cb1[117].xywx
    div r2.xy, r2.xyxx, r2.zzzz
    mad r2.zw, r0.xxxy, cb1[58].xxxy, cb1[58].wwwz
    mad r2.zw, r2.zzzw, cb1[126].xxxy, l(0.000000, 0.000000, 0.500000, 0.500000)
    ftoi r2.zw, r2.zzzw
    add r3.xy, cb1[121].xyxx, cb1[122].xyxx
    add r3.xy, r3.xyxx, l(-1.000000, -1.000000, 0.000000, 0.000000)
    ftoi r4.zw, cb1[121].xxxy
    ftoi r3.xy, r3.xyxx
    imax r2.zw, r2.zzzw, r4.zzzw
    imin r5.xy, r3.xyxx, r2.zwzz
    mov r5.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r2.zw, r5.xyzw, t6.zwxy
    dp2 r1.w, r2.zwzz, r2.zwzz
    lt r1.w, l(0.000000), r1.w
    add r2.zw, r2.zzzw, l(0.000000, 0.000000, -0.499992371, -0.499992371)
    mad r0.xy, -r2.zwzz, l(4.008016, 4.008016, 0.000000, 0.000000), r0.xyxx
    movc r0.xy, r1.wwww, r0.xyxx, r2.xyxx
    mad r2.xy, r0.xyxx, cb1[123].xyxx, cb1[123].wzww
    mad r2.xy, r2.xyxx, cb1[126].xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
    add r2.zw, cb1[124].xxxy, cb1[125].xxxy
    add r2.zw, r2.zzzw, l(0.000000, 0.000000, -1.000000, -1.000000)
    ftoi r3.xy, cb1[124].xyxx
    ftoi r2.xyzw, r2.xyzw
    imax r2.xy, r3.xyxx, r2.xyxx
    imin r2.xy, r2.zwzz, r2.xyxx
    mov r2.zw, l(0,0,0,0)
    ld_indexable(texture2d)(float,float,float,float) r5.xyz, r2.xyww, t7.xyzw
    min r5.xyz, r5.xyzx, l(65504.000000, 65504.000000, 65504.000000, 0.000000)
    ld_indexable(texture2d)(float,float,float,float) r2.xyz, r2.xyzw, t8.xyzw
    min r2.xyz, r2.xyzx, l(65504.000000, 65504.000000, 65504.000000, 0.000000)
    mul r2.xyz, r2.xyzx, cb0[20].yyyy
    dp3 r1.x, r1.xyzx, r1.xyzx
    sqrt r1.x, r1.x
    rcp r1.x, r1.x
    mul_sat r1.x, r0.w, r1.x
    mad r1.yzw, r5.xxyz, cb0[20].yyyy, -r2.xxyz
    mad r1.xyz, r1.xxxx, r1.yzwy, r2.xyzx
    mov r1.w, l(1.000000)
    mul r1.xyzw, r3.zzzz, r1.xyzw
    add r0.xy, -r4.xyxx, r0.xyxx
    mul r0.xy, r0.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
    mad_sat r0.xy, |r0.xyxx|, l(5.000000, 5.000000, 0.000000, 0.000000), l(-4.000000, -4.000000, 0.000000, 0.000000)
    dp2 r0.x, r0.xyxx, r0.xyxx
    add r0.x, -r0.x, l(1.000000)
    max r0.x, r0.x, l(0.000000)
    mul r1.xyzw, r0.xxxx, r1.xyzw
    mul r0.x, r3.w, r0.w
    mul r0.x, r0.x, r0.x
    max r0.x, r0.x, l(0.000010)
    rcp r0.x, r0.x
    min r0.x, r0.x, l(1.000000)
    mul r1.xyzw, r0.xxxx, r1.xyzw
    and r0.x, r0.z, l(2)
    movc r0.x, r0.x, cb0[19].y, cb0[19].z
    mul r0.x, r0.x, cb0[19].x
    mul r0.xyzw, r0.xxxx, r1.xyzw
    mul o0.xyz, r0.xyzx, cb1[128].xxxx
    mov o0.w, r0.w
  else
    mov o0.xyzw, l(0,0,0,0)
  endif
else
  mov o0.xyzw, l(0,0,0,0)
endif
ret
// Approximately 0 instruction slots used

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
