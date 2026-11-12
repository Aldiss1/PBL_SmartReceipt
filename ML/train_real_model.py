"""Train and export the SmartReceipt classifier (CLI).

Usage:
  python -m pip install -r requirements.txt
  python train_real_model.py --base Dataset_SmartReceipt_Sintetis.csv \
      --catalog Dataset_Katalog_Indonesia_Sintetis_v1.csv \
      --output model_kategori_produk.json

Semua resep pelatihan ada di `training.py`, yang juga dipakai notebook laporan,
sehingga keduanya menghasilkan artefak yang sama.

Leakage guards (dijaga `training.split_dataset` / `training.fit_production_model`):

* split per produk; produk val/test tidak pernah masuk train,
* baris val/test yang teks mentahnya identik dengan train dibuang,
* metrik dilaporkan dari model yang dilatih pada train saja,
* model ekspor dilatih pada train + val, tidak pernah menyentuh test.

Preprocessing memakai `preprocessing.TextPreprocessor`, kembaran Python dari
`IndonesianTextPreprocessor` di Flutter. Jangan menambahkan salinan lokal.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import pandas as pd
from sklearn.metrics import accuracy_score, classification_report, f1_score

import training as T
from preprocessing import PREPROCESSING_VERSION, TextPreprocessor


def load_csv(path: Path, preprocessor: TextPreprocessor) -> pd.DataFrame:
    frame = pd.read_csv(path)
    required = {"receipt_text", "kategori"}
    if not required.issubset(frame.columns):
        raise ValueError(f"{path} must contain: {', '.join(sorted(required))}")
    frame = frame.dropna(subset=["receipt_text", "kategori"]).copy()
    frame["receipt_text"] = frame["receipt_text"].astype(str)
    frame = frame[frame["receipt_text"].map(preprocessor.normalize).str.len() > 0]
    return frame.reset_index(drop=True)


def report(name: str, frame: pd.DataFrame, prediction) -> None:
    truth = frame["kategori"]
    print(
        f"{name}: n={len(frame)}, "
        f"15-kelas acc={accuracy_score(truth, prediction):.3f} "
        f"macro_f1={f1_score(truth, prediction, average='macro'):.3f} | "
        f"9-kelas acc={accuracy_score(T.to_app_categories(truth), T.to_app_categories(prediction)):.3f} "
        f"macro_f1={f1_score(T.to_app_categories(truth), T.to_app_categories(prediction), average='macro'):.3f}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, action="append", default=[])
    parser.add_argument("--real", type=Path, action="append", default=[])
    parser.add_argument(
        "--real-train",
        type=Path,
        action="append",
        default=[],
        help=(
            "Data struk asli untuk DILATIH (bukan untuk diuji). Wajib terpisah "
            "dari --real-test; skrip menolak jalan bila ada teks yang sama."
        ),
    )
    parser.add_argument("--real-test", type=Path)
    parser.add_argument(
        "--rules",
        type=Path,
        default=None,
        help="Override tabel aturan preprocessing (default: assets/text_normalization_id.json)",
    )
    parser.add_argument("--output", type=Path, default=Path("model_kategori_produk.json"))
    parser.add_argument(
        "--ngram", type=int, nargs=2, default=list(T.DEFAULT_PARAMS["ngram"])
    )
    parser.add_argument("--alpha", type=float, default=T.DEFAULT_PARAMS["alpha"])
    parser.add_argument(
        "--fit-prior",
        action=argparse.BooleanOptionalAction,
        default=T.DEFAULT_PARAMS["fit_prior"],
    )
    parser.add_argument("--noise-copies", type=int, default=T.DEFAULT_NOISE_COPIES)
    parser.add_argument(
        "--real-noise-copies",
        type=int,
        default=T.DEFAULT_REAL_NOISE_COPIES,
        help="Salinan ber-noise untuk data --real-train (0 = tanpa augmentasi)",
    )
    parser.add_argument(
        "--review-margin",
        type=float,
        default=None,
        help="Patok margin review manual; default dikalibrasi pada data validasi",
    )
    parser.add_argument("--target-accept-accuracy", type=float, default=0.95)
    parser.add_argument("--min-coverage", type=float, default=0.60)
    args = parser.parse_args()

    preprocessor = TextPreprocessor(args.rules)
    params = {
        "ngram": tuple(args.ngram),
        "alpha": args.alpha,
        "fit_prior": args.fit_prior,
    }

    base = load_csv(args.base, preprocessor)
    train, validation, test = T.split_dataset(base, preprocessor)

    catalogs = [load_csv(path, preprocessor) for path in args.catalog]
    catalog = pd.concat(catalogs, ignore_index=True) if catalogs else None

    # --- Data struk asli untuk latihan -------------------------------------
    real_train_frames = [load_csv(path, preprocessor) for path in args.real_train]
    real_train = (
        pd.concat(real_train_frames, ignore_index=True)
        if real_train_frames
        else None
    )
    real_test = (
        T.prepare(load_csv(args.real_test, preprocessor), preprocessor)
        if args.real_test
        else None
    )
    if real_train is not None and real_test is not None:
        # Kebocoran paling mudah terjadi di sini: baris yang sama dipakai untuk
        # melatih sekaligus menguji. Tolak dengan keras, bukan sekadar dicatat.
        shared = set(real_train["receipt_text"]) & set(real_test["receipt_text"])
        assert not shared, (
            f"{len(shared)} teks muncul di --real-train dan --real-test, "
            f"mis. {sorted(shared)[:3]}"
        )
    if real_train is not None:
        print(
            f"\n[real-train] {len(real_train)} baris struk asli ikut dilatih "
            f"(kelas: {real_train['kategori'].nunique()})"
        )

    # --- Metrik: model dilatih pada train saja ------------------------------
    held_out = set()
    for frame in (validation, test):
        if "nama_produk" in frame.columns:
            held_out |= set(frame["nama_produk"])
    model = T.fit_eval_model(
        train,
        catalog,
        preprocessor,
        held_out_products=held_out,
        params=params,
        n_noisy=args.noise_copies,
        seed=1,
        real_train=real_train,
        real_noise_copies=args.real_noise_copies,
    )

    print("\n=== EVALUASI (model dilatih pada train saja) ===")
    report("validation", validation, model.predict(validation["text"]))
    test_pred = model.predict(test["text"])
    report("synthetic test", test, test_pred)
    print("\nTest - classification report (15 kelas):")
    print(classification_report(test["kategori"], test_pred, digits=3, zero_division=0))
    print("Test - classification report (9 kategori aplikasi):")
    print(
        classification_report(
            T.to_app_categories(test["kategori"]),
            T.to_app_categories(test_pred),
            digits=3,
            zero_division=0,
        )
    )

    if real_test is not None:
        print("\n=== REAL HELD-OUT TEST ===")
        report("real test", real_test, model.predict(real_test["text"]))
        print(
            classification_report(
                real_test["kategori"],
                model.predict(real_test["text"]),
                digits=3,
                zero_division=0,
            )
        )

    # --- Margin review: dikalibrasi di validasi, dicek di test --------------
    if args.review_margin is not None:
        review_margin = float(args.review_margin)
        print(f"\n[review] margin dipatok manual: {review_margin}")
    else:
        review_margin, table = T.calibrate_review_margin(
            model,
            validation,
            target_accuracy=args.target_accept_accuracy,
            min_coverage=args.min_coverage,
        )
        print(f"\n[review] margin terpilih dari validasi: {review_margin}")
        print(table.to_string(index=False, float_format=lambda v: f"{v:.3f}"))
    for name, frame in (("validation", validation), ("test", test)):
        coverage, accuracy = T.review_report(model, frame, review_margin)
        print(
            f"[review] {name}: coverage={coverage:.1%}, "
            f"accuracy_diterima={accuracy:.1%}"
        )
    if real_test is not None:
        coverage, accuracy = T.review_report(model, real_test, review_margin)
        print(
            f"[review] real test: coverage={coverage:.1%}, "
            f"accuracy_diterima={accuracy:.1%}"
        )

    # --- Artefak produksi: train + val, tanpa produk test -------------------
    real_frames = [load_csv(path, preprocessor) for path in args.real]
    train_plus_real = pd.concat([train, *real_frames], ignore_index=True) if real_frames else train
    final_model, final_training = T.fit_production_model(
        train_plus_real,
        validation,
        test,
        catalog,
        preprocessor,
        params=params,
        n_noisy=args.noise_copies,
        seed=3,
        real_train=real_train,
        real_noise_copies=args.real_noise_copies,
    )
    T.export_model(final_model, args.output, review_margin)
    joblib.dump(final_model, args.output.with_suffix(".joblib"))
    print(
        f"\nExported {args.output} dan {args.output.with_suffix('.joblib')}\n"
        f"  preprocessing={PREPROCESSING_VERSION} review_margin={review_margin}\n"
        f"  vocab={len(final_model.named_steps['tfidf'].vocabulary_)} "
        f"train_rows={len(final_training)}"
    )


if __name__ == "__main__":
    main()
