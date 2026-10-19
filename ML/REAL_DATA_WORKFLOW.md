# Workflow Data Struk Nyata

Tujuan workflow ini adalah meningkatkan model berdasarkan teks OCR nyata tanpa membuat hasil evaluasi menjadi bias.

## 1. Kumpulkan dan Labeli Data

Gunakan file CSV UTF-8 dengan kolom berikut:

```csv
receipt_text,kategori
"INDMIE GRG SPL 85G",Makanan
"AQUA BTL 600ML",Minuman
"TOKEN PLN 50RB",Tagihan & Utilitas
```

- Salin teks item hasil OCR apa adanya, termasuk kesalahan OCR.
- Jangan simpan nama pelanggan, nomor kartu, alamat, nomor telepon, atau nomor transaksi.
- Gunakan hanya 15 label kategori yang ada pada model.
- Kumpulkan variasi toko, merek, dan kategori; target awal minimal 20 item per kategori.

## 2. Pisahkan Sebelum Training

- Simpan sekitar 20% data nyata sebagai `struk_nyata_test.csv`.
- Sisanya simpan sebagai `struk_nyata_train.csv`.
- Produk atau merek yang sama sebaiknya hanya berada pada salah satu file.
- File test tidak boleh menjadi masukan `--real`; file ini hanya untuk evaluasi akhir.

## 3. Latih dan Evaluasi

Jalankan dari folder `ML`:

```powershell
python -m pip install -r requirements.txt
python train_real_model.py --base Dataset_SmartReceipt_Sintetis.csv --catalog Dataset_Katalog_Indonesia_Sintetis_v1.csv --real struk_nyata_train.csv --real-test struk_nyata_test.csv --output model_kategori_produk_real.json
```

Flag `--catalog` menjaga pengetahuan 170 produk katalog tetap ada saat model dilatih ulang. Guard anti-kebocoran di dalam skrip otomatis membuang baris dengan produk yang tumpang tindih dengan data validation/test bila kolom `nama_produk` tersedia.

Catat metrik `REAL HELD-OUT TEST`, terutama macro-F1, bukan hanya akurasi. Tambahkan data pada kelas dengan recall atau F1 terendah.

## 4. Pasang Model Baru ke Flutter

Setelah metrik data nyata sudah layak, salin `model_kategori_produk_real.json` ke `smart_receipt/assets/model_kategori_produk.json`, lalu jalankan:

```powershell
flutter test
```

Model baru memiliki penanda `preprocessing: flutter_id_v1`. Aplikasi akan otomatis memakai preprocessing yang sama seperti saat training. Model lama tanpa penanda tetap diproses sebagai input mentah agar tidak terjadi perubahan perilaku diam-diam.

## 5. Ulangi Secara Berkala

Ekspor koreksi kategori pengguna, verifikasi labelnya, gabungkan hanya ke data train, lalu jalankan ulang evaluasi pada test set yang sama. Jangan mengubah test set ketika membandingkan model lama dan baru.
