# Katalog Produk Indonesia Sintetis

`katalog_produk_indonesia_v1.json` adalah katalog awal produk dan layanan umum Indonesia untuk memperluas variasi data SmartReceipt. Katalog ini dibuat untuk augmentasi terkontrol, bukan sebagai daftar lengkap seluruh produk Indonesia dan bukan sebagai data transaksi nyata.

## Generate Dataset

```powershell
python generate_catalog_dataset.py
```

Output `Dataset_Katalog_Indonesia_Sintetis_v1.csv` memakai skema yang sama dengan dataset lama dan berisi variasi nama bersih, huruf kapital, ukuran, alias format struk, tanpa spasi, teks terpotong, serta kode PLU.

## Penggunaan Yang Aman

1. Gunakan sebagai tambahan data training saja.
2. Jangan memakai metrik dari dataset sintetis sebagai klaim akurasi pada struk nyata.
3. Simpan produk atau merek nyata yang akan diuji hanya di data test nyata.
4. Tambahkan produk baru ke JSON dengan `name`, `category`, dan minimal dua `aliases` dari format struk yang benar-benar ditemukan.

## Batasan

Tidak ada dataset yang bisa memuat semua produk Indonesia secara permanen. Produk, ukuran, harga, dan nama singkat pada struk berubah terus. Katalog ini harus diperbarui dari koreksi pengguna dan hasil OCR struk nyata.
