"""Bangkitkan fixture yang dipakai uji Dart, dari model produksi.

Menghasilkan tiga berkas:

1. `smart_receipt/assets/eval_dataset_dummy.json`
   Data evaluasi bawaan aplikasi (dipakai `shipped_model_test` dan layar
   Analisis). Diambil dari split test yang belum pernah dilihat model.

2. `smart_receipt/test/fixtures/preprocessing_parity.json`
   Pasangan (teks mentah, hasil `TextPreprocessor.normalize`). Uji Dart gagal
   bila `IndonesianTextPreprocessor` menyimpang dari versi Python.

3. `smart_receipt/test/fixtures/model_parity_predictions.json`
   Prediksi mesin Python (dari JSON model, bukan dari scikit-learn) untuk teks
   yang sama. Uji Dart wajib menghasilkan label + margin identik, sehingga
   kesalahan vektorisasi di Dart tidak bisa lolos diam-diam.

Jalankan setelah `train_real_model.py`:

    python make_fixtures.py
"""

from __future__ import annotations

import json
import math
from collections import Counter, defaultdict
from pathlib import Path

import pandas as pd

import training as T
from preprocessing import TextPreprocessor

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
APP = PROJECT / "smart_receipt"

MODEL_JSON = HERE / "model_kategori_produk.json"
BASE_CSV = HERE / "Dataset_SmartReceipt_Sintetis.csv"
EVAL_ASSET = APP / "assets" / "eval_dataset_dummy.json"
FIXTURES = APP / "test" / "fixtures"

EVAL_SAMPLES = 300
PARITY_SAMPLES = 300


# ---------------------------------------------------------------------------
# Peniru mesin inferensi Dart (`TfidfNaiveBayesEngine`)
# ---------------------------------------------------------------------------
class DartEngineReplica:
    """Replika 1:1 `tfidf_classifier.dart`, membaca JSON hasil ekspor.

    Sengaja tidak memakai scikit-learn: yang diuji adalah kecocokan angka yang
    benar-benar tersimpan di JSON (sudah dibulatkan 4-5 desimal), bukan model
    Python aslinya.
    """

    def __init__(self, payload: dict):
        self.classes = list(payload["classes"])
        self.vocab = {k: int(v) for k, v in payload["vocabulary"].items()}
        self.idf = [float(x) for x in payload["idf"]]
        self.prior = [float(x) for x in payload["class_log_prior"]]
        self.flp = [[float(x) for x in row] for row in payload["feature_log_prob"]]
        self.min_n, self.max_n = (int(x) for x in payload["ngram_range"])
        self.review_margin = float(payload["review_margin"])
        self.fallback = payload["fallback_label"]

    def char_ngrams(self, text: str) -> list[str]:
        grams: list[str] = []
        for word in text.lower().split():
            padded = f" {word} "
            for n in range(self.min_n, self.max_n + 1):
                if len(padded) < n:
                    continue
                for i in range(len(padded) - n + 1):
                    grams.append(padded[i : i + n])
        return grams

    def vectorize(self, text: str) -> dict[int, float]:
        counts: Counter[str] = Counter(self.char_ngrams(text))
        weighted: dict[int, float] = {}
        for term, count in counts.items():
            index = self.vocab.get(term)
            if index is None:
                continue
            weighted[index] = weighted.get(index, 0.0) + (
                1 + math.log(count)
            ) * self.idf[index]
        total = sum(v * v for v in weighted.values())
        if total <= 0:
            return {}
        norm = math.sqrt(total)
        return {i: v / norm for i, v in weighted.items()}

    def decision_scores(self, vector: dict[int, float]) -> list[float]:
        return [
            self.prior[c] + sum(v * self.flp[c][i] for i, v in vector.items())
            for c in range(len(self.classes))
        ]

    def predict(self, text: str) -> dict:
        vector = self.vectorize(text)
        if not vector:
            return {
                "label": self.fallback,
                "margin": 0.0,
                "confidence": 0.0,
                "categoryId": 9,
            }
        scores = self.decision_scores(vector)
        order = sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)
        margin = scores[order[0]] - scores[order[1]] if len(scores) > 1 else math.inf
        needs_review = margin < self.review_margin
        others = len(self.classes) - 1
        confidence = 1.0 / (1.0 + others * math.exp(-margin)) if math.isfinite(margin) else 1.0
        return {
            "label": self.fallback if needs_review else self.classes[order[0]],
            "topLabel": self.classes[order[0]],
            "margin": margin,
            "confidence": confidence,
            "categoryId": T.LABEL_TO_CATEGORY_ID.get(self.classes[order[0]], 9),
        }


# ---------------------------------------------------------------------------
def build_eval_dataset(test: pd.DataFrame) -> list[dict]:
    """Ambil sampel berimbang per label dari split test."""
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in test.itertuples(index=False):
        grouped[row.kategori].append({"text": row.receipt_text, "label": row.kategori})

    quota = max(1, EVAL_SAMPLES // max(1, len(grouped)))
    samples: list[dict] = []
    for label in sorted(grouped):
        samples.extend(grouped[label][:quota])
    # Isi sisa kuota dari label yang masih punya stok.
    if len(samples) < EVAL_SAMPLES:
        used = {id(s) for s in samples}
        for label in sorted(grouped):
            for sample in grouped[label][quota:]:
                if len(samples) >= EVAL_SAMPLES:
                    break
                if id(sample) not in used:
                    samples.append(sample)
    return samples[:EVAL_SAMPLES]


def main() -> None:
    preprocessor = TextPreprocessor()
    payload = json.loads(MODEL_JSON.read_text(encoding="utf-8"))
    engine = DartEngineReplica(payload)

    base = pd.read_csv(BASE_CSV).dropna(subset=["receipt_text", "kategori"])
    train, val, test = T.split_dataset(base, preprocessor)

    # --- 1. Dataset evaluasi aplikasi --------------------------------------
    samples = build_eval_dataset(test)
    EVAL_ASSET.write_text(
        json.dumps(
            {
                "_comment": (
                    "Data evaluasi untuk model TF-IDF + Naive Bayes yang dikirim "
                    "ke aplikasi. Diambil dari split test Dataset_SmartReceipt_"
                    "Sintetis.csv (produk tidak pernah dilihat model, duplikat "
                    "verbatim terhadap train sudah dibuang). `text` adalah teks "
                    "MENTAH seperti keluaran OCR; aplikasi menerapkan "
                    "IndonesianTextPreprocessor sebelum memprediksi karena model "
                    "bertanda preprocessing=flutter_id_v1. Dibangkitkan oleh "
                    "ML/make_fixtures.py."
                ),
                "samples": samples,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"{EVAL_ASSET.relative_to(PROJECT)}: {len(samples)} sampel")

    # --- 2 & 3. Fixture paritas -------------------------------------------
    FIXTURES.mkdir(parents=True, exist_ok=True)
    parity_rows = samples[:PARITY_SAMPLES]

    preprocessing_rows = [
        {"raw": row["text"], "expected": preprocessor.normalize(row["text"])}
        for row in parity_rows
    ]
    (FIXTURES / "preprocessing_parity.json").write_text(
        json.dumps(
            {
                "_comment": (
                    "Dibangkitkan ML/make_fixtures.py. `expected` berasal dari "
                    "ML/preprocessing.py; Dart wajib menghasilkan string identik."
                ),
                "cases": preprocessing_rows,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"preprocessing_parity.json: {len(preprocessing_rows)} kasus")

    prediction_rows = []
    for row in parity_rows:
        normalized = preprocessor.normalize(row["text"])
        result = engine.predict(normalized)
        prediction_rows.append(
            {
                "text": normalized,
                "label": result["label"],
                "topLabel": result["topLabel"],
                "categoryId": result["categoryId"],
                "margin": round(result["margin"], 6),
                "confidence": round(result["confidence"], 6),
            }
        )
    (FIXTURES / "model_parity_predictions.json").write_text(
        json.dumps(
            {
                "_comment": (
                    "Dibangkitkan ML/make_fixtures.py dari model_kategori_produk"
                    ".json. `text` sudah dipreprocess. Dart wajib menghasilkan "
                    "label, categoryId, dan margin yang sama persis."
                ),
                "reviewMargin": engine.review_margin,
                "cases": prediction_rows,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"model_parity_predictions.json: {len(prediction_rows)} kasus")

    # --- Ringkasan ---------------------------------------------------------
    correct = sum(
        1
        for row, sample in zip(prediction_rows, parity_rows)
        if row["label"] == sample["label"]
    )
    print(
        f"akurasi fixture (label setelah review gating): "
        f"{correct}/{len(prediction_rows)} = {correct / len(prediction_rows):.1%}"
    )
    print("label distribution:", dict(Counter(s["label"] for s in samples)))


if __name__ == "__main__":
    main()
