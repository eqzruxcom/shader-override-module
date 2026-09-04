"""Compare source-preserving donor replay outputs; not a quality/deployment gate.

Uses the existing capture decoder. Sampling is sparse complete 2x2 quads, so
checkerboard reconstruction can be checked against independently read raw rays.
Native light membership/facing is a proxy, not full native dispatch or shading.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from analyze_intergrade_contact_capture import dds, linear_depth, sha

LIGHTS = (50, 38, 54, 20, 52)
TOL = 2e-6


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_manifest(directory, mode, repo):
    report = json.loads((directory / "manifest.json").read_text())
    require(report["implementation"] == "Rebirth" and report["reconstruction"] == mode,
            "Unexpected implementation or reconstruction mode")
    require(report["sampleLayout"] == "SparseCompleteQuads" and report["sampleStride"] == 8
            and report["grid"] == [960, 540], "Wrong sample layout")
    require(not report["runtimeEligible"] and not report["gameFilesModified"], "Not an offline receipt")
    require(len(report["results"]) == 10, "Incomplete replay")
    for source in report["sources"]:
        require(sha(repo / source["path"]) == source["sha256"], "Replay source is no longer current")
    outputs = {item["path"]: item["sha256"] for item in report["outputs"]}
    for light in LIGHTS:
        for mode_value in (0, 1):
            for extension in ("f32", "valid.u8"):
                name = f"light-{light}-{mode_value}.{extension}"
                require(name in outputs and sha(directory / name) == outputs[name], "Readback hash mismatch")
    require(sha(directory / "capture-kernel.cso") == outputs["capture-kernel.cso"], "Kernel hash mismatch")
    require(sha(directory / "results.csv") == outputs["results.csv"], "CSV hash mismatch")
    return report


def read_output(directory, light, enabled):
    values = np.fromfile(directory / f"light-{light}-{enabled}.f32", dtype="<f4")
    valid = np.fromfile(directory / f"light-{light}-{enabled}.valid.u8", dtype=np.uint8)
    require(values.size == 518400 and valid.size == values.size, "Wrong readback length")
    require(np.isfinite(values).all() and ((values >= 0) & (values <= 1)).all(), "Invalid visibility")
    require((valid <= 1).all(), "Invalid receiver flags")
    if not enabled:
        require((values == 1).all() and (valid == 0).all(), "Disabled output not exactly neutral")
    return values.reshape(540, 960), valid.reshape(540, 960).astype(bool)


def stats(raw, quad, mask):
    count = int(mask.sum())
    a, b = raw[mask], quad[mask]
    return {
        "samples": count,
        "rawShadowed": int((a < .999).sum()), "quadShadowed": int((b < .999).sum()),
        "changedAboveTolerance": int((np.abs(a - b) > TOL).sum()),
        "darkenedAtLeastOnePercent": int((a - b > .01).sum()),
        "lightenedAtLeastOnePercent": int((b - a > .01).sum()),
        "acquiredShadowFromNeutral": int(((a >= .999) & (b < .99)).sum()),
        "returnedToNeutral": int(((a < .99) & (b >= .999)).sum()),
        "meanRawVisibility": float(a.mean()) if count else None,
        "meanQuadVisibility": float(b.mean()) if count else None,
        "maxAbsoluteChange": float(np.max(np.abs(a-b))) if count else None,
    }


def compare(raw_directory, quad_directory, repo, shared_directory=None):
    raw_receipt = load_manifest(raw_directory, "Raw", repo)
    quad_receipt = load_manifest(quad_directory, "RecomputeQuad", repo)
    require(raw_receipt["inputHashes"] == quad_receipt["inputHashes"], "Replay captures differ")
    require(raw_receipt["sources"] == quad_receipt["sources"], "Replay sources differ")
    shared_receipt = None
    if shared_directory is not None:
        shared_receipt = load_manifest(shared_directory, "SharedQuad", repo)
        require(shared_receipt["dispatchGroupWidth"] == 16, "Shared replay must dispatch full 16x16 groups")
        require(shared_receipt["inputHashes"] == raw_receipt["inputHashes"] and
                shared_receipt["sources"] == raw_receipt["sources"], "Shared replay inputs/sources differ")
    capture = Path(raw_receipt["captureDirectory"])
    resources = {key: capture / name for key, name in raw_receipt["inputFiles"].items()}
    # cb3/tile records are analysis inputs only; they are not bound by replay.
    keys = ("cb0", "cb1", "cb3", "cb4", "normal", "material", "depth", "tile_records")
    for key in keys:
        require(sha(resources[key]) == raw_receipt["inputHashes"][key], "Capture input hash mismatch")
    view = np.fromfile(resources["cb1"], dtype="<f4").reshape(-1, 4)
    dispatch = np.fromfile(resources["cb0"], dtype="<u4").reshape(-1, 4)
    lights = np.fromfile(resources["cb4"], dtype="<f4").reshape(-1, 4)
    directions = np.fromfile(resources["cb3"], dtype="<f4").reshape(-1, 4)
    tiles = np.fromfile(resources["tile_records"], dtype="<u4").reshape(-1, 20)
    depth, _ = dds(resources["depth"], "depth")
    normals, _ = dds(resources["normal"], "normal")
    material, _ = dds(resources["material"], "material")
    require(depth.shape == normals.shape == material.shape == (2160, 3840), "Capture dimensions differ")
    yy, xx = np.mgrid[:540, :960]
    px, py = (xx >> 1)*8 + (xx & 1), (yy >> 1)*8 + (yy & 1)
    phase, noise = (int(n) for n in view.view("<u4")[139, 2:4])
    selected = ((px + py + phase) & 1) != 0
    require(selected.sum() == 259200, "Both checkerboard parities must be sampled")
    material_ids = (np.asarray(material[py, px]) >> 24) & 15
    z = linear_depth(np.asarray(depth[py, px]), view)
    rect = dispatch[1].astype(np.int64)
    require(np.array_equal(rect, [0, 0, 3840, 2160]), "This proxy expects the captured full viewport")
    ndcx = (px.astype(np.float32)+.5)/np.float32(3840)*2-1
    ndcy = (py.astype(np.float32)+.5)/np.float32(2160)*-2+1
    h = (ndcy*z)[..., None]*view[41]
    h += (ndcx*z)[..., None]*view[40]
    h += z[..., None]*view[42]
    h += view[43]
    with np.errstate(divide="ignore", invalid="ignore"):
        world = h[..., :3]/h[..., 3:4]
    packed_normal = np.asarray(normals[py, px])
    normal = np.stack([(packed_normal >> shift) & 1023 for shift in (0, 10, 20)], axis=-1).astype(np.float32)
    normal = normal / 1023*2-1
    normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-8)
    tile_index = (px // 16) + ((py // 16) << 8)
    require(tile_index.max() < len(tiles), "Tile index outside capture")
    counts = np.minimum(tiles[tile_index, 0], 64)
    packed_indices = tiles[tile_index, 4:20]
    indices = np.stack([(packed_indices >> shift) & 255 for shift in (0, 8, 16, 24)], axis=-1).reshape(540, 960, 64)
    present = np.arange(64)[None, None, :] < counts[..., None]
    material_quad = material_ids.reshape(270, 2, 480, 2).transpose(0, 2, 1, 3).reshape(270, 480, 4)
    material_edge = (material_quad.min(-1) != material_quad.max(-1)).repeat(2, 0).repeat(2, 1)
    results = []
    for light in LIGHTS:
        for folder in (raw_directory, quad_directory):
            read_output(folder, light, 0)
        a, valid = read_output(raw_directory, light, 1)
        b, quad_valid = read_output(quad_directory, light, 1)
        require(np.array_equal(valid, quad_valid), "Receiver preflight changed between modes")
        lane = np.where(selected, a, np.float32(1))
        expected_quad = np.clip((lane[::2, ::2] + lane[::2, 1::2] + lane[1::2, ::2] + lane[1::2, 1::2])*.5-1, 0, 1)
        expected = np.where(selected, a, expected_quad.repeat(2, 0).repeat(2, 1))
        expected = np.where(valid, expected, np.float32(1))
        error = np.abs(b-expected)
        require((error <= TOL).all(), f"Raw-ray reconstruction mismatch for light {light}: {error.max()}")
        require((a[~valid] == 1).all() and (b[~valid] == 1).all(), "Invalid receiver not neutral")
        shared_result = None
        if shared_directory is not None:
            read_output(shared_directory, light, 0)
            shared, shared_valid = read_output(shared_directory, light, 1)
            require(np.array_equal(valid, shared_valid), "Shared receiver preflight differs")
            shared_error = np.abs(shared-expected)
            require((shared_error <= TOL).all() and (np.abs(shared-b) <= TOL).all(),
                    f"Shared reconstruction mismatch for light {light}: {shared_error.max()}")
            require((shared[~valid] == 1).all(), "Shared invalid receiver not neutral")
            shared_result = {"maxRawReferenceError": float(shared_error.max()),
                             "maxRecomputeDifference": float(np.abs(shared-b).max()),
                             "bitIdenticalToRecompute": bool(np.array_equal(shared.view('<u4'), b.view('<u4'))),
                             "samplesVerified": int(shared.size),
                             "partialFinalGroupSamples": int(shared[-12:].size)}
        membership = ((indices == light) & present).any(-1)
        delta = lights[light, :3] - world
        distance2 = np.sum(delta*delta, axis=-1)
        distance = np.sqrt(distance2)
        no_l = np.sum(normal*delta, axis=-1)/np.maximum(distance, 1e-8)
        inv_radius = float(lights[light, 3])
        influence = membership & valid & (inv_radius > 0) & (distance*inv_radius < 1) & (no_l > .05)
        radial = np.maximum(0, 1-(distance2*inv_radius**2)**2)**2
        attenuation = radial/(distance2+1+directions[light+512, 2]**2)
        if lights[light+512, 3] != 0:
            attenuation = np.ones_like(distance)
        if directions[light+256, 3] != 0:
            cosine = np.sum(delta*directions[light, :3], axis=-1)/np.maximum(distance, 1e-8)
            attenuation *= np.clip((cosine-directions[light+512, 0])*directions[light+512, 1], 0, 1)**2
        influence &= attenuation > 0
        difference = np.where(influence, np.abs(a-b), 0)
        strongest = np.argsort(difference.ravel())[-8:][::-1]
        examples = []
        for flat in strongest:
            y, x = np.unravel_index(flat, a.shape)
            if difference[y, x] <= TOL:
                continue
            examples.append({"pixel": [int(px[y, x]), int(py[y, x])], "materialId": int(material_ids[y, x]),
                             "linearDepth": float(z[y, x]), "raw": float(a[y, x]), "quad": float(b[y, x])})
        results.append({"light": light, "maxReconstructionError": float(error.max()), "shared": shared_result,
                        "selectedPixelsBitIdentical": bool(np.array_equal(a[selected], b[selected])),
                        "allValidReceivers": stats(a, b, valid),
                        "nativeLightFacingProxy": stats(a, b, influence),
                        "proxyMaterialBoundaries": stats(a, b, influence & material_edge),
                        "proxyByMaterial": {str(int(m)): stats(a, b, influence & (material_ids == m)) for m in np.unique(material_ids[influence])},
                        "largestProxyChanges": examples})
    return {"schemaVersion": 1, "result": "passed-reconstruction-identity-only", "runtimeEligible": False,
            "gameFilesModified": False, "sampleCountPerLight": 518400, "selectedPerLight": 259200,
            "capturedPhase": phase, "capturedNoiseIndex": noise,
            "sampledMaterialCounts": {str(int(m)): int((material_ids == m).sum()) for m in np.unique(material_ids)},
            "rawManifest": {"path": str(raw_directory / "manifest.json"), "sha256": sha(raw_directory / "manifest.json")},
            "quadManifest": {"path": str(quad_directory / "manifest.json"), "sha256": sha(quad_directory / "manifest.json")},
            "sharedManifest": ({"path": str(shared_directory / "manifest.json"), "sha256": sha(shared_directory / "manifest.json")}
                               if shared_receipt is not None else None),
            "analysisInputs": {key: {"path": str(resources[key]), "sha256": sha(resources[key])} for key in keys},
            "sources": {p.name: sha(p) for p in (Path(__file__), Path(__file__).with_name("analyze_intergrade_contact_capture.py"))},
            "lights": results,
            "limitations": ["Acquired/lost coverage is descriptive, not false-shadow ground truth",
                            "One saved frame; no camera motion, phase progression, animation or engine TAA",
                            "Sparse complete quads, not a full-frame render",
                            "Light proxy omits native shadows, BRDF, IES and actual dispatch coverage",
                            "Material ID 7/hair mapping is structural, not a visually verified material mask",
                            "No quality or performance approval; earlier motion regressions remain"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("quad", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--shared", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    require(output.is_relative_to(repo / "artifacts") and output != repo / "artifacts" and not output.exists(),
            "Use a new output directory below workspace artifacts")
    report = compare(args.raw.resolve(), args.quad.resolve(), repo, args.shared.resolve() if args.shared else None)
    output.mkdir(parents=True)
    (output / "comparison.json").write_text(json.dumps(report, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    print(json.dumps({"result": report["result"], "phase": report["capturedPhase"],
                      "noise": report["capturedNoiseIndex"], "materials": report["sampledMaterialCounts"],
                      "lights": [{"light": r["light"], "identityError": r["maxReconstructionError"],
                                  "proxy": r["nativeLightFacingProxy"]} for r in report["lights"]]}, indent=2))


if __name__ == "__main__":
    main()
