cs_5_0
sample_l_indexable(texture3d)(float,float,float,float) r2.xyzw, r2.xyzx, t7.xyzw, s2, l(0.000000)
add r2.xyzw, -r5.xyzw, r2.xyzw
mul r0.w, r0.w, l(0.700000)
mad r5.xyzw, r0.wwww, r2.xyzw, r5.xyzw
store_uav_typed u0.xyzw, vThreadID.xyzz, r5.xyzw
ret
