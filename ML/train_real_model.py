"""Train and export the SmartReceipt classifier with Flutter-aligned text rules.

Usage:
  python -m pip install -r requirements.txt
  python train_real_model.py --base Dataset_SmartReceipt_Sintetis.csv \
      --real struk_asli.csv --output model_kategori_produk_real.json

The optional real CSV must contain receipt_text,kategori. Keep a held-out
real-test CSV out of --real so its metrics remain an honest final evaluation.

Leakage guard: rows whose nama_produk appears in the base validation/test
splits are excluded from training, and the exported model is trained on
train+val only, so the synthetic test set stays held-out and re-verifiable.
"""

from __future__ import annotations

import argparse
import json
import random
import re
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import accuracy_score, classification_report, f1_score
from sklearn.naive_bayes import MultinomialNB
from sklearn.pipeline import Pipeline

SEED = 42
random.seed(SEED)
np.random.seed(SEED)


class FlutterPreprocessor:
    """Python implementation of Flutter IndonesianTextPreprocessor rules."""

    currency = re.compile(r"(?:rp\.?\s*)?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?")
    number_unit = re.compile(
        r"\b\d+\s*(?:x|pcs|pc|pck|ctn|dus|box|botol|bks|bungkus|sachet|sct|"
        r"kg|gr|gram|ml|ltr|liter|ons|papan|rim|set|pack|pak|lusin|mah|gb|tb|"
        r"watt|w|v|volt|s|l|g|ma|mm|cm|m)\b"
    )
    plain_number = re.compile(r"\b\d+\b")
    percent = re.compile(r"\d+\s*%")
    non_alnum = re.compile(r"[^a-z0-9\s]")
    repeated = re.compile(r"(.)\1{2,}")
    spaces = re.compile(r"\s+")

    def __init__(self, rules_path: Path):
        rules = json.loads(rules_path.read_text(encoding="utf-8"))
        self.abbreviations = {
            self.key(key): value for key, value in rules["abbreviations"].items()
        }
        self.stopwords = {self.key(value) for value in rules["stopwords"]}
        self.units = {self.key(value) for value in rules["units"]}
        unit_pattern = "|".join(re.escape(value) for value in sorted(self.units, key=len, reverse=True))
        self.unit_noise = re.compile(rf"\b(?:x|qty|{unit_pattern})\b")

    def key(self, value: str) -> str:
        return self.spaces.sub(" ", value.lower()).strip()

    def normalize(self, value: str) -> str:
        text = str(value).lower()
        text = (text.replace("’", "'").replace("‘", "'").replace("“", '"')
                     .replace("”", '"').replace("–", "-").replace("—", "-")
                     .replace("×", "x"))
        text = self.percent.sub(" ", text)
        text = self.currency.sub(" ", text)
        text = self.number_unit.sub(" ", text)
        text = self.unit_noise.sub(" ", text)
        text = self.plain_number.sub(" ", text)
        text = self.repeated.sub(lambda match: match.group(1) * 2, text)
        text = self.spaces.sub(" ", self.non_alnum.sub(" ", text)).strip()
        tokens = [token for token in text.split() if len(token) >= 2]
        joined = " ".join(tokens)
        for key, replacement in self.abbreviations.items():
            if " " in key and key in joined:
                joined = joined.replace(key, replacement)
        result: list[str] = []
        for token in joined.split():
            if len(token) < 2 or token in self.units or token in self.stopwords:
                continue
            result.extend(word for word in self.abbreviations.get(token, token).split() if len(word) >= 2)
        return " ".join(result)


def load_csv(path: Path, preprocessor: FlutterPreprocessor) -> pd.DataFrame:
    frame = pd.read_csv(path).dropna(subset=["receipt_text", "kategori"]).copy()
    required = {"receipt_text", "kategori"}
    if not required.issubset(frame.columns):
        raise ValueError(f"{path} must contain: {', '.join(sorted(required))}")
    frame["text"] = frame["receipt_text"].map(preprocessor.normalize)
    return frame[frame["text"].str.len() > 0].reset_index(drop=True)


def exclude_products(frame: pd.DataFrame, forbidden: set[str]) -> pd.DataFrame:
    """Drop rows whose product appears in a held-out split (leakage guard)."""
    if forbidden and "nama_produk" in frame.columns:
        return frame[~frame["nama_produk"].isin(forbidden)].reset_index(drop=True)
    return frame


def export_model(model: Pipeline, path: Path, threshold: float) -> None:
    tfidf = model.named_steps["tfidf"]
    nb = model.named_steps["nb"]
    payload = {
        "classes": [str(item) for item in nb.classes_],
        "analyzer": tfidf.analyzer,
        "ngram_range": list(tfidf.ngram_range),
        "sublinear_tf": tfidf.sublinear_tf,
        "norm": tfidf.norm,
        "lowercase": tfidf.lowercase,
        "preprocessing": "flutter_id_v1",
        "vocabulary": {key: int(value) for key, value in tfidf.vocabulary_.items()},
        "idf": [round(float(value), 5) for value in tfidf.idf_],
        "class_log_prior": [round(float(value), 6) for value in nb.class_log_prior_],
        "feature_log_prob": [[round(float(value), 4) for value in row] for row in nb.feature_log_prob_],
        "threshold": threshold,
        "fallback_label": "Perlu Review",
    }
    path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, action="append", default=[])
    parser.add_argument("--real", type=Path, action="append", default=[])
    parser.add_argument("--real-test", type=Path)
    parser.add_argument("--rules", type=Path, default=Path("../smart_receipt/assets/text_normalization_id.json"))
    parser.add_argument("--output", type=Path, default=Path("model_kategori_produk_real.json"))
    parser.add_argument("--threshold", type=float, default=0.90)
    args = parser.parse_args()

    preprocessor = FlutterPreprocessor(args.rules)
    base = load_csv(args.base, preprocessor)
    train = base[base["split"] == "train"]
    validation = base[base["split"] == "val"]
    test = base[base["split"] == "test"]
    test_products = set(test.get("nama_produk", pd.Series(dtype=str)))
    val_products = set(validation.get("nama_produk", pd.Series(dtype=str)))
    # Produk val+test tidak boleh muncul di data latih saat metrik dilaporkan,
    # dan produk test tidak boleh muncul di model ekspor akhir.
    catalog_raw = [load_csv(path, preprocessor) for path in args.catalog]
    catalog_train = [exclude_products(frame, val_products | test_products) for frame in catalog_raw]
    real_train = [load_csv(path, preprocessor) for path in args.real]
    training = pd.concat([train, *catalog_train, *real_train], ignore_index=True)

    model = Pipeline([
        ("tfidf", TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 4), sublinear_tf=True, max_features=20000)),
        ("nb", MultinomialNB(alpha=0.03, fit_prior=True)),
    ])
    model.fit(training["text"], training["kategori"])

    for name, frame in (("validation", validation), ("synthetic test", test)):
        prediction = model.predict(frame["text"])
        print(f"{name}: n={len(frame)}, accuracy={accuracy_score(frame['kategori'], prediction):.3f}, "
              f"macro_f1={f1_score(frame['kategori'], prediction, average='macro'):.3f}")

    if args.real_test:
        real_test = load_csv(args.real_test, preprocessor)
        prediction = model.predict(real_test["text"])
        print("\nREAL HELD-OUT TEST")
        print(f"n={len(real_test)}, accuracy={accuracy_score(real_test['kategori'], prediction):.3f}, "
              f"macro_f1={f1_score(real_test['kategori'], prediction, average='macro'):.3f}")
        print(classification_report(real_test["kategori"], prediction, digits=3, zero_division=0))

    # Model ekspor akhir dilatih pada train+val, tanpa produk test (tetap held-out).
    export_train = pd.concat([train, validation, *real_train], ignore_index=True)
    export_catalog = [exclude_products(frame, test_products) for frame in catalog_raw]
    all_training = pd.concat([export_train, *export_catalog], ignore_index=True)
    model.fit(all_training["text"], all_training["kategori"])
    export_model(model, args.output, args.threshold)
    joblib.dump(model, args.output.with_suffix(".joblib"))
    print(f"\nExported {args.output} and {args.output.with_suffix('.joblib')}")


if __name__ == "__main__":
    main()
