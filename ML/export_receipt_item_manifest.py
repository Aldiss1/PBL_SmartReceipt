"""Export item_belanja crop metadata from the Roboflow COCO receipt dataset.

The dataset labels receipt regions, not text transcripts or spending categories.
This manifest is for evaluating a detector/crop stage before ML Kit OCR.

Usage from ML:
  python export_receipt_item_manifest.py
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("OCR Struk Belanja.v2i.coco"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("receipt_item_crops.json"),
    )
    args = parser.parse_args()

    samples: list[dict[str, object]] = []
    for split in ("train", "valid", "test"):
        annotation_path = args.dataset / split / "_annotations.coco.json"
        data = json.loads(annotation_path.read_text(encoding="utf-8"))
        category_ids = {
            category["id"]
            for category in data["categories"]
            if category["name"] == "item_belanja"
        }
        if len(category_ids) != 1:
            raise ValueError(f"{annotation_path}: category item_belanja tidak ditemukan.")
        item_category_id = category_ids.pop()
        images = {image["id"]: image for image in data["images"]}

        for annotation in data["annotations"]:
            if annotation["category_id"] != item_category_id:
                continue
            image = images[annotation["image_id"]]
            x, y, width, height = annotation["bbox"]
            samples.append(
                {
                    "split": split,
                    "image_path": str(Path(split) / image["file_name"]),
                    "image_width": image["width"],
                    "image_height": image["height"],
                    "bbox_xywh": [x, y, width, height],
                    "label": "item_belanja",
                }
            )

    payload = {
        "description": "COCO item_belanja regions for receipt crop/detection evaluation.",
        "warning": "This dataset has no OCR transcript or spending-category labels.",
        "samples": samples,
    }
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(samples)} item_belanja crop samples to {args.output}")


if __name__ == "__main__":
    main()
