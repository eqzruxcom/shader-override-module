"""Compare saved visibility buffers, not screenshots or the full game renderer."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--fork", type=Path, required=True)
    p.add_argument("--baseline", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = a.output.resolve()
    if not output.is_relative_to(repo / "artifacts") or output.exists():
        raise ValueError("Use a new artifacts output directory")
    dirs = {i: a.fork / "artifacts" / f"profile-capture-{i}-v2" for i in (0, 1)}
    manifests = {i: json.loads((d / "manifest.json").read_text(encoding="utf-8-sig")) for i, d in dirs.items()}
    fingerprints = []
    for i, m in manifests.items():
        assert m["edgePercent"] == i and m["leftOnly"]
        assert m["cutoffPercent"] == (0.5 if i else 0)
        assert m["fullStrengthPercent"] == (4 if i else 0)
        for source in m["sources"]:
            assert sha(a.fork / source["path"]) == source["sha256"]
        for key in m["boundInputKeys"]:
            assert m["inputHashes"][key] == manifests[0]["inputHashes"][key]
        for f in m["outputs"]:
            path = dirs[i] / f["path"]
            assert sha(path) == f["sha256"]
            fingerprints.append({"path": str(path), "sha256": f["sha256"]})
        fingerprints.append({"path": str(dirs[i] / "manifest.json"), "sha256": sha(dirs[i] / "manifest.json")})
    prior = json.loads((a.baseline / "manifest.json").read_text(encoding="utf-8-sig"))
    for source in prior["sources"]:
        assert sha(repo / source["path"]) == source["sha256"]
    baseline_matches = 0
    for f in prior["outputs"]:
        if f["path"].startswith("light-"):
            assert sha(a.baseline / f["path"]) == f["sha256"] == sha(dirs[0] / f["path"])
            baseline_matches += 1
    assert baseline_matches == 20
    records = []
    for light in (50, 38, 54, 20, 52):
        for enabled in (0, 1):
            name = f"light-{light}-{enabled}.f32"
            values = {i: np.fromfile(d / name, dtype="<f4") for i, d in dirs.items()}
            assert all(v.size == 518400 and np.isfinite(v).all() and ((v >= 0) & (v <= 1)).all() for v in values.values())
            for i in (1,):
                assert sha(dirs[i] / f"light-{light}-{enabled}.valid.u8") == sha(dirs[0] / f"light-{light}-{enabled}.valid.u8")
                assert (values[i] >= values[0] - 2e-6).all(), "Fade darkened a sample"
            if not enabled:
                assert all((v == 1).all() for v in values.values())
            row = {"light": light, "enabled": enabled}
            for i in (1,):
                changed = np.flatnonzero(values[i] - values[0] > .001)
                # SparseCompleteQuads: x = (gridX >> 1)*8 + (gridX & 1).
                xs = ((changed % 960) // 2) * 8 + ((changed % 960) % 2)
                row[str(i)] = {"changedMoreThanPoint001": int(changed.size),
                               "receiverXRange": [int(xs.min()), int(xs.max())] if xs.size else None}
            records.append(row)
    assert any(r["1"]["changedMoreThanPoint001"] > 0 for r in records if r["enabled"])
    for f in fingerprints:
        assert sha(Path(f["path"])) == f["sha256"]
    output.mkdir()
    report = {"status": "passed-captured-profile-comparison", "zeroWidthBitIdenticalFiles": baseline_matches,
              "cutoffPercent": 0.5, "fullStrengthPercent": 4,
              "records": records, "evidence": fingerprints, "scriptSha256": sha(Path(__file__)),
              "gameModified": False, "qualityGatePassed": False,
              "limits": ["One saved frame, sparse complete quads, not full game shading",
                         "Receiver may be farther inside than fade width when its blocker lies at left edge",
                         "No live movement or performance result"]}
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("status", "zeroWidthBitIdenticalFiles", "records")}, indent=2))

if __name__ == "__main__":
    main()
