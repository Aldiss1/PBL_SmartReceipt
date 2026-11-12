"""Satu-satunya sumber aturan preprocessing teks SmartReceipt.

Modul ini adalah salinan Python dari `IndonesianTextPreprocessor` milik aplikasi
Flutter (`smart_receipt/lib/services/text_normalizer.dart`). Notebook, skrip
pelatihan, dan evaluasi WAJIB memakai kelas ini agar teks yang dilihat model saat
latihan identik dengan teks yang dilihatnya di HP.

Sebelum modul ini ada, proyek punya tiga implementasi berbeda:

* `preprocess()` di notebook v2 - regex sederhana, tanpa stopword/satuan,
* `FlutterPreprocessor` di `train_real_model.py`,
* `IndonesianTextPreprocessor` di Dart.

Model yang dilatih dengan aturan berbeda tidak bisa dipakai di aplikasi
(model v2 hanya 56% saat dijalankan di Dart). Modul ini menutup celah tersebut.

Versi aturan ditandai `flutter_id_v1` dan disimpan di
`smart_receipt/assets/text_normalization_id.json`; nilai yang sama ditulis ke
JSON model sebagai kunci `preprocessing`, sehingga aplikasi tahu apakah ia harus
menjalankan preprocessor sebelum memprediksi.

Hanya memakai pustaka standar Python agar bisa diimpor dari notebook mana pun.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

#: Penanda versi kontrak preprocessing. Harus sama dengan nilai yang dibaca
#: `TfidfNaiveBayesEngine.usesApplicationPreprocessing` di Dart.
PREPROCESSING_VERSION = "flutter_id_v1"

#: Lokasi bawaan tabel aturan, dihitung dari file ini (bukan dari cwd) supaya
#: notebook dan skrip CLI selalu menemukan file yang sama.
DEFAULT_RULES_PATH = (
    Path(__file__).resolve().parent.parent
    / "smart_receipt"
    / "assets"
    / "text_normalization_id.json"
)


class TextPreprocessor:
    """Pra-pengolahan teks struk, identik dengan versi aplikasi Flutter.

    Tahapan (urutannya penting dan sama dengan Dart):

    1. case folding + normalisasi karakter unicode mirip,
    2. buang persen, nominal uang, ukuran kemasan, dan angka,
    3. rapatkan huruf berulang berlebihan ("aquaaa" -> "aqua"),
    4. buang simbol non-alfanumerik, rapikan spasi,
    5. ekspansi singkatan (termasuk frasa multi-kata),
    6. buang satuan dan stopword.
    """

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

    def __init__(self, rules_path: Path | str | None = None):
        path = Path(rules_path) if rules_path is not None else DEFAULT_RULES_PATH
        rules = json.loads(path.read_text(encoding="utf-8"))
        self.abbreviations = {
            self.key(key): value for key, value in rules["abbreviations"].items()
        }
        self.stopwords = {self.key(value) for value in rules["stopwords"]}
        self.units = {self.key(value) for value in rules["units"]}
        unit_pattern = "|".join(
            re.escape(value) for value in sorted(self.units, key=len, reverse=True)
        )
        # Sama dengan `_unitNoise` di Dart: satuan berdiri sendiri + penanda qty.
        self.unit_noise = re.compile(rf"\b(?:x|qty|{unit_pattern})\b")

    def key(self, value: str) -> str:
        """Normalisasi kunci aturan (huruf kecil, spasi tunggal)."""
        return self.spaces.sub(" ", value.lower()).strip()

    def normalize(self, value: str) -> str:
        """Kembalikan teks siap-vektor untuk [value].

        Sengaja didelegasikan ke tahap terpisah supaya `normalize()` dan
        `process()` tidak bisa menyimpang satu sama lain.
        """
        return " ".join(self.normalize_tokens(self.tokenize(self.clean(value))))

    @staticmethod
    def _collapse_repeats(tokens: list[str]) -> list[str]:
        """Rapatkan token kembar bersebelahan.

        Tabel singkatan memetakan merek ke bentuk umum, sementara bentuk umum
        itu juga ada di tabel sebagai pemetaan identitas ("sabun" -> "sabun").
        Akibatnya "SABUN LIFEBUOY" menjadi "sabun sabun". Menggabungkan token
        kembar menghasilkan "sabun" tanpa kehilangan informasi, dan menjaga
        hasilnya sama dengan Dart.
        """
        out: list[str] = []
        for token in tokens:
            if not out or out[-1] != token:
                out.append(token)
        return out

    # ------------------------------------------------------------------
    # Tahap terpisah, dipakai untuk audit/debug (padanan `process()` di Dart)
    # ------------------------------------------------------------------
    def clean(self, value: str) -> str:
        """Tahap 1-4 saja: pembersihan tanpa ekspansi singkatan."""
        text = str(value).lower()
        text = (
            text.replace("\u2019", "'")
            .replace("\u2018", "'")
            .replace("\u201c", '"')
            .replace("\u201d", '"')
            .replace("\u2013", "-")
            .replace("\u2014", "-")
            .replace("\u00d7", "x")
        )
        text = self.percent.sub(" ", text)
        text = self.currency.sub(" ", text)
        text = self.number_unit.sub(" ", text)
        text = self.unit_noise.sub(" ", text)
        text = self.plain_number.sub(" ", text)
        text = self.repeated.sub(lambda match: match.group(1) * 2, text)
        text = self.non_alnum.sub(" ", text)
        return self.spaces.sub(" ", text).strip()

    def tokenize(self, cleaned: str) -> list[str]:
        """Tahap 2: pecah menjadi token, buang fragmen 1 karakter."""
        if not cleaned.strip():
            return []
        return [token for token in cleaned.split() if len(token) >= 2]

    def normalize_tokens(self, tokens: list[str]) -> list[str]:
        """Tahap 3: ekspansi singkatan, buang satuan dan stopword."""
        if not tokens:
            return []
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
        return self._collapse_repeats(result)

    def process(self, value: str) -> dict[str, object]:
        """Semua tahap, untuk layar audit dan uji paritas."""
        cleaned = self.clean(value)
        tokens = self.tokenize(cleaned)
        normalized_tokens = self.normalize_tokens(tokens)
        return {
            "raw": value,
            "cleaned": cleaned,
            "tokens": tokens,
            "normalized_tokens": normalized_tokens,
            "normalized": " ".join(normalized_tokens),
        }
