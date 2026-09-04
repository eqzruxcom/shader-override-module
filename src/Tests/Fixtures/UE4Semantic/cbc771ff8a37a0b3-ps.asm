ps_5_0
dcl_sampler s0, mode_default
dcl_sampler s1, mode_default
dcl_resource_texture3d (float,float,float,float) t0
dcl_resource_texture3d (float,float,float,float) t1
dcl_resource_texture3d (float,float,float,float) t2
dcl_input_ps_siv linear noperspective v1.xy, position
dcl_input_ps_siv constant v2.x, rendertarget_array_index
dcl_output o0.xyzw
utof r0.xy, r0.xyxx
utof r0.z, v2.x
exp r2.w, r2.w
sample_l_indexable(texture3d)(float,float,float,float) r3.w, r4.xyzx, t0.yzwx, s0, l(0.000000)
sample_l_indexable(texture3d)(float,float,float,float) r3.x, r3.xyzx, t0.xyzw, s0, l(0.000000)
sample_l_indexable(texture3d)(float,float,float,float) r3.x, r3.xyzx, t2.xyzw, s1, l(0.000000)
sample_l_indexable(texture3d)(float,float,float,float) r2.y, r2.yzwy, t1.yxzw, s0, l(0.000000)
mul o0.xyzw, r1.xyzw, l(0.500000, 0.500000, 0.500000, 0.500000)
mov o0.xyzw, l(0,0,0,0)
ret
