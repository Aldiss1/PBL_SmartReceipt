"""Resep pelatihan tunggal untuk model kategori SmartReceipt.

Dipakai oleh dua pemanggil:

* `train_real_model.py` (CLI, menghasilkan artefak produksi), dan
* `SmartReceipt_Klasifikasi_Kategori_v2.ipynb` (notebook laporan).

Keduanya harus menghasilkan model yang identik. Sebelum modul ini ada, notebook
melatih dengan augmentasi noise + `alpha=0.01, fit_prior=False`, sedangkan skrip
CLI melatih tanpa augmentasi + `alpha=0.03, fit_prior=True`; dua artefak berbeda
dengan angka berbeda beredar dengan nama yang sama.

Protokol yang dijaga modul ini:

* split per produk (bukan baris acak),
* baris val/test yang teks mentahnya identik dengan train dibuang,
* model evaluasi dilatih pada train saja,
* model produksi dilatih pada train + val, tidak pernah menyentuh test,
* ambang "Perlu Review" dikalibrasi pada validasi memakai margin log-odds.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.naive_bayes import MultinomialNB
from sklearn.pipeline import Pipeline

from preprocessing import PREPROCESSING_VERSION, TextPreprocessor

SEED = 42

#: Konfigurasi terpilih dari grid tuning pada data validasi (notebook §4).
#: Notebook memilih ini lewat grid; CLI memakainya sebagai default, sehingga
#: keduanya menghasilkan artefak yang sama.
DEFAULT_PARAMS: dict = {"ngram": (2, 5), "alpha": 0.01, "fit_prior": False}

#: Jumlah salinan ber-noise per baris latih. Augmentasi hanya untuk training.
DEFAULT_NOISE_COPIES = 6

#: Salinan ber-noise untuk data struk asli (`--real-train`).
#:
#: Diukur pada 182 item CORD test yang tidak pernah dilatih (DartEngineReplica
#: tidak dipakai di sini; angka dari model sklearn, lihat README §9):
#:
#:     salinan   0      3      6     10     15     20     30
#:     akurasi  .615   .676   .687   .709   .709   .720   .703
#:
#: 10 dipilih karena masih menaikkan akurasi struk asli hampir 10 poin sementara
#: akurasi sintetis praktis tidak turun (.734 -> .722). Di atas 20 sintetis mulai
#: turun dan keuntungannya mendatar. Angka ini stabil lintas seed:
#: real .712 +/- .015, sintetis .726 +/- .003 pada seed 7/11/23/42.
DEFAULT_REAL_NOISE_COPIES = 10

#: Model label -> id kategori aplikasi. Harus sama dengan
#: `TfidfNaiveBayesEngine.classToCategoryId` di Dart.
LABEL_TO_CATEGORY_ID: dict[str, int] = {
    "Makanan": 1,
    "Minuman": 2,
    "Rumah Tangga": 3,
    "Perawatan Diri": 4,
    "Kesehatan": 5,
    "Transportasi": 6,
    "Elektronik": 7,
    "Pakaian & Fashion": 8,
    "Pakaian": 8,
    "Lainnya": 9,
    "Bayi & Anak": 9,
    "Hewan Peliharaan": 9,
    "Hiburan & Hobi": 9,
    "Pendidikan & ATK": 9,
    "Rokok & Tembakau": 9,
    "Tagihan & Utilitas": 9,
}

CATEGORY_NAMES: dict[int, str] = {
    1: "Makanan",
    2: "Minuman",
    3: "Rumah Tangga",
    4: "Perawatan Diri",
    5: "Kesehatan",
    6: "Transportasi",
    7: "Elektronik",
    8: "Pakaian",
    9: "Lainnya",
}

CONFUSABLE = {
    "i": ["l", "1", "j"], "l": ["i", "1"], "o": ["0", "c"], "0": ["o"], "s": ["5"],
    "b": ["6", "h"], "a": ["e", "o"], "e": ["c", "a"], "u": ["v"], "v": ["u"],
    "m": ["n"], "n": ["m", "r"], "g": ["q", "9"], "q": ["g"],
}


# ---------------------------------------------------------------------------
# Teks
# ---------------------------------------------------------------------------
def add_ocr_noise(text: str, rng: random.Random, p: float = 0.08) -> str:
    """Simulasi salah baca OCR: tukar huruf mirip, hapus, gandakan, tukar posisi."""
    out: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch != " " and rng.random() < p:
            aksi = rng.choice(["ganti", "ganti", "hapus", "gandakan", "tukar"])
            if aksi == "ganti":
                out.append(rng.choice(CONFUSABLE.get(ch.lower(), [ch])))
            elif aksi == "gandakan":
                out.extend([ch, ch])
            elif aksi == "tukar" and i + 1 < len(text) and text[i + 1] != " ":
                out.extend([text[i + 1], ch])
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
    """Salinan frame dengan kolom `receipt_text` diberi noise OCR."""
    rng = random.Random(seed)
    out = frame.copy()
    out["receipt_text"] = [
        add_ocr_noise(str(t), rng, p=rng.uniform(p_min, p_max))
        for t in out["receipt_text"]
    ]
    return out


def prepare(frame: pd.DataFrame, preprocessor: TextPreprocessor) -> pd.DataFrame:
    """Terapkan preprocessing bersama; buang baris yang habis setelah dibersihkan."""
    out = pd.DataFrame(
        {
            "receipt_text": frame["receipt_text"].astype(str).values,
            "kategori": frame["kategori"].values,
        }
    )
    if "nama_produk" in frame.columns:
        out["nama_produk"] = frame["nama_produk"].values
    out["text"] = out["receipt_text"].map(preprocessor.normalize)
    return out[out["text"].str.len() > 0].reset_index(drop=True)


def augment(
    frame: pd.DataFrame,
    preprocessor: TextPreprocessor,
    n_noisy: int = DEFAULT_NOISE_COPIES,
    seed: int = 1,
) -> pd.DataFrame:
    """Data asli + `n_noisy` salinan ber-noise. Hanya untuk training."""
    parts = [prepare(frame, preprocessor)]
    for i in range(n_noisy):
        parts.append(prepare(versi_noise(frame, seed * 100 + i), preprocessor))
    return (
        pd.concat(parts, ignore_index=True)
        .drop_duplicates(["text", "kategori"])
        .reset_index(drop=True)
    )


# ---------------------------------------------------------------------------
# Split
# ---------------------------------------------------------------------------
def split_dataset(
    base: pd.DataFrame, preprocessor: TextPreprocessor
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Split train/val/test dengan leakage guard.

    * produk pada val/test tidak pernah muncul di train (dataset sudah dipecah
      per produk; ini hanya memverifikasi),
    * baris val/test yang teks mentahnya identik dengan baris train dibuang,
      karena duplikat verbatim menaikkan akurasi tanpa mengukur generalisasi.
    """
    frame = pd.DataFrame(
        {
            "receipt_text": base["receipt_text"].astype(str).values,
            "kategori": base["kategori"].values,
            "split": base["split"].values,
        }
    )
    if "nama_produk" in base.columns:
        frame["nama_produk"] = base["nama_produk"].values
    frame["text"] = frame["receipt_text"].map(preprocessor.normalize)
    frame = frame[frame["text"].str.len() > 0].reset_index(drop=True)

    train = frame[frame["split"] == "train"].reset_index(drop=True)
    val = frame[frame["split"] == "val"].reset_index(drop=True)
    test = frame[frame["split"] == "test"].reset_index(drop=True)

    seen = set(train["receipt_text"])
    val = val[~val["receipt_text"].isin(seen)].reset_index(drop=True)
    test = test[~test["receipt_text"].isin(seen)].reset_index(drop=True)

    if "nama_produk" in frame.columns:
        overlap = set(val["nama_produk"]) & set(train["nama_produk"])
        assert not overlap, f"produk validasi bocor ke train: {sorted(overlap)[:5]}"
        overlap = set(test["nama_produk"]) & set(train["nama_produk"])
        assert not overlap, f"produk uji bocor ke train: {sorted(overlap)[:5]}"
    return train, val, test


def exclude_products(frame: pd.DataFrame, forbidden: set[str]) -> pd.DataFrame:
    """Buang baris yang produknya ada di split held-out."""
    if forbidden and "nama_produk" in frame.columns:
        return frame[~frame["nama_produk"].isin(forbidden)].reset_index(drop=True)
    return frame


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
def build_model(
    ngram: tuple[int, int] = (2, 4),
    alpha: float = 0.01,
    fit_prior: bool = False,
    max_features: int = 20000,
) -> Pipeline:
    return Pipeline(
        [
            (
                "tfidf",
                TfidfVectorizer(
                    analyzer="char_wb",
                    ngram_range=ngram,
                    sublinear_tf=True,
                    max_features=max_features,
                ),
            ),
            ("nb", MultinomialNB(alpha=alpha, fit_prior=fit_prior)),
        ]
    )


def fit_eval_model(
    train: pd.DataFrame,
    catalog: pd.DataFrame | None,
    preprocessor: TextPreprocessor,
    held_out_products: set[str] | None = None,
    params: dict | None = None,
    n_noisy: int = DEFAULT_NOISE_COPIES,
    seed: int = 1,
    real_train: pd.DataFrame | None = None,
    real_noise_copies: int = DEFAULT_REAL_NOISE_COPIES,
) -> Pipeline:
    """Model untuk pelaporan metrik: dilatih pada train (+ katalog bersih) saja.

    `real_train` adalah data nyata yang **terpisah** dari set uji nyata. Ia ikut
    dilatih agar metrik pada `--real-test` mengukur generalisasi ke struk yang
    belum pernah dilihat, bukan mengukur model yang tidak pernah melihat struk
    asli sama sekali.
    """
    params = {**DEFAULT_PARAMS, **(params or {})}
    parts = [augment(train, preprocessor, n_noisy=n_noisy, seed=seed)]
    parts.extend(
        _real_training_parts(real_train, preprocessor, real_noise_copies, seed)
    )
    if catalog is not None and len(catalog):
        catalog_prepared = prepare(catalog, preprocessor)
        parts.append(exclude_products(catalog_prepared, held_out_products or set()))
    training = pd.concat(parts, ignore_index=True)
    return build_model(**params).fit(training["text"], training["kategori"])


def _real_training_parts(
    real_train: pd.DataFrame | None,
    preprocessor: TextPreprocessor,
    copies: int,
    seed: int,
) -> list[pd.DataFrame]:
    """Baris struk asli untuk latihan: versi bersih + salinan ber-noise.

    Teks struk asli sudah mengandung singkatan kasir, tetapi keluarannya di
    aplikasi tetap melewati OCR yang bisa salah baca. Menambahkan salinan
    ber-noise membuat model tidak hanya menghafal ejaan struk latihan.
    """
    if real_train is None or not len(real_train):
        return []
    parts = [prepare(real_train, preprocessor)]
    if copies > 0:
        parts.append(augment(real_train, preprocessor, n_noisy=copies, seed=seed + 4))
    return parts


def fit_production_model(
    train: pd.DataFrame,
    val: pd.DataFrame,
    test: pd.DataFrame,
    catalog: pd.DataFrame | None,
    preprocessor: TextPreprocessor,
    params: dict | None = None,
    n_noisy: int = DEFAULT_NOISE_COPIES,
    seed: int = 3,
    real_train: pd.DataFrame | None = None,
    real_noise_copies: int = DEFAULT_REAL_NOISE_COPIES,
) -> tuple[Pipeline, pd.DataFrame]:
    """Model yang diekspor: train + val, tanpa produk test."""
    params = {**DEFAULT_PARAMS, **(params or {})}
    train_final = pd.concat([train, val], ignore_index=True)

    test_products = (
        set(test["nama_produk"]) if "nama_produk" in test.columns else set()
    )
    if test_products:
        leaked = set(train_final["nama_produk"]) & test_products
        assert not leaked, f"produk uji bocor ke data latih: {sorted(leaked)[:5]}"

    parts = [augment(train_final, preprocessor, n_noisy=n_noisy, seed=seed)]
    parts.extend(
        _real_training_parts(real_train, preprocessor, real_noise_copies, seed)
    )
    if catalog is not None and len(catalog):
        catalog_prepared = prepare(catalog, preprocessor)
        parts.append(exclude_products(catalog_prepared, test_products))
    training = pd.concat(parts, ignore_index=True)
    model = build_model(**params).fit(training["text"], training["kategori"])
    return model, training


# ---------------------------------------------------------------------------
# Review margin
# ---------------------------------------------------------------------------
def decision_margins(model: Pipeline, texts) -> np.ndarray:
    """Selisih skor log-joint peringkat 1 dan 2.

    Identik dengan `TfidfPrediction.margin` di Dart. Posterior softmax tidak
    dipakai karena saturasi di ~1.000, sehingga ambang posterior tidak pernah
    aktif.
    """
    scores = model.predict_log_proba(texts)
    if scores.shape[1] < 2:
        return np.full(len(scores), np.inf)
    ordered = np.sort(scores, axis=1)
    return ordered[:, -1] - ordered[:, -2]


def _labels(frame: pd.DataFrame) -> np.ndarray:
    """Ambil kolom label, apa pun namanya (`kategori` atau `label`)."""
    for column in ("kategori", "label"):
        if column in frame.columns:
            return frame[column].to_numpy()
    raise KeyError("frame harus punya kolom 'kategori' atau 'label'")


def margin_table(model: Pipeline, frame: pd.DataFrame) -> pd.DataFrame:
    margins = decision_margins(model, frame["text"])
    correct = model.predict(frame["text"]) == _labels(frame)
    rows = []
    for threshold in np.arange(0.0, 8.01, 0.25):
        accepted = margins >= threshold
        rows.append(
            {
                "margin": round(float(threshold), 2),
                "coverage": float(accepted.mean()),
                "accuracy_accepted": (
                    float(correct[accepted].mean()) if accepted.any() else float("nan")
                ),
            }
        )
    return pd.DataFrame(rows)


def calibrate_review_margin(
    model: Pipeline,
    validation: pd.DataFrame,
    target_accuracy: float = 0.95,
    min_coverage: float = 0.60,
) -> tuple[float, pd.DataFrame]:
    """Pilih margin dengan cakupan terlebar yang masih memenuhi target akurasi."""
    table = margin_table(model, validation)
    eligible = table[
        (table["accuracy_accepted"] >= target_accuracy)
        & (table["coverage"] >= min_coverage)
    ]
    if eligible.empty:
        return 4.0, table
    chosen = float(
        eligible.sort_values("coverage", ascending=False).iloc[0]["margin"]
    )
    return chosen, table


def review_report(
    model: Pipeline, frame: pd.DataFrame, margin: float
) -> tuple[float, float]:
    """(cakupan, akurasi item yang diterima otomatis) pada [frame]."""
    margins = decision_margins(model, frame["text"])
    accepted = margins >= margin
    if not accepted.any():
        return 0.0, float("nan")
    correct = model.predict(frame["text"]) == _labels(frame)
    return float(accepted.mean()), float(correct[accepted].mean())


# ---------------------------------------------------------------------------
# Metrik
# ---------------------------------------------------------------------------
def to_app_categories(labels) -> list[str]:
    """Petakan 15 label model ke 9 kategori aplikasi."""
    return [
        CATEGORY_NAMES[LABEL_TO_CATEGORY_ID.get(str(label), 9)] for label in labels
    ]


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
def export_model(model: Pipeline, path: Path, review_margin: float) -> dict:
    """Tulis model ke JSON yang bisa dijalankan `TfidfNaiveBayesEngine`."""
    tfidf = model.named_steps["tfidf"]
    nb = model.named_steps["nb"]
    payload = {
        "classes": [str(item) for item in nb.classes_],
        "analyzer": tfidf.analyzer,
        "ngram_range": list(tfidf.ngram_range),
        "sublinear_tf": tfidf.sublinear_tf,
        "norm": tfidf.norm,
        "lowercase": tfidf.lowercase,
        # Aplikasi hanya menjalankan preprocessor bila penanda ini ada.
        "preprocessing": PREPROCESSING_VERSION,
        "vocabulary": {key: int(value) for key, value in tfidf.vocabulary_.items()},
        "idf": [round(float(value), 5) for value in tfidf.idf_],
        "class_log_prior": [round(float(value), 6) for value in nb.class_log_prior_],
        "feature_log_prob": [
            [round(float(value), 4) for value in row] for row in nb.feature_log_prob_
        ],
        # `review_margin` dibaca Dart; `threshold` (posterior) sengaja tidak
        # ditulis karena posterior model ini saturasi.
        "review_margin": round(float(review_margin), 2),
        "fallback_label": "Perlu Review",
    }
    Path(path).write_text(
        json.dumps(payload, separators=(",", ":")), encoding="utf-8"
    )
    return payload
