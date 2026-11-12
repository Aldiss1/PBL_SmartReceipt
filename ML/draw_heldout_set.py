#!/usr/bin/env python3
"""Regenerate the held-out receipt sets from the cached CORD v2 split.

The sets are gitignored because they are ~20 MB each and fully reproducible
from `ML/.cord_cache/cord_validation_0.parquet`. This script is the record of
exactly how each one was drawn, so a fresh clone can rebuild them.

    python ML/draw_heldout_set.py --check    # verify the checked-out sets match
    python ML/draw_heldout_set.py            # (re)write every set

Each set is ten receipts drawn with a fixed seed from the CORD v2 validation
receipts that carry at least two annotated menu items, excluding every receipt
used by an earlier set. Sets A, B and C were each used to find and fix defects,
so only set D is still held out.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys

import pyarrow.parquet as pq

HERE = os.path.dirname(os.path.abspath(__file__))
PARQUET = os.path.join(HERE, ".cord_cache", "cord_validation_0.parquet")
OUT_ROOT = os.path.join(HERE, "..", "smart_receipt", "test_assets", "struk")

# Draw order matters: each set excludes the receipts the earlier ones used.
# The file prefix is kept for compatibility with the sets already on disk
# (set A was written as `val_01.jpg` before the letters were introduced).
SETS = [
    ("heldout", 42, "A", "val"),
    ("heldout_b", 7, "B", "valb"),
    ("heldout_c", 2026, "C", "valc"),
    ("heldout_d", 2027, "D", "vald"),
]


def names_of(ground_truth: dict) -> list[str]:
    menu = ground_truth["gt_parse"].get("menu")
    if isinstance(menu, dict):
        menu = [menu]
    out: list[str] = []
    for item in menu or []:
        name = item.get("nm", "")
        if isinstance(name, list):
            name = " ".join(str(x) for x in name)
        name = str(name).strip()
        if name:
            out.append(name)
    return out


def to_int(value: str) -> int:
    digits = re.sub(r"[^0-9]", "", str(value))
    return int(digits) if digits else 0


def draw(table, used: set[int], seed: int) -> list[dict]:
    """Ten receipts, in parquet order, excluding everything in `used`."""
    candidates = []
    for index in range(table.num_rows):
        if index in used:
            continue
        ground_truth = json.loads(table["ground_truth"][index].as_py())
        names = names_of(ground_truth)
        if len(names) >= 2:
            candidates.append(
                {
                    "index": index,
                    "items": names,
                    "total": to_int(
                        ground_truth["gt_parse"].get("total", {}).get("total_price", "")
                    ),
                    "image": table["image"][index].as_py()["bytes"],
                }
            )
    return random.Random(seed).sample(candidates, 10)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare against the sets on disk instead of writing them",
    )
    args = parser.parse_args()

    if not os.path.exists(PARQUET):
        print(f"Missing {PARQUET}.", file=sys.stderr)
        print("Fetch it with the CORD download step in ML/README.md.", file=sys.stderr)
        return 1

    table = pq.read_table(PARQUET)
    used: set[int] = set()
    failures = 0

    for name, seed, letter, prefix in SETS:
        picked = draw(table, used, seed)
        used.update(entry["index"] for entry in picked)

        out_dir = os.path.join(OUT_ROOT, name)
        truth_path = os.path.join(out_dir, "ground_truth.json")
        expected_files = [f"{prefix}_{i:02d}.jpg" for i in range(1, 11)]

        if args.check:
            if not os.path.exists(truth_path):
                print(f"MISSING {truth_path}")
                failures += 1
                continue
            with open(truth_path, encoding="utf-8") as handle:
                existing = json.load(handle)
            existing_rows = existing["receipts"]
            problems = []
            if len(existing_rows) != 10:
                problems.append(f"{len(existing_rows)} receipts, expected 10")
            for row, entry, filename in zip(existing_rows, picked, expected_files):
                if row["file"] != filename:
                    problems.append(f"file {row['file']} != {filename}")
                if row["cordIndex"] != entry["index"]:
                    problems.append(
                        f"{filename}: cordIndex {row['cordIndex']} != {entry['index']}"
                    )
                if row["items"] != entry["items"]:
                    problems.append(f"{filename}: item list differs")
                if row["total"] != entry["total"]:
                    problems.append(f"{filename}: total differs")
                photo = os.path.join(out_dir, filename)
                if not os.path.exists(photo):
                    problems.append(f"{filename}: photo missing")
            if problems:
                print(f"FAIL {name}")
                for problem in problems:
                    print(f"  {problem}")
                failures += 1
            else:
                print(f"OK   {name}  (seed {seed}, {len(picked)} receipts)")
            continue

        os.makedirs(out_dir, exist_ok=True)
        rows = []
        for entry, filename in zip(picked, expected_files):
            with open(os.path.join(out_dir, filename), "wb") as handle:
                handle.write(entry["image"])
            rows.append(
                {
                    "file": filename,
                    "cordIndex": entry["index"],
                    "source": f"CORD v2 validation (held out, set {letter})",
                    "items": entry["items"],
                    "itemCount": len(entry["items"]),
                    "total": entry["total"],
                }
            )
        with open(truth_path, "w", encoding="utf-8") as handle:
            json.dump({"_comment": f"Held-out set {letter}: seed {seed}.", "receipts": rows}, handle, indent=1, ensure_ascii=False)
        print(f"WROTE {name}  (seed {seed})")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
