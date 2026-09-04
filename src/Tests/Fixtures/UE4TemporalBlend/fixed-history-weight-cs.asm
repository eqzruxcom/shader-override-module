cs_5_0
sample_l_indexable(texture3d)(float,float,float,float) r0.xyzw, r0.xyzx, t7.xyzw, s3, l(0.000000)
add r0.xyzw, -r1.xyzw, r0.xyzw
mad r1.xyzw, r0.xyzw, l(0.850000, 0.850000, 0.850000, 0.850000), r1.xyzw
store_uav_typed u0.xyzw, vThreadID.xyzz, r1.xyzw
ret
