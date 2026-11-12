# Arsip model (JANGAN dipakai di aplikasi)

Ketiga pasangan berkas di folder ini adalah artefak lama yang **tidak valid**
untuk dipakai maupun dilaporkan. Disimpan hanya sebagai jejak historis.

| Berkas | Kenapa diarsipkan |
|---|---|
| `model_kategori_produk_v2.{json,joblib}` | Dilatih dengan `preprocess()` versi notebook (bukan aturan Flutter). Hanya ~56% saat dijalankan mesin inferensi Dart. |
| `model_kategori_produk_aligned.{json,joblib}` | Ekspor ulang yang sudah diselaraskan, tetapi dilatih termasuk data uji (leaky), sehingga angkanya tidak bisa dipertanggungjawabkan. |
| `model_kategori_produk_old_copy.joblib` | Salinan `joblib` lama yang dulu diletakkan di `smart_receipt/Asset/` dan tidak dipakai kode mana pun. |

Model produksi ada di `../model_kategori_produk.json` dan dihasilkan ulang dengan:

```bash
python train_real_model.py \
  --base Dataset_SmartReceipt_Sintetis.csv \
  --catalog Dataset_Katalog_Indonesia_Sintetis_v1.csv \
  --output model_kategori_produk.json
```
