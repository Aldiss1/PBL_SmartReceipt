# SmartReceipt Machine Learning: Klasifikasi Kategori Item Struk

Dokumentasi pipeline Machine Learning untuk klasifikasi otomatis nama item struk belanja pada aplikasi **SmartReceipt**.

Model ini dirancang untuk berjalan secara lokal (*on-device*) di dalam aplikasi Flutter (offline), tanpa memerlukan server cloud atau koneksi internet.

```text
Teks Item Hasil OCR -> Preprocessing (flutter_id_v1) -> TF-IDF char n-gram -> Multinomial Naive Bayes -> Kategori / Perlu Review
```

---

## 0. Satu jalur reproduksi, satu artefak

| Peran | Berkas |
|---|---|
| Aturan preprocessing (satu-satunya) | `preprocessing.py` ≡ `smart_receipt/lib/services/text_normalizer.dart` |
| Resep pelatihan (satu-satunya) | `training.py` |
| CLI pembangkit artefak | `train_real_model.py` |
| Pembangkit fixture uji | `make_fixtures.py` |
| Pengambil struk asli (CORD v2) | `import_cord.py` → `real_struk_train.csv`, `real_struk_indonesia.csv` |
| Model produksi | `model_kategori_produk.json` → disalin ke `smart_receipt/assets/` |

Notebook `SmartReceipt_Klasifikasi_Kategori_v2.ipynb` mengimpor `training.py` dan
`preprocessing.py`, jadi angka di notebook dan artefak yang dikirim ke aplikasi
tidak bisa berbeda. Artefak lama ada di `archive/` (lihat `archive/README.md`).

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python import_cord.py        # sekali saja: unduh CORD, tulis 2 CSV
.venv/bin/python train_real_model.py \
  --base Dataset_SmartReceipt_Sintetis.csv \
  --catalog Dataset_Katalog_Indonesia_Sintetis_v1.csv \
  --real-train real_struk_train.csv \
  --real-test real_struk_indonesia.csv \
  --output model_kategori_produk.json
cp model_kategori_produk.json ../smart_receipt/assets/model_kategori_produk.json
.venv/bin/python make_fixtures.py      # segarkan fixture uji Dart
```

Artefak yang dikirim ke aplikasi **wajib** dilatih dengan `--real-train`; tanpa
flag itu model kembali runtuh pada struk asli (47% vs 71%, lihat §9).

---

## 1. Deskripsi Dataset

Dataset utama: `Dataset_SmartReceipt_Sintetis.csv`, diperkaya
`Dataset_Katalog_Indonesia_Sintetis_v1.csv`.

| Karakteristik | Nilai |
|---|---:|
| Total baris dataset utama | 6.026 |
| Produk / kata kunci unik | 1.419 |
| Baris katalog tambahan | 1.190 |
| Kategori target (model) | 15 |
| Kategori aplikasi | 9 |
| Train / Val / Test (mentah) | 4.474 / 762 / 790 |
| Train / Val / Test (setelah dedup) | 4.473 / 755 / 781 |

### Kolom
* `nama_produk` — nama baku produk.
* `receipt_text` — teks menyerupai keluaran OCR (singkatan, typo, noise thermal). Fitur input.
* `kategori` — label target.
* `split` — `train` / `val` / `test`.

### 15 kategori model → 9 kategori aplikasi

| Label model | Kategori aplikasi |
|---|---|
| Makanan, Minuman, Rumah Tangga, Perawatan Diri, Kesehatan, Transportasi, Elektronik, Pakaian & Fashion | id 1–8 (sama) |
| Bayi & Anak, Hewan Peliharaan, Hiburan & Hobi, Pendidikan & ATK, Rokok & Tembakau, Tagihan & Utilitas, Lainnya | `Lainnya` (id 9) |

Pemetaan ini ada di `training.LABEL_TO_CATEGORY_ID` dan
`TfidfNaiveBayesEngine.classToCategoryId`. Konsekuensinya **31,6% baris uji
(247/781) berada di kategori `Lainnya`**, jadi laporan memuat metrik 15 kelas
dan 9 kelas sekaligus.

### Leakage guard
1. Split berbasis **produk unik**: produk val/test tidak pernah ada di train.
2. Baris val/test yang `receipt_text`-nya **identik** dengan baris train dibuang
   (9 baris uji, 7 baris validasi).
3. Produk test tidak pernah masuk data latih model ekspor (dijaga `assert`).
4. Notebook dan CLI sama-sama gagal keras bila guard ini dilanggar.

---

## 2. Preprocessing (`flutter_id_v1`)

Satu implementasi saja: `ML/preprocessing.py` (Python) dan
`IndonesianTextPreprocessor` (Dart), keduanya membaca
`smart_receipt/assets/text_normalization_id.json`.

1. Case folding + normalisasi karakter unicode mirip.
2. Buang persen, nominal uang, ukuran kemasan (`600ml`, `2pcs`), angka, PLU.
3. Rapatkan huruf berulang berlebihan (`aquaaa` → `aqua`).
4. Buang simbol non-alfanumerik, rapikan spasi.
5. Ekspansi singkatan (termasuk frasa multi-kata), buang satuan dan stopword.
6. Rapatkan token kembar bersebelahan (`sabun sabun` → `sabun`).

Contoh:

| Input | Hasil |
|---|---|
| `AQUA BTL 600ML` | `air mineral btl` |
| `INDOMIE GRG SPL 85G` | `mie instan grg spl` |
| `2 PERTAMAX 5,2 L` | `bensin` |
| `SABUN LIFEBUOY` | `sabun` |

> Versi lama punya tiga implementasi preprocessing berbeda. Model yang dilatih
> dengan aturan notebook hanya mencapai **56%** saat dijalankan di Dart, padahal
> laporan mengklaim 93%. Kesalahan itu sudah ditutup dan dijaga
> `test/preprocessing_parity_test.dart` (lihat `model_parity_test.dart`).

---

## 3. Ekstraksi Fitur

**TF-IDF** `TfidfVectorizer`:

| Parameter | Nilai |
|---|---|
| Analyzer | `char_wb` |
| N-gram | 2–5 karakter (hasil tuning) |
| Pembobotan | sublinear TF `1 + ln(tf)` × IDF |
| Normalisasi | L2 |
| Maksimum fitur | 20.000 |

`char_wb` dipilih karena teks struk rentan salah baca OCR: `INDOMIE` bisa
terbaca `1ND0M1E`, dan karakter n-gram tetap mempertahankan kemiripan pola.

---

## 4. Algoritma

**Multinomial Naive Bayes**, `alpha=0.01`, `fit_prior=False` (dipilih dari grid
pada data validasi). Skor kelas:

$$\text{Skor}_c = \log P(C_c) + \sum_i \text{TF-IDF}_i \cdot \log P(w_i \mid C_c)$$

Augmentasi noise OCR (6 salinan per baris latih) hanya dipakai saat training.

### Mekanisme "Perlu Review"

Ambang **bukan** posterior softmax (posterior model ini saturasi ~1.000 sehingga
ambang 0.90 tidak pernah aktif). Sinyalnya adalah **margin log-odds** antara
peringkat 1 dan 2:

```text
margin = skor_top1 - skor_top2
needs_review = margin < review_margin
```

`review_margin` dikalibrasi pada data **validasi** (target: akurasi item yang
diterima otomatis ≥ 95%, cakupan ≥ 60%), lalu ditulis ke JSON dan dibaca
`TfidfNaiveBayesEngine`. Nilai sekarang: **4.0**.

---

## 5. Hasil Evaluasi

Model dilatih pada `train` saja (+ katalog bersih + 195 item struk asli CORD
`validation`). Data uji sintetis: 781 baris, produk tidak pernah dilihat.

| Skenario | Akurasi 15 kelas | Macro-F1 15 kelas | Akurasi 9 kelas | Macro-F1 9 kelas |
|---|---:|---:|---:|---:|
| Teks bersih (test) | **72,1%** | 0,680 | **77,1%** | 0,699 |
| Teks + simulasi noise OCR | 68,4% | 0,647 | 73,6% | 0,662 |
| Produk dikenal + noise baru (n=1000) | 96,0% | — | — | — |
| GroupKFold per merek (5-fold) | 59,9% ± 5,3 | 0,573 | — | — |
| **Struk asli CORD (test, n=182)** | **71,4%** | 0,199 | **71,4%** | 0,324 |

Macro-F1 15 kelas pada CORD rendah (0,199) karena data uji CORD hanya memuat 5
dari 15 kelas (Makanan, Minuman, Rumah Tangga, Kesehatan, Pakaian & Fashion);
kelas yang tidak muncul otomatis bernilai 0 pada macro average. Angka 9 kelas
(0,324) lebih bermakna untuk dibandingkan.

Bacaan angka di atas:

* **72%** adalah performa jujur pada produk yang belum pernah dilihat.
* **71%** pada struk asli berarti model tidak lagi runtuh saat menghadapi bahasa
  struk sungguhan. Sebelum data CORD ditambahkan, angkanya **47,3%**.
* **96%** pada produk yang sudah dikenal menunjukkan model menghafal dengan baik;
  selisihnya adalah "harga" mengenali produk baru.
* **59,9%** pada GroupKFold per merek adalah batas bawah realistis: seluruh
  produk satu merek disembunyikan sekaligus, jadi model menghadapi merek asing.

### Harga dari menambahkan struk asli

| | Sintetis saja | + struk asli CORD |
|---|---:|---:|
| Akurasi uji sintetis | 73,1% | 72,1% |
| Akurasi struk asli (n=182) | 47,3% | **71,4%** |
| Aset yang dikirim, akurasi (n=300) | 0,770 | 0,730 |
| Aset yang dikirim, cakupan review | 69,0% | 74,0% |

Akurasi sintetis turun ~1 poin dan akurasi struk asli naik ~24 poin. Cakupan
review juga naik, artinya model lebih sering minta konfirmasi ketika ragu --
perilaku yang diinginkan pada aplikasi yang inputnya foto struk, bukan nama
produk katalog.

### Kualitas "Perlu Review" (margin 4.0)

| Data | Cakupan otomatis | Akurasi item yang diterima |
|---|---:|---:|
| Validasi, teks bersih (kalibrasi) | 67,7% | 92,0% |
| Uji, teks bersih (held-out) | 67,0% | 87,4% |
| **Struk asli CORD (held-out)** | **69,8%** | **84,3%** |

Sekitar dua pertiga item diterima otomatis; sisanya diminta konfirmasi pengguna.
Angka struk asli penting: gerbang review tetap menjaga mutu di luar domain data
latih, turun hanya dari 87% ke 84% walaupun akurasi mentahnya lebih rendah.

### Angka yang TIDAK boleh dipakai lagi

Model lama yang dulu dikirim ke aplikasi dilatih **termasuk data uji**, sehingga
mencapai 98,4% pada data uji itu sendiri. Angka 93–98% di dokumentasi versi
sebelumnya berasal dari protokol bocor tersebut. Model tersebut sudah dipindah ke
`archive/` dan tidak dipakai.

---

## 6. Integrasi ke Aplikasi (on-device)

Model diekspor ke JSON (`export_model` di `training.py`):

| Kunci | Isi |
|---|---|
| `classes` | 15 label kategori |
| `analyzer`, `ngram_range`, `sublinear_tf`, `norm` | konfigurasi vektorisasi |
| `preprocessing` | `flutter_id_v1` — aplikasi menjalankan preprocessor bila ada |
| `vocabulary`, `idf` | 20.000 n-gram |
| `class_log_prior`, `feature_log_prob` | bobot Naive Bayes |
| `review_margin` | ambang margin (4.0) |
| `fallback_label` | `Perlu Review` |

`tfidf_classifier.dart` memuat aset sekali saat startup lalu menghitung
TF-IDF + skor NB secara native: **< 5 ms per item**, tanpa jaringan.

### Uji yang menjaga kontrak ini

| Berkas | Menjaga apa |
|---|---|
| `test/model_parity_test.dart` | 300 kasus: preprocessing Dart = Python, dan prediksi Dart = Python (label, kategori, margin) |
| `test/shipped_model_test.dart` | akurasi aset yang dikirim ≥ 0.72, macro-F1 ≥ 0.63, cakupan review ≥ 50%, `review_margin` & `preprocessing` wajib ada |
| `test/category_taxonomy_test.dart` | pemetaan 15 → 9 kategori dan kebijakan review |

Fixture dibangkitkan `make_fixtures.py` — **jalankan ulang setiap kali model
dilatih ulang**, kalau tidak uji paritas akan gagal (dan itu memang tujuannya).

---

## 7. Notebook UTS (`uts/`)

Empat notebook perbandingan algoritma (Naive Bayes, kNN, SVM, Random Forest)
mengimplementasikan pipeline tanpa `scikit-learn`. Kelas `TextPreprocessor` di
dalamnya adalah salinan aturan yang sama dengan `ML/preprocessing.py`, jadi
perbandingan antar model adil: satu-satunya yang berbeda adalah algoritmanya.

| Model | Akurasi uji (versi library) | Macro-F1 |
|---|---:|---:|
| k-Nearest Neighbors | 0,773 | 0,736 |
| Support Vector Machine | 0,747 | 0,705 |
| Multinomial Naive Bayes | 0,742 | 0,706 |
| Random Forest | 0,729 | 0,695 |

> Angka ini berasal dari `hasil_perbandingan.csv` (protokol sebelum dedup
> verbatim). Setelah dedup, selisihnya < 1 poin persentase dan urutan model tidak
> berubah. Jalankan ulang notebook untuk angka terkini.

---

## 8. Keterbatasan & langkah berikutnya

1. **Data latih asli baru 4 dari 15 kelas.** CORD v2 (§9) menaikkan akurasi struk
   asli dari 47% ke 71%, tetapi isinya hanya Makanan, Minuman, Rumah Tangga, dan
   Perawatan Diri (data ujinya menyentuh 5 kelas). Kategori lain masih murni sintetis. Kumpulkan 30–50 struk
   fisik sendiri (minimarket, SPBU, apotek) → `struk_asli.csv`
   (`receipt_text,kategori`, ≥100 baris), lalu evaluasi dengan `--real-test`
   (lihat notebook §10).
2. **Kategori `Lainnya` menampung 31,6% data uji.** Bila kategori seperti Rokok
   dan Tagihan perlu dibedakan di UI, tambahkan kategori aplikasi baru alih-alih
   memetakannya ke `Lainnya`.
3. **GroupKFold per merek hanya 59,9%.** Menambah produk per merek di dataset
   akan menaikkan angka ini lebih dari sekadar menambah merek baru.
4. **Ambang review perlu kalibrasi ulang** setiap model dilatih ulang; nilai 4.0
   hanya valid untuk artefak saat ini.

## 9. Struk Indonesia asli: CORD v2

Seluruh angka sintetis di §5 berasal dari nama produk katalog. Untuk mengukur
perilaku pada teks struk sungguhan, `import_cord.py` mengambil dataset publik
[CORD v2](https://github.com/clovaai/cord) (CC-BY-4.0): struk Indonesia beranotasi
dari NAVER CLOVA, di mana setiap baris `menu.nm` adalah nama item persis seperti
tercetak di struk, lengkap dengan singkatan kasir.

```bash
cd ML
.venv/bin/python import_cord.py     # unduh ke .cord_cache/ lalu tulis dua CSV
```

Split resmi CORD dipakai apa adanya, sehingga tidak ada kebocoran:

| File | Isi | Untuk |
|---|---|---|
| `real_struk_train.csv` | split `validation`, 218 baris / 206 item unik | `--real-train` |
| `real_struk_indonesia.csv` | split `test`, 208 baris / 198 item unik | `--real-test` |

43 baris uji dibuang karena teksnya persis sama dengan data latihan (kebijakan
verbatim dedup yang sama dengan `training.split_dataset`). Setelah itu tersisa
**182 item uji** yang benar-benar belum pernah dilihat.

### Pelabelan: aturan kata kunci + koreksi manusia

`kategori` diisi aturan kata kunci, lalu 8 baris yang keliru dikoreksi manual dan
disimpan di `cord_label_corrections.json` agar regenerasi deterministik. Pola
kesalahannya konsisten: kata rasa (`caramel`, `choco`, `hazelnut`) diperiksa
sebelum kata minuman, sehingga `S-Caramel Milk Tea` menjadi Makanan. Urutan aturan
sudah diperbaiki; koreksi manual menang atas aturan dan ditandai
`label_source=koreksi_manual`.

27 baris sisa (14 item ambigu + 13 promo/ukuran) ditandai `perlu_dicek=ya` dan
dibuang otomatis oleh `load_csv` karena `kategori`-nya kosong. **Label ini tetap
bukan anotasi penuh**: ia berasal dari aturan, jadi jangan mengutip angkanya
sebagai hasil yang diaudit manusia baris per baris.

### Hasil

| | Sintetis saja | + struk asli CORD |
|---|---:|---:|
| Akurasi struk asli, sklearn (n=182) | 47,3% | **71,4%** |
| Akurasi struk asli, mesin Dart (n=182) | 50,5% | **59,9%** |
| Cakupan review, struk asli | 46,7% | 69,8% |
| Akurasi item yang diterima, struk asli | 69,4% | **84,3%** |

Selisih angka sklearn dan Dart (~6 poin) adalah efek pembulatan JSON ke 4-5
desimal; keduanya arahnya sama. Yang dilaporkan di §5 adalah angka sklearn karena
itu yang dihasilkan `train_real_model.py`.

Sebelum data CORD ditambahkan, model benar-benar runtuh pada struk asli:
`BULGOGI RICE` → Elektronik, `BLACK PEPPER MEATBALL` → Kesehatan, `BLUS WANITA` →
Perawatan Diri. Penyebabnya masuk akal: model dilatih pada **nama produk katalog**
(Indomie, Aqua, Sunlight), sedangkan CORD berisi **menu restoran** dengan kosakata
dan singkatan kasir yang berbeda. Setelah 195 item CORD ikut dilatih, kesalahan
jenis itu hilang dan akurasinya naik ~24 poin tanpa merusak data sintetis.

### Kenapa data asli ikut diaugmentasi noise

`DEFAULT_REAL_NOISE_COPIES = 10`. Diukur pada 182 item uji CORD:

| Salinan ber-noise | 0 | 3 | 6 | 10 | 15 | 20 | 30 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Akurasi struk asli | 0,615 | 0,676 | 0,687 | **0,709** | 0,709 | 0,720 | 0,703 |
| Akurasi sintetis | 0,734 | 0,734 | 0,725 | 0,722 | 0,721 | 0,718 | 0,722 |

10 dipilih karena keuntungannya hampir penuh sementara sintetis praktis tidak
turun. Stabil lintas seed (7/11/23/42): real 0,712 ± 0,015, sintetis 0,726 ± 0,003.

### Batasan yang harus disebut di laporan

CORD adalah struk restoran/kafe: 95% isinya Makanan dan Minuman, sehingga data
latih asli hanya mencakup **4 dari 15 kelas** (Makanan, Minuman, Rumah Tangga,
Perawatan Diri) dan data ujinya 5 kelas. Dataset ini membuktikan model bisa
belajar kosakata struk nyata, tetapi **tidak** bisa menggantikan data sintetis
untuk kategori seperti Elektronik, Transportasi, atau Tagihan. Untuk itu tetap
perlu 30-50 struk fisik sendiri (minimarket, SPBU, apotek) sesuai §8 poin 1.

Split `train` CORD (800 struk) belum dipakai; `import_cord.py --train-splits train`
sudah mendukungnya bila diinginkan, tetapi unduhannya ~1,8 GB.
