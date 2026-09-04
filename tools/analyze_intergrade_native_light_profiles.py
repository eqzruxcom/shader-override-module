"""Correlate FF7 Remake native light-profile records with captured tile lists.

This augments a preserved contact-capture analysis without changing the
fingerprinted analyzer used by the guarded contact-shadow staging chain.
It is read-only with respect to the game and capture directory.
"""

import argparse
import json
import struct
from pathlib import Path

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
        correlated.append({
            "rank": rank,
            "index": index,
            "profileFlagged": record is not None,
            "flags": record["flags"] if record else decode_u32(payload, index + 768, 0),
            "lowTwoBits": record["lowTwoBits"] if record else 0,
            "profileRow": record["profileRow"] if record else decode_u32(payload, index + 768, 2),
            "radius": light["radius"],
            "tileMemberSamples": light["tileMemberSamples"],
            "geometricFacingSamples": light["geometricFacingSamples"],
            "contactEligibleProxyScore": light["contactEligibleProxyScore"],
        })
    flagged_candidates = [entry for entry in correlated if entry["profileFlagged"]]

    report = {
        "schemaVersion": 1,
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
        "profileFields": {
            "flags": "cb3[index+768].x interpreted as uint; low two bits",
            "row": "cb3[index+768].z interpreted as uint",
        },
        "flaggedBufferRecordCount": len(flagged_records),
        "flaggedBufferRecords": flagged_records,
        "rankedTileMemberCandidateCount": len(correlated),
        "profileFlaggedTileMemberCandidateCount": len(flagged_candidates),
        "profileFlaggedTileMemberCandidates": flagged_candidates,
        "strongestFiveCandidates": correlated[:5],
        "result": "native-profile-flags-present-in-ranked-tile-member-lights" if flagged_candidates else "no-profile-flags-in-ranked-tile-member-lights",
        "interpretation": [
            "The captured native light records and packed tile lists intersect; profile-flagged records are not merely unused trailing constant-buffer data.",
            "A profile row of zero is not an off sentinel: native assembly adds 0.5 before multiplying by inverse atlas height.",
            "This supports native per-light angular shaping as a cause of angle-dependent illumination, but does not identify the red beacon's exact record.",
        ],
        "limitations": [
            "The base ranking is a sampled geometric proxy and omits the profile-atlas texel, native shadows, BRDF, and final post-processing.",
            "Tile membership and positive geometric influence do not prove a particular screen pixel executed every nested branch.",
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
        "strongestFiveCandidates": report["strongestFiveCandidates"],
        "output": str(report_path),
    }, indent=2))


if __name__ == "__main__":
    main()
