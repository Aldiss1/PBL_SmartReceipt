"""Generate labelled synthetic receipt text from katalog_produk_indonesia_v1.json."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
from pathlib import Path

SEED = 42
SIZES = ("85G", "100GR", "250ML", "500ML", "1KG", "2PCS")


def product_split(name: str) -> str:
    bucket = int(hashlib.sha256(name.encode("utf-8")).hexdigest()[:8], 16) % 100
    return "train" if bucket < 70 else "val" if bucket < 85 else "test"


def variants(product: dict[str, object], rng: random.Random) -> list[tuple[str, str]]:
    name = str(product["name"])
    aliases = [str(value) for value in product["aliases"]]
    compact = name.upper().replace(" ", "")
    words = name.upper().split()
    short = " ".join(words[: max(1, len(words) - 1)])
    return [
        (name, "clean"),
        (name.upper(), "upper"),
        (f"{name.upper()} {rng.choice(SIZES)}", "size"),
        (rng.choice(aliases), "receipt_alias"),
        (compact, "nospace"),
        (short, "trunc"),
        (f"{rng.randint(100000000000, 999999999999)} {rng.choice(aliases)}", "plu"),
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, default=Path("katalog_produk_indonesia_v1.json"))
    parser.add_argument("--output", type=Path, default=Path("Dataset_Katalog_Indonesia_Sintetis_v1.csv"))
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    rng = random.Random(SEED)
    rows: list[dict[str, str]] = []
    for index, product in enumerate(catalog["products"], start=1):
        name = str(product["name"])
        category = str(product["category"])
        split = product_split(name)
        group = name.split()[0].lower()
        for text, style in variants(product, rng):
            rows.append({
                "id": f"K{len(rows) + 1:06d}", "product_id": f"K{index:04d}",
                "nama_produk": name, "receipt_text": text, "kategori": category,
                "gaya": style, "grup": group, "split": split, "sumber": "katalog_sintetis",
            })
    with args.output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows for {len(catalog['products'])} catalog products to {args.output}")


if __name__ == "__main__":
    main()
