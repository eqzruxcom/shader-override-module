"""Numerical explanation of a synthetic case; NOT a replacement shader test.

GPU results from Audit-ContactShadowMotion remain authoritative. This helper
prints geometric depths and the production interval predicate for diagnosis.
"""
import argparse
import math
import numpy as np

p = argparse.ArgumentParser()
p.add_argument('--frame', type=int, default=2)
p.add_argument('--receiver', type=int, default=192)
a = p.parse_args()
phase = 0 if a.frame == 95 else 2*math.pi*a.frame/95
yaw = .14*math.sin(phase)
camera = np.array([18*math.sin(phase), 3*math.sin(2*phase), -8*math.cos(phase)])
right = np.array([math.cos(yaw), 0, -math.sin(yaw)])
forward = np.array([math.sin(yaw), 0, math.cos(yaw)])
rotation = np.stack([right, [0, 1, 0], forward])
box = np.array([35*math.sin(phase), 10, 130])
light = np.array([80, 45, 40])
size = np.array([1280, 720])
proj = np.array([1.7320509, 3.079202])
u, v = (a.receiver % 32+.5)/32, (a.receiver//32+.5)/16
point = np.array([(u-.5)*65, (v-.5)*45, 0])
point[2] = 160+.35*point[0]-.18*point[1]
normal = np.array([.35, -.18, -1]); normal /= np.linalg.norm(normal)
direction = light-point; distance = np.linalg.norm(direction); direction /= distance

def box_hit(o, d):
    lo, hi = 0, 1e20
    for j, half in enumerate([8, 10, 8]):
        if abs(d[j]) < 1e-12:
            if not box[j]-half <= o[j] <= box[j]+half: return 1e20
        else:
            x, y = (box[j]-half-o[j])/d[j], (box[j]+half-o[j])/d[j]
            lo, hi = max(lo, min(x, y)), min(hi, max(x, y))
            if hi < lo: return 1e20
    return lo if lo > 1e-5 else hi if hi > 1e-5 else 1e20

def sample_depth(uv):
    uv = (np.floor(uv*size)+.5)/size
    ray = rotation.T @ np.array([(2*uv[0]-1)/proj[0], (1-2*uv[1])/proj[1], 1])
    z = (160+.35*camera[0]-.18*camera[1]-camera[2])/(ray[2]-.35*ray[0]+.18*ray[1])
    z = z if z > 0 else 1e20
    return min(z, box_hit(camera, ray)), uv

vp, vn, vd = rotation @ (point-camera), rotation @ normal, rotation @ direction
bias = 100/720
origin = vp+vn*bias*.5+vd*bias
length = min(100, distance-bias-26.25)
end = origin+vd*length
def clip(pt): return np.array([pt[0]*proj[0], pt[1]*proj[1], .1, pt[2]])
c0, c1 = clip(origin), clip(end)
def planes(c): return [c[3]-1e-5,c[0]+c[3],c[3]-c[0],c[1]+c[3],c[3]-c[1],c[2],c[3]-c[2]]
exit_t = min([1]+[s/(s-e) for s,e in zip(planes(c0),planes(c1)) if e < 0])
c1 = c0+(c1-c0)*exit_t
uv0, uv1 = c0[:2]/c0[3]*[.5,-.5]+.5, c1[:2]/c1[3]*[.5,-.5]+.5
def ray_depth(t): return 1/((1-t)/c0[3]+t/c1[3])
minimum_t = (.5+1-np.dot(normal,direction))/16
segment0 = ray_depth(minimum_t)
print('world receiver', point, 'box', box, 'exact entry', box_hit(point, direction), 'ray length', length, 'exit', exit_t)
print('start', origin, 'end', end, 'minT', minimum_t)
previous_t, previous_pen = minimum_t, None
for i in range(16):
    t = 1 if i == 15 else (i+.5)/16
    end_t = 1 if i == 15 else min(1,t+.5/16)
    if end_t <= minimum_t: continue
    segment1 = ray_depth(end_t)
    z, uv = sample_depth(uv0+(uv1-uv0)*t)
    pen = ray_depth(t)-z
    thickness = min(25,max(5,5+max(2*z/(proj*size))*32))
    direct = ray_depth(t)>z+bias and max(segment0,segment1)>z+bias and min(segment0,segment1)<z+thickness
    ndc = (uv-.5)/np.array([.5,-.5])
    surface = np.array([ndc[0]*z/proj[0], ndc[1]*z/proj[1], z])
    plane_distance = np.dot(surface-vp,vn)
    crossing = previous_pen is not None and previous_pen <= bias and pen > bias
    print(f'{i:2}: t={t:.4f} rayZ={ray_depth(t):.5f} sceneZ={z:.5f} pen={pen:.5f} thickness={thickness:.5f} direct={direct} crossing={crossing} plane={plane_distance:.5f}')
    if not direct and crossing:
        low, high = previous_t, t
        last_z, last_uv = z, uv
        for _ in range(5):
            mid = (low+high)/2
            mz, muv = sample_depth(uv0+(uv1-uv0)*mid)
            if ray_depth(mid)>mz+bias: high, last_z, last_uv=mid,mz,muv
            else: low=mid
        print('    refined',high,'rayZ',ray_depth(high),'sceneZ',last_z,'penetration',ray_depth(high)-last_z)
    previous_t, previous_pen, segment0 = t, pen, segment1
