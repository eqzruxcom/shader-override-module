ps_5_0
dcl_sampler s0, mode_default
dcl_resource_texture3d (float,float,float,float) t0
dcl_resource_texture2d (float,float,float,float) t1
dcl_resource_texture2d (float,float,float,float) t2
dcl_resource_texture2d (float,float,float,float) t3
dcl_resource_texture2d (float,float,float,float) t4
dcl_resource_texture2d (float,float,float,float) t5
ld_indexable(texture3d)(float,float,float,float) r2.xy, r2.xyzw, t0.yzxw
ld_indexable(texture2d)(float,float,float,float) r0.z, r0.xyww, t2.yzxw
ld_indexable(texture2d)(float,float,float,float) r4.xyz, r0.xyww, t1.xyzw
ld_indexable(texture2d)(float,float,float,float) r0.xy, r0.xyww, t4.xyzw
log r4.w, r4.w
log r2.y, r2.y
sample_l_indexable(texture2d)(float,float,float,float) r5.w, r8.zwzz, t5.yzwx, s0, r4.w
sample_l_indexable(texture2d)(float,float,float,float) r9.x, r9.xyxx, t5.xyzw, s0, r4.w
sample_l_indexable(texture2d)(float,float,float,float) r2.z, r11.xyxx, t5.yzxw, s0, r4.w
sample_l_indexable(texture2d)(float,float,float,float) r4.w, r11.zwzz, t5.yzwx, s0, r4.w
sample_l_indexable(texture2d)(float,float,float,float) r2.w, r7.zwzz, t5.yzwx, s0, r2.y
sample_l_indexable(texture2d)(float,float,float,float) r3.w, r7.zwzz, t5.yzwx, s0, r2.y
sample_l_indexable(texture2d)(float,float,float,float) r2.x, r9.xyxx, t5.xyzw, s0, r2.y
sample_l_indexable(texture2d)(float,float,float,float) r2.y, r9.zwzz, t5.yxzw, s0, r2.y
dp3 r5.w, r8.xyzx, r8.xyzx
dp3 r8.z, r9.xyzx, r9.xyzx
dp3 r2.z, r12.xyzx, r12.xyzx
dp3 r4.w, r10.xyzx, r10.xyzx
dp3 r2.w, r10.xyzx, r10.xyzx
dp3 r3.w, r5.yzwy, r5.yzwy
dp3 r2.x, r5.yzwy, r5.yzwy
dp3 r2.y, r5.yzwy, r5.yzwy
dp3 r3.y, r5.xyzx, r5.xyzx
dp3 r2.z, r5.xyzx, r5.xyzx
sample_l_indexable(texture2d)(float,float,float,float) r0.xyw, r0.xyxx, t3.xywz, s0, l(0.000000)
mov o0.xyzw, r2.wxyz
ret
