ps_5_0
dcl_resource_texture2d (float,float,float,float) t0
dcl_resource_texture2d (float,float,float,float) t1
dcl_resource_texture2d (float,float,float,float) t2
dcl_input_ps_siv linear noperspective v1.xy, position
dcl_output o0.xyzw
dp2 r2.x, r0.zwzz, l(0.067111, 0.005837, 0.000000, 0.000000)
mul r2.x, r2.x, l(52.982918)
dp2 r0.x, r0.xyxx, l(0.067111, 0.005837, 0.000000, 0.000000)
mul r0.x, r0.x, l(52.982918)
round_ni r0.xy, r0.xyxx
ftoi r0.xy, r0.xyxx
round_ni r1.xy, r1.xyxx
ftoi r1.xy, r1.xyxx
round_ni r2.xy, r2.xyxx
ftoi r2.xy, r2.xyxx
round_ni r3.xy, r3.xyxx
ftoi r3.xy, r3.xyxx
round_ni r4.xy, r4.xyxx
ftoi r4.xy, r4.xyxx
round_ni r5.xy, r5.xyxx
ftoi r5.xy, r5.xyxx
round_ni r6.xy, r6.xyxx
ftoi r6.xy, r6.xyxx
round_ni r7.xy, r7.xyxx
ftoi r7.xy, r7.xyxx
round_ni r8.xy, r8.xyxx
ftoi r8.xy, r8.xyxx
round_ni r9.xy, r9.xyxx
ftoi r9.xy, r9.xyxx
ld_indexable(texture2d)(float,float,float,float) r0.xyz, r0.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r1.xyz, r1.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r2.xyz, r2.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r3.xyz, r3.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r4.xyz, r4.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r5.xyz, r5.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r6.xyz, r6.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r7.xyz, r7.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r8.xyz, r8.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r9.xyz, r9.xyww, t0.xyzw
ld_indexable(texture2d)(float,float,float,float) r0.xy, r0.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r1.xy, r1.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r2.xy, r2.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r3.xy, r3.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r4.xy, r4.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r5.xy, r5.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r6.xy, r6.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r7.xy, r7.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r8.xy, r8.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r9.xy, r9.xyww, t2.xyzw
mul r5.xyz, r6.xyzx, l(0.125000, 0.125000, 0.125000, 0.000000)
mov o0.xyz, r5.xyzx
mov o0.w, l(0)
ret
