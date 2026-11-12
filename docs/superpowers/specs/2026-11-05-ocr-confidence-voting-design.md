# Desain: Confidence ML Kit sebagai Tie-Breaker + Multi-Variant Voting

Tanggal: 2026-11-05
Status: disetujui (2026-11-12) — diimplementasikan sesuai scope spec ini
      (voting amount + tie-breaker confidence). Perluasan voting ke nama item
      disengaja di luar scope ini; pertimbangkan sebagai follow-up terpisah.

Catatan implementasi (2026-11-12): `prepareSharpened` dihapus dari
`image_quality.dart` pada commit d76be49 (dead code — satu-satunya calon
pemakainya adalah fitur ini yang belum disetujui). Method itu (49 baris)
harus dikembalikan, misalnya dari `git show d76be49^:smart_receipt/lib/ocr/image_quality.dart`,
sebelum voting diimplementasikan.

## Intent & why

Akurasi OCR held-out D masih CER 18,2% (akurasi karakter 81,8%). Dua sumber
kehilangan akurasi yang belum dimanfaatkan:

1. **Confidence per-baris dari ML Kit dibuang total.** `MlKitOcrEngine`
   hanya menyimpan teks + bounding box. `TextLine.confidence` (double?)
   tersedia di Android, `null` di iOS (versi paket 0.14.0, terverifikasi
   di sumber paket).
2. **Retry OCR memilih satu hasil terbaik, bukan menggabungkan bukti.**
   Saat hasil pertama lemah (`_isWeak`), pipeline mencoba varian gambar
   lalu memilih skor parse tertinggi. Amount yang terbaca konsisten di
   beberapa varian tidak mendapat bobot lebih.

## Goals

- Amount yang hilang di foto pudar lebih sering tertolong oleh voting
  antar varian.
- Dua hasil retry dengan skor parse sama diputuskan oleh confidence,
  bukan urutan eksekusi.
- Perilaku tidak pernah lebih buruk dari sekarang (confidence null /
  iOS / varian gagal → jalur lama).

## Non-goals

- Tidak mengganti scoring `scoreOf(parsed)` dengan confidence.
- Tidak membuang baris berdasarkan ambang confidence (berisiko buang
  item asli).
- Tidak menyentuh varian crop/perspective (geometri bergeser, tidak
  bisa dipetakan 1:1).
- Tidak menambah varian OCR baru; `prepareSharpened` sudah ada.

## Anti-goals

- Regresi pada set dev/held-out mana pun.
- Waktu scan naik untuk struk yang sudah terbaca baik (voting hanya
  jalan saat `_isWeak`).

## Pendekatan (dipilih setelah diskusi)

Dua pendekatan per topik dipertimbangkan; yang dipilih:

### 1. Confidence = tie-breaker saja (bukan sinyal utama)

- `OcrLine` dapat field baru `confidence` (`double?`), diisi dari
  `TextLine.confidence`.
- `OcrRawResult` dapat getter `averageConfidence` (rata-rata baris yang
  punya confidence; `null` kalau tidak ada).
- Di `_retryOcr`, jika `scoreOf` dua kandidat **sama persis**, pilih
  yang `averageConfidence` lebih tinggi. Jika confidence tidak
  tersedia di salah satu/keduanya → pertahankan urutan lama.

Alternatif yang ditolak:
- *Confidence sebagai sinyal utama*: tidak reliable (Android cluster
  0.5–0.9, iOS null), berisiko regresi.
- *Filter baris confidence rendah*: berisiko buang item asli.

### 2. Voting amount antar varian resolusi-sama (asli + binarisasi + sharpened)

Saat `_isWeak(parsed)` true, selain strategi retry lama (perspective,
crop, binarisasi — tetap berjalan seperti sekarang), pipeline menjalankan
**dua pass tambahan** pada varian resolusi-identik:

- `prepareSharpened(preparedPath)` (baru dipanggil; fungsinya sudah ada).
- `prepareBinarized(preparedPath)` (sudah dipanggil di retry lama; hasil
  raw-nya kini ikut dipakai untuk voting, bukan hanya untuk `scoreOf`).

Voting dilakukan **per baris amount**:

- Baris dipasangkan antar hasil dengan IoU bounding box ≥ 0.6 dan teks
  dinormalisasi (huruf kecil, tanpa non-alnum) dibandingkan.
- Untuk setiap kelompok baris yang cocok secara posisi: jika ≥2 dari 3
  varian membaca **amount** yang sama → amount itu dikunci pada baris
  hasil utama; jika semua berbeda → pertahankan bacaan utama (asli).
- Nama produk tidak disentuh voting (korektor teks sudah menanganinya).

Hasil voting menjadi satu `OcrRawResult` gabungan yang ikut kompetisi
`scoreOf` bersama kandidat lama — jadi voting tidak pernah memaksa
hasil yang lebih buruk.

Alternatif yang ditolak:
- *Voting penuh per-karakter lintas semua varian (termasuk crop)*:
  koordinat crop bergeser, pemetaan mahal dan rapuh.
- *OCR ulang varian sama dua kali*: ML Kit on-device deterministik,
  hasilnya identik — sia-sia.

## Constraints

- Flutter/Dart, paket `google_mlkit_text_recognition` 0.14.0 (tidak
  dinaikkan).
- `confidence` & `angle` null di iOS → semua jalur baru harus no-op
  di sana.
- Waktu tambahan hanya saat struk lemah: maks +2 pass OCR
  (~2× waktu pass tunggal) pada kasus itu saja.
- Gaya kode mengikuti pola file yang ada (komentar bahasa Inggris,
  doc-comment menjelaskan *kenapa*).

## Keputusan yang diambil pengguna

- Confidence hanya tie-breaker, bukan sinyal utama (alasan: null di
  iOS, tidak boleh lebih buruk dari sekarang).
- Pengguna mendelegasikan pilihan varian ke asisten → 3 pass
  (asli + binarisasi + sharpened).

## Yang masih terserah builder

- Detail struktur data voting (kelas kecil `_LineVote` atau fungsi
  murni) — bebas asal unit-testable.
- Posisi fungsi voting: file baru `lib/ocr/ocr_voting.dart` atau di
  dalam `ocr_service.dart` — builder putuskan berdasarkan ukuran.
- Urutan pass & toleransi IoU — boleh disetel saat implementasi
  berdasarkan unit test.

## Verifikasi

- Unit test: voting murni (dummy `OcrRawResult`), tie-break confidence,
  no-op saat confidence null. Tanpa device.
- Integration: harness `tool/ocr_assets.sh run dev` + satu set held-out
  yang masih tersedia di disk, bandingkan CER/WER sebelum vs sesudah
  pada set yang sama. Harapan: CER turun atau minimal setara; total
  exact tidak turun.
