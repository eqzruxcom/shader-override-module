"""Geometric diagnostic of the synthetic static audit, not GPU validation.

Uses double precision to explain candidate planes and their intersection with
the independently known box. The shader's WARP results remain authoritative.
"""
import argparse
import math
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('--case', type=int, default=961)
args = parser.parse_args()
case = args.case
if not 0 <= case < 20480:
    parser.error('case must be in 0..20479')
test = case % 320
slope, gap = -1.5 + (test % 8)*.5, .01 + ((test//8) % 10)*.1
depth = 100. if (test//80) % 2 == 0 else 1000.
theta = ((case//640) % 8)*math.pi/4
axis = np.array([math.cos(theta), math.sin(theta)])
size = np.array([3840., 2160.])
proj = np.array([1.7320509, 3.079202])
shift = np.array([2., -2.])*(-.4 + (case//5120)*.29)/size
quantized = test >= 160
receiver = np.array([0., 0., depth])
normal = np.array([slope*axis[0], slope*axis[1], -1.])
normal /= np.linalg.norm(normal)
direction = np.array([*axis, slope-gap]); direction /= np.linalg.norm(direction)
box = receiver + direction*40
has_box = case % 640 >= 320
bias = 100/2160
origin = receiver + normal*bias*.5 + direction*bias

def aabb(o, d):
    near, far = 0., 1e20
    for j in range(3):
        if abs(d[j]) < 1e-12:
            if not box[j]-8 <= o[j] <= box[j]+8:
                return 1e20
        else:
            a, b = (box[j]-8-o[j])/d[j], (box[j]+8-o[j])/d[j]
            near, far = max(near, min(a,b)), min(far, max(a,b))
            if near > far:
                return 1e20
    return near if near > 0 else far

def project(p):
    return (p[:2]/p[2]*proj+shift)*[.5, -.5]+.5

def snap(uv):
    return np.clip(np.floor(uv*size)+.5, .5, size-.5)/size if quantized else uv

def surface(uv):
    uv = snap(uv)
    ray = np.array([*((uv*[2,-2]+[-1,1]-shift)/proj), 1.])
    denom = 1-slope*np.dot(axis,ray[:2])
    z = depth/denom if abs(denom) > 1e-12 else 1e20
    z = z if z > 0 else 1e20
    bz = aabb(np.zeros(3), ray) if has_box else 1e20
    return ray*min(z,bz), ('box' if bz < z else 'plane')

def plane(uv):
    p, label = surface(uv)
    left, _ = surface(uv-[1/size[0],0]); right, _ = surface(uv+[1/size[0],0])
    up, _ = surface(uv-[0,1/size[1]]); down, _ = surface(uv+[0,1/size[1]])
    best = None
    for q in range(4):
        dx = right-p if q&1 else p-left
        dy = down-p if q&2 else p-up
        n = np.cross(dx,dy)
        if np.linalg.norm(n) < 1e-8:
            continue
        n /= np.linalg.norm(n)
        diag, _ = surface(uv+np.array([1 if q&1 else -1,1 if q&2 else -1])/size)
        residual = abs(np.dot(diag-p,n))
        if best is None or residual < best[0]:
            best = (residual,n,q)
    return p, best[1], label, best[0], best[2]

def clip(p):
    return np.array([*(p[:2]*proj+shift*p[2]), .1, p[2]])

def sides(c):
    return [c[3]-1e-5, c[0]+c[3], c[3]-c[0], c[1]+c[3], c[3]-c[1], c[2], c[3]-c[2]]

c0, c1 = clip(origin), clip(origin+direction*100)
exit_t = min([1.]+[s/(s-e) for s,e in zip(sides(c0),sides(c1)) if e < 0])
end = origin + direction*100*exit_t
uv0, uv1 = project(origin), project(end)
minimum_t = (.5+1-max(0,np.dot(normal,direction)))/16
def world_distance(t):
    return t/end[2]/((1-t)/origin[2]+t/end[2])*exit_t*100

print('CPU double-precision diagnostic only; compare with WARP readback.')
print('case',case,'slope/gap',slope,gap,'quantized',quantized)
print('biased ray entry',aabb(origin,direction),'minimum distance',world_distance(minimum_t),'visible exit',exit_t*100)
for i in range(16):
    t = 1. if i == 15 else (i+.5)/16
    if min(1,t+.5/16) <= minimum_t:
        continue
    uv = snap(uv0+(uv1-uv0)*t)
    p,n,label,residual,q = plane(uv)
    denominator = np.dot(direction,n)
    distance = np.dot(p-origin,n)/denominator if abs(denominator)>1e-6 else math.inf
    status = 'outside traced interval'
    if world_distance(minimum_t) <= distance <= exit_t*100:
        hit_point = origin+direction*distance
        hit_uv = snap(project(hit_point))
        p2,n2,label2,_,_ = plane(hit_uv)
        den2 = np.dot(direction,n2)
        distance2 = np.dot(p2-origin,n2)/den2 if abs(den2)>1e-6 else math.inf
        if math.isfinite(distance2):
            refined = origin+direction*distance2
            refined_uv = project(refined)
            pf,labelf = surface(refined_uv)
            status = f'refit={distance2:.5f} shiftPx={max(abs(refined_uv-hit_uv)*size):.4f} residual={abs(np.dot(pf-refined,n2)):.7f} labels={label2}/{labelf}'
    print(f'{i:02} surface={label} n={np.round(n,4)} q={q} fitResidual={residual:.8f} candidate={distance:.5f} {status}')
