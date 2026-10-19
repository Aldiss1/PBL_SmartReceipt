"""Evaluasi ketahanan noise OCR untuk model v2 (metode sama dengan notebook).

Noise diterapkan pada teks MENTAH (receipt_text), lalu diproses dengan
preprocessing Flutter sebelum prediksi. Data uji memakai seed=8 dan produk
yang sudah dikenal memakai seed=9, persis seperti di notebook.
"""
import argparse
import random
from pathlib import Path

import joblib
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score

from train_real_model import FlutterPreprocessor

CONFUSABLE = {
    "i": ["l", "1", "j"], "l": ["i", "1"], "o": ["0", "c"], "0": ["o"], "s": ["5"],
    "b": ["6", "h"], "a": ["e", "o"], "e": ["c", "a"], "u": ["v"], "v": ["u"],
    "m": ["n"], "n": ["m", "r"], "g": ["q", "9"], "q": ["g"],
}


def add_ocr_noise(teks: str, rng: random.Random, p: float = 0.08) -> str:
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


def versi_noise(frame: pd.DataFrame, seed: int, p_min: float = 0.04, p_max: float = 0.15) -> pd.DataFrame:
    rng = random.Random(seed)
    out = frame.copy()
    out["receipt_text"] = [
        add_ocr_noise(t, rng, p=rng.uniform(p_min, p_max)) for t in out["receipt_text"]
    ]
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, default=Path("Dataset_SmartReceipt_Sintetis.csv"))
    parser.add_argument("--model", type=Path, default=Path("model_kategori_produk_v2.joblib"))
    parser.add_argument("--rules", type=Path, default=Path("../smart_receipt/assets/text_normalization_id.json"))
    args = parser.parse_args()

    pre = FlutterPreprocessor(args.rules)
    model = joblib.load(args.model)
    df = pd.read_csv(args.base)
    train = df[df["split"] == "train"]
    test = df[df["split"] == "test"]

    def predict(frame: pd.DataFrame):
        texts = frame["receipt_text"].map(pre.normalize)
        mask = texts.str.len() > 0
        texts, labels = texts[mask], frame["kategori"][mask]
        pred = model.predict(texts)
        return labels, pred

    for name, frame in (
        ("teks bersih (test)", test),
        ("noise OCR (test, seed=8)", versi_noise(test, seed=8)),
        ("produk dikenal + noise (seed=9, n=1000)",
         versi_noise(train.sample(1000, random_state=42), seed=9)),
    ):
        labels, pred = predict(frame)
        print(f"{name}: n={len(labels)}, accuracy={accuracy_score(labels, pred):.3f}, "
              f"macro_f1={f1_score(labels, pred, average='macro'):.3f}")


if __name__ == "__main__":
    main()
