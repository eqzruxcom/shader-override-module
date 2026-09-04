"""Explain recorded donor hit decisions using known synthetic geometry only."""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from analyze_rebirth_pixel_truth import PROJ, SIZE, load, require, scene, sha


def analyze(directory, raw_directory, repo):
    manifest = json.loads((directory/'manifest.json').read_text())
    require(manifest['result'] == 'completed-observer-only' and manifest['frames'] == 96
            and manifest['receivers'] == 512 and manifest['float4RowsPerReceiver'] == 54, 'Wrong trace layout')
    for item in manifest['sources']:
        require(sha(repo/item['path']) == item['sha256'], f"Trace source changed: {item['path']}")
    for item in manifest['outputs']:
        require(sha(directory/item['path']) == item['sha256'], f"Trace output changed: {item['path']}")
    for item in manifest['inputs']:
        require(sha(Path(item['path'])) == item['sha256'], 'Saved trace input changed')
    raw, input_hashes = load(raw_directory, 'RawPixel', repo)
    trace = np.fromfile(directory/'trace.f32', dtype='<f4').reshape(96, 512, 54, 4).astype(np.float64)
    vis = np.fromfile(directory/'visibility.f32', dtype='<f4').reshape(96, 512)
    require(np.array_equal(vis.view('<u4'), raw['visibility'].view('<u4')), 'Trace differs from saved values')
    require(np.array_equal(trace[:, :, 0, 0], vis), 'Trace header/result mismatch')
    steps = trace[:, :, 6:].reshape(96, 512, 16, 3, 4)
    used = steps[..., 2, 0] >= 0
    hit = used & (steps[..., 2, 1] == 1)
    require(np.array_equal(used.sum(-1), trace[:, :, 0, 1]), 'Observer count mismatch')
    require(np.isfinite(trace).all(), 'Nonfinite trace')
    require(np.all(steps[..., 2, 0][used] == np.broadcast_to(np.arange(16), used.shape)[used]), 'Wrong step index')
    depth0, depth1, thickness, bias = (steps[..., 1, n] for n in range(4))
    depth = steps[..., 0, 2]
    predicate = (np.maximum(depth0, depth1) > depth+bias) & (np.minimum(depth0, depth1) < depth+thickness)
    require(np.array_equal(predicate[used], hit[used]), 'Recorded interval predicate mismatch')
    sample_t = steps[..., 0, 3]
    predicted = np.where(hit, sample_t**6, 1).min(-1)
    require(np.max(np.abs(predicted-vis)) < 2e-6, 'Recorded hits do not explain final visibility')
    first = np.argmax(hit, axis=-1)
    false = raw['active'] & ~raw['expectedShadow'] & (vis < .999)
    missed = raw['active'] & raw['screenVisibleBlocker'] & (vis >= .5)
    records = []
    max_depth_error = 0.
    for frame in range(96):
        phase = 0 if frame == 95 else 2*math.pi*frame/95
        yaw = .14*math.sin(phase)
        camera = np.array([18*math.sin(phase), 3*math.sin(2*phase), -8*math.cos(phase)])
        rotation = np.array([[math.cos(yaw), 0, -math.sin(yaw)], [0, 1, 0], [math.sin(yaw), 0, math.cos(yaw)]])
        box = np.array([35*math.sin(phase), 10., 130.])
        uv = steps[frame, ..., 0, :2]
        # The shader multiplies in float32 before floor. Promoting first can
        # select the previous texel when the product rounds to an integer.
        pixels = np.clip(np.floor(uv.astype(np.float32)*SIZE.astype(np.float32)), 0, SIZE-1)
        ndc = (pixels+.5)/SIZE*[2, -2]+[-1, 1]
        view_ray = np.concatenate([ndc/PROJ, np.ones((*pixels.shape[:-1], 1))], axis=-1)
        exact_depth, on_box = scene(camera, view_ray @ rotation, box)
        error = np.abs(exact_depth-depth[frame])
        max_depth_error = max(max_depth_error, float(error[used[frame]].max(initial=0)))
        if not (error[used[frame]] < .002).all():
            receiver, index = np.unravel_index(np.argmax(np.where(used[frame], error, 0)), error.shape)
            raise ValueError(f'Logged texel depth differs: frame={frame} receiver={receiver} step={index} '
                             f'pixel={pixels[receiver,index]} expected={exact_depth[receiver,index]} '
                             f'actual={depth[frame,receiver,index]} uv={uv[receiver,index]}')
        origin, direction = trace[frame, :, 1, :3], trace[frame, :, 2, :3]
        world_origin, world_direction = origin @ rotation+camera, direction @ rotation
        geometric_hit, _ = scene(world_origin, world_direction, box)
        # Solve the logged ray's 3D point at its sample UV independently of
        # the donor's finite depth-interval intersection. Use its float32
        # projection constants, selecting the better-conditioned component.
        k = (uv-.5)*[2, -2]/PROJ.astype(np.float32)
        numerator = k*origin[:, None, 2, None]-origin[:, None, :2]
        denominator = direction[:, None, :2]-k*direction[:, None, 2, None]
        axis = np.argmax(np.abs(denominator), axis=-1)[..., None]
        den = np.take_along_axis(denominator, axis, -1)[..., 0]
        t = np.take_along_axis(numerator, axis, -1)[..., 0]/np.where(np.abs(den) > 1e-12, den, 1)
        point_depth = origin[:, None, 2]+direction[:, None, 2]*t
        continuous_ndc = (uv-.5)*[2, -2]
        continuous_ray = np.concatenate([continuous_ndc/PROJ, np.ones((*uv.shape[:-1], 1))], axis=-1)
        continuous_depth, continuous_box = scene(camera, continuous_ray @ rotation, box)
        for receiver in np.flatnonzero(false[frame]):
            index = first[frame, receiver]
            require(hit[frame, receiver, index], 'False result without a logged hit')
            ray_z = float(point_depth[receiver, index])
            scene_z = float(depth[frame, receiver, index])
            bias_z = float(bias[frame, receiver, index])
            thick_z = float(thickness[frame, receiver, index])
            records.append({'frame': frame, 'receiver': int(receiver), 'step': int(index),
                            'visibility': float(vis[frame, receiver]), 'sampleT': float(sample_t[frame, receiver, index]),
                            'sampledSurface': 'box' if on_box[receiver, index] else 'plane',
                            'biasedRayIntersectsGeometry': bool(geometric_hit[receiver] < trace[frame, receiver, 1, 3]),
                            'sampleUVChangesSurfaceVsTexelCenter': bool(on_box[receiver, index] != continuous_box[receiver, index]),
                            'sampleDepth': scene_z, 'pointRayDepth': ray_z, 'bias': bias_z, 'thickness': thick_z,
                            'intervalDepthMin': float(min(depth0[frame, receiver, index], depth1[frame, receiver, index])),
                            'intervalDepthMax': float(max(depth0[frame, receiver, index], depth1[frame, receiver, index])),
                            'pointBeforeFront': ray_z <= scene_z+bias_z,
                            'pointBeyondBack': ray_z >= scene_z+thick_z,
                            'pointWithinDepthVolume': scene_z+bias_z < ray_z < scene_z+thick_z,
                            'continuousUVDepth': float(continuous_depth[receiver, index]),
                            'pixel': pixels[receiver, index].astype(int).tolist(),
                            'receiverViewPosition': trace[frame, receiver, 5, :3].tolist()})
    keys = ['biasedRayIntersectsGeometry', 'sampleUVChangesSurfaceVsTexelCenter', 'pointBeforeFront', 'pointBeyondBack', 'pointWithinDepthVolume']
    summary = {'receiversVerified': int(vis.size), 'stepsVerified': int(used.sum()), 'acceptedSteps': int(hit.sum()),
               'instrumentedValuesBitIdentical': True, 'maximumSampleDepthError': max_depth_error,
               'maximumVisibilityFromHitsError': float(np.max(np.abs(predicted-vis))),
               'originalFalseHits': int(false.sum()), 'originalMissedEligible': int(missed.sum()),
               'falseHitFirstSurfaceCounts': {name: sum(r['sampledSurface'] == name for r in records) for name in ('box', 'plane')},
               'falseHitFirstStepCounts': {str(i): sum(r['step'] == i for r in records) for i in range(16)},
               'falseHitClassifications': {key: sum(r[key] for r in records) for key in keys}}
    return {'result': 'donor-ray-diagnostic-only', 'runtimeEligible': False, 'qualityGatePassed': False,
            'gameFilesModified': False, 'summary': summary, 'falseHitCases': records,
            'traceManifest': {'path': str(directory/'manifest.json'), 'sha256': sha(directory/'manifest.json')},
            'rawInputs': input_hashes,
            'sources': {p.name: sha(p) for p in (Path(__file__), Path(__file__).with_name('analyze_rebirth_pixel_truth.py'))},
            'limitations': ['Synthetic moving box, not a reproduction of Cloud arm banding',
                            'First accepted interval is attributed; other accepted intervals can coexist',
                            'Geometric ray check includes normal/depth bias but not viewport clipping',
                            'Point-depth classifications use CPU double geometry around recorded float32 inputs',
                            'A finite screen-depth interval is an approximation; its false hits alone do not identify an adapter bug',
                            'No changes to donor algorithm, quality gates, or live game']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('raw', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    require(output.is_relative_to(repo/'artifacts') and output != repo/'artifacts' and not output.exists(), 'Use a fresh artifacts directory')
    report = analyze(args.trace.resolve(), args.raw.resolve(), repo)
    output.mkdir(parents=True)
    (output/'analysis.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps(report['summary'], indent=2))
    print(json.dumps(report['falseHitCases'][:3], indent=2))


if __name__ == '__main__':
    main()
