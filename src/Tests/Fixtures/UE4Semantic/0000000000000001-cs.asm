cs_5_0
dcl_resource_texture3d (float,float,float,float) t0
dcl_uav_typed_texture3d (float,float,float,float) u0
dcl_input vThreadID.xyz
dcl_thread_group 4, 4, 4
ld_indexable(texture3d)(float,float,float,float) r0.xyzw, vThreadID.xyzz, t0.xyzw
store_uav_typed u0.xyzw, vThreadID.xyzz, r0.xyzw
ret
