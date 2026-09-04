"""Classify static-audit failures using independent camera/box geometry.

Being inside the view frustum does not mean the first ray/box intersection is
present in the camera's depth buffer. This reports that distinction without
changing any GPU results or deployment expectations.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('audit_directory', type=Path)
args = parser.parse_args()
root = args.audit_directory.resolve()
target = root/'visibility-analysis.json'
if target.exists():
    raise SystemExit('Preserve existing evidence; choose a fresh audit directory.')

def intersect_box(origin, direction, center):
    entry, exit_t = 0., 1e20
    for j in range(3):
        if abs(direction[j]) < 1e-12:
            if not center[j]-8 <= origin[j] <= center[j]+8:
                return math.inf, math.inf
        else:
            a, b = (center[j]-8-origin[j])/direction[j], (center[j]+8-origin[j])/direction[j]
            entry, exit_t = max(entry,min(a,b)), min(exit_t,max(a,b))
            if entry > exit_t:
                return math.inf, math.inf
    return entry, exit_t

counts = {}
examples = {}
records = []
for row in csv.DictReader((root/'results.csv').open(newline='')):
    if row['expectedShadow'] != '1':
        continue
    case = int(row['case'])
    slope, gap, depth = float(row['slope']), float(row['lightSlopeGap']), float(row['receiverDepth'])
    theta = int(row['orientation'])*math.pi/4
    axis = np.array([math.cos(theta),math.sin(theta)])
    receiver = np.array([0.,0.,depth])
    normal = np.array([*(slope*axis),-1.]); normal /= np.linalg.norm(normal)
    direction = np.array([*axis,slope-gap]); direction /= np.linalg.norm(direction)
    center = receiver+direction*40
    bias = 100/2160
    origin = receiver+normal*bias*.5+direction*bias
    entry, exit_t = intersect_box(origin,direction,center)
    hit = origin+direction*entry
    camera_entry, _ = intersect_box(np.zeros(3),hit,center)
    denominator = hit[2]-slope*np.dot(axis,hit[:2])
    plane_t = depth/denominator if denominator > 0 else math.inf
    first_camera_t = min(camera_entry,plane_t)
    camera_gap = (1-first_camera_t)*np.linalg.norm(hit)
    first_hit_visible = abs(first_camera_t-1) < 1e-6
    missed = float(row['visibility']) >= .5
    group = ('quantized' if row['pointQuantized']=='1' else 'exact')
    label = ('visible-entry' if first_hit_visible else 'hidden-entry')
    key = f'{group}/{label}'
    c = counts.setdefault(key,dict(cases=0,missed=0,detected=0))
    c['cases'] += 1; c['missed' if missed else 'detected'] += 1
    record = dict(case=case,group=key,missed=missed,biasedEntry=entry,biasedExit=exit_t,
                  visibleRayExit=float(row['visibleRayExit']),cameraSurfaceGap=camera_gap)
    records.append(record)
    if missed and key not in examples:
        examples[key] = record

result = dict(scope='Independent synthetic box/plane geometry; not a game diagnosis',
              classification='Whether the first biased light-ray/box hit is visible to the camera',
              counts=counts,examples=examples,
              limitations=['Hidden entry does not imply no usable depth evidence elsewhere on the ray',
                           'No GPU results, acceptance thresholds or deployment gates are changed',
                           'Double-precision geometry versus the shader floating-point implementation'],
              inputSha256=hashlib.sha256((root/'results.csv').read_bytes()).hexdigest().upper(),
              analyzerSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper(),records=records)
target.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))
