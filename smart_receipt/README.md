# Smart Receipt

Aplikasi Flutter untuk memindai struk belanja, mengekstrak item dan total,
mengklasifikasi kategori produk, lalu menyimpan transaksi secara lokal.

Dokumen proyek (proposal, SKPL, desain) ada di [`Document/`](../Document/).
Pipeline pelatihan model ada di [`ML/`](../ML/).

## Platform

Android dan iOS saja. OCR memakai `google_mlkit_text_recognition`, yang hanya
tersedia untuk kedua platform itu; scaffolding web/desktop sudah dihapus.

## Struktur

```
lib/
  data/          adapter model database (receipt_model) ke model UI (models)
  helpers/       akses SQLite
  models/        model data, kategori, transaksi
  navigation/    rute dan transisi halaman
  ocr/           mesin OCR, koreksi teks, parser struk, klasifikasi, metrik
  providers/     state management (Provider)
  screens/       satu file per layar
  services/      klasifikasi ML, penyimpanan foto, analitik, evaluasi model
  theme/         palet warna dan controller tema
  widgets/       widget yang dipakai lintas layar

assets/          model klasifikasi + kamus normalisasi (dibundel ke APK)
test/            unit test dan widget test
integration_test/ harness OCR on-device
tool/            skrip bantu (lihat di bawah)
```

## Menjalankan

```bash
flutter pub get
flutter run
```

## Test

```bash
flutter test                              # unit + widget test
flutter analyze lib test integration_test
```

Mengukur akurasi OCR butuh emulator/HP karena memakai ML Kit asli:

```bash
bash tool/ocr_assets.sh list
bash tool/ocr_assets.sh run dev
```

Detail metrik, angka akurasi, dan batas datanya ada di
[`OCR_TESTING.md`](OCR_TESTING.md).

## Menjaga repo tetap ringan

`flutter run` / `flutter test` / `flutter build` menulis 1–2 GB ke `build/`
dan `.dart_tool/`. Keduanya di-`.gitignore`, jadi aman dihapus kapan saja:

```bash
bash tool/clean.sh          # artefak Flutter
bash tool/clean.sh --all    # + Pods iOS dan cache Python
```

Yang sengaja tidak dihapus: `assets/`, `test_assets/struk/`, dan
`ML/.cord_cache/` — yang terakhir adalah sumber data held-out dan tidak bisa
dibuat ulang tanpa mengunduh CORD lagi.
