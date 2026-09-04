"""Diagnose tracked-point versus pixel/quad geometry in saved donor motion tests.

No shader changes, new rendering, quality approval, or modified gate results.
Only the analytic moving-box scene is modeled. GPU visibility stays authoritative.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np

SIZE = np.array([1280, 720])
PROJ = np.array([1.7320509, 3.079202])
LIGHT = np.array([80., 45., 40.])
INF = 1e20


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def scene(origin, direction, box):
    """Same analytic sloped plane / AABB as Audit-ContactShadowMotion.cpp."""
    origin, direction = np.broadcast_arrays(origin, direction)
    near = np.zeros(direction.shape[:-1])
    far = np.full_like(near, INF)
    good = np.ones_like(near, dtype=bool)
    for axis, half in enumerate([8, 10, 8]):
        o, d = origin[..., axis], direction[..., axis]
        parallel = np.abs(d) < 1e-12
        safe = np.where(parallel, 1., d)
        a, b = (box[axis]-half-o)/safe, (box[axis]+half-o)/safe
        near = np.maximum(near, np.where(parallel, -INF, np.minimum(a, b)))
        far = np.minimum(far, np.where(parallel, INF, np.maximum(a, b)))
        good &= ~parallel | ((o >= box[axis]-half) & (o <= box[axis]+half))
    box_t = np.where(good & (far >= near), np.where(near > 1e-5, near, np.where(far > 1e-5, far, INF)), INF)
    den = direction[..., 2]-.35*direction[..., 0]+.18*direction[..., 1]
    plane_t = (160+.35*origin[..., 0]-.18*origin[..., 1]-origin[..., 2])/np.where(np.abs(den) < 1e-12, 1., den)
    plane_t = np.where((np.abs(den) >= 1e-12) & (plane_t > 1e-5), plane_t, INF)
    return np.minimum(plane_t, box_t), box_t <= plane_t


def truth(points, camera, rotation, box):
    delta = LIGHT-points
    distance = np.linalg.norm(delta, axis=-1)
    direction = delta/distance[..., None]
    hit, _ = scene(points+direction*.001, direction, box)
    shadow = hit < np.minimum(100., distance-26.25)
    hit_point = points+direction*hit[..., None]
    hp = (hit_point-camera) @ rotation.T
    uv = hp[..., :2]/hp[..., 2, None]*PROJ*[.5, -.5]+.5
    visible_t, _ = scene(camera, hit_point-camera, box)
    eligible = shadow & (hit > 12) & (hit < 70) & (hp[..., 2] > 0)
    eligible &= (uv > .01).all(-1) & (uv < .99).all(-1) & (np.abs(visible_t-1) < .002)
    return shadow, eligible


def load(directory, mode, repo):
    manifest = json.loads((directory/'manifest.json').read_text())
    require(manifest['implementation'] == 'Rebirth' and manifest['reconstruction'] == mode, 'Wrong donor/mode')
    require(manifest['framesPerScene'] == 96 and manifest['receiversPerFrame'] == 512
            and manifest['noiseMode'] == 'donor-animated-IGN', 'Unexpected motion layout')
    # Verify the scene and shader that produced the stored values, not unrelated
    # included runner utilities subsequently extended for repeated-light tests.
    relevant = ('tools/Audit-ContactShadowMotion.cpp', 'src/Tests/ContactShadowsMotion_cs.hlsl',
                'src/Tests/RebirthContactMotion_cs.hlsl', 'src/Effects/Lighting/RebirthContactShadows.hlsl',
                'src/Effects/Lighting/ContactShadowCommon.hlsl',
                'src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl',
                'src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl',
                'src/ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl')
    sources = {s['path']: s['sha256'] for s in manifest['sources']}
    for path in relevant:
        require(sources.get(path) == sha(repo/path), f'Motion source changed: {path}')
    with (directory/'results.csv').open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    require(len(rows) == 4*96*512, 'Incomplete motion CSV')
    values = np.fromfile(directory/'visibility.f32', dtype='<f4')
    require(values.size == len(rows) and np.isfinite(values).all() and ((values >= 0) & (values <= 1)).all(), 'Bad readback')
    require(np.allclose(values, [float(r['visibility']) for r in rows], atol=1e-6, rtol=0), 'CSV/readback differ')
    for index, row in enumerate(rows):
        require((int(row['scene']), int(row['frame']), int(row['receiver'])) ==
                (index//(96*512), index//512 % 96, index % 512), 'Unexpected row order')
    records = rows[2*96*512:3*96*512]
    fields = {key: np.array([int(r[key]) for r in records], dtype=bool).reshape(96, 512)
              for key in ('active', 'expectedShadow', 'screenVisibleBlocker')}
    fields['visibility'] = values.reshape(4, 96, 512)[2]
    return fields, {name: sha(directory/name) for name in ('manifest.json', 'results.csv', 'visibility.f32')}


def analyze(raw, quad):
    for name in ('active', 'expectedShadow', 'screenVisibleBlocker'):
        require(np.array_equal(raw[name], quad[name]), f'Unmatched motion inputs: {name}')
    i = np.arange(512)
    points = np.stack([((i % 32+.5)/32-.5)*65, ((i//32+.5)/16-.5)*45, np.zeros(512)], axis=-1)
    points[:, 2] = 160+.35*points[:, 0]-.18*points[:, 1]
    center_truth, center_eligible, neighbor_truth, selection, crossed, boundary = [], [], [], [], [], []
    for frame in range(96):
        phase = 0 if frame == 95 else 2*math.pi*frame/95
        yaw = .14*math.sin(phase)
        camera = np.array([18*math.sin(phase), 3*math.sin(2*phase), -8*math.cos(phase)])
        rotation = np.array([[math.cos(yaw), 0, -math.sin(yaw)], [0, 1, 0], [math.sin(yaw), 0, math.cos(yaw)]])
        box = np.array([35*math.sin(phase), 10., 130.])
        expected, eligible = truth(points, camera, rotation, box)
        require(np.array_equal(expected, raw['expectedShadow'][frame]) and
                np.array_equal(eligible, raw['screenVisibleBlocker'][frame]), 'Analytic truth does not match recorded host')
        # Match float32 receiver upload / projection arithmetic. Values close
        # to an integer pixel boundary are flagged, not silently reclassified.
        vp = ((points-camera) @ rotation.T).astype(np.float32)
        uv = (vp[:, :2]*PROJ.astype(np.float32))/vp[:, 2, None]
        uv = uv*np.array([.5, -.5], np.float32)+np.float32(.5)
        screen = uv*SIZE.astype(np.float32)
        pixel = np.floor(screen).astype(int)
        boundary.append(np.min(np.abs(screen-np.round(screen)), axis=1) < .001)
        require(((pixel >= 2) & (pixel < SIZE-2)).all(), 'Diagnostic requires interior receivers')
        neighbors = (pixel[:, None, :] & ~1)+np.array([[0, 0], [1, 0], [0, 1], [1, 1]])
        pixels = np.concatenate([pixel[:, None, :], neighbors], axis=1)
        ndc = ((pixels+.5)/SIZE)*[2, -2]+[-1, 1]
        view_ray = np.concatenate([ndc/PROJ, np.ones((*pixels.shape[:-1], 1))], axis=-1)
        world_ray = view_ray @ rotation
        depth, on_box = scene(camera, world_ray, box)
        require((depth < INF*.5).all(), 'Missing analytic pixel surface')
        world = camera+world_ray*depth[..., None]
        pixel_shadow, pixel_eligible = truth(world, camera, rotation, box)
        center_truth.append(pixel_shadow[:, 0])
        center_eligible.append(pixel_eligible[:, 0])
        noise_frame = 0 if frame == 95 else frame
        selected = ((neighbors.sum(-1)+(noise_frame & 7)) & 1) != 0
        neighbor_truth.append((pixel_shadow[:, 1:] & selected).any(-1))
        selection.append(((pixel.sum(-1)+(noise_frame & 7)) & 1) != 0)
        crossed.append(on_box[:, 0])
    center_truth, center_eligible, neighbor_truth, selection, crossed, boundary = map(np.array,
        (center_truth, center_eligible, neighbor_truth, selection, crossed, boundary))
    active = raw['active']
    result = {'active': int(active.sum()), 'verifiedTrackedTruthRows': 96*512,
              'activePixelTruthDiffers': int((active & (center_truth != raw['expectedShadow'])).sum()),
              'activePixelSurfaceChangedToBox': int((active & crossed).sum()),
              'activeNearPixelBoundary': int((active & boundary).sum()), 'modes': {}}
    for name, data in (('RawPixel', raw), ('RecomputeQuad', quad)):
        vis = data['visibility']
        false = active & ~data['expectedShadow'] & (vis < .999)
        miss = active & data['screenVisibleBlocker'] & (vis >= .5)
        unresolved = false & ~center_truth
        changes = active[1:] & active[:-1] & (data['expectedShadow'][1:] == data['expectedShadow'][:-1]) & (np.abs(vis[1:]-vis[:-1]) > .5)
        records = []
        for frame, receiver in np.argwhere(unresolved)[:8]:
            records.append({'frame': int(frame), 'receiver': int(receiver), 'visibility': float(vis[frame, receiver]),
                            'checkerboardSelected': bool(selection[frame, receiver]), 'selectedNeighborHasGeometricShadow': bool(neighbor_truth[frame, receiver]),
                            'nearPixelBoundary': bool(boundary[frame, receiver])})
        result['modes'][name] = {
            'originalFalseHits': int(false.sum()), 'originalMissedEligible': int(miss.sum()),
            'originalStableTruthLargeChanges': int(changes.sum()),
            'originalFalseWithShadowAtPixelCenter': int((false & center_truth).sum()),
            'originalFalseStillUnshadowedAtPixelCenter': int(unresolved.sum()),
            'originalFalseCheckerboardUnselectedWithShadowedNeighbor': int((unresolved & ~selection & neighbor_truth).sum()),
            'originalFalseUnshadowedCenterAndSelectedNeighbors': int((unresolved & ~neighbor_truth).sum()),
            'originalFalseNearPixelBoundary': int((false & boundary).sum()),
            'originalMissStillEligibleAtPixelCenter': int((miss & center_eligible).sum()),
            'largeChangesWithChangedPixelTruth': int((changes & (center_truth[1:] != center_truth[:-1])).sum()),
            'examplesStillUnshadowedAtCenter': records}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('quad', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    require(output.is_relative_to(repo/'artifacts') and output != repo/'artifacts' and not output.exists(), 'Use a fresh artifacts directory')
    raw, raw_hashes = load(args.raw, 'RawPixel', repo)
    quad, quad_hashes = load(args.quad, 'RecomputeQuad', repo)
    report = {'result': 'diagnostic-only', 'runtimeEligible': False, 'qualityGatePassed': False,
              'gameFilesModified': False, 'analysis': analyze(raw, quad),
              'rawInputs': {'directory': str(args.raw.resolve()), 'sha256': raw_hashes},
              'quadInputs': {'directory': str(args.quad.resolve()), 'sha256': quad_hashes},
              'analyzerSha256': sha(Path(__file__)),
              'limitations': ['Moving-box scene only; not an FF7 reproduction',
                              'Analytic pixel surface truth is not a biased donor ray or temporal-AA oracle',
                              'CPU float32 projection may differ at pixel boundaries; near-boundary samples are reported',
                              'RawPixel traces every receiver; checkerboard labels there are comparison metadata only',
                              'Shadowed neighbors explain possible reconstruction spreading, not acceptable visual quality',
                              'Original audit results and deployment gates remain unchanged']}
    output.mkdir(parents=True)
    (output/'analysis.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps(report['analysis'], indent=2))


if __name__ == '__main__':
    main()
