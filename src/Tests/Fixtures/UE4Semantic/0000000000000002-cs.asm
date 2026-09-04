cs_5_0
dcl_globalFlags refactoringAllowed
dcl_resource_texture3d (float,float,float,float) t0
dcl_resource_texture3d (float,float,float,float) t1
dcl_resource_texture3d (float,float,float,float) t2
dcl_sampler s0, mode_default
dcl_uav_typed_texture3d (float,float,float,float) u0
dcl_thread_group 4, 4, 4
ld_indexable(texture3d)(float,float,float,float) r0.xyzw, r0.xyzw, t0.xyzw
ld_indexable(texture3d)(float,float,float,float) r1.xyzw, r0.xyzw, t1.xyzw
sample_l_indexable(texture3d)(float,float,float,float) r2.xyzw, r0.xyzw, t2.xyzw, s0, l(0.000000)
add r3.xyzw, -r0.xyzw, r2.xyzw
mul r3.xyzw, r3.xyzw, l(0.700000, 0.700000, 0.700000, 0.700000)
mad r0.xyzw, r3.xyzw, l(0.700000, 0.700000, 0.700000, 0.700000), r0.xyzw
store_uav_typed u0.xyzw, r0.xyzw, r0.xyzw
ret
