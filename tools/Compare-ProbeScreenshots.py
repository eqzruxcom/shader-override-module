import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageStat


def parse_fraction_rect(value: str) -> tuple[float, float, float, float]:
    parts = tuple(float(part.strip()) for part in value.split(","))
    if len(parts) != 4 or any(part < 0.0 or part > 1.0 for part in parts):
        raise argparse.ArgumentTypeError("rectangle must be four fractions in [0, 1]")
    if parts[0] >= parts[2] or parts[1] >= parts[3]:
        raise argparse.ArgumentTypeError("rectangle must have positive width and height")
    return parts


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare probe screenshots with ignored regions.")
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--diff", type=Path, required=True)
    parser.add_argument("--metrics", type=Path, required=True)
    parser.add_argument(
        "--ignore-rect",
        action="append",
        default=[],
        type=parse_fraction_rect,
        help="Ignored rectangle as left,top,right,bottom fractions; repeatable.",
    )
    parser.add_argument("--amplify", type=float, default=4.0)
    args = parser.parse_args()

    before = Image.open(args.before).convert("RGB")
    after = Image.open(args.after).convert("RGB")
    if before.size != after.size:
        raise RuntimeError(f"image dimensions differ: {before.size} vs {after.size}")

    width, height = before.size
    mask = Image.new("L", before.size, 255)
    draw = ImageDraw.Draw(mask)
    ignored_pixels = []
    for left, top, right, bottom in args.ignore_rect:
        pixel_rect = (
            round(left * width),
            round(top * height),
            round(right * width) - 1,
            round(bottom * height) - 1,
        )
        draw.rectangle(pixel_rect, fill=0)
        ignored_pixels.append(
            {
                "fraction": [left, top, right, bottom],
                "pixels": list(pixel_rect),
            }
        )

    included_pixel_count = round(ImageStat.Stat(mask).sum[0] / 255.0)
    if included_pixel_count == 0:
        raise RuntimeError("ignore rectangles exclude every pixel")

    difference = ImageChops.difference(before, after)
    mask_rgb = Image.merge("RGB", (mask, mask, mask))
    masked_difference = ImageChops.multiply(difference, mask_rgb)
    amplified = ImageEnhance.Brightness(masked_difference).enhance(args.amplify)
    args.diff.parent.mkdir(parents=True, exist_ok=True)
    amplified.save(args.diff)

    channels = difference.split()
    maximum_channel = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    changed = maximum_channel.point(lambda value: 255 if value > 2 else 0)
    significant = maximum_channel.point(lambda value: 255 if value > 10 else 0)
    changed_count = round(ImageStat.Stat(changed, mask=mask).sum[0] / 255.0)
    significant_count = round(ImageStat.Stat(significant, mask=mask).sum[0] / 255.0)

    stats = ImageStat.Stat(difference, mask=mask)
    channel_means = stats.mean
    channel_rms = stats.rms
    maximum_outside_mask = max(channel.getextrema()[1] for channel in masked_difference.split())
    significant_outside_mask = ImageChops.multiply(significant, mask)

    metrics = {
        "schemaVersion": 1,
        "beforePath": str(args.before.resolve()),
        "afterPath": str(args.after.resolve()),
        "diffPath": str(args.diff.resolve()),
        "width": width,
        "height": height,
        "totalPixelCount": width * height,
        "includedPixelCount": included_pixel_count,
        "includedPixelPercent": round(100.0 * included_pixel_count / (width * height), 4),
        "ignoredRectangles": ignored_pixels,
        "changedPixelCount": changed_count,
        "changedPixelPercent": round(100.0 * changed_count / included_pixel_count, 4),
        "significantPixelCount": significant_count,
        "significantPixelPercent": round(100.0 * significant_count / included_pixel_count, 4),
        "meanAbsoluteChannelDifference": round(sum(channel_means) / 3.0, 4),
        "rootMeanSquareChannelDifference": round(
            math.sqrt(sum(value * value for value in channel_rms) / 3.0), 4
        ),
        "maximumChannelDifference": maximum_outside_mask,
        "significantBounds": significant_outside_mask.getbbox(),
        "differenceAmplification": args.amplify,
    }
    args.metrics.parent.mkdir(parents=True, exist_ok=True)
    args.metrics.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()