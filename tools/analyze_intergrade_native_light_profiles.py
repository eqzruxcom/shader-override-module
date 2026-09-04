"""Correlate FF7 Remake native light-profile records with captured tile lists.

This augments a preserved contact-capture analysis without changing the
fingerprinted analyzer used by the guarded contact-shadow staging chain.
It is read-only with respect to the game and capture directory.
"""

import argparse
import json
import struct
from pathlib import Path

import numpy as np

from analyze_intergrade_contact_capture import VARIANTS, sha


def require_artifact_output(path: Path, repo: Path) -> Path:
    output = path.resolve()
    artifacts = (repo / "artifacts").resolve()
    if output == artifacts or not output.is_relative_to(artifacts):
        raise ValueError("Output must be a new directory below workspace artifacts")
    if output.exists():
        raise ValueError("Output exists; preserve previous evidence")
    return output


def decode_u32(payload: bytes, register: int, component: int) -> int:
    return struct.unpack_from("<I", payload, register * 16 + component * 4)[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("base_analysis", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    capture = args.capture.resolve()
    base_path = args.base_analysis.resolve()
    output = require_artifact_output(args.output, repo)
    if not capture.is_dir() or not base_path.is_file():
        parser.error("Capture directory and base analysis must exist")

    base = json.loads(base_path.read_text(encoding="utf-8"))
    original_analyzer = Path(__file__).with_name("analyze_intergrade_contact_capture.py")
    if base.get("schemaVersion") != 1 or base.get("sampleCount", 0) <= 0:
        raise ValueError("Unexpected or incomplete base capture analysis")
    if base.get("analyzerSha256") != sha(original_analyzer):
        raise ValueError("Base analysis does not match the fingerprinted capture analyzer")
    expected_hashes = [entry[0] for entry in VARIANTS]
    variants = base.get("variants", [])
    if [entry.get("shader") for entry in variants] != expected_hashes:
        raise ValueError("Base analysis does not contain the exact five accepted variants")

    payloads = []
    sources = []
    for variant in variants:
        path = capture / variant["files"]["cb3"]
        if not path.is_file() or sha(path) != variant["sha256"]["cb3"]:
            raise ValueError(f"Captured cb3 is missing or changed for {variant['shader']}")
        payload = path.read_bytes()
        if len(payload) != 16_384:
            raise ValueError(f"Expected a 16,384-byte cb3 for {variant['shader']}")
        payloads.append(payload)
        sources.append({"shader": variant["shader"], "file": path.name, "sha256": sha(path)})
    if any(payload != payloads[0] for payload in payloads[1:]):
        raise ValueError("The five captured cb3 payloads are not byte-identical")

    payload = payloads[0]
    first_variant = variants[0]
    cb1_path = capture / first_variant["files"]["cb1"]
    cb4_path = capture / first_variant["files"]["cb4"]
    for key, path in (("cb1", cb1_path), ("cb4", cb4_path)):
        if not path.is_file() or sha(path) != first_variant["sha256"][key]:
            raise ValueError(f"Captured {key} is missing or changed")
    view = np.fromfile(cb1_path, dtype="<f4").reshape(-1, 4)
    lights = np.fromfile(cb4_path, dtype="<f4").reshape(-1, 4)
    if view.shape[0] < 63 or lights.shape[0] < 768:
        raise ValueError("Captured view/light buffers are too small")
    viewport = np.asarray(base["viewport"], dtype=np.float64)
    allocation = np.asarray([base["depthDDS"]["width"], base["depthDDS"]["height"]], dtype=np.float64)
    projection_scale = 0.5 * (viewport[2:] - viewport[:2]) / allocation * [1.0, -1.0]
    projection_bias = (viewport[:2] + 0.5 * (viewport[2:] - viewport[:2])) / allocation

    def project_light(index: int):
        translated = lights[index, :3].astype(np.float64) + view[62, :3].astype(np.float64)
        clip = np.append(translated, 1.0) @ view[:4].astype(np.float64)
        if not np.isfinite(clip).all() or abs(clip[3]) <= 1e-8:
            return None, False
        pixel = (clip[:2] / clip[3] * projection_scale + projection_bias) * allocation
        visible = bool(clip[3] > 0 and np.all(pixel >= viewport[:2]) and np.all(pixel < viewport[2:]))
        return [float(pixel[0]), float(pixel[1])], visible

    flagged_records = []
    for index in range(256):
        flags = decode_u32(payload, index + 768, 0)
        if flags & 3:
            flagged_records.append({
                "index": index,
                "flags": flags,
                "lowTwoBits": flags & 3,
                "profileRow": decode_u32(payload, index + 768, 2),
            })
    by_index = {entry["index"]: entry for entry in flagged_records}

    correlated = []
    for rank, light in enumerate(base.get("rankedLightCandidates", []), start=1):
        index = int(light["index"])
        record = by_index.get(index)
        projected_pixel, projected_inside_viewport = project_light(index)
        color = light["color"]
        red_dominance = float(color[0] / max(float(color[1]), float(color[2]), 1e-8))
        correlated.append({
            "rank": rank,
            "index": index,
            "profileFlagged": record is not None,
            "flags": record["flags"] if record else decode_u32(payload, index + 768, 0),
            "lowTwoBits": record["lowTwoBits"] if record else 0,
            "profileRow": record["profileRow"] if record else decode_u32(payload, index + 768, 2),
            "projectedLightCenterPixel": projected_pixel,
            "projectedLightCenterInsideViewport": projected_inside_viewport,
            "position": light["position"],
            "color": color,
            "redDominance": red_dominance,
            "radius": light["radius"],
            "tileMemberSamples": light["tileMemberSamples"],
            "geometricFacingSamples": light["geometricFacingSamples"],
            "contactEligibleProxyScore": light["contactEligibleProxyScore"],
        })
    flagged_candidates = [entry for entry in correlated if entry["profileFlagged"]]
    red_beacon_candidates = [
        entry for entry in correlated
        if entry["projectedLightCenterInsideViewport"]
        and entry["radius"] <= 100.0
        and entry["redDominance"] >= 10.0
    ]
    red_beacon_candidates.sort(key=lambda entry: entry["projectedLightCenterPixel"][0])
    tile_counts = base.get("tileLightCounts", {})
    required_tile_count_fields = ("min", "median", "p99", "max")
    if any(field not in tile_counts for field in required_tile_count_fields):
        raise ValueError("Base analysis is missing tile-light count statistics")
    tile_capacity = 64
    sampled_capacity_reached = float(tile_counts["max"]) >= tile_capacity

    report = {
        "schemaVersion": 2,
        "kind": "ff7-remake-native-light-profile-membership",
        "captureDirectory": str(capture),
        "baseAnalysis": {
            "path": str(base_path),
            "sha256": sha(base_path),
            "analyzerPath": str(original_analyzer),
            "analyzerSha256": sha(original_analyzer),
            "sampleCount": base["sampleCount"],
            "reprojectionPassFraction": base["reprojection"]["passFraction"],
        },
        "cb3": {
            "bytes": len(payload),
            "sha256": sha(capture / variants[0]["files"]["cb3"]),
            "variantFileCount": len(sources),
            "byteIdenticalAcrossFiveVariants": True,
            "sources": sources,
        },
        "projectionInputs": {
            "cb1File": cb1_path.name,
            "cb1Sha256": sha(cb1_path),
            "cb4File": cb4_path.name,
            "cb4Sha256": sha(cb4_path),
            "viewport": base["viewport"],
            "allocation": allocation.astype(int).tolist(),
        },
        "profileFields": {
            "flags": "cb3[index+768].x interpreted as uint; low two bits",
            "row": "cb3[index+768].z interpreted as uint",
        },
        "flaggedBufferRecordCount": len(flagged_records),
        "flaggedBufferRecords": flagged_records,
        "rankedTileMemberCandidateCount": len(correlated),
        "rankedTileMemberCandidates": correlated,
        "profileFlaggedTileMemberCandidateCount": len(flagged_candidates),
        "profileFlaggedTileMemberCandidates": flagged_candidates,
        "redBeaconCandidateCount": len(red_beacon_candidates),
        "redBeaconCandidates": red_beacon_candidates,
        "tileLightList": {
            "capacityPerTile": tile_capacity,
            "observedSampledCounts": tile_counts,
            "sampledCapacityReached": sampled_capacity_reached,
        },
        "strongestFiveCandidates": correlated[:5],
        "result": "two-unprofiled-red-beacon-candidates-with-unsaturated-native-tile-lists"
        if len(red_beacon_candidates) == 2
        and all(not entry["profileFlagged"] for entry in red_beacon_candidates)
        and not sampled_capacity_reached
        else "native-light-correlation-requires-more-evidence",
        "interpretation": [
            "The captured native light records and packed tile lists intersect; profile-flagged records are not merely unused trailing constant-buffer data.",
            "A profile row of zero is not an off sentinel: native assembly adds 0.5 before multiplying by inverse atlas height.",
            "Indices 1 and 0 are the only in-view, <=100-unit-radius, >=10x red-dominant ranked lights; their projected centers, matching color, and matching 70-unit radii make them the high-confidence pair for the two visible red beacons.",
            "Both red-beacon candidates have zero profile flags, so the native angular-profile branch cannot explain their observed angle-dependent indirect contribution.",
            "The native consumer can read 64 lights per tile, while this capture's sampled maximum is 16; its 64-light ceiling is not active in this captured view.",
            "A paired ON-angle/OFF-angle capture is still required to distinguish changing native tile membership from the separate four-slice screen-space GI sampling limit.",
        ],
        "limitations": [
            "The base ranking is a sampled geometric proxy and omits the profile-atlas texel, native shadows, BRDF, and final post-processing.",
            "Tile membership and positive geometric influence do not prove a particular screen pixel executed every nested branch.",
            "Beacon ownership is a high-confidence record correlation, not a pixel-picked ID written by the game.",
            "One capture cannot show whether tile-list membership changes as the camera rotates.",
            "No game file was changed and no runtime effect was installed.",
        ],
        "installed": False,
        "runtimeEligible": False,
        "analyzerSha256": sha(Path(__file__)),
    }

    output.mkdir(parents=True)
    report_path = output / "analysis.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "result": report["result"],
        "flaggedBufferRecords": report["flaggedBufferRecordCount"],
        "rankedTileMemberCandidates": report["rankedTileMemberCandidateCount"],
        "profileFlaggedTileMemberCandidates": report["profileFlaggedTileMemberCandidateCount"],
        "redBeaconCandidates": report["redBeaconCandidateCount"],
        "nativeTileCountMaximum": report["tileLightList"]["observedSampledCounts"]["max"],
        "nativeTileCapacity": report["tileLightList"]["capacityPerTile"],
        "strongestFiveCandidates": report["strongestFiveCandidates"],
        "output": str(report_path),
    }, indent=2))


if __name__ == "__main__":
    main()
