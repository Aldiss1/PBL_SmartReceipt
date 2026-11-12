"""Evaluasi ketahanan noise OCR untuk model produksi.

Noise diterapkan pada teks MENTAH (receipt_text), lalu diproses dengan
preprocessing Flutter (`preprocessing.TextPreprocessor`) sebelum prediksi.
Data uji memakai seed=8 dan produk yang sudah dikenal memakai seed=9, persis
seperti di notebook.

Contoh:
  python evaluate_noise.py \
      --model model_kategori_produk.joblib \
      --dataset-json model_kategori_produk.json
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

import joblib
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score

import training as T
from preprocessing import TextPreprocessor

CONFUSABLE = {
    "i": ["l", "1", "j"], "l": ["i", "1"], "o": ["0", "c"], "0": ["o"], "s": ["5"],
    "b": ["6", "h"], "a": ["e", "o"], "e": ["c", "a"], "u": ["v"], "v": ["u"],
    "m": ["n"], "n": ["m", "r"], "g": ["q", "9"], "q": ["g"],
}


def add_ocr_noise(teks: str, rng: random.Random, p: float = 0.08) -> str:
    """Tukar huruf mirip, hapus, gandakan, atau tukar posisi secara acak."""
    out, i = [], 0
    while i < len(teks):
        ch = teks[i]
        if ch != " " and rng.random() < p:
            aksi = rng.choice(["ganti", "ganti", "hapus", "gandakan", "tukar"])
            if aksi == "ganti":
                out.append(rng.choice(CONFUSABLE.get(ch.lower(), [ch])))
            elif aksi == "gandakan":
                out.extend([ch, ch])
            elif aksi == "tukar" and i + 1 < len(teks) and teks[i + 1] != " ":
                out.extend([teks[i + 1], ch])
                i += 1
            elif aksi != "hapus":
                out.append(ch)
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def versi_noise(
    frame: pd.DataFrame, seed: int, p_min: float = 0.04, p_max: float = 0.15
) -> pd.DataFrame:
    rng = random.Random(seed)
    out = frame.copy()
    out["receipt_text"] = [
        add_ocr_noise(t, rng, p=rng.uniform(p_min, p_max)) for t in out["receipt_text"]
    ]
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base", type=Path, default=Path("Dataset_SmartReceipt_Sintetis.csv")
    )
    parser.add_argument(
        "--model", type=Path, default=Path("model_kategori_produk.joblib")
    )
    parser.add_argument(
        "--dataset-json",
        type=Path,
        default=None,
        help="Model JSON; bila ada, dipakai untuk melaporkan margin review.",
    )
    parser.add_argument("--rules", type=Path, default=None)
    args = parser.parse_args()

    pre = TextPreprocessor(args.rules)
    model = joblib.load(args.model)
    df = pd.read_csv(args.base)

    # Split + leakage guard yang sama dengan pelatihan, supaya angka di sini
    # bisa dibandingkan langsung dengan README.
    _train, _val, test = T.split_dataset(df, pre)
    train_raw = df[df["split"] == "train"]

    review_margin = None
    if args.dataset_json and args.dataset_json.exists():
        review_margin = json.loads(
            args.dataset_json.read_text(encoding="utf-8")
        ).get("review_margin")

    def predict(frame: pd.DataFrame):
        texts = frame["receipt_text"].map(pre.normalize)
        mask = texts.str.len() > 0
        texts, labels = texts[mask], frame["kategori"][mask]
        pred = model.predict(texts)
        return labels, pred, texts

    for name, frame in (
        ("teks bersih (test)", test),
        ("noise OCR (test, seed=8)", versi_noise(test, seed=8)),
        (
            "produk dikenal + noise (seed=9, n=1000)",
            versi_noise(train_raw.sample(1000, random_state=42), seed=9),
        ),
    ):
        labels, pred, texts = predict(frame)
        print(
            f"{name}: n={len(labels)}, accuracy={accuracy_score(labels, pred):.3f}, "
            f"macro_f1={f1_score(labels, pred, average='macro'):.3f}"
        )
        if review_margin is not None:
            scores = model.predict_log_proba(texts)
            import numpy as np

            ordered = np.sort(scores, axis=1)
            margins = ordered[:, -1] - ordered[:, -2]
            accepted = margins >= review_margin
            if accepted.any():
                correct = (pred == labels.to_numpy())
                print(
                    f"    review margin {review_margin}: coverage={accepted.mean():.1%}, "
                    f"accuracy_diterima={correct[accepted].mean():.1%}"
                )


if __name__ == "__main__":
    main()
