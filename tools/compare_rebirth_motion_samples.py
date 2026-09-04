"""Matched existing donor sample settings; diagnostic, never deployment approval."""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from analyze_rebirth_pixel_truth import load, require, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    require(output.is_relative_to(repo/'artifacts') and output != repo/'artifacts' and not output.exists(), 'Use fresh artifacts output')
    records = []
    baseline = None
    for samples in (16, 32, 64):
        for prefix, mode in (('pixel', 'RawPixel'), ('quad', 'RecomputeQuad')):
            suffix = '-20260831-v2' if samples == 16 else f'{samples}-20260831-v1'
            directory = repo/f'artifacts/rebirth-contact-{prefix}-motion{suffix}'
            manifest = json.loads((directory/'manifest.json').read_text())
            require(manifest['samples'] == samples, 'Wrong sample count')
            data, hashes = load(directory, mode, repo)
            if baseline is None:
                baseline = data
            for key in ('active', 'expectedShadow', 'screenVisibleBlocker'):
                require(np.array_equal(data[key], baseline[key]), f'Unmatched scene: {key}')
            vis = data['visibility']
            active = data['active']
            false = active & ~data['expectedShadow'] & (vis < np.float32(.999))
            missed = active & data['screenVisibleBlocker'] & (vis >= .5)
            changes = active[1:] & active[:-1] & (data['expectedShadow'][1:] == data['expectedShadow'][:-1]) & (np.abs(vis[1:]-vis[:-1]) > .5)
            computed = {'active': int(active.sum()), 'falseHits': int(false.sum()),
                        'visibleBlockers': int((active & data['screenVisibleBlocker']).sum()),
                        'missedVisibleBlockers': int(missed.sum()), 'stableTruthLargeChanges': int(changes.sum())}
            with (directory/'frames.csv').open(newline='') as stream:
                frames = list(csv.DictReader(stream))
            require(len(frames) == 384, 'Incomplete frames')
            require([(int(r['scene']), int(r['frame'])) for r in frames] ==
                    [(scene, frame) for scene in range(4) for frame in range(96)], 'Wrong frame order')
            for key, value in computed.items():
                require(sum(int(r[key]) for r in frames if r['scene'] == '2') == value, 'Summary/readback mismatch')
            all_values = np.fromfile(directory/'visibility.f32', dtype='<f4').reshape(4, 96, 512)
            require(np.array_equal(all_values[:, 0].view('<u4'), all_values[:, -1].view('<u4')), 'Endpoint repeat mismatch')
            require(all(int(r['falseHits']) == 0 and int(r['missedVisibleBlockers']) == 0
                        and int(r['stableTruthLargeChanges']) == 0 for r in frames if r['scene'] != '2'), 'Non-box regression changed')
            records.append({'samples': samples, 'mode': mode, **computed,
                            'regressionDetected': manifest['regressionDetected'],
                            'directory': str(directory), 'hashes': {**hashes, 'frames.csv': sha(directory/'frames.csv')}})
    report = {'result': 'sample-setting-comparison-only', 'runtimeEligible': False, 'qualityGatePassed': False,
              'gameFilesModified': False, 'records': records,
              'sources': {p.name: sha(p) for p in (Path(__file__), Path(__file__).with_name('analyze_rebirth_pixel_truth.py'))},
              'limitations': ['Synthetic motion without engine history or TAA',
                              'All settings retain unresolved failures; no default or acceptance gate changed',
                              'Higher nominal sample counts do not establish measured hardware cost',
                              'Shared native integration has been executed at 16 samples only; other settings are not deployed']}
    output.mkdir(parents=True)
    (output/'comparison.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps([{k: r[k] for k in ('samples', 'mode', 'falseHits', 'missedVisibleBlockers', 'stableTruthLargeChanges', 'regressionDetected')} for r in records], indent=2))


if __name__ == '__main__':
    main()
