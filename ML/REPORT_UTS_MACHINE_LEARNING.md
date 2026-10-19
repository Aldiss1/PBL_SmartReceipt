# Laporan UTS Machine Learning

## SmartReceipt Analyzer: Klasifikasi Kategori Item Struk

**Model:** TF-IDF *character n-gram* + Multinomial Naive Bayes  
**Tujuan:** mengklasifikasikan teks nama item hasil OCR pada struk belanja ke kategori pengeluaran secara otomatis. Model berjalan secara lokal (*on-device*) di aplikasi Flutter, sehingga tidak memerlukan API atau koneksi internet.

Alur sistem:

```text
Teks item hasil OCR -> preprocessing -> ekstraksi TF-IDF ->
Multinomial Naive Bayes -> kategori / Perlu Review
```

## 1. Deskripsi Data

Dataset yang digunakan adalah `Dataset_SmartReceipt_Sintetis.csv`. Data dibuat secara sintetis dari daftar produk serta variasi penulisan yang lazim muncul pada struk dan hasil OCR. Oleh karena itu, dataset ini digunakan untuk membangun prototipe dan belum dapat dianggap sebagai representasi penuh semua struk asli di Indonesia.

| Karakteristik | Nilai |
|---|---:|
| Total baris | 6.026 |
| Produk/kata kunci unik | 1.419 |
| Jumlah kategori | 15 |
| Data sintetis produk spesifik | 5.212 baris |
| Data kata kunci generik | 814 baris |
| Data latih | 4.474 baris |
| Data validasi | 762 baris |
| Data uji | 790 baris |

Kolom utama dataset adalah sebagai berikut.

| Kolom | Deskripsi |
|---|---|
| `id` | Identitas setiap sampel. |
| `product_id` | Identitas produk atau kata kunci. |
| `nama_produk` | Nama produk dalam bentuk normal. |
| `receipt_text` | Teks produk yang menyerupai keluaran OCR pada struk. Kolom ini menjadi fitur masukan model. |
| `kategori` | Label target yang diprediksi model. |
| `gaya` | Jenis variasi teks, misalnya `clean`, `abbr`, `trunc`, `nospace`, `vowel`, `dropword`, dan `kode_plu`. |
| `grup` | Merek atau kelompok produk, digunakan untuk evaluasi GroupKFold. |
| `split` | Pembagian data `train`, `val`, atau `test`. |
| `sumber` | Asal contoh: `sintetis` atau `kata_kunci`. |

Lima belas kategori target adalah: Bayi & Anak, Elektronik, Hewan Peliharaan, Hiburan & Hobi, Kesehatan, Lainnya, Makanan, Minuman, Pakaian & Fashion, Pendidikan & ATK, Perawatan Diri, Rokok & Tembakau, Rumah Tangga, Tagihan & Utilitas, dan Transportasi.

Pembagian data dilakukan berdasarkan produk. Satu produk hanya berada dalam satu *split*, sehingga produk pada data uji tidak pernah muncul pada data latih. Data kata kunci generik hanya dimasukkan pada data latih agar model mempelajari istilah umum kategori tanpa membocorkan contoh tersebut ke validasi atau pengujian.

## 2. Preprocess

Preprocessing dilakukan untuk mengurangi *noise* yang tidak membawa informasi kategori, terutama akibat format struk dan kesalahan OCR. Tahapan preprocessing di notebook pelatihan adalah:

1. Mengubah seluruh teks menjadi huruf kecil.
2. Menghapus angka, nominal, barcode/PLU, ukuran, dan satuan, misalnya `600ML`, `1KG`, atau `50000`.
3. Menghapus simbol dan karakter selain huruf.
4. Merapikan spasi menjadi satu spasi.
5. Menghapus sampel yang hasil preprocessing-nya kosong.

Contoh: `8992761134019 INDOMIE GRG 85G` menjadi `indomie grg`, sedangkan `AQUA BTL 600ML` menjadi `aqua btl`.

Pada aplikasi Flutter, preprocessing diperluas agar sesuai kondisi OCR nyata. Implementasi `IndonesianTextPreprocessor` juga menangani normalisasi Unicode, mata uang, persentase, pengulangan karakter OCR, tokenisasi, penghapusan *stopword* dan satuan, serta ekspansi singkatan/merek. Contohnya, `indomie` dinormalisasi menjadi `mie instan`, `aqua` menjadi `air mineral`, dan `panadol` menjadi `obat`.

Untuk meningkatkan ketahanan model terhadap OCR, data latih diaugmentasi dengan enam salinan ber-*noise*. Noise dibuat dengan operasi penggantian karakter mirip, penghapusan karakter, penggandaan karakter, dan pertukaran posisi karakter. Tingkat noise diacak pada rentang 4% sampai 15%. Augmentasi hanya diterapkan pada data latih agar validasi dan pengujian tetap adil.

## 3. Extract Feature

Fitur diekstraksi menggunakan `TfidfVectorizer` dari scikit-learn dengan konfigurasi berikut.

| Parameter | Nilai |
|---|---|
| Analyzer | `char_wb` |
| Rentang n-gram | 2 sampai 4 karakter |
| Pembobotan | TF-IDF dengan `sublinear_tf=True` |
| Normalisasi vektor | L2 |
| Maksimum fitur saat pelatihan | 20.000 |
| Vocabulary model ekspor | 20.000 fitur |

Pendekatan *character n-gram* dipilih karena teks item struk sering tidak lengkap dan memiliki kesalahan OCR. Sebagai contoh, kata `INDOMIE GORENG` dapat muncul sebagai `INDOMIE GRG`, `INDME GORENG`, atau `INDOMIEGORENG`. N-gram karakter dapat mempertahankan kemiripan pola karakter pada bentuk-bentuk tersebut, dibandingkan representasi berbasis kata penuh yang lebih mudah kehilangan kecocokan.

Skema `char_wb` membentuk n-gram dalam batas kata dengan menambahkan spasi di awal dan akhir kata. Nilai TF menggunakan rumus `1 + ln(tf)`, kemudian dikalikan nilai IDF dan dinormalisasi dengan norma L2. Vektor hasil inilah yang menjadi masukan Multinomial Naive Bayes.

## 4. Training Strategy

Strategi pelatihan dirancang untuk mengukur kemampuan model pada produk baru dan teks yang bernoise.

1. Data dibagi menjadi train, validation, dan test berdasarkan produk, bukan hanya berdasarkan baris. Dengan demikian, variasi dari produk uji tidak pernah dipakai saat pelatihan.
2. Data train diaugmentasi dengan enam versi *noise OCR* untuk meningkatkan robustnes model terhadap salah baca OCR.
3. Data validation digabung dengan satu versi *noise OCR*. Data ini digunakan untuk memilih hiperparameter dan ambang keyakinan tanpa menyentuh data test.
4. Model dibandingkan pada kombinasi `ngram_range` `(2,4)`, `(2,5)`, `(3,5)`, parameter smoothing `alpha` `0,01`, `0,03`, `0,1`, `0,3`, serta opsi `fit_prior` bernilai benar atau salah.
5. Model terbaik dipilih menggunakan **macro-F1** pada validation set. Metrik ini dipilih agar tiap kategori memiliki bobot sama walaupun distribusi jumlah data tidak seimbang.
6. Model terpilih diuji pada teks bersih dan teks dengan noise OCR dari produk yang belum pernah dilihat.
7. Evaluasi tambahan menggunakan **5-fold GroupKFold** berdasarkan `grup`/merek. Dalam skenario ini semua produk dari sebuah merek/kelompok dapat disembunyikan sekaligus dari data latih, sehingga pengujian lebih ketat.
8. Setelah evaluasi selesai, model final dilatih ulang menggunakan gabungan train dan validation. Produk pada data test tidak pernah disertakan dalam model ekspor sehingga metrik evaluasi tetap dapat diverifikasi ulang secara jujur. Guard anti-kebocoran juga menerapkan aturan yang sama pada data tambahan: baris katalog yang produknya tumpang tindih dengan data validation atau test dibuang dari data latih (41 baris katalog dibuang dari data uji, 4 baris dari data validasi). Model akhir diekspor menjadi `model_kategori_produk.joblib` untuk Python dan `model_kategori_produk.json` untuk Flutter.

Model menerapkan mekanisme penolakan prediksi. Ambang keyakinan dipilih dari validation set dengan target akurasi prediksi yang diterima otomatis minimal 90%. Model ekspor menggunakan ambang `0,90`; jika probabilitas kelas tertinggi di bawah nilai tersebut, keluaran menjadi **Perlu Review** agar pengguna dapat mengoreksi kategori secara manual.

Koreksi pengguna di aplikasi disimpan sebagai pasangan teks item ternormalisasi dan kategori koreksi. Data tersebut dapat diekspor sebagai dataset tambahan untuk pelatihan berikutnya. Dengan strategi ini, kualitas model dapat ditingkatkan dari data penggunaan nyata tanpa mengubah prediksi secara langsung di perangkat.

## 5. Train Method

Metode klasifikasi yang digunakan adalah **Multinomial Naive Bayes**. Metode ini sesuai untuk data fitur non-negatif dan berdimensi tinggi seperti bobot TF-IDF. Untuk setiap kelas, model menghitung skor:

```text
skor_kelas = log prior_kelas + jumlah(TF-IDF_fitur x log probabilitas_fitur|kelas)
```

Skor seluruh kelas diubah menjadi probabilitas posterior menggunakan softmax. Kategori dengan probabilitas tertinggi dipilih apabila melewati ambang keyakinan; jika tidak, sistem mengembalikan `Perlu Review`.

Alasan pemilihan metode:

1. Cepat dilatih dan ringan saat inferensi di perangkat mobile.
2. Cocok untuk klasifikasi teks pendek dengan jumlah fitur besar.
3. Dapat bekerja dengan baik bersama TF-IDF dan n-gram karakter.
4. Parameter model dapat diekspor sebagai JSON dan dihitung ulang di Dart tanpa layanan eksternal.
5. Memberikan probabilitas yang dapat digunakan untuk menentukan item yang perlu ditinjau pengguna.

Implementasi Flutter mereplikasi transformasi saat pelatihan: ekstraksi `char_wb` n-gram, TF sublinear, pembobotan IDF, normalisasi L2, perhitungan skor Naive Bayes, dan softmax. Hal ini menjaga hasil inferensi aplikasi tetap konsisten dengan model yang dilatih pada Python.

## 6. Hasil Evaluasi Performa

### Hasil evaluasi utama pada data uji

Model dievaluasi pada 790 data uji dari `Dataset_SmartReceipt_Sintetis.csv`. Produk pada data uji tidak pernah digunakan pada data latih. Evaluasi dilakukan pada dua skenario: teks bersih dan teks yang diberi simulasi noise OCR.

| Skenario | Jumlah data | Akurasi | Macro-F1 |
|---|---:|---:|---:|
| Teks bersih (model awal) | 790 | 70,6% | 0,669 |
| Teks + noise OCR (model awal) | 790 | 67,5% | 0,637 |
| Teks bersih (model selaras Flutter) | 790 | 72,3% | 0,687 |
| Teks bersih (model v2 + katalog 170 produk) | 790 | 74,9% | 0,712 |
| Teks + noise OCR (model v2) | 790 | 68,2% | 0,646 |

Model selaras Flutter dilatih ulang dengan aturan preprocessing yang sama dengan aplikasi. Model v2 memasukkan tambahan 170 produk Indonesia dari katalog lintas 15 kategori (`katalog_produk_indonesia_v1.json`), menghasilkan total 1.190 baris augmentasi tambahan. Dibanding model awal, akurasi teks bersih naik 4,3 poin (70,6% → 74,9%) dan macro-F1 naik 0,043 (0,669 → 0,712). Pada skenario noise OCR, model v2 memperoleh 68,2% akurasi dan 0,646 macro-F1, sedikit lebih baik daripada model awal (67,5% dan 0,637). Sebagai pembanding, akurasi pada produk yang sudah dikenal dengan noise OCR baru adalah **96,0%** (model awal: 96,6%). Selisih terhadap data uji produk baru menunjukkan tantangan utama model, yaitu melakukan generalisasi kategori untuk nama produk yang belum pernah dilihat. Metrik di atas dihitung dengan guard anti-kebocoran sehingga produk yang tumpang tindih dengan data val/test tidak pernah ada di data latih; pengujian struk nyata tetap perlu dilakukan.

### Hasil evaluasi integrasi model ekspor

Selain evaluasi utama, `eval_dataset_dummy.json` digunakan untuk menguji integrasi model JSON pada aplikasi Flutter. File ini berisi 72 sampel berlabel dari 15 kategori. Model JSON dievaluasi melalui implementasi Dart yang sama dengan aplikasi menggunakan perintah berikut:

```bash
flutter test test/model_evaluator_test.dart --reporter expanded
```

| Metrik | Hasil |
|---|---:|
| Jumlah sampel | 72 |
| Akurasi | 0,931 atau 93,1% |
| Macro-F1 | 0,894 |
| Weighted-F1 | 0,955 |
| Status pengujian | 8 test lulus |

Hasil tersebut menunjukkan bahwa model JSON dapat dimuat dan dijalankan dengan benar di Flutter, serta metrik dihitung dari prediksi aktual model, bukan nilai statis. Evaluasi 72 sampel ini merupakan pengujian integrasi aplikasi, bukan metrik performa utama model.

### Evaluasi eksperimen yang disediakan notebook

Notebook menyediakan evaluasi terpisah untuk teks uji bersih, teks uji dengan noise OCR, laporan klasifikasi per kelas, confusion matrix, dan rata-rata 5-fold GroupKFold per merek. Hasil utama untuk 790 data uji di atas diperoleh dari eksekusi notebook pada Google Colab. Evaluasi noise OCR model v2 dijalankan dengan `evaluate_noise.py`, yang mereplikasi metode notebook: noise diterapkan pada teks mentah sebelum preprocessing Flutter, dengan seed 8 untuk data uji dan seed 9 untuk sampel produk yang sudah dikenal. Metrik per kelas, confusion matrix, dan GroupKFold perlu ditambahkan setelah output lengkapnya tersedia.

### Katalog produk Indonesia (penambahan data sintetis)

Dataset awal berisi 1.419 produk. Untuk memperluas cakupan, ditambahkan `katalog_produk_indonesia_v1.json` yang memuat 170 produk dan layanan umum Indonesia tambahan, tersebar merata di seluruh 15 kategori. Setiap produk menghasilkan 7 variasi teks struk (bersih, kapital, ukuran, alias, tanpa spasi, terpotong, kode PLU) sehingga total 1.190 baris augmentasi. Dataset ini bersifat sintetis dan ditandai `sumber=katalog_sintetis` untuk membedakannya dari data asli.

### Kesimpulan dan tindak lanjut

Kombinasi preprocessing selaras Flutter dan penambahan 170 produk katalog menghasilkan model v2 dengan akurasi teks bersih 74,9% dan macro-F1 0,712 pada 790 data test sintetis; dengan noise OCR model memperoleh 68,2% dan 0,646. Semua metrik dihitung dengan guard anti-kebocoran produk. Walaupun demikian, dataset utama masih sintetis sehingga hasil belum menggambarkan sepenuhnya kondisi struk nyata. Evaluasi lanjutan yang diperlukan adalah mengumpulkan minimal 100 item dari 30-50 struk asli, menjalankan OCR aplikasi, memberi label kategori secara manual, lalu menghitung akurasi, precision, recall, macro-F1, weighted-F1, dan confusion matrix pada data tersebut. Sampel struk nyata harus tidak digunakan sebagai data latih sebelum evaluasi selesai.

Dengan penambahan data struk nyata dan koreksi pengguna, model dapat dilatih ulang secara berkala untuk memperluas cakupan produk, merek, serta variasi kesalahan OCR yang ditemui di penggunaan sebenarnya.
