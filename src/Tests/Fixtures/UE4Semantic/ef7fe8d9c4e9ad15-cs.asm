cs_5_0
dcl_resource_texture3d (float,float,float,float) t6
dcl_resource_texture3d (float,float,float,float) t7
dcl_resource_texture3d (float,float,float,float) t8
dcl_uav_typed_texture3d (float,float,float,float) u0
dcl_input vThreadID.xyz
dcl_thread_group 4, 4, 4
ld_indexable(texture3d)(float,float,float,float) r6.xyzw, r5.xyzw, t8.xyzw
ld_indexable(texture3d)(float,float,float,float) r2.xyzw, r5.xyzw, t6.xyzw
sample_l_indexable(texture3d)(float,float,float,float) r0.xyzw, r0.xyzx, t7.xyzw, s3, l(0.000000)
add r0.xyzw, -r1.xyzw, r0.xyzw
mad r1.xyzw, r0.xyzw, l(0.850000, 0.850000, 0.850000, 0.850000), r1.xyzw
store_uav_typed u0.xyzw, vThreadID.xyzz, r1.xyzw
ret
