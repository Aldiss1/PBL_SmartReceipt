# Penilaian Dataset OCR Struk Belanja

Sumber: Roboflow Universe, OCR Struk Belanja v2i, lisensi CC BY 4.0.

## Isi Dataset

| Split | Gambar | Anotasi | Area `item_belanja` |
|---|---:|---:|---:|
| Train | 539 | 2.143 | 531 |
| Valid | 155 | 618 | 154 |
| Test | 77 | 308 | 77 |
| Total | 771 | 3.069 | 762 |

Kelas anotasi COCO: `struk_belanja`, `info_toko`, `item_belanja`, dan `total`. Hampir setiap gambar memiliki satu bounding box untuk masing-masing area. File anotasi hanya menyimpan `bbox`, `segmentation`, dan identitas kelas; tidak ada nilai teks, nama produk, atau kategori pengeluaran.

## Dapat Digunakan Untuk

1. Melatih atau mengevaluasi *object detector* untuk menemukan area struk, informasi toko, area item, dan total.
2. Memotong area `item_belanja` sebelum dikirim ke ML Kit OCR. Ini mengurangi kemungkinan OCR membaca header toko, total, atau informasi pembayaran sebagai item belanja.
3. Menguji ketahanan proses deteksi pada 77 gambar test tanpa melatih pada split tersebut.

Jalankan utilitas berikut dari folder `ML` untuk membuat metadata crop area item:

```powershell
python export_receipt_item_manifest.py
```

Hasilnya adalah `receipt_item_crops.json`, berisi path gambar, ukuran gambar, dan bounding box `item_belanja` untuk seluruh split.

## Tidak Dapat Digunakan Langsung Untuk

Dataset ini tidak dapat langsung digunakan untuk melatih model TF-IDF + Naive Bayes SmartReceipt karena tidak memiliki:

- transkripsi OCR per baris item;
- label kategori pengeluaran seperti `Makanan` atau `Minuman`;
- bounding box per nama produk individual.

Untuk meningkatkan classifier kategori, setiap item hasil OCR masih harus diberi label ke salah satu dari 15 kategori. Untuk meningkatkan OCR karakter, gambar atau crop harus memiliki *ground-truth transcription*.

## Langkah Implementasi Yang Tepat

1. Gunakan atau latih detector dari dataset ini untuk mendeteksi `item_belanja`.
2. Crop hanya area item pada gambar struk.
3. Jalankan Google ML Kit pada crop tersebut.
4. Ambil setiap baris item yang valid dan labeli kategorinya secara manual.
5. Simpan pasangan `receipt_text,kategori` sebagai data nyata, lalu latih ulang dengan `train_real_model.py`.

Detector area item dan classifier kategori adalah dua model berbeda. Dataset ini menyelesaikan bagian pertama, tetapi data berlabel kategori tetap diperlukan untuk memperbaiki bagian kedua.
