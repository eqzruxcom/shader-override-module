"""Separate synthetic motion boundary ambiguity from wider false shadows.

The unmodified GPU readback remains primary. The CPU closest-point calculation
uses the SAME known box geometry, not the shader's depth/thickness algorithm.
It also checks the shader's biased ray origin, so bias-induced edge crossings
are not misreported as rays that miss the box.
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
target = root / 'geometry-analysis.json'
if target.exists():
    raise SystemExit('Preserve existing analysis; choose a fresh audit directory.')

def clearance_and_chord(frame, receiver):
    phase = 0 if frame == 95 else 2*math.pi*frame/95
    u, v = (receiver % 32+.5)/32, (receiver//32+.5)/16
    p = np.array([(u-.5)*65, (v-.5)*45, 0.])
    p[2] = 160+.35*p[0]-.18*p[1]
    normal = np.array([.35, -.18, -1.]); normal /= np.linalg.norm(normal)
    d = np.array([80., 45., 40.])-p
    distance = np.linalg.norm(d); d /= distance
    bias = 100/720
    origin = p+normal*bias*.5+d*bias
    length = min(100, distance-bias-26.25)
    center = np.array([35*math.sin(phase), 10., 130.])
    lower, upper = center-[8, 10, 8], center+[8, 10, 8]
    # Derivative of squared distance from a line point to a convex AABB is
    # monotone. Bisection finds the global nearest point on the finite ray.
    left, right = 0., length
    for _ in range(45):
        t = (left+right)*.5
        q = origin+d*t
        derivative = np.dot(d, q-np.clip(q, lower, upper))
        if derivative > 0: right = t
        else: left = t
    q = origin+d*((left+right)*.5)
    clearance = float(np.linalg.norm(q-np.clip(q, lower, upper)))
    entry, exit_t = 0., length
    for i in range(3):
        if abs(d[i]) < 1e-12:
            if not lower[i] <= origin[i] <= upper[i]: return clearance, 0.
        else:
            a, b = (lower[i]-origin[i])/d[i], (upper[i]-origin[i])/d[i]
            entry, exit_t = max(entry, min(a, b)), min(exit_t, max(a, b))
    return clearance, max(0., exit_t-entry)

rows = list(csv.DictReader((root/'results.csv').open(newline='')))
previous = {}
false_clearances, missed_chords = [], []
stable_unblocked_changes, wide_changes = [], []
examples = []
for r in rows:
    if r['scene'] != '2': continue
    frame, receiver = int(r['frame']), int(r['receiver'])
    key = receiver
    old = previous.get(key)
    if r['active'] == '1':
        false = r['expectedShadow'] == '0' and float(r['visibility']) < .999
        missed = r['screenVisibleBlocker'] == '1' and float(r['visibility']) >= .5
        if false or missed:
            clearance, chord = clearance_and_chord(frame, receiver)
            if false:
                false_clearances.append(clearance)
                if clearance > 1 and len(examples) < 8:
                    examples.append(dict(frame=frame, receiver=receiver, visibility=float(r['visibility']), biasedRayBoxClearance=clearance))
            if missed: missed_chords.append(chord)
        if old and old['active'] == '1' and r['expectedShadow'] == old['expectedShadow'] == '0' and abs(float(r['visibility'])-float(old['visibility'])) > .5:
            c0, _ = clearance_and_chord(frame-1, receiver)
            c1, _ = clearance_and_chord(frame, receiver)
            stable_unblocked_changes.append(min(c0, c1))
            if min(c0, c1) > 1: wide_changes.append(dict(frame=frame, receiver=receiver, before=float(old['visibility']), after=float(r['visibility']), minimumBiasedRayBoxClearance=min(c0, c1)))
    previous[key] = r

def summary(values):
    a = np.asarray(values)
    return dict(count=len(values), percentiles=dict(zip(['min', 'p25', 'median', 'p75', 'max'], np.percentile(a, [0, 25, 50, 75, 100]).tolist()))) if len(a) else dict(count=0)

result = dict(
    scope='Synthetic moving-box sequence; not a live FF7 diagnosis',
    falseHitClearance=summary(false_clearances),
    falseHitsWithBiasedRayClearanceOverOneUnit=sum(x > 1 for x in false_clearances),
    missedVisibleBlockerBiasedRayChord=summary(missed_chords),
    missedVisibleBlockersWithChordOverFiveUnits=int(sum(x > 5 for x in missed_chords)),
    stableUnblockedLargeChanges=summary(stable_unblocked_changes),
    stableUnblockedChangesWithClearanceOverOneUnit=len(wide_changes),
    wideChangeExamples=wide_changes[:8], falseHitExamples=examples,
    limitations=['One unit is an explanatory geometry category, not a live quality acceptance threshold',
                 'Visibility/active/oracle classification comes from the recorded CPU/GPU audit',
                 'This analysis neither changes the shader nor relaxes its deployment gate'],
    inputSha256=hashlib.sha256((root/'results.csv').read_bytes()).hexdigest().upper(),
    analyzerSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper(),
)
target.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
print(json.dumps(result, indent=2))
