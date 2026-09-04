"""Decode captured GPU buffers/DDS and validate the production adapter's math.

Local binary research only. Does not modify the game, render images, or make a
runtime preset. Light ranking is a geometric proxy, not full native shading.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

import numpy as np


VARIANTS = [
    ("c30cdc8365df9840", "ContactC30", 5, 11, 12),
    ("62b33a2d1e505241", "Contact62B", 4, 10, 11),
    ("5a9fbefe0ab6f815", "Contact5A9", 4, 10, 11),
    ("0e97888f9a8767da", "Contact0E9", 5, 11, 12),
    ("08bb8764f1840179", "Contact08B", 5, 11, 12),
]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest().upper()


def unique(paths, label):
    paths = list(paths)
    if len(paths) != 1:
        raise ValueError(f"Expected one {label}, found {len(paths)}")
    return paths[0]


def dds(path, kind):
    with path.open("rb") as stream:
        head = stream.read(148)
    if head[:4] != b"DDS " or struct.unpack_from("<I", head, 4)[0] != 124:
        raise ValueError(f"Invalid DDS header: {path}")
    height, width, pitch = struct.unpack_from("<III", head, 12)
    mip_count = struct.unpack_from("<I", head, 28)[0]
    dx10 = head[84:88] == b"DX10"
    offset = 148 if dx10 else 128
    dxgi = struct.unpack_from("<I", head, 128)[0] if dx10 else None
    if mip_count not in (0, 1):
        raise ValueError("Unexpected mip chain")
    if dx10 and struct.unpack_from("<III", head, 132) != (3, 0, 1):
        raise ValueError("Expected a single non-cube Texture2D")
    if kind == "depth":
        if dxgi != 21 or pitch != width * 8:
            raise ValueError("Expected R32_FLOAT_X8X24_TYPELESS depth")
        data = np.memmap(path, dtype="<f4", mode="r", offset=offset,
                         shape=(height, width, 2))[:, :, 0]
    elif kind == "normal":
        if dxgi != 24 or pitch != width * 4:
            raise ValueError("Expected R10G10B10A2_UNORM normals")
        data = np.memmap(path, dtype="<u4", mode="r", offset=offset, shape=(height, width))
    else:
        masks = struct.unpack_from("<IIII", head, 92)
        if dx10 or pitch != width * 4 or masks != (0xFF0000, 0xFF00, 0xFF, 0xFF000000):
            raise ValueError("Expected legacy BGRA8 material DDS")
        data = np.memmap(path, dtype="<u4", mode="r", offset=offset, shape=(height, width))
    if path.stat().st_size != offset + pitch * height:
        raise ValueError("Unexpected DDS payload size")
    return data, {"width": width, "height": height, "pitch": pitch, "dxgi": dxgi, "offset": offset}


def linear_depth(device_z, view):
    c = view[57]
    with np.errstate(divide="ignore", invalid="ignore"):
        return device_z * c[0] + c[1] + np.float32(1) / (device_z * c[2] - c[3])


def distribution(values):
    values = np.asarray(values)
    return {"min": float(np.min(values)), "median": float(np.median(values)),
            "p99": float(np.quantile(values, .99)), "max": float(np.max(values))}


def analyze(capture, stride, replay=None):
    log = (capture / "log.txt").read_text(errors="replace")
    files = list(capture.iterdir())
    records = []
    resources = []
    for shader, section, depth_slot, list_slot, record_slot in VARIANTS:
        matches = re.findall(rf"(?m)^(\d+) CSSetShader\([^\r\n]+hash={shader}\s*$", log)
        event = unique(matches, f"dispatch event for {shader}")
        def resource(slot, extension):
            return unique((p for p in files if p.name.startswith(event + ".")
                           and f"-cs-{slot}=" in p.name and p.suffix == extension), slot)
        r = {"cb0": resource("cb0", ".buf"), "cb1": resource("cb1", ".buf"),
             "cb3": resource("cb3", ".buf"), "cb4": resource("cb4", ".buf"),
             "normal": resource("t1", ".dds"), "material": resource("t2", ".dds"),
             "depth": resource(f"t{depth_slot}", ".dds"),
             "tile_list": resource(f"t{list_slot}", ".buf"),
             "tile_records": resource(f"t{record_slot}", ".buf")}
        hashes = {key: sha(path) for key, path in r.items()}
        record = {"shader": shader, "event": int(event), "files": {k: p.name for k, p in r.items()},
                  "sha256": hashes, "bytes": {k: p.stat().st_size for k, p in r.items()}}
        resources.append(r)
        records.append(record)
    # These bindings should be common, but prove equality rather than trusting
    # resource hashes (3Dmigoto hashes can describe layouts, not buffer data).
    common = {key: len({r["sha256"][key] for r in records}) == 1 for key in resources[0]}
    if not all(common[key] for key in ("cb1", "normal", "material", "depth", "tile_records")):
        raise ValueError("View/GBuffer/tile records differ between variants; analyze separately")
    r = resources[0]
    view = np.fromfile(r["cb1"], dtype="<f4").reshape(-1, 4)
    dispatch = np.fromfile(r["cb0"], dtype="<u4").reshape(-1, 4)
    lights = np.fromfile(r["cb4"], dtype="<f4").reshape(-1, 4)
    # Compare the full native light layout, excluding unused trailing rows.
    active_lights_common = all(np.array_equal(
        np.fromfile(other["cb4"], dtype="<u4").reshape(-1, 4)[:768],
        lights.view("<u4")[:768]) for other in resources)
    if not active_lights_common:
        raise ValueError("Active light rows differ between variants; analyze separately")
    directions = np.fromfile(r["cb3"], dtype="<f4").reshape(-1, 4)
    tiles = np.fromfile(r["tile_records"], dtype="<u4").reshape(-1, 20)
    depth, depth_info = dds(r["depth"], "depth")
    normal_data, normal_info = dds(r["normal"], "normal")
    material_data, material_info = dds(r["material"], "material")
    height, width = depth.shape
    if normal_data.shape != depth.shape or material_data.shape != depth.shape:
        raise ValueError("GBuffer dimensions disagree")
    rect = dispatch[1].astype(np.int64)
    if not (0 <= rect[0] < rect[2] <= width and 0 <= rect[1] < rect[3] <= height):
        raise ValueError("Invalid captured viewport")
    if not np.array_equal(view[126, :2], [width, height]):
        raise ValueError("View allocation size differs from depth DDS")
    yy, xx = np.mgrid[rect[1]:rect[3]:stride, rect[0]:rect[2]:stride]
    pixels = np.column_stack((xx.ravel(), yy.ravel()))
    z = np.asarray(depth[yy, xx]).ravel()
    valid = np.isfinite(z) & (z > 0) & (z <= 1)
    pixels, z = pixels[valid], z[valid]
    linear = linear_depth(z, view)
    ndc = ((pixels.astype(np.float32) - rect[:2].astype(np.float32) + .5)
           / (rect[2:] - rect[:2]).astype(np.float32)) * [2., -2.] + [-1., 1.]
    ndc = ndc.astype(np.float32)
    # Mirror the native/adapter row-combination order in FP32.
    h = (ndc[:, 1] * linear)[:, None] * view[41]
    h += (ndc[:, 0] * linear)[:, None] * view[40]
    h += linear[:, None] * view[42]
    h += view[43]
    world = h[:, :3] / h[:, 3:4]
    translated = world + view[62, :3]
    clip = np.column_stack((translated, np.ones(len(world), dtype=np.float32))) @ view[:4]
    scale = .5 * (rect[2:] - rect[:2]) / [width, height] * [1, -1]
    bias = (rect[:2] + .5 * (rect[2:] - rect[:2])) / [width, height]
    uv = clip[:, :2] / clip[:, 3:4] * scale + bias
    pixel_error = np.max(np.abs(uv * [width, height] - (pixels + .5)), axis=1)
    projected = linear_depth(clip[:, 2] / clip[:, 3], view)
    depth_error = np.abs(projected - linear)
    allowed = np.maximum(.01, linear * .002)
    guard_pass = np.isfinite(clip).all(axis=1) & (clip[:, 3] > 1e-5)
    guard_pass &= (pixel_error <= .75) & np.isfinite(projected) & (depth_error <= allowed)
    packed_normal = normal_data[pixels[:, 1], pixels[:, 0]]
    normals = np.column_stack([(packed_normal >> shift) & 1023 for shift in (0, 10, 20)]).astype(np.float32)
    normals = normals / 1023 * 2 - 1
    normal_lengths = np.linalg.norm(normals, axis=1)
    normals /= np.maximum(normal_lengths[:, None], 1e-8)
    material_ids = ((material_data[pixels[:, 1], pixels[:, 0]] >> 24) & 15).astype(np.uint32)
    tile_xy = (pixels - rect[:2]) // 16
    tile_indices = tile_xy[:, 0] + (tile_xy[:, 1] << 8)
    if tile_indices.max() >= len(tiles):
        raise ValueError("Packed tile addressing exceeds the captured buffer")
    counts = np.minimum(tiles[tile_indices, 0], 64)
    packed_indices = tiles[tile_indices, 4:20]
    indices = np.stack([(packed_indices >> shift) & 255 for shift in (0, 8, 16, 24)], axis=2).reshape(-1, 64)
    present = np.arange(64)[None, :] < counts[:, None]
    light_ranking = []
    for light in np.unique(indices[present]):
        light = int(light)
        membership = ((indices == light) & present).any(axis=1)
        delta = lights[light, :3] - world
        distance2 = np.sum(delta * delta, axis=1)
        inv_radius = float(lights[light, 3])
        distance = np.sqrt(distance2)
        no_l = np.sum(normals * delta, axis=1) / np.maximum(distance, 1e-8)
        influence = membership & guard_pass & (inv_radius > 0) & (distance * inv_radius < 1) & (no_l > .05)
        color = lights[light + 512, :3]
        # Mirror native radial/spot attenuation. Still omits shadow maps, IES,
        # BRDF and native occlusion; this is not proof of visible contribution.
        radial = np.maximum(0, 1 - (distance2 * inv_radius**2)**2)**2
        attenuation = radial / (distance2 + 1 + directions[light + 512, 2]**2)
        if lights[light + 512, 3] != 0:
            attenuation = np.ones_like(distance)
        if directions[light + 256, 3] != 0:
            cosine = np.sum(delta * directions[light, :3], axis=1) / np.maximum(distance, 1e-8)
            spot = np.clip((cosine - directions[light + 512, 0]) * directions[light + 512, 1], 0, 1)**2
            attenuation *= spot
        influence &= attenuation > 0
        proxy = attenuation * np.maximum(no_l, 0) * max(0, float(np.max(color)))
        proxy[~influence] = 0
        if not influence.any():
            continue
        strongest = int(np.argmax(proxy))
        depth_bias = max(1 / width, 1 / height) * 100
        trace_eligible = influence & (distance > depth_bias + .175 / inv_radius + .0001)
        contact_proxy = np.where(trace_eligible, proxy, 0)
        strongest_contact = int(np.argmax(contact_proxy))
        replay_stats = None
        replay_path = replay / f"light-{light}-1.f32" if replay else None
        if replay_path and replay_path.exists():
            visibility = np.fromfile(replay_path, dtype="<f4")
            if visibility.size != valid.size or not np.all(np.isfinite(visibility)) or np.any((visibility < 0) | (visibility > 1)):
                raise ValueError("Replay output does not match this sample grid")
            visibility = visibility[valid]
            changed = trace_eligible & (visibility < .999)
            suppressed_proxy = contact_proxy * (1 - visibility)
            strongest_shadow = int(np.argmax(suppressed_proxy))
            replay_stats = {"sha256": sha(replay_path), "eligibleShadowedSamples": int(changed.sum()),
                "suppressedProxy": float(suppressed_proxy.sum()),
                "fractionOfEligibleProxy": float(suppressed_proxy.sum() / max(contact_proxy.sum(), 1e-8)),
                "strongestSuppressedPixel": pixels[strongest_shadow].tolist(),
                "materialShadowedCounts": {str(int(m)): int((changed & (material_ids == m)).sum()) for m in np.unique(material_ids[changed])}}
        light_ranking.append({"index": light, "position": lights[light, :3].tolist(),
            "inverseRadius": inv_radius, "radius": 1 / inv_radius, "color": color.tolist(),
            "directionParameters": directions[light].tolist(),
            "tileMemberSamples": int(membership.sum()), "geometricFacingSamples": int(influence.sum()),
            "proxyScore": float(proxy.sum()), "strongestSamplePixel": pixels[strongest].tolist(),
            "strongestSampleDistance": float(distance[strongest]),
            "contactEligibleSamples": int(trace_eligible.sum()),
            "contactEligibleProxyScore": float(contact_proxy.sum()),
            "strongestContactPixel": pixels[strongest_contact].tolist() if trace_eligible.any() else None,
            "strongestContactDistance": float(distance[strongest_contact]) if trace_eligible.any() else None,
            "capturedKernelReplay": replay_stats,
            "materialSampleCounts": {str(int(m)): int((influence & (material_ids == m)).sum())
                                     for m in np.unique(material_ids[influence])}})
    light_ranking.sort(key=lambda light: light["contactEligibleProxyScore"], reverse=True)
    return {"schemaVersion": 1, "captureDirectory": str(capture), "sampleStride": stride,
        "sampleCount": len(pixels), "filesUnchangedAcrossVariants": common,
        "activeLightRowsUnchangedAcrossVariants": active_lights_common, "variants": records,
        "depthDDS": depth_info, "normalDDS": normal_info, "materialDDS": material_info,
        "viewport": rect.tolist(), "projectionScale": [float(view[24, 0]), float(view[25, 1])],
        "perspective": bool(view[27, 3] < 1), "pretranslation": view[62, :3].tolist(),
        "inverseAllocationConsistent": bool(np.allclose(view[126, 2:], [1/width, 1/height], rtol=1e-6)),
        "reprojection": {"passCount": int(guard_pass.sum()), "passFraction": float(guard_pass.mean()),
                         "pixelError": distribution(pixel_error), "linearDepthError": distribution(depth_error),
                         "relativeDepthError": distribution(depth_error / linear)},
        "linearDepth": distribution(linear), "normalLength": distribution(normal_lengths),
        "tileLightCounts": distribution(counts), "rankedLightCandidates": light_ranking,
        "installedEffect": False, "runtimeEligible": False,
        "limitations": ["Sampled numeric analysis, not full-frame equivalence",
                        "FP32 NumPy math does not duplicate every GPU fused operation",
                        "Light ranking includes native radial/spot attenuation and donor exclusion; omits IES, native shadows and BRDF",
                        "No indirect argument counts captured; populated tile records alone do not prove dispatched coverage",
                        "No claim of visual improvement or GPU performance"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--stride", type=int, default=8)
    parser.add_argument("--replay", type=Path)
    args = parser.parse_args()
    if not 1 <= args.stride <= 64:
        parser.error("Stride must be between 1 and 64")
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if not output.is_relative_to(repo / "artifacts") or output == repo / "artifacts":
        parser.error("Output must be below workspace artifacts")
    if output.exists():
        parser.error("Output exists; preserve previous analysis")
    if args.replay:
        replay_manifest = json.loads((args.replay / "manifest.json").read_text())
        if replay_manifest["sampleStride"] != args.stride:
            parser.error("Replay stride differs")
        # The wrapper intentionally uses the first variant's shared active light data.
        for key in ("cb0", "cb1", "cb4", "normal", "depth"):
            path = args.capture / replay_manifest["inputFiles"][key]
            if sha(path) != replay_manifest["inputHashes"][key]:
                parser.error("Replay inputs differ from this capture")
    report = analyze(args.capture.resolve(), args.stride, args.replay)
    report["analyzerSha256"] = sha(Path(__file__))
    output.mkdir(parents=True)
    (output / "analysis.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(json.dumps({"samples": report["sampleCount"], "reprojection": report["reprojection"],
                      "lightCandidates": report["rankedLightCandidates"][:5], "output": str(output)}, indent=2))


if __name__ == "__main__":
    main()
