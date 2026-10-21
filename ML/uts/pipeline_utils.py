"""Utilitas bersama pipeline UTS PBL Machine Learning SmartReceipt.

Modul ini dipakai oleh seluruh notebook anggota tim agar tahapan
pra-pengolahan, ekstraksi fitur TF-IDF, dan pembagian data BENAR-BENAR
identik. Dengan begitu perbandingan performa antar model menjadi adil:
satu-satunya yang berbeda hanyalah algoritma klasifikasinya.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)

SEED = 42
np.random.seed(SEED)

UTS_DIR = Path(__file__).resolve().parent
ML_DIR = UTS_DIR.parent
PROJECT_DIR = ML_DIR.parent

BASE_CSV = ML_DIR / "Dataset_SmartReceipt_Sintetis.csv"
CATALOG_CSV = ML_DIR / "Dataset_Katalog_Indonesia_Sintetis_v1.csv"
RULES_PATH = PROJECT_DIR / "smart_receipt" / "assets" / "text_normalization_id.json"
RESULTS_CSV = UTS_DIR / "hasil_perbandingan.csv"

# Konfigurasi TF-IDF yang dikunci untuk semua anggota tim.
TFIDF_CONFIG = dict(
    analyzer="char_wb",
    ngram_range=(2, 4),
    sublinear_tf=True,
    max_features=20000,
)


class TextPreprocessor:
    """Pra-pengolahan teks struk, selaras dengan aturan aplikasi Flutter."""

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

    def __init__(self, rules_path: Path = RULES_PATH):
        rules = json.loads(Path(rules_path).read_text(encoding="utf-8"))
        self.abbreviations = {
            self._key(key): value for key, value in rules["abbreviations"].items()
        }
        self.stopwords = {self._key(value) for value in rules["stopwords"]}
        self.units = {self._key(value) for value in rules["units"]}
        unit_pattern = "|".join(
            re.escape(value) for value in sorted(self.units, key=len, reverse=True)
        )
        self.unit_noise = re.compile(rf"\b(?:x|qty|{unit_pattern})\b")

    def _key(self, value: str) -> str:
        return self.spaces.sub(" ", value.lower()).strip()

    def normalize(self, value: str) -> str:
        text = str(value).lower()
        text = (
            text.replace("’", "'")
            .replace("‘", "'")
            .replace("“", '"')
            .replace("”", '"')
            .replace("–", "-")
            .replace("—", "-")
            .replace("×", "x")
        )
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
            result.extend(
                word
                for word in self.abbreviations.get(token, token).split()
                if len(word) >= 2
            )
        return " ".join(result)


def _prepare(path: Path, preprocessor: TextPreprocessor) -> pd.DataFrame:
    frame = pd.read_csv(path).dropna(subset=["receipt_text", "kategori"]).copy()
    frame["text"] = frame["receipt_text"].map(preprocessor.normalize)
    frame = frame[frame["text"].str.len() > 0].reset_index(drop=True)
    return frame


def load_splits(rules_path: Path = RULES_PATH):
    """Muat data latih/validasi/uji dengan leakage guard berbasis produk.

    - Data latih : split ``train`` dari dataset utama + katalog yang produknya
      tidak muncul di split val/test dataset utama.
    - Data uji   : split ``test`` dataset utama (produk belum pernah dilihat).
    - Data val   : split ``val`` dataset utama, hanya untuk pemantauan.
    """
    preprocessor = TextPreprocessor(rules_path)
    base = _prepare(BASE_CSV, preprocessor)
    catalog = _prepare(CATALOG_CSV, preprocessor)

    train = base[base["split"] == "train"]
    val = base[base["split"] == "val"]
    test = base[base["split"] == "test"]

    held_out = set(val["nama_produk"]) | set(test["nama_produk"])
    catalog_train = catalog[~catalog["nama_produk"].isin(held_out)]

    train = pd.concat([train, catalog_train], ignore_index=True)
    val = val.reset_index(drop=True)
    test = test.reset_index(drop=True)
    return train, val, test


def build_vectorizer() -> TfidfVectorizer:
    """TF-IDF identik untuk semua anggota tim (lihat TFIDF_CONFIG)."""
    return TfidfVectorizer(**TFIDF_CONFIG)


def fit_features(train: pd.DataFrame):
    """Fit TF-IDF pada data latih saja, lalu transform train/val/test."""
    vectorizer = build_vectorizer()
    x_train = vectorizer.fit_transform(train["text"])
    return vectorizer, x_train


def evaluate_model(name: str, model, x_test, y_test) -> dict:
    """Hitung metrik uji dan kembalikan ringkasan + confusion matrix."""
    y_pred = model.predict(x_test)
    labels = sorted(set(y_test) | set(y_pred))
    result = {
        "Model": name,
        "Akurasi": accuracy_score(y_test, y_pred),
        "Presisi (macro)": precision_score(
            y_test, y_pred, average="macro", zero_division=0
        ),
        "Recall (macro)": recall_score(
            y_test, y_pred, average="macro", zero_division=0
        ),
        "F1-Score (macro)": f1_score(y_test, y_pred, average="macro", zero_division=0),
        "F1-Score (weighted)": f1_score(
            y_test, y_pred, average="weighted", zero_division=0
        ),
    }
    result["_report"] = classification_report(
        y_test, y_pred, digits=4, zero_division=0, labels=labels
    )
    result["_confusion"] = pd.DataFrame(
        confusion_matrix(y_test, y_pred, labels=labels),
        index=[f"Aktual: {label}" for label in labels],
        columns=[f"Prediksi: {label}" for label in labels],
    )
    return result


def print_result(result: dict) -> None:
    print(f"Model           : {result['Model']}")
    print(f"Akurasi         : {result['Akurasi']:.4f}")
    print(f"Presisi (macro) : {result['Presisi (macro)']:.4f}")
    print(f"Recall (macro)  : {result['Recall (macro)']:.4f}")
    print(f"F1-Score (macro): {result['F1-Score (macro)']:.4f}")
    print(f"F1-Score (weight): {result['F1-Score (weighted)']:.4f}")
    print("\nClassification Report:\n")
    print(result["_report"])


def summary_table(result: dict) -> pd.DataFrame:
    return pd.DataFrame([{k: v for k, v in result.items() if not k.startswith("_")}])


def save_result(result: dict) -> None:
    """Simpan metrik ke hasil_perbandingan.csv agar bisa dibandingkan tim."""
    row = summary_table(result)
    if RESULTS_CSV.exists():
        existing = pd.read_csv(RESULTS_CSV)
        existing = existing[existing["Model"] != result["Model"]]
        row = pd.concat([existing, row], ignore_index=True)
    row.to_csv(RESULTS_CSV, index=False)
