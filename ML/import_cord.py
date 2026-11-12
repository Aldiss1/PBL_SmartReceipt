"""Impor item struk Indonesia asli dari dataset CORD v2 (CC-BY-4.0).

Kenapa CORD
-----------
Model SmartReceipt selama ini hanya diuji pada data sintetis. CORD berisi
**struk Indonesia sungguhan** (restoran, kafe, toko) yang dikumpulkan dan
dianotasi NAVER CLOVA; lisensinya CC-BY-4.0 sehingga boleh dipakai dan dikutip.
Anotasi `valid_line` memberi kita baris `menu.nm` = nama item persis seperti
tercetak di struk, lengkap dengan singkatan kasir ("NASI GRG SFD TLR",
"A.MINERAL GELAS", "Y.BASO PROM").

Yang dihasilkan
---------------
`real_struk_indonesia.csv` dengan kolom:

| Kolom | Isi |
|---|---|
| `receipt_text` | nama item apa adanya dari struk |
| `kategori` | label 15 kelas. Baris `perlu_dicek=tidak` sudah diisi otomatis |
| `perlu_dicek` | `ya` = label belum tepercaya, **wajib** diperiksa manusia |
| `saran_kategori` | tebakan dari kata kunci (alat bantu, bukan kebenaran) |
| `saran_yakin` | `tinggi` bila kata kunci tidak ambigu |
| `catatan` | `item`, `bukan_item` (promo/ukuran), atau `perlu_cek` |
| `jumlah` | berapa kali muncul di 200 struk |

PENTING: label `kategori` untuk baris `perlu_dicek=tidak` berasal dari aturan
kata kunci, **bukan** anotasi manusia. Sebelum angkanya dipakai di laporan,
periksa kolom itu. Menilai model memakai label kata kunci membuat evaluasi
melingkar (model dan pelabel sama-sama menebak dari kata yang sama).

Pemakaian
---------
    python import_cord.py                # unduh bila perlu, lalu tulis CSV
    python import_cord.py --cache-dir .cord_cache --out real_struk_indonesia.csv

Data diunduh dari Hugging Face (`naver-clova-ix/cord-v2`), split test +
validation (200 struk). Split train (800 struk, ~1,8 GB) tidak diunduh secara
default karena 200 struk sudah cukup untuk set evaluasi yang dilabeli manual.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import urllib.request
from collections import Counter
from pathlib import Path

import pyarrow.parquet as pq

HF_BASE = "https://huggingface.co/datasets/naver-clova-ix/cord-v2/resolve/main/data"
#: Satu split bisa terdiri dari beberapa file parquet (train dipecah 4).
SPLITS: dict[str, list[str]] = {
    "test": ["test-00000-of-00001-9c204eb3f4e11791.parquet"],
    "validation": ["validation-00000-of-00001-cc3c5779fe22e8ca.parquet"],
    "train": [
        "train-00000-of-00004-b4aaeceff1d90ecb.parquet",
        "train-00001-of-00004-7dbbe248962764c5.parquet",
        "train-00002-of-00004-688fe1305a55e5cc.parquet",
        "train-00003-of-00004-2d0cd200555ed7fd.parquet",
    ],
}

#: 15 kelas model. Urutan sama dengan `training.LABEL_TO_CATEGORY_ID`.
KATEGORI = [
    "Makanan", "Minuman", "Rumah Tangga", "Perawatan Diri", "Kesehatan",
    "Transportasi", "Elektronik", "Pakaian & Fashion", "Pendidikan & ATK",
    "Hiburan & Hobi", "Rokok & Tembakau", "Tagihan & Utilitas",
    "Bayi & Anak", "Hewan Peliharaan", "Lainnya",
]

# Aturan disusun dari yang paling spesifik ke paling umum. Urutannya penting:
# "MILK PASTRY ROLL" harus tertangkap sebagai roti, bukan sebagai minuman
# karena mengandung "milk"; "CHOCOLATE LOG CAKE" sebagai kue, bukan minuman.
#
# Teks CORD adalah ketikan kasir apa adanya, jadi aturan harus tahan typo dan
# singkatan: "blackcoffe", "donnut", "bred", "iviner", "pocai", "mt" (milk tea).
RULES: list[tuple[str, str, str]] = [
    # --- bukan item -------------------------------------------------------
    (r"\b(ticket|tiket|promo|discount|diskon|kupon|voucher|charge|service|tax|pb1|"
     r"poin|point|refund|deposit|tips?|kembalian|total|subtotal|off)\b",
     "bukan_item", ""),
    (r"^[=\*\-]*(large|medium|regular|small|reg)\b[=\*\-\d\s]*$", "bukan_item", ""),
    (r"^[\s=\*\-\.]+$", "bukan_item", ""),

    # --- Pakaian & Fashion ------------------------------------------------
    (r"\b(blus|blouse|kemeja|kaos|baju|celana|rok\b|dress|jaket|jacket|sandal|"
     r"sepatu|tas\b)\b", "Pakaian & Fashion", "item"),

    # --- Rumah Tangga (kemasan & perlengkapan) ----------------------------
    (r"\b(plastik|plastic|kresek|kantong|paper bag|shopping bag|mika|tutup seal|"
     r"cup\b|rice case|styrofoam|sedotan|straw|tissue|tisu|container|box makan)\b",
     "Rumah Tangga", "item"),

    # --- Perawatan Diri ---------------------------------------------------
    (r"\b(sabun|sampo|shampoo|pasta gigi|odol|sikat gigi|lotion|body wash)\b",
     "Perawatan Diri", "item"),

    # --- Kesehatan --------------------------------------------------------
    (r"\b(propolis|vitamin|suplemen|obat|paracetamol|panadol|betadine|plester|"
     r"hansaplast|masker|hand sanitizer|cuka apel)\b", "Kesehatan", "item"),

    # --- Makanan: es krim & camilan beku (sebelum "ice"/"cream") -----------
    (r"\b(ice cream|es krim|gelato|sorbet|paddle pop|superice|single scoop|"
     r"cone\b|sundae)\b", "Makanan", "item"),

    # --- Makanan: olesan & saus (harus menang atas kata minuman) -----------
    # "OREO GREEN TEA SPREAD" adalah selai, bukan teh.
    (r"\b(spread|selai|saus|sauce|sambal)\b", "Makanan", "item"),

    # --- Minuman: kata benda minuman (sebelum kata rasa) -------------------
    # Kata rasa (caramel, choco, hazelnut) dulu mendahului kata minuman,
    # sehingga "S-Caramel Milk Tea" salah menjadi Makanan. Kata benda minuman
    # sekarang diperiksa lebih dulu; "milk" polos sengaja tidak dipakai agar
    # "MILK PASTRY ROLL" tetap Makanan.
    (r"\b(teh|tea|kopi|coffee|coffe|coff|latte|cappuc\w*|capuc\w*|espresso|"
     r"americano|mocha|matcha|ocha|jus|juice|lemonade|lychee|leci|shake|"
     r"smoothie|boba|frappe|float|squash|mocktail|cocktail|sirup|syrup|"
     r"minuman|mineral|iviner|aqua|soda|cola|sprite|fanta|coca\w*|"
     r"pocari|pocai|lipton|pitcher|jasmine|chamomile|blackcoffe|blackcoff|"
     r"milk tea|susu|es batu|iced gt|iced tt|cha keaw|koi cafe)\b",
     "Minuman", "item"),

    # --- Makanan: permen & camilan kemasan --------------------------------
    (r"\b(gum|permen|candy|mike & ike|mike & berry)\b", "Makanan", "item"),

    # --- Makanan: bakery, kue, camilan manis ------------------------------
    (r"\b(roti|bread|bred|bun\b|buns|kue|cake|cakes|pastry|pastries|donut|donat|"
     r"donnut|doughnut|cookie|cookies|tart|toast|bagel|croissant|croque|brioche|"
     r"puff|eclair|eclairs|mochi|castela|brownies|onde|talam|lemper|cakwe|"
     r"bika|pancake|waffle|biskuit|biscuit|wafer|puding|pudding|dessert|"
     r"croquette|kroket|croquet|spring roll|lumpia|pastel|bolu|risoles|"
     r"ganache|choco|chocolate|cheese|cheeze|keju|cream|krim|nutella|"
     r"hazelnut|redbean|read bean|kacang|nut\b|nuts|cashew|almond|"
     r"popcorn|mantau|pain au|kaya|stix|pillow|durian|duria|bandeng|"
     r"twister|fuji|berry|blueberry|strawberry|caramel|vanilla|"
     r"ambush|dbl chs|cinnamon|chocochip|walnut|jelly|roll\b|steamed|"
     r"soft ori|soft serve|supreme|mike & ike|sundubu|maling|paha\b|"
     r"udng|teishoku|curry|sul lung tang|wngr|cheezemania)\b",
     "Makanan", "item"),

    # --- Minuman ----------------------------------------------------------
    (r"\b(teh|tea|kopi|coffee|coffe|coff|latte|cappuc\w*|capuc\w*|espresso|"
     r"americano|mocha|matcha|ocha|milo|ovaltine|sprite|coca\w*|cola|fanta|"
     r"soda|mineral|iviner|aqua|le mineral|air mineral|jus|juice|lemonade|"
     r"lychee|leci|milk|susu|shake|smoothie|boba|bubble|frappe|float|squash|"
     r"sirup|syrup|makoli|makgeolli|soju|sake|beer|bir\b|wine|mocktail|"
     r"cocktail|honey|jeruk|lemon|blackcurrant|blackcoffe|blackcoff|"
     r"pocari|pocai|lipton|pitcher|minuman|nestle|chamomile|jasmine|"
     r"passion fruit|koi cafe|es batu|ice\b|iced\b|cha keaw)\b",
     "Minuman", "item"),

    # Nama minuman yang tersambung angka/kode tanpa spasi ("LEMONADE22OZ",
    # "IVINERAL WATER") tidak tertangkap `\b`, jadi dicocokkan sebagai substring.
    (r"(lemonade|black sakura|ivineral|blackcoffe)", "Minuman", "item"),

    # --- Makanan: hidangan -------------------------------------------------
    (r"\b(nasi|rice|mie|mi\b|bihun|kwetiaw|kwetiau|udon|pasta|spaghetti|"
     r"fettucine|macaroni|carbonara|marinara|pizza|burger|bur\b|sandwich|"
     r"ayam|chicken|chkn|chk|winger|aym|sapi|beef|kambing|lamb|babi|pork|"
     r"ikan|fish|gurame|fillet|udang|shrimp|prawn|cumi|squid|calamari|"
     r"kepiting|crab|kerang|seafood|salmon|tuna|surimi|stick\b|"
     r"wagyu|steak|gyoza|dimsum|siomay|siew mai|shumai|sio may|tofu|"
     r"tahu|tempe|oncom|bakso|baso|meatball|bola ubi|sate|soto|sop\b|sui jiao|"
     r"gado|pecel|sayur|sayap|kol\b|sawi|kailan|jamur|terong|paru|otak|"
     r"usus|babat|telur|telor|egg|eggtart|kentang|potato|fries|salad|"
     r"soup|sup\b|bubur|kerupuk|krupuk|gorengan|cireng|arem|martabak|ketan|"
     r"singkong|ubi\b|jagung|rendang|gulai|opor|sambal|samabal|bumbu|kaldu|"
     r"sausage|sosis|frankfurt|frankfrut|nugget|katsu|karaage|tempura|"
     r"omurice|bento|bulgogi|japchae|samgyopsal|gyeop|bibimbap|pho\b|"
     r"thai|siram|platter|sliders|paket|combo|porsi|snack|makanan|"
     r"fu yung|kentir|kenthir|puyuh|ati\b|ampl|sbl|seol|gibab|"
     r"dine for|topper|hulk|hot dog|hotdog|chulpan|dak galbi|"
     r"lemak|kikil|tendon|iso\b|cakar|jeroan)\b",
     "Makanan", "item"),

    # --- Lainnya: jasa/biaya di struk -------------------------------------
    (r"\b(ongkir|parkir|delivery|antar|biaya|admin|fee)\b", "Lainnya", "item"),
]

# Jaga agar aturan tidak diam-diam menghasilkan kelas di luar 15 kelas model.
assert all(
    category in KATEGORI for _pattern, category, _note in RULES
    if category != "bukan_item"
), "RULES memuat kategori yang tidak dikenal model"


def download(cache: Path, split: str) -> list[Path]:
    """Unduh semua file parquet satu split bila belum ada di cache."""
    cache.mkdir(parents=True, exist_ok=True)
    targets: list[Path] = []
    for index, filename in enumerate(SPLITS[split]):
        target = cache / f"cord_{split}_{index}.parquet"
        if not target.exists():
            print(f"mengunduh {split} ... ({filename})")
            urllib.request.urlretrieve(f"{HF_BASE}/{filename}", target)
            print(f"  -> {target} ({target.stat().st_size / 1e6:.0f} MB)")
        targets.append(target)
    return targets


def extract_items(path: Path, split: str) -> list[tuple[str, str, int]]:
    """Ambil semua baris `menu.nm` (nama item) dari satu file parquet.

    Mengembalikan (teks, split, nomor_struk). Nomor struk dipakai untuk memisah
    data per struk, bukan per baris: item dalam satu struk sangat mirip sehingga
    memisah per baris akan membocorkan isi struk ke sisi latih dan uji.
    """
    table = pq.read_table(path, columns=["ground_truth"])
    rows: list[tuple[str, str, int]] = []
    for receipt, raw in enumerate(table.column("ground_truth").to_pylist()):
        try:
            payload = json.loads(raw)
        except (TypeError, json.JSONDecodeError):
            continue
        for line in payload.get("valid_line", []):
            if line.get("category") != "menu.nm":
                continue
            text = " ".join(word["text"] for word in line.get("words", []))
            text = re.sub(r"\s+", " ", text).strip()
            # Buang baris yang praktis tidak punya huruf (kode, angka, simbol).
            if len(re.sub(r"[^A-Za-z]", "", text)) >= 3:
                rows.append((text, split, receipt))
    return rows


def suggest(text: str) -> tuple[str, str, str]:
    """Tebak kategori dari kata kunci. Kembalikan (kategori, keyakinan, catatan)."""
    haystack = text.lower()
    for pattern, category, note in RULES:
        if re.search(pattern, haystack):
            if category == "bukan_item":
                return "", "", "bukan_item"
            return category, "tinggi", note
    return "", "rendah", "perlu_cek"


def load_corrections(path: Path | None) -> dict[str, str]:
    """Baca koreksi manual hasil pemeriksaan manusia."""
    if path is None:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    corrections = payload.get("koreksi", {})
    unknown = set(corrections.values()) - set(KATEGORI)
    assert not unknown, f"koreksi memuat kategori asing: {sorted(unknown)}"
    return dict(corrections)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(__file__).resolve().parent / ".cord_cache",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent / "real_struk_indonesia.csv",
        help="CSV evaluasi (default: split test CORD)",
    )
    parser.add_argument(
        "--out-train",
        type=Path,
        default=Path(__file__).resolve().parent / "real_struk_train.csv",
        help="CSV latihan (default: split validation CORD)",
    )
    parser.add_argument(
        "--corrections",
        type=Path,
        default=Path(__file__).resolve().parent / "cord_label_corrections.json",
    )
    parser.add_argument(
        "--eval-splits",
        nargs="+",
        default=["test"],
        choices=sorted(SPLITS),
    )
    parser.add_argument(
        "--train-splits",
        nargs="+",
        default=["validation"],
        choices=sorted(SPLITS),
    )
    args = parser.parse_args()

    corrections = load_corrections(args.corrections)

    # Split resmi CORD dipakai apa adanya: `validation` untuk melatih dan `test`
    # untuk menguji. Karena keduanya struk yang berbeda, tidak ada kebocoran
    # tingkat struk. Namun sebagian nama item (mis. "NASI PUTIH") muncul di
    # kedua sisi; menguji teks yang persis sama dengan yang dilatih akan
    # menaikkan skor secara palsu, jadi baris itu dibuang dari sisi evaluasi --
    # kebijakan yang sama dengan `training.split_dataset`.
    eval_rows = _extract(args.cache_dir, args.eval_splits)
    train_rows = _extract(args.cache_dir, args.train_splits)
    train_texts = {text for text, _, _ in train_rows}
    before = len(eval_rows)
    eval_rows = [row for row in eval_rows if row[0] not in train_texts]
    print(
        f"verbatim dedup: {before - len(eval_rows)} baris evaluasi dibuang "
        f"karena teksnya juga ada di data latihan"
    )

    for rows, target, label in (
        (eval_rows, args.out, "evaluasi"),
        (train_rows, args.out_train, "latihan"),
    ):
        _write(rows, target, corrections, label)

    print(
        "\nLangkah berikutnya:\n"
        "  python train_real_model.py --base Dataset_SmartReceipt_Sintetis.csv \\\n"
        "      --catalog Dataset_Katalog_Indonesia_Sintetis_v1.csv \\\n"
        f"      --real-train {args.out_train.name} --real-test {args.out.name}"
    )


def _extract(cache: Path, splits: list[str]) -> list[tuple[str, str, int]]:
    rows: list[tuple[str, str, int]] = []
    for split in splits:
        extracted: list[tuple[str, str, int]] = []
        for path in download(cache, split):
            extracted.extend(extract_items(path, split))
        print(f"{split}: {len(extracted)} baris item")
        rows.extend(extracted)
    return rows


def _write(
    rows: list[tuple[str, str, int]],
    target: Path,
    corrections: dict[str, str],
    label: str,
) -> None:
    """Tulis satu CSV (satu baris per item unik) beserta labelnya."""
    counts: Counter[str] = Counter(text for text, _, _ in rows)
    source_of: dict[str, set[str]] = {}
    for text, split, _receipt in rows:
        source_of.setdefault(text, set()).add(split)

    applied = 0
    with target.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["receipt_text", "kategori", "label_source", "perlu_dicek",
             "saran_kategori", "saran_yakin", "catatan", "jumlah", "sumber"]
        )
        for text in sorted(counts):
            category, confidence, note = suggest(text)
            is_item = note == "item"
            source = "aturan_kata_kunci"
            if text in corrections:
                # Koreksi manusia menang atas aturan, termasuk untuk baris yang
                # tadinya berstatus perlu_cek.
                category, is_item, source = corrections[text], True, "koreksi_manual"
                applied += 1
            writer.writerow(
                [
                    text,
                    category if is_item else "",
                    source if is_item else "",
                    "tidak" if is_item else "ya",
                    category,
                    confidence,
                    note,
                    counts[text],
                    "CORD v2 " + "+".join(sorted(source_of[text])),
                ]
            )

    usable = sum(1 for text in counts if text in corrections or suggest(text)[2] == "item")
    print(
        f"{target} [{label}]: {len(counts)} item unik dari {len(rows)} baris, "
        f"{usable} siap pakai, {applied} koreksi manual"
    )


if __name__ == "__main__":
    main()
