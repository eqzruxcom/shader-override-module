// ---- Created with 3Dmigoto v1.3.16 on Sat Aug 29 14:06:43 2026
Texture2D<float4> t5 : register(t5);

Texture2D<float4> t4 : register(t4);

Texture2D<float4> t3 : register(t3);

Texture2D<float4> t2 : register(t2);

Texture2D<float4> t1 : register(t1);

Texture3D<float4> t0 : register(t0);

SamplerState s0_s : register(s0);

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
  float4 r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12;
  uint4 bitmask, uiDest;
  float4 fDest;

  r0.xy = (int2)v1.xy;
  r1.xy = trunc(v1.xy);
  r1.xy = float2(0.5,0.5) + r1.xy;
  r1.xy = -cb1[121].xy + r1.xy;
  r1.xy = cb1[122].zw * r1.xy;
  r1.xy = r1.xy * float2(2,2) + float2(-1,-1);
  r1.zw = float2(1,-1) * r1.xy;
  r0.z = asuint(cb1[139].w) << 1;
  r2.xyz = (int3)r0.xyz & int3(63,63,63);
  r2.w = 0;
  r2.xy = t0.Load(r2.xyzw).yz;
  r0.w = 0;
  r0.z = t2.Load(r0.xyw).x;
  r2.z = r0.z * cb1[57].x + cb1[57].y;
  r2.w = r0.z * cb1[57].z + -cb1[57].w;
  r2.w = rcp(r2.w);
  r3.z = r2.z + r2.w;
  r4.xyz = t1.Load(r0.xyw).xyz;
  r4.xyz = r4.xyz * float3(2,2,2) + float3(-1,-1,-1);
  r2.z = dot(r4.xyz, r4.xyz);
  r2.z = rsqrt(r2.z);
  r4.xyz = r4.xyz * r2.zzz;
  r5.xyz = cb1[9].xyz * r4.yyy;
  r4.xyw = r4.xxx * cb1[8].xyz + r5.xyz;
  r4.xyz = r4.zzz * cb1[10].xyz + r4.xyw;
  r2.yz = float2(1.57079637,0.5) * r2.yx;
  sincos(r2.y, r5.x, r6.x);
  r2.y = 0.125 * cb1[122].x;
  r2.w = rcp(cb0[20].x);
  r2.w = cb0[3].z * r2.w;
  r2.w = 1.41421354 * r2.w;
  r3.w = 500 * cb0[18].w;
  r4.w = rcp(r3.z);
  r3.w = r4.w * r3.w;
  r3.w = min(0.75, r3.w);
  r5.yz = r3.zz * r1.zw;
  r7.xz = float2(1,1);
  r7.yw = cb0[19].zw;
  r3.xy = r7.xy * r5.yz;
  r2.z = r2.z * r2.z;
  r2.z = r2.z * r3.w;
  r2.z = max(r2.w, r2.z);
  r4.w = r2.z * r2.y;
  r4.w = log2(r4.w);
  r4.w = min(4, r4.w);
  r6.y = r5.x;
  r5.yz = r7.zw * r6.xy;
  r8.xy = r5.yz * r2.zz + r1.zw;
  r8.zw = cmp(float2(0,0) < r8.xy);
  r9.xy = cmp(r8.xy < float2(0,0));
  r8.zw = (int2)-r8.zw + (int2)r9.xy;
  r8.zw = (uint2)r8.zw << int2(1,1);
  r8.zw = (int2)r8.zw;
  r9.xy = float2(-1,-1) + abs(r8.xy);
  r9.xy = max(float2(0,0), r9.xy);
  r8.zw = -r8.zw * r9.xy + r8.xy;
  r8.zw = r8.zw * cb0[20].xy + cb0[20].zw;
  r5.w = t5.SampleLevel(s0_s, r8.zw, r4.w).x;
  r8.z = r5.w * cb1[57].x + cb1[57].y;
  r5.w = r5.w * cb1[57].z + -cb1[57].w;
  r5.w = rcp(r5.w);
  r9.z = r8.z + r5.w;
  r8.xy = r9.zz * r8.xy;
  r9.xy = r8.xy * r7.xy;
  r8.xyz = r9.xyz + -r3.xyz;
  r9.xy = cb0[18].zz * r8.xy;
  r8.xy = float2(0.5,0.5) * r9.xy;
  r5.w = dot(r8.xyz, r8.xyz);
  r5.w = sqrt(r5.w);
  r5.w = max(9.99999975e-005, r5.w);
  r8.x = -r8.z / r5.w;
  r8.x = max(-1, r8.x);
  r8.x = min(1, r8.x);
  r8.y = r8.x * r8.x;
  r8.y = r8.y * r8.y;
  r8.y = r8.y * -0.57032001 + -1.00048006;
  r5.w = -500 + r5.w;
  r5.w = saturate(-0.00999999978 * r5.w);
  r8.x = r8.y * r8.x + -1.57079279;
  r5.w = r5.w * r8.x + 3.14159274;
  r5.w = min(3.14159274, r5.w);
  r8.x = -250 + -r8.z;
  r8.x = saturate(-0.00400000019 * r8.x);
  r5.w = -3.14159274 + r5.w;
  r5.w = r8.x * r5.w + 3.14159274;
  r6.z = -r6.x;
  r8.xy = r7.zw * r6.yz;
  r8.zw = r8.xy * r2.zz + r1.zw;
  r9.xy = cmp(float2(0,0) < r8.zw);
  r9.zw = cmp(r8.zw < float2(0,0));
  r9.xy = (int2)-r9.xy + (int2)r9.zw;
  r9.xy = (uint2)r9.xy << int2(1,1);
  r9.xy = (int2)r9.xy;
  r9.zw = float2(-1,-1) + abs(r8.zw);
  r9.zw = max(float2(0,0), r9.zw);
  r9.xy = -r9.xy * r9.zw + r8.zw;
  r9.xy = r9.xy * cb0[20].xy + cb0[20].zw;
  r9.x = t5.SampleLevel(s0_s, r9.xy, r4.w).x;
  r9.y = r9.x * cb1[57].x + cb1[57].y;
  r9.x = r9.x * cb1[57].z + -cb1[57].w;
  r9.x = rcp(r9.x);
  r9.z = r9.y + r9.x;
  r8.zw = r9.zz * r8.zw;
  r9.xy = r8.zw * r7.xy;
  r9.xyz = r9.xyz + -r3.xyz;
  r8.zw = cb0[18].zz * r9.xy;
  r9.xy = float2(0.5,0.5) * r8.zw;
  r8.z = dot(r9.xyz, r9.xyz);
  r8.z = sqrt(r8.z);
  r8.z = max(9.99999975e-005, r8.z);
  r8.w = -r9.z / r8.z;
  r8.w = max(-1, r8.w);
  r8.w = min(1, r8.w);
  r9.x = r8.w * r8.w;
  r9.x = r9.x * r9.x;
  r9.x = r9.x * -0.57032001 + -1.00048006;
  r8.z = -500 + r8.z;
  r8.z = saturate(-0.00999999978 * r8.z);
  r8.w = r9.x * r8.w + -1.57079279;
  r8.z = r8.z * r8.w + 3.14159274;
  r8.z = min(3.14159274, r8.z);
  r8.w = -250 + -r9.z;
  r8.w = saturate(-0.00400000019 * r8.w);
  r8.z = -3.14159274 + r8.z;
  r8.z = r8.w * r8.z + 3.14159274;
  r6.w = -r5.x;
  r9.xyzw = r7.zwzw * r6.zwwx;
  r10.xyzw = r9.xyzw * r2.zzzz + r1.zwzw;
  r11.xyzw = cmp(float4(0,0,0,0) < r10.xyzw);
  r12.xyzw = cmp(r10.xyzw < float4(0,0,0,0));
  r11.xyzw = (int4)-r11.xyzw + (int4)r12.xyzw;
  r11.xyzw = (uint4)r11.xyzw << int4(1,1,1,1);
  r11.xyzw = (int4)r11.xyzw;
  r12.xyzw = float4(-1,-1,-1,-1) + abs(r10.xyzw);
  r12.xyzw = max(float4(0,0,0,0), r12.xyzw);
  r11.xyzw = -r11.xyzw * r12.xyzw + r10.xyzw;
  r11.xyzw = r11.xyzw * cb0[20].xyxy + cb0[20].zwzw;
  r2.z = t5.SampleLevel(s0_s, r11.xy, r4.w).x;
  r6.z = r2.z * cb1[57].x + cb1[57].y;
  r2.z = r2.z * cb1[57].z + -cb1[57].w;
  r2.z = rcp(r2.z);
  r12.z = r6.z + r2.z;
  r7.zw = r12.zz * r10.xy;
  r12.xy = r7.zw * r7.xy;
  r12.xyz = r12.xyz + -r3.xyz;
  r7.zw = cb0[18].zz * r12.xy;
  r12.xy = float2(0.5,0.5) * r7.zw;
  r2.z = dot(r12.xyz, r12.xyz);
  r2.z = sqrt(r2.z);
  r2.z = max(9.99999975e-005, r2.z);
  r6.z = -r12.z / r2.z;
  r6.z = max(-1, r6.z);
  r6.z = min(1, r6.z);
  r7.z = r6.z * r6.z;
  r7.z = r7.z * r7.z;
  r7.z = r7.z * -0.57032001 + -1.00048006;
  r2.z = -500 + r2.z;
  r2.z = saturate(-0.00999999978 * r2.z);
  r6.z = r7.z * r6.z + -1.57079279;
  r2.z = r2.z * r6.z + 3.14159274;
  r2.z = min(3.14159274, r2.z);
  r6.z = -250 + -r12.z;
  r6.z = saturate(-0.00400000019 * r6.z);
  r2.z = -3.14159274 + r2.z;
  r2.z = r6.z * r2.z + 3.14159274;
  r4.w = t5.SampleLevel(s0_s, r11.zw, r4.w).x;
  r6.z = r4.w * cb1[57].x + cb1[57].y;
  r4.w = r4.w * cb1[57].z + -cb1[57].w;
  r4.w = rcp(r4.w);
  r11.z = r6.z + r4.w;
  r7.zw = r11.zz * r10.zw;
  r11.xy = r7.zw * r7.xy;
  r10.xyz = r11.xyz + -r3.xyz;
  r7.zw = cb0[18].zz * r10.xy;
  r10.xy = float2(0.5,0.5) * r7.zw;
  r4.w = dot(r10.xyz, r10.xyz);
  r4.w = sqrt(r4.w);
  r4.w = max(9.99999975e-005, r4.w);
  r6.z = -r10.z / r4.w;
  r6.z = max(-1, r6.z);
  r6.z = min(1, r6.z);
  r7.z = r6.z * r6.z;
  r7.z = r7.z * r7.z;
  r7.z = r7.z * -0.57032001 + -1.00048006;
  r4.w = -500 + r4.w;
  r4.w = saturate(-0.00999999978 * r4.w);
  r6.z = r7.z * r6.z + -1.57079279;
  r4.w = r4.w * r6.z + 3.14159274;
  r4.w = min(3.14159274, r4.w);
  r6.z = -250 + -r10.z;
  r6.z = saturate(-0.00400000019 * r6.z);
  r4.w = -3.14159274 + r4.w;
  r4.w = r6.z * r4.w + 3.14159274;
  r2.x = 1 + r2.x;
  r2.x = 0.5 * r2.x;
  r2.x = r2.x * r2.x;
  r2.x = r2.x * r3.w;
  r2.x = max(r2.w, r2.x);
  r2.y = r2.x * r2.y;
  r2.y = log2(r2.y);
  r2.y = min(4, r2.y);
  r5.yz = r5.yz * r2.xx + r1.zw;
  r7.zw = cmp(float2(0,0) < r5.yz);
  r10.xy = cmp(r5.yz < float2(0,0));
  r7.zw = (int2)-r7.zw + (int2)r10.xy;
  r7.zw = (uint2)r7.zw << int2(1,1);
  r7.zw = (int2)r7.zw;
  r10.xy = float2(-1,-1) + abs(r5.yz);
  r10.xy = max(float2(0,0), r10.xy);
  r7.zw = -r7.zw * r10.xy + r5.yz;
  r7.zw = r7.zw * cb0[20].xy + cb0[20].zw;
  r2.w = t5.SampleLevel(s0_s, r7.zw, r2.y).x;
  r3.w = r2.w * cb1[57].x + cb1[57].y;
  r2.w = r2.w * cb1[57].z + -cb1[57].w;
  r2.w = rcp(r2.w);
  r10.z = r3.w + r2.w;
  r5.yz = r10.zz * r5.yz;
  r10.xy = r5.yz * r7.xy;
  r10.xyz = r10.xyz + -r3.xyz;
  r5.yz = cb0[18].zz * r10.xy;
  r10.xy = float2(0.5,0.5) * r5.yz;
  r2.w = dot(r10.xyz, r10.xyz);
  r2.w = sqrt(r2.w);
  r2.w = max(9.99999975e-005, r2.w);
  r3.w = -r10.z / r2.w;
  r3.w = max(-1, r3.w);
  r3.w = min(1, r3.w);
  r5.y = r3.w * r3.w;
  r5.y = r5.y * r5.y;
  r5.y = r5.y * -0.57032001 + -1.00048006;
  r2.w = -500 + r2.w;
  r2.w = saturate(-0.00999999978 * r2.w);
  r3.w = r5.y * r3.w + -1.57079279;
  r2.w = r2.w * r3.w + 3.14159274;
  r2.w = min(r2.w, r5.w);
  r3.w = -250 + -r10.z;
  r3.w = saturate(-0.00400000019 * r3.w);
  r2.w = r2.w + -r5.w;
  r2.w = r3.w * r2.w + r5.w;
  r5.yz = r8.xy * r2.xx + r1.zw;
  r7.zw = cmp(float2(0,0) < r5.yz);
  r8.xy = cmp(r5.yz < float2(0,0));
  r7.zw = (int2)-r7.zw + (int2)r8.xy;
  r7.zw = (uint2)r7.zw << int2(1,1);
  r7.zw = (int2)r7.zw;
  r8.xy = float2(-1,-1) + abs(r5.yz);
  r8.xy = max(float2(0,0), r8.xy);
  r7.zw = -r7.zw * r8.xy + r5.yz;
  r7.zw = r7.zw * cb0[20].xy + cb0[20].zw;
  r3.w = t5.SampleLevel(s0_s, r7.zw, r2.y).x;
  r5.w = r3.w * cb1[57].x + cb1[57].y;
  r3.w = r3.w * cb1[57].z + -cb1[57].w;
  r3.w = rcp(r3.w);
  r10.z = r5.w + r3.w;
  r5.yz = r10.zz * r5.yz;
  r10.xy = r5.yz * r7.xy;
  r5.yzw = r10.xyz + -r3.xyz;
  r7.zw = cb0[18].zz * r5.yz;
  r5.yz = float2(0.5,0.5) * r7.zw;
  r3.w = dot(r5.yzw, r5.yzw);
  r3.w = sqrt(r3.w);
  r3.w = max(9.99999975e-005, r3.w);
  r5.y = -r5.w / r3.w;
  r5.y = max(-1, r5.y);
  r5.y = min(1, r5.y);
  r5.z = r5.y * r5.y;
  r5.z = r5.z * r5.z;
  r5.z = r5.z * -0.57032001 + -1.00048006;
  r3.w = -500 + r3.w;
  r3.w = saturate(-0.00999999978 * r3.w);
  r5.y = r5.z * r5.y + -1.57079279;
  r3.w = r3.w * r5.y + 3.14159274;
  r3.w = min(r3.w, r8.z);
  r5.y = -250 + -r5.w;
  r5.y = saturate(-0.00400000019 * r5.y);
  r3.w = r3.w + -r8.z;
  r3.w = r5.y * r3.w + r8.z;
  r8.xyzw = r9.xyzw * r2.xxxx + r1.zwzw;
  r9.xyzw = cmp(float4(0,0,0,0) < r8.xyzw);
  r10.xyzw = cmp(r8.xyzw < float4(0,0,0,0));
  r9.xyzw = (int4)-r9.xyzw + (int4)r10.xyzw;
  r9.xyzw = (uint4)r9.xyzw << int4(1,1,1,1);
  r9.xyzw = (int4)r9.xyzw;
  r10.xyzw = float4(-1,-1,-1,-1) + abs(r8.xyzw);
  r10.xyzw = max(float4(0,0,0,0), r10.xyzw);
  r9.xyzw = -r9.xyzw * r10.xyzw + r8.xyzw;
  r9.xyzw = r9.xyzw * cb0[20].xyxy + cb0[20].zwzw;
  r2.x = t5.SampleLevel(s0_s, r9.xy, r2.y).x;
  r5.y = r2.x * cb1[57].x + cb1[57].y;
  r2.x = r2.x * cb1[57].z + -cb1[57].w;
  r2.x = rcp(r2.x);
  r10.z = r5.y + r2.x;
  r5.yz = r10.zz * r8.xy;
  r10.xy = r5.yz * r7.xy;
  r5.yzw = r10.xyz + -r3.xyz;
  r7.zw = cb0[18].zz * r5.yz;
  r5.yz = float2(0.5,0.5) * r7.zw;
  r2.x = dot(r5.yzw, r5.yzw);
  r2.x = sqrt(r2.x);
  r2.x = max(9.99999975e-005, r2.x);
  r5.y = -r5.w / r2.x;
  r5.y = max(-1, r5.y);
  r5.y = min(1, r5.y);
  r5.z = r5.y * r5.y;
  r5.z = r5.z * r5.z;
  r5.z = r5.z * -0.57032001 + -1.00048006;
  r2.x = -500 + r2.x;
  r2.x = saturate(-0.00999999978 * r2.x);
  r5.y = r5.z * r5.y + -1.57079279;
  r2.x = r2.x * r5.y + 3.14159274;
  r2.x = min(r2.x, r2.z);
  r5.y = -250 + -r5.w;
  r5.y = saturate(-0.00400000019 * r5.y);
  r2.x = r2.x + -r2.z;
  r2.x = r5.y * r2.x + r2.z;
  r2.y = t5.SampleLevel(s0_s, r9.zw, r2.y).x;
  r2.z = r2.y * cb1[57].x + cb1[57].y;
  r2.y = r2.y * cb1[57].z + -cb1[57].w;
  r2.y = rcp(r2.y);
  r9.z = r2.z + r2.y;
  r2.yz = r9.zz * r8.zw;
  r9.xy = r2.yz * r7.xy;
  r5.yzw = r9.xyz + -r3.xyz;
  r2.yz = cb0[18].zz * r5.yz;
  r5.yz = float2(0.5,0.5) * r2.yz;
  r2.y = dot(r5.yzw, r5.yzw);
  r2.y = sqrt(r2.y);
  r2.y = max(9.99999975e-005, r2.y);
  r2.z = -r5.w / r2.y;
  r2.z = max(-1, r2.z);
  r2.z = min(1, r2.z);
  r3.x = r2.z * r2.z;
  r3.x = r3.x * r3.x;
  r3.x = r3.x * -0.57032001 + -1.00048006;
  r2.y = -500 + r2.y;
  r2.y = saturate(-0.00999999978 * r2.y);
  r2.z = r3.x * r2.z + -1.57079279;
  r2.y = r2.y * r2.z + 3.14159274;
  r2.y = min(r2.y, r4.w);
  r2.z = -250 + -r5.w;
  r2.z = saturate(-0.00400000019 * r2.z);
  r2.y = r2.y + -r4.w;
  r2.y = r2.z * r2.y + r4.w;
  r3.xy = r5.xx * r4.yx;
  r2.z = r4.x * r6.x + r3.x;
  r3.x = r4.y * r6.x + -r3.y;
  r5.xy = -r6.wx * r3.xx + r4.xy;
  r5.z = r4.z;
  r3.y = dot(r5.xyz, r5.xyz);
  r3.y = sqrt(r3.y);
  r3.y = max(9.99999975e-005, r3.y);
  r4.w = -r4.z / r3.y;
  r4.w = max(-1, r4.w);
  r4.w = min(1, r4.w);
  r5.w = cmp(0 < r2.z);
  r6.z = cmp(r2.z < 0);
  r5.w = (int)-r5.w + (int)r6.z;
  r5.w = (int)r5.w;
  r6.z = r4.w * r4.w;
  r6.w = -r4.w * r4.w + 1;
  r6.w = sqrt(r6.w);
  r6.w = r6.w * r5.w;
  r6.z = r6.z * r6.z;
  r6.z = r6.z * -0.57032001 + -1.00048006;
  r4.w = r6.z * r4.w + 1.57079995;
  r6.z = r5.w * r4.w;
  r2.w = -r5.w * r4.w + r2.w;
  r2.w = min(1.57079637, r2.w);
  r2.x = -r5.w * r4.w + -r2.x;
  r2.x = max(-1.57079637, r2.x);
  r4.w = r6.z * 2 + r2.w;
  r4.w = r4.w + r2.x;
  r2.w = r2.w * 2 + r6.z;
  r2.x = r2.x * 2 + r6.z;
  r2.xw = cos(r2.xw);
  r2.x = r2.w + r2.x;
  r2.x = 0.5 * r2.x;
  r2.x = r4.w * r6.w + -r2.x;
  r5.xy = -r6.xy * r2.zz + r4.xy;
  r2.z = dot(r5.xyz, r5.xyz);
  r2.z = sqrt(r2.z);
  r2.z = max(9.99999975e-005, r2.z);
  r2.w = -r4.z / r2.z;
  r2.w = max(-1, r2.w);
  r2.w = min(1, r2.w);
  r4.x = cmp(0 < r3.x);
  r3.x = cmp(r3.x < 0);
  r3.x = (int)-r4.x + (int)r3.x;
  r3.x = (int)r3.x;
  r4.x = r2.w * r2.w;
  r4.y = -r2.w * r2.w + 1;
  r4.y = sqrt(r4.y);
  r4.y = r4.y * r3.x;
  r4.x = r4.x * r4.x;
  r4.x = r4.x * -0.57032001 + -1.00048006;
  r2.w = r4.x * r2.w + 1.57079995;
  r4.x = r3.x * r2.w;
  r2.y = -r3.x * r2.w + r2.y;
  r2.y = min(1.57079637, r2.y);
  r2.w = -r3.x * r2.w + -r3.w;
  r2.w = max(-1.57079637, r2.w);
  r3.x = r4.x * 2 + r2.y;
  r3.x = r3.x + r2.w;
  r2.y = r2.y * 2 + r4.x;
  r2.w = r2.w * 2 + r4.x;
  r2.yw = cos(r2.yw);
  r2.y = r2.y + r2.w;
  r2.y = 0.5 * r2.y;
  r2.y = r3.x * r4.y + -r2.y;
  r2.y = r2.z * r2.y;
  r2.x = r3.y * r2.x + r2.y;
  r2.y = 0.5 * r5.z;
  r2.x = r2.x * 0.25 + -r2.y;
  r2.w = max(0, r2.x);
  r3.xyw = cb1[115].xyw * r1.www;
  r3.xyw = r1.zzz * cb1[114].xyw + r3.xyw;
  r3.xyw = r0.zzz * cb1[116].xyw + r3.xyw;
  r3.xyw = cb1[117].xyw + r3.xyw;
  r3.xy = r3.xy / r3.ww;
  r3.xy = r1.xy * float2(1,-1) + -r3.xy;
  r0.xy = t4.Load(r0.xyw).xy;
  r0.z = dot(r0.xy, r0.xy);
  r0.z = cmp(0 < r0.z);
  r0.xy = float2(-0.499992371,-0.499992371) + r0.xy;
  r0.xy = float2(4.00801611,4.00801611) * r0.xy;
  r0.xy = r0.zz ? r0.xy : r3.xy;
  r0.xy = r1.xy * float2(1,-1) + -r0.xy;
  r1.xy = cb1[125].xy * r0.xy;
  r1.xy = r1.zw * cb1[122].xy + -r1.xy;
  r0.w = dot(r1.xy, r1.xy);
  r0.w = sqrt(r0.w);
  r0.w = 0.0125000002 * r0.w;
  r2.y = min(1, r0.w);
  r0.w = max(abs(r0.x), abs(r0.y));
  r0.w = cmp(r0.w < 1);
  if (r0.w != 0) {
    r0.xy = r0.xy * cb1[123].xy + cb1[123].wz;
    r0.xy = cb1[126].xy * r0.xy;
    r1.xy = float2(0.5,0.5) + cb1[124].xy;
    r1.zw = cb1[125].xy + cb1[124].xy;
    r1.zw = float2(-0.5,-0.5) + r1.zw;
    r0.xy = max(r1.xy, r0.xy);
    r0.xy = min(r0.xy, r1.zw);
    r0.xy = cb0[1].zw * r0.xy;
    r0.xyw = t3.SampleLevel(s0_s, r0.xy, 0).xyz;
    r1.x = cmp(r0.y != 0.000000);
    r0.y = r0.w * 0.800000012 + r2.y;
    r0.w = ~(int)r0.z;
    r0.w = r1.x ? r0.w : 0;
    r2.x = 1;
    r2.xy = r0.ww ? r2.wx : r0.xy;
  } else {
    r2.xy = r2.wy;
  }
  r2.z = r0.z ? -r3.z : r3.z;
  // Diagnostic: zero only packed SSR output channel x.
  o0.xyzw = float4(0, r2.x, r2.y, r2.z);
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
dcl_sampler s0, mode_default
dcl_resource_texture3d (float,float,float,float) t0
dcl_resource_texture2d (float,float,float,float) t1
dcl_resource_texture2d (float,float,float,float) t2
dcl_resource_texture2d (float,float,float,float) t3
dcl_resource_texture2d (float,float,float,float) t4
dcl_resource_texture2d (float,float,float,float) t5
dcl_input_ps_siv linear noperspective v1.xy, position
dcl_output o0.xyzw
dcl_temps 13
ftoi r0.xy, v1.xyxx
round_z r1.xy, v1.xyxx
add r1.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
add r1.xy, r1.xyxx, -cb1[121].xyxx
mul r1.xy, r1.xyxx, cb1[122].zwzz
mad r1.xy, r1.xyxx, l(2.000000, 2.000000, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
mul r1.zw, r1.xxxy, l(0.000000, 0.000000, 1.000000, -1.000000)
ishl r0.z, cb1[139].w, l(1)
and r2.xyz, r0.xyzx, l(63, 63, 63, 0)
mov r2.w, l(0)
ld_indexable(texture3d)(float,float,float,float) r2.xy, r2.xyzw, t0.yzxw
mov r0.w, l(0)
ld_indexable(texture2d)(float,float,float,float) r0.z, r0.xyww, t2.yzxw
mad r2.z, r0.z, cb1[57].x, cb1[57].y
mad r2.w, r0.z, cb1[57].z, -cb1[57].w
rcp r2.w, r2.w
add r3.z, r2.w, r2.z
ld_indexable(texture2d)(float,float,float,float) r4.xyz, r0.xyww, t1.xyzw
mad r4.xyz, r4.xyzx, l(2.000000, 2.000000, 2.000000, 0.000000), l(-1.000000, -1.000000, -1.000000, 0.000000)
dp3 r2.z, r4.xyzx, r4.xyzx
rsq r2.z, r2.z
mul r4.xyz, r2.zzzz, r4.xyzx
mul r5.xyz, r4.yyyy, cb1[9].xyzx
mad r4.xyw, r4.xxxx, cb1[8].xyxz, r5.xyxz
mad r4.xyz, r4.zzzz, cb1[10].xyzx, r4.xywx
mul r2.yz, r2.yyxy, l(0.000000, 1.57079637, 0.500000, 0.000000)
sincos r5.x, r6.x, r2.y
mul r2.y, cb1[122].x, l(0.125000)
rcp r2.w, cb0[20].x
mul r2.w, r2.w, cb0[3].z
mul r2.w, r2.w, l(1.41421354)
mul r3.w, cb0[18].w, l(500.000000)
rcp r4.w, r3.z
mul r3.w, r3.w, r4.w
min r3.w, r3.w, l(0.750000)
mul r5.yz, r1.zzwz, r3.zzzz
mov r7.xz, l(1.000000,0,1.000000,0)
mov r7.yw, cb0[19].zzzw
mul r3.xy, r5.yzyy, r7.xyxx
mul r2.z, r2.z, r2.z
mul r2.z, r3.w, r2.z
max r2.z, r2.z, r2.w
mul r4.w, r2.y, r2.z
log r4.w, r4.w
min r4.w, r4.w, l(4.000000)
mov r6.y, r5.x
mul r5.yz, r6.xxyx, r7.zzwz
mad r8.xy, r5.yzyy, r2.zzzz, r1.zwzz
lt r8.zw, l(0.000000, 0.000000, 0.000000, 0.000000), r8.xxxy
lt r9.xy, r8.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
iadd r8.zw, -r8.zzzw, r9.xxxy
ishl r8.zw, r8.zzzw, l(0, 0, 1, 1)
itof r8.zw, r8.zzzw
add r9.xy, |r8.xyxx|, l(-1.000000, -1.000000, 0.000000, 0.000000)
max r9.xy, r9.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
mad r8.zw, -r8.zzzw, r9.xxxy, r8.xxxy
mad r8.zw, r8.zzzw, cb0[20].xxxy, cb0[20].zzzw
sample_l_indexable(texture2d)(float,float,float,float) r5.w, r8.zwzz, t5.yzwx, s0, r4.w
mad r8.z, r5.w, cb1[57].x, cb1[57].y
mad r5.w, r5.w, cb1[57].z, -cb1[57].w
rcp r5.w, r5.w
add r9.z, r5.w, r8.z
mul r8.xy, r8.xyxx, r9.zzzz
mul r9.xy, r7.xyxx, r8.xyxx
add r8.xyz, -r3.xyzx, r9.xyzx
mul r9.xy, r8.xyxx, cb0[18].zzzz
mul r8.xy, r9.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
dp3 r5.w, r8.xyzx, r8.xyzx
sqrt r5.w, r5.w
max r5.w, r5.w, l(0.000100)
div r8.x, -r8.z, r5.w
max r8.x, r8.x, l(-1.000000)
min r8.x, r8.x, l(1.000000)
mul r8.y, r8.x, r8.x
mul r8.y, r8.y, r8.y
mad r8.y, r8.y, l(-0.570320), l(-1.000480)
add r5.w, r5.w, l(-500.000000)
mul_sat r5.w, r5.w, l(-0.010000)
mad r8.x, r8.y, r8.x, l(-1.57079279)
mad r5.w, r5.w, r8.x, l(3.14159274)
min r5.w, r5.w, l(3.14159274)
add r8.x, -r8.z, l(-250.000000)
mul_sat r8.x, r8.x, l(-0.004000)
add r5.w, r5.w, l(-3.14159274)
mad r5.w, r8.x, r5.w, l(3.14159274)
mov r6.z, -r6.x
mul r8.xy, r6.yzyy, r7.zwzz
mad r8.zw, r8.xxxy, r2.zzzz, r1.zzzw
lt r9.xy, l(0.000000, 0.000000, 0.000000, 0.000000), r8.zwzz
lt r9.zw, r8.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
iadd r9.xy, -r9.xyxx, r9.zwzz
ishl r9.xy, r9.xyxx, l(1, 1, 0, 0)
itof r9.xy, r9.xyxx
add r9.zw, |r8.zzzw|, l(0.000000, 0.000000, -1.000000, -1.000000)
max r9.zw, r9.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
mad r9.xy, -r9.xyxx, r9.zwzz, r8.zwzz
mad r9.xy, r9.xyxx, cb0[20].xyxx, cb0[20].zwzz
sample_l_indexable(texture2d)(float,float,float,float) r9.x, r9.xyxx, t5.xyzw, s0, r4.w
mad r9.y, r9.x, cb1[57].x, cb1[57].y
mad r9.x, r9.x, cb1[57].z, -cb1[57].w
rcp r9.x, r9.x
add r9.z, r9.x, r9.y
mul r8.zw, r8.zzzw, r9.zzzz
mul r9.xy, r7.xyxx, r8.zwzz
add r9.xyz, -r3.xyzx, r9.xyzx
mul r8.zw, r9.xxxy, cb0[18].zzzz
mul r9.xy, r8.zwzz, l(0.500000, 0.500000, 0.000000, 0.000000)
dp3 r8.z, r9.xyzx, r9.xyzx
sqrt r8.z, r8.z
max r8.z, r8.z, l(0.000100)
div r8.w, -r9.z, r8.z
max r8.w, r8.w, l(-1.000000)
min r8.w, r8.w, l(1.000000)
mul r9.x, r8.w, r8.w
mul r9.x, r9.x, r9.x
mad r9.x, r9.x, l(-0.570320), l(-1.000480)
add r8.z, r8.z, l(-500.000000)
mul_sat r8.z, r8.z, l(-0.010000)
mad r8.w, r9.x, r8.w, l(-1.57079279)
mad r8.z, r8.z, r8.w, l(3.14159274)
min r8.z, r8.z, l(3.14159274)
add r8.w, -r9.z, l(-250.000000)
mul_sat r8.w, r8.w, l(-0.004000)
add r8.z, r8.z, l(-3.14159274)
mad r8.z, r8.w, r8.z, l(3.14159274)
mov r6.w, -r5.x
mul r9.xyzw, r6.zwwx, r7.zwzw
mad r10.xyzw, r9.xyzw, r2.zzzz, r1.zwzw
lt r11.xyzw, l(0.000000, 0.000000, 0.000000, 0.000000), r10.xyzw
lt r12.xyzw, r10.xyzw, l(0.000000, 0.000000, 0.000000, 0.000000)
iadd r11.xyzw, -r11.xyzw, r12.xyzw
ishl r11.xyzw, r11.xyzw, l(1, 1, 1, 1)
itof r11.xyzw, r11.xyzw
add r12.xyzw, |r10.xyzw|, l(-1.000000, -1.000000, -1.000000, -1.000000)
max r12.xyzw, r12.xyzw, l(0.000000, 0.000000, 0.000000, 0.000000)
mad r11.xyzw, -r11.xyzw, r12.xyzw, r10.xyzw
mad r11.xyzw, r11.xyzw, cb0[20].xyxy, cb0[20].zwzw
sample_l_indexable(texture2d)(float,float,float,float) r2.z, r11.xyxx, t5.yzxw, s0, r4.w
mad r6.z, r2.z, cb1[57].x, cb1[57].y
mad r2.z, r2.z, cb1[57].z, -cb1[57].w
rcp r2.z, r2.z
add r12.z, r2.z, r6.z
mul r7.zw, r10.xxxy, r12.zzzz
mul r12.xy, r7.xyxx, r7.zwzz
add r12.xyz, -r3.xyzx, r12.xyzx
mul r7.zw, r12.xxxy, cb0[18].zzzz
mul r12.xy, r7.zwzz, l(0.500000, 0.500000, 0.000000, 0.000000)
dp3 r2.z, r12.xyzx, r12.xyzx
sqrt r2.z, r2.z
max r2.z, r2.z, l(0.000100)
div r6.z, -r12.z, r2.z
max r6.z, r6.z, l(-1.000000)
min r6.z, r6.z, l(1.000000)
mul r7.z, r6.z, r6.z
mul r7.z, r7.z, r7.z
mad r7.z, r7.z, l(-0.570320), l(-1.000480)
add r2.z, r2.z, l(-500.000000)
mul_sat r2.z, r2.z, l(-0.010000)
mad r6.z, r7.z, r6.z, l(-1.57079279)
mad r2.z, r2.z, r6.z, l(3.14159274)
min r2.z, r2.z, l(3.14159274)
add r6.z, -r12.z, l(-250.000000)
mul_sat r6.z, r6.z, l(-0.004000)
add r2.z, r2.z, l(-3.14159274)
mad r2.z, r6.z, r2.z, l(3.14159274)
sample_l_indexable(texture2d)(float,float,float,float) r4.w, r11.zwzz, t5.yzwx, s0, r4.w
mad r6.z, r4.w, cb1[57].x, cb1[57].y
mad r4.w, r4.w, cb1[57].z, -cb1[57].w
rcp r4.w, r4.w
add r11.z, r4.w, r6.z
mul r7.zw, r10.zzzw, r11.zzzz
mul r11.xy, r7.xyxx, r7.zwzz
add r10.xyz, -r3.xyzx, r11.xyzx
mul r7.zw, r10.xxxy, cb0[18].zzzz
mul r10.xy, r7.zwzz, l(0.500000, 0.500000, 0.000000, 0.000000)
dp3 r4.w, r10.xyzx, r10.xyzx
sqrt r4.w, r4.w
max r4.w, r4.w, l(0.000100)
div r6.z, -r10.z, r4.w
max r6.z, r6.z, l(-1.000000)
min r6.z, r6.z, l(1.000000)
mul r7.z, r6.z, r6.z
mul r7.z, r7.z, r7.z
mad r7.z, r7.z, l(-0.570320), l(-1.000480)
add r4.w, r4.w, l(-500.000000)
mul_sat r4.w, r4.w, l(-0.010000)
mad r6.z, r7.z, r6.z, l(-1.57079279)
mad r4.w, r4.w, r6.z, l(3.14159274)
min r4.w, r4.w, l(3.14159274)
add r6.z, -r10.z, l(-250.000000)
mul_sat r6.z, r6.z, l(-0.004000)
add r4.w, r4.w, l(-3.14159274)
mad r4.w, r6.z, r4.w, l(3.14159274)
add r2.x, r2.x, l(1.000000)
mul r2.x, r2.x, l(0.500000)
mul r2.x, r2.x, r2.x
mul r2.x, r3.w, r2.x
max r2.x, r2.x, r2.w
mul r2.y, r2.y, r2.x
log r2.y, r2.y
min r2.y, r2.y, l(4.000000)
mad r5.yz, r5.yyzy, r2.xxxx, r1.zzwz
lt r7.zw, l(0.000000, 0.000000, 0.000000, 0.000000), r5.yyyz
lt r10.xy, r5.yzyy, l(0.000000, 0.000000, 0.000000, 0.000000)
iadd r7.zw, -r7.zzzw, r10.xxxy
ishl r7.zw, r7.zzzw, l(0, 0, 1, 1)
itof r7.zw, r7.zzzw
add r10.xy, |r5.yzyy|, l(-1.000000, -1.000000, 0.000000, 0.000000)
max r10.xy, r10.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
mad r7.zw, -r7.zzzw, r10.xxxy, r5.yyyz
mad r7.zw, r7.zzzw, cb0[20].xxxy, cb0[20].zzzw
sample_l_indexable(texture2d)(float,float,float,float) r2.w, r7.zwzz, t5.yzwx, s0, r2.y
mad r3.w, r2.w, cb1[57].x, cb1[57].y
mad r2.w, r2.w, cb1[57].z, -cb1[57].w
rcp r2.w, r2.w
add r10.z, r2.w, r3.w
mul r5.yz, r5.yyzy, r10.zzzz
mul r10.xy, r7.xyxx, r5.yzyy
add r10.xyz, -r3.xyzx, r10.xyzx
mul r5.yz, r10.xxyx, cb0[18].zzzz
mul r10.xy, r5.yzyy, l(0.500000, 0.500000, 0.000000, 0.000000)
dp3 r2.w, r10.xyzx, r10.xyzx
sqrt r2.w, r2.w
max r2.w, r2.w, l(0.000100)
div r3.w, -r10.z, r2.w
max r3.w, r3.w, l(-1.000000)
min r3.w, r3.w, l(1.000000)
mul r5.y, r3.w, r3.w
mul r5.y, r5.y, r5.y
mad r5.y, r5.y, l(-0.570320), l(-1.000480)
add r2.w, r2.w, l(-500.000000)
mul_sat r2.w, r2.w, l(-0.010000)
mad r3.w, r5.y, r3.w, l(-1.57079279)
mad r2.w, r2.w, r3.w, l(3.14159274)
min r2.w, r5.w, r2.w
add r3.w, -r10.z, l(-250.000000)
mul_sat r3.w, r3.w, l(-0.004000)
add r2.w, -r5.w, r2.w
mad r2.w, r3.w, r2.w, r5.w
mad r5.yz, r8.xxyx, r2.xxxx, r1.zzwz
lt r7.zw, l(0.000000, 0.000000, 0.000000, 0.000000), r5.yyyz
lt r8.xy, r5.yzyy, l(0.000000, 0.000000, 0.000000, 0.000000)
iadd r7.zw, -r7.zzzw, r8.xxxy
ishl r7.zw, r7.zzzw, l(0, 0, 1, 1)
itof r7.zw, r7.zzzw
add r8.xy, |r5.yzyy|, l(-1.000000, -1.000000, 0.000000, 0.000000)
max r8.xy, r8.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
mad r7.zw, -r7.zzzw, r8.xxxy, r5.yyyz
mad r7.zw, r7.zzzw, cb0[20].xxxy, cb0[20].zzzw
sample_l_indexable(texture2d)(float,float,float,float) r3.w, r7.zwzz, t5.yzwx, s0, r2.y
mad r5.w, r3.w, cb1[57].x, cb1[57].y
mad r3.w, r3.w, cb1[57].z, -cb1[57].w
rcp r3.w, r3.w
add r10.z, r3.w, r5.w
mul r5.yz, r5.yyzy, r10.zzzz
mul r10.xy, r7.xyxx, r5.yzyy
add r5.yzw, -r3.xxyz, r10.xxyz
mul r7.zw, r5.yyyz, cb0[18].zzzz
mul r5.yz, r7.zzwz, l(0.000000, 0.500000, 0.500000, 0.000000)
dp3 r3.w, r5.yzwy, r5.yzwy
sqrt r3.w, r3.w
max r3.w, r3.w, l(0.000100)
div r5.y, -r5.w, r3.w
max r5.y, r5.y, l(-1.000000)
min r5.y, r5.y, l(1.000000)
mul r5.z, r5.y, r5.y
mul r5.z, r5.z, r5.z
mad r5.z, r5.z, l(-0.570320), l(-1.000480)
add r3.w, r3.w, l(-500.000000)
mul_sat r3.w, r3.w, l(-0.010000)
mad r5.y, r5.z, r5.y, l(-1.57079279)
mad r3.w, r3.w, r5.y, l(3.14159274)
min r3.w, r8.z, r3.w
add r5.y, -r5.w, l(-250.000000)
mul_sat r5.y, r5.y, l(-0.004000)
add r3.w, -r8.z, r3.w
mad r3.w, r5.y, r3.w, r8.z
mad r8.xyzw, r9.xyzw, r2.xxxx, r1.zwzw
lt r9.xyzw, l(0.000000, 0.000000, 0.000000, 0.000000), r8.xyzw
lt r10.xyzw, r8.xyzw, l(0.000000, 0.000000, 0.000000, 0.000000)
iadd r9.xyzw, -r9.xyzw, r10.xyzw
ishl r9.xyzw, r9.xyzw, l(1, 1, 1, 1)
itof r9.xyzw, r9.xyzw
add r10.xyzw, |r8.xyzw|, l(-1.000000, -1.000000, -1.000000, -1.000000)
max r10.xyzw, r10.xyzw, l(0.000000, 0.000000, 0.000000, 0.000000)
mad r9.xyzw, -r9.xyzw, r10.xyzw, r8.xyzw
mad r9.xyzw, r9.xyzw, cb0[20].xyxy, cb0[20].zwzw
sample_l_indexable(texture2d)(float,float,float,float) r2.x, r9.xyxx, t5.xyzw, s0, r2.y
mad r5.y, r2.x, cb1[57].x, cb1[57].y
mad r2.x, r2.x, cb1[57].z, -cb1[57].w
rcp r2.x, r2.x
add r10.z, r2.x, r5.y
mul r5.yz, r8.xxyx, r10.zzzz
mul r10.xy, r7.xyxx, r5.yzyy
add r5.yzw, -r3.xxyz, r10.xxyz
mul r7.zw, r5.yyyz, cb0[18].zzzz
mul r5.yz, r7.zzwz, l(0.000000, 0.500000, 0.500000, 0.000000)
dp3 r2.x, r5.yzwy, r5.yzwy
sqrt r2.x, r2.x
max r2.x, r2.x, l(0.000100)
div r5.y, -r5.w, r2.x
max r5.y, r5.y, l(-1.000000)
min r5.y, r5.y, l(1.000000)
mul r5.z, r5.y, r5.y
mul r5.z, r5.z, r5.z
mad r5.z, r5.z, l(-0.570320), l(-1.000480)
add r2.x, r2.x, l(-500.000000)
mul_sat r2.x, r2.x, l(-0.010000)
mad r5.y, r5.z, r5.y, l(-1.57079279)
mad r2.x, r2.x, r5.y, l(3.14159274)
min r2.x, r2.z, r2.x
add r5.y, -r5.w, l(-250.000000)
mul_sat r5.y, r5.y, l(-0.004000)
add r2.x, -r2.z, r2.x
mad r2.x, r5.y, r2.x, r2.z
sample_l_indexable(texture2d)(float,float,float,float) r2.y, r9.zwzz, t5.yxzw, s0, r2.y
mad r2.z, r2.y, cb1[57].x, cb1[57].y
mad r2.y, r2.y, cb1[57].z, -cb1[57].w
rcp r2.y, r2.y
add r9.z, r2.y, r2.z
mul r2.yz, r8.zzwz, r9.zzzz
mul r9.xy, r7.xyxx, r2.yzyy
add r5.yzw, -r3.xxyz, r9.xxyz
mul r2.yz, r5.yyzy, cb0[18].zzzz
mul r5.yz, r2.yyzy, l(0.000000, 0.500000, 0.500000, 0.000000)
dp3 r2.y, r5.yzwy, r5.yzwy
sqrt r2.y, r2.y
max r2.y, r2.y, l(0.000100)
div r2.z, -r5.w, r2.y
max r2.z, r2.z, l(-1.000000)
min r2.z, r2.z, l(1.000000)
mul r3.x, r2.z, r2.z
mul r3.x, r3.x, r3.x
mad r3.x, r3.x, l(-0.570320), l(-1.000480)
add r2.y, r2.y, l(-500.000000)
mul_sat r2.y, r2.y, l(-0.010000)
mad r2.z, r3.x, r2.z, l(-1.57079279)
mad r2.y, r2.y, r2.z, l(3.14159274)
min r2.y, r4.w, r2.y
add r2.z, -r5.w, l(-250.000000)
mul_sat r2.z, r2.z, l(-0.004000)
add r2.y, -r4.w, r2.y
mad r2.y, r2.z, r2.y, r4.w
mul r3.xy, r4.yxyy, r5.xxxx
mad r2.z, r4.x, r6.x, r3.x
mad r3.x, r4.y, r6.x, -r3.y
mad r5.xy, -r6.wxww, r3.xxxx, r4.xyxx
mov r5.z, r4.z
dp3 r3.y, r5.xyzx, r5.xyzx
sqrt r3.y, r3.y
max r3.y, r3.y, l(0.000100)
div r4.w, -r4.z, r3.y
max r4.w, r4.w, l(-1.000000)
min r4.w, r4.w, l(1.000000)
lt r5.w, l(0.000000), r2.z
lt r6.z, r2.z, l(0.000000)
iadd r5.w, -r5.w, r6.z
itof r5.w, r5.w
mul r6.z, r4.w, r4.w
mad r6.w, -r4.w, r4.w, l(1.000000)
sqrt r6.w, r6.w
mul r6.w, r5.w, r6.w
mul r6.z, r6.z, r6.z
mad r6.z, r6.z, l(-0.570320), l(-1.000480)
mad r4.w, r6.z, r4.w, l(1.570800)
mul r6.z, r4.w, r5.w
mad r2.w, -r5.w, r4.w, r2.w
min r2.w, r2.w, l(1.57079637)
mad r2.x, -r5.w, r4.w, -r2.x
max r2.x, r2.x, l(-1.57079637)
mad r4.w, r6.z, l(2.000000), r2.w
add r4.w, r2.x, r4.w
mad r2.w, r2.w, l(2.000000), r6.z
mad r2.x, r2.x, l(2.000000), r6.z
sincos null, r2.xw, r2.xxxw
add r2.x, r2.x, r2.w
mul r2.x, r2.x, l(0.500000)
mad r2.x, r4.w, r6.w, -r2.x
mad r5.xy, -r6.xyxx, r2.zzzz, r4.xyxx
dp3 r2.z, r5.xyzx, r5.xyzx
sqrt r2.z, r2.z
max r2.z, r2.z, l(0.000100)
div r2.w, -r4.z, r2.z
max r2.w, r2.w, l(-1.000000)
min r2.w, r2.w, l(1.000000)
lt r4.x, l(0.000000), r3.x
lt r3.x, r3.x, l(0.000000)
iadd r3.x, -r4.x, r3.x
itof r3.x, r3.x
mul r4.x, r2.w, r2.w
mad r4.y, -r2.w, r2.w, l(1.000000)
sqrt r4.y, r4.y
mul r4.y, r3.x, r4.y
mul r4.x, r4.x, r4.x
mad r4.x, r4.x, l(-0.570320), l(-1.000480)
mad r2.w, r4.x, r2.w, l(1.570800)
mul r4.x, r2.w, r3.x
mad r2.y, -r3.x, r2.w, r2.y
min r2.y, r2.y, l(1.57079637)
mad r2.w, -r3.x, r2.w, -r3.w
max r2.w, r2.w, l(-1.57079637)
mad r3.x, r4.x, l(2.000000), r2.y
add r3.x, r2.w, r3.x
mad r2.y, r2.y, l(2.000000), r4.x
mad r2.w, r2.w, l(2.000000), r4.x
sincos null, r2.yw, r2.yyyw
add r2.y, r2.w, r2.y
mul r2.y, r2.y, l(0.500000)
mad r2.y, r3.x, r4.y, -r2.y
mul r2.y, r2.y, r2.z
mad r2.x, r3.y, r2.x, r2.y
mul r2.y, r5.z, l(0.500000)
mad r2.x, r2.x, l(0.250000), -r2.y
max r2.w, r2.x, l(0.000000)
mul r3.xyw, r1.wwww, cb1[115].xyxw
mad r3.xyw, r1.zzzz, cb1[114].xyxw, r3.xyxw
mad r3.xyw, r0.zzzz, cb1[116].xyxw, r3.xyxw
add r3.xyw, r3.xyxw, cb1[117].xyxw
div r3.xy, r3.xyxx, r3.wwww
mad r3.xy, r1.xyxx, l(1.000000, -1.000000, 0.000000, 0.000000), -r3.xyxx
ld_indexable(texture2d)(float,float,float,float) r0.xy, r0.xyww, t4.xyzw
dp2 r0.z, r0.xyxx, r0.xyxx
lt r0.z, l(0.000000), r0.z
add r0.xy, r0.xyxx, l(-0.499992371, -0.499992371, 0.000000, 0.000000)
mul r0.xy, r0.xyxx, l(4.008016, 4.008016, 0.000000, 0.000000)
movc r0.xy, r0.zzzz, r0.xyxx, r3.xyxx
mad r0.xy, r1.xyxx, l(1.000000, -1.000000, 0.000000, 0.000000), -r0.xyxx
mul r1.xy, r0.xyxx, cb1[125].xyxx
mad r1.xy, r1.zwzz, cb1[122].xyxx, -r1.xyxx
dp2 r0.w, r1.xyxx, r1.xyxx
sqrt r0.w, r0.w
mul r0.w, r0.w, l(0.012500)
min r2.y, r0.w, l(1.000000)
max r0.w, |r0.y|, |r0.x|
lt r0.w, r0.w, l(1.000000)
if_nz r0.w
  mad r0.xy, r0.xyxx, cb1[123].xyxx, cb1[123].wzww
  mul r0.xy, r0.xyxx, cb1[126].xyxx
  add r1.xy, cb1[124].xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  add r1.zw, cb1[124].xxxy, cb1[125].xxxy
  add r1.zw, r1.zzzw, l(0.000000, 0.000000, -0.500000, -0.500000)
  max r0.xy, r0.xyxx, r1.xyxx
  min r0.xy, r1.zwzz, r0.xyxx
  mul r0.xy, r0.xyxx, cb0[1].zwzz
  sample_l_indexable(texture2d)(float,float,float,float) r0.xyw, r0.xyxx, t3.xywz, s0, l(0.000000)
  ne r1.x, r0.y, l(0.000000)
  mad r0.y, r0.w, l(0.800000), r2.y
  not r0.w, r0.z
  and r0.w, r1.x, r0.w
  mov r2.x, l(1.000000)
  movc r2.xy, r0.wwww, r2.wxww, r0.xyxx
else
  mov r2.xy, r2.wyww
endif
movc r2.z, r0.z, -r3.z, r3.z
mov o0.xyzw, r2.wxyz
ret
// Approximately 0 instruction slots used

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
