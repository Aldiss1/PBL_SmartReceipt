# SmartReceipt Machine Learning: Klasifikasi Kategori Item Struk

Dokumentasi pipeline Machine Learning untuk klasifikasi otomatis nama item struk belanja pada aplikasi **SmartReceipt**.

Model ini dirancang untuk berjalan secara lokal (*on-device*) di dalam aplikasi Flutter (offline), tanpa memerlukan server cloud atau koneksi internet.

```text
Teks Item Hasil OCR -> Preprocessing Teks -> Ekstraksi TF-IDF -> Multinomial Naive Bayes -> Kategori / Perlu Review
```

---

## 1. Deskripsi Dataset

Dataset utama yang digunakan untuk melatih model adalah `Dataset_SmartReceipt_Sintetis.csv` yang diperkaya dengan katalog produk retail Indonesia (`katalog_produk_indonesia_v1.json`).

| Karakteristik | Nilai |
|---|---:|
| Total Sampel | 6.026 baris |
| Produk / Kata Kunci Unik | 1.419 produk |
| Jumlah Kategori Target | 15 kategori |
| Data Latih (*Train*) | 4.474 baris |
| Data Validasi (*Val*) | 762 baris |
| Data Uji (*Test*) | 790 baris |

### Kolom Dataset
* `nama_produk`: Nama baku produk dalam bahasa Indonesia.
* `receipt_text`: Teks nama produk menyerupai keluaran OCR struk (mengandung singkatan, typo, variasi huruf, dan noise cetak thermal). Menjadi fitur input model.
* `kategori`: Label target kategori belanja.
* `split`: Pembagian data (`train`, `val`, `test`).

### 15 Kategori Target
Bayi & Anak, Elektronik, Hewan Peliharaan, Hiburan & Hobi, Kesehatan, Lainnya, Makanan, Minuman, Pakaian & Fashion, Pendidikan & ATK, Perawatan Diri, Rokok & Tembakau, Rumah Tangga, Tagihan & Utilitas, dan Transportasi. (Pada aplikasi mobile, kategori ini dipetakan ke 9 kategori kanonikal utama).

### *Leakage Guard* (Pencegahan Kebocoran Data)
Pembagian data dilakukan berbasis **produk unik**, bukan sekadar baris acak. Produk yang berada di data uji (*test*) dipastikan tidak pernah muncul di data latih (*train*), sehingga evaluasi akurasi benar-benar mengukur kemampuan model dalam mengklasifikasikan produk baru yang belum pernah dilihat.

---

## 2. Preprocessing Teks

Tahapan pembersihan teks bertujuan meredam noise cetakan struk thermal sebelum diekstraksi fiturnya:
1. **Case Folding**: Mengubah seluruh teks menjadi huruf kecil (*lowercase*).
2. **Pembersihan Entitas**: Menghapus nominal uang (`Rp 15.000`), ukuran kemasan (`600ml`, `1kg`, `2pcs`), angka acak, dan barcode/PLU.
3. **Pembersihan Simbol**: Menghapus karakter non-alfanumerik dan merapikan spasi berlebih.
4. **Normalisasi Kata & Singkatan**: Memulihkan singkatan umum kasir minimarket Indonesia (misal: `grg` -> `goreng`, `btl` -> `botol`, `s/` -> tanda kemasan).

---

## 3. Ekstraksi Fitur (Feature Extraction)

Model menggunakan **TF-IDF Vectorizer** dari Scikit-Learn dengan konfigurasi:

| Parameter | Konfigurasi |
|---|---|
| **Analyzer** | `char_wb` (character n-gram di dalam batas kata) |
| **Rentang N-gram** | 2 sampai 4 karakter huruf |
| **Pembobotan** | Sublinear TF (`1 + ln(tf)`) dikalikan nilai IDF |
| **Normalisasi Vektor** | L2 Normalization |
| **Maksimum Fitur** | 20.000 n-gram teratas |

Pendekatan *character n-gram* dipilih karena teks struk belanja sangat rentan terhadap salah baca OCR (misal: `"INDOMIE"` terbaca `"1ND0M1E"`). Karakter n-gram tetap mempertahankan kemiripan pola huruf, berbeda dengan pendekatan kata utuh (*word-level*) yang langsung gagal jika ada satu huruf salah.

---

## 4. Algoritma Klasifikasi (Model)

Klasifikasi dilakukan menggunakan **Multinomial Naive Bayes (`MultinomialNB`)**:
* **Smoothing**: Laplace smoothing ($\alpha = 0.03$).
* **Fit Prior**: Diaktifkan (`fit_prior=True`).
* **Rumus Scoring**:
  $$\text{Skor Kelas} = \log P(C) + \sum_{i} \text{TF-IDF}_i \times \log P(w_i \mid C)$$
* Skor kelas diubah menjadi probabilitas posterior menggunakan fungsi **Softmax**.

### Mekanisme Penolakan / Review Margin
Model menghitung margin selisih skor antara peringkat 1 (pemenang) dan peringkat 2 (runner-up). Jika selisihnya berada di bawah ambang batas (*threshold*), status prediksi ditandai sebagai **`Perlu Review`** agar pengguna dapat mengonfirmasi atau mengoreksi kategori secara manual di layar aplikasi.

---

## 5. Hasil Evaluasi Performa

Model dievaluasi pada 790 sampel data uji held-out (*unseen products*):

| Skenario Pengujian | Akurasi | Macro-F1 |
|---|---:|---:|
| Teks Bersih (Baseline Model) | 70,6% | 0,669 |
| Teks dengan Simulasi Noise OCR | 67,5% | 0,637 |
| **Teks Bersih (Model v2 + Preprocessing Selaras Flutter)** | **74,9%** | **0,712** |
| **Teks dengan Simulasi Noise OCR (Model v2)** | **68,2%** | **0,646** |
| Produk Dikenal dengan Noise OCR Baru | **96,0%** | **0,958** |

---

## 6. Integrasi ke Aplikasi Mobile (On-Device Inference)

Karena aplikasi Flutter (bahasa Dart) tidak dapat menjalankan library Scikit-Learn Python secara langsung di HP, model diekspor ke dalam format JSON:

1. **Ekspor Bobot ke JSON**:
   Fungsi `export_model()` mengekstrak:
   * `classes`: Daftar nama kelas kategori.
   * `vocabulary`: Indeks pemetaan 20.000 n-gram karakter.
   * `idf`: Nilai bobot Inverse Document Frequency tiap n-gram.
   * `class_log_prior`: Log probabilitas kemunculan tiap kelas.
   * `feature_log_prob`: Matriks log likelihood probabilitas fitur per kelas.
   * `review_margin`: Batas margin keyakinan.
2. **Eksekusi di Flutter (`tfidf_classifier.dart`)**:
   * File `assets/model_kategori_produk.json` dimuat sekali ke memori saat startup.
   * Saat struk discan, kode Dart melakukan vektorisasi TF-IDF dan perkalian matriks Naive Bayes secara native.
   * Waktu prediksi rata-rata: **< 5 milidetik per item** tanpa koneksi internet.

---

## 7. Cara Menjalankan Script

### Instalasi Dependensi
```bash
pip install -r requirements.txt
```

### Melatih Ulang Model
```bash
python train_real_model.py \
  --base Dataset_SmartReceipt_Sintetis.csv \
  --catalog katalog_produk_indonesia_v1.json \
  --output model_kategori_produk_v2.json
```

### Mengevaluasi Ketahanan Noise OCR
```bash
python evaluate_noise.py
```
