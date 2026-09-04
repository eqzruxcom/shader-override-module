#!/usr/bin/env python3
"""Measure native-resolution A/B screenshot differences without resampling.

The tool reports whole-frame, named-region, and exclusion-masked metrics. It
does not guess whether a difference is acceptable: each adapter supplies the
static regions and dynamic exclusions appropriate to its validation scene.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import NamedTuple

import numpy as np
from PIL import Image


class Rect(NamedTuple):
    name: str
    x0: int
    y0: int
    x1: int
    y1: int


def parse_rect(value: str) -> Rect:
    try:
        name, coordinates = value.split(":", 1)
        x0, y0, x1, y1 = (int(part) for part in coordinates.split(","))
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "rectangle must be NAME:X0,Y0,X1,Y1"
        ) from exc
    if not name or x0 < 0 or y0 < 0 or x1 <= x0 or y1 <= y0:
        raise argparse.ArgumentTypeError(
            "rectangle needs a name and positive X0,Y0,X1,Y1 bounds"
        )
    return Rect(name, x0, y0, x1, y1)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def load_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.int16)


def metrics(signed: np.ndarray) -> dict[str, object]:
    if signed.size == 0:
        raise ValueError("metric region contains no pixels")
    pixels = signed.reshape(-1, 3)
    absolute = np.abs(pixels)
    pixel_mean = absolute.mean(axis=1)
    signed_rgb = pixels.mean(axis=0)
    signed_luma = pixels @ np.asarray([0.2126, 0.7152, 0.0722])
    return {
        "pixelCount": int(pixels.shape[0]),
        "meanAbsRgb": round(float(absolute.mean()), 6),
        "medianAbsRgb": round(float(np.median(absolute)), 6),
        "p95AbsRgb": round(float(np.percentile(absolute, 95)), 6),
        "p99AbsRgb": round(float(np.percentile(absolute, 99)), 6),
        "maxAbsChannel": int(absolute.max()),
        "pixelsMeanOver1Percent": round(float((pixel_mean > 1).mean() * 100), 6),
        "pixelsMeanOver3Percent": round(float((pixel_mean > 3).mean() * 100), 6),
        "pixelsMeanOver10Percent": round(float((pixel_mean > 10).mean() * 100), 6),
        "signedMeanRgb": [round(float(value), 6) for value in signed_rgb],
        "signedMeanLuma": round(float(signed_luma.mean()), 6),
    }


def validate_rect(rect: Rect, width: int, height: int) -> None:
    if rect.x1 > width or rect.y1 > height:
        raise ValueError(
            f"rectangle {rect.name!r} exceeds {width}x{height}: "
            f"{rect.x0},{rect.y0},{rect.x1},{rect.y1}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--region",
        action="append",
        type=parse_rect,
        default=[],
        metavar="NAME:X0,Y0,X1,Y1",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        type=parse_rect,
        default=[],
        metavar="NAME:X0,Y0,X1,Y1",
    )
    parser.add_argument("--tile-size", type=int, default=128)
    parser.add_argument("--top-tiles", type=int, default=12)
    args = parser.parse_args()

    if args.tile_size <= 0 or args.top_tiles < 0:
        parser.error("--tile-size must be positive and --top-tiles non-negative")

    original = load_rgb(args.original)
    current = load_rgb(args.current)
    if original.shape != current.shape:
        raise ValueError(
            f"image dimensions differ: {original.shape} versus {current.shape}"
        )
    height, width, channels = original.shape
    if channels != 3:
        raise ValueError(f"expected RGB input, found {channels} channels")

    for rect in [*args.region, *args.exclude]:
        validate_rect(rect, width, height)

    signed = current - original
    static_mask = np.ones((height, width), dtype=bool)
    for rect in args.exclude:
        static_mask[rect.y0 : rect.y1, rect.x0 : rect.x1] = False

    region_metrics = {
        rect.name: {
            "bounds": [rect.x0, rect.y0, rect.x1, rect.y1],
            "metrics": metrics(signed[rect.y0 : rect.y1, rect.x0 : rect.x1]),
        }
        for rect in args.region
    }

    tiles: list[dict[str, object]] = []
    for y0 in range(0, height, args.tile_size):
        for x0 in range(0, width, args.tile_size):
            x1 = min(x0 + args.tile_size, width)
            y1 = min(y0 + args.tile_size, height)
            mean_absolute = float(np.abs(signed[y0:y1, x0:x1]).mean())
            tiles.append(
                {
                    "bounds": [x0, y0, x1, y1],
                    "meanAbsRgb": round(mean_absolute, 6),
                }
            )
    tiles.sort(key=lambda item: float(item["meanAbsRgb"]), reverse=True)

    report = {
        "schemaVersion": 1,
        "method": "native-rgb-absolute-and-signed-difference",
        "images": {
            "original": {
                "path": str(args.original.resolve()),
                "sha256": file_sha256(args.original),
            },
            "current": {
                "path": str(args.current.resolve()),
                "sha256": file_sha256(args.current),
            },
            "width": width,
            "height": height,
        },
        "wholeFrame": metrics(signed),
        "staticMask": {
            "excluded": [
                {
                    "name": rect.name,
                    "bounds": [rect.x0, rect.y0, rect.x1, rect.y1],
                }
                for rect in args.exclude
            ],
            "metrics": metrics(signed[static_mask]),
        },
        "regions": region_metrics,
        "topDifferenceTiles": tiles[: args.top_tiles],
    }

    serialized = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    print(serialized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
