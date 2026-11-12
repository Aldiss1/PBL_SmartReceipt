# Mengukur akurasi OCR struk

Metrik "berapa item ketemu" menyembunyikan seberapa salah sisanya. Menemukan
9 dari 10 item tetap kehilangan uang, dan `SABUN LIFEBUOY 856` dihitung
"ketemu" padahal salah baca. Karena itu harness mengukur jarak teks yang
sesungguhnya.

## Cara menjalankan

Harness memakai ML Kit asli di perangkat, jadi butuh emulator/HP:

```bash
bash tool/ocr_assets.sh list          # set apa saja yang tersedia
bash tool/ocr_assets.sh run dev       # set pengembangan
bash tool/ocr_assets.sh run heldout_d # set held-out yang masih bersih
```

Skrip itu menyalakan server HTTP kecil di host, lalu `flutter test` mengunduh
fotonya ke cache aplikasi. Ini perlu karena `flutter test` **menginstal ulang
APK**, yang menghapus folder penyimpanan eksternal aplikasi — jadi menaruh foto
di perangkat lebih dulu tidak bertahan.

Foto struk **tidak dibundel ke APK**: APK rilis tidak boleh membawa ~70 MB
gambar uji. Semua pemanggilan tetap lewat `OcrService.process()` — jalur kode
yang sama dengan layar scan — lalu dibandingkan dengan `ground_truth.json` di
tiap folder. Logika penilaian bersama ada di `integration_test/ocr_harness.dart`.

## Metrik

Semua dihitung pada **field nama item**, karena itu yang dipakai untuk
mengklasifikasi kategori dan menghitung belanja.

| Metrik | Arti |
|---|---|
| `CER` | Character Error Rate — karakter yang salah / total karakter acuan |
| `WER` | Word Error Rate — kata yang salah / total kata acuan |
| `item count exact` | jumlah item sama persis dengan acuan |
| `total exact` | total rupiah sama persis dengan acuan |

Aturan penghitungan (`lib/ocr/ocr_accuracy.dart`):

- Huruf besar/kecil, spasi, dan tanda baca **bukan** error.
- Item yang hilang dihitung sebagai **deletion** sepanjang nama item itu.
- Item yang muncul tapi tidak ada di struk dihitung sebagai **insertion**.
- Karakter salah baca dihitung sebagai **substitution**.
- Angka gabungan dijumlahkan dari `edits`/`units`, bukan rata-rata persen —
  struk 3 item tidak boleh berbobot sama dengan struk 10 item.

Contoh: `SABUN LIFEBUOY 85G` terbaca `SABUN LIFEBUOY 856` → 1 edit dari 16
karakter → CER 6,3%, sedangkan metrik "ketemu" akan melaporkannya 100% benar.

## Set data

| Set | Isi | Status |
|---|---|---|
| **Dev** (`test_assets/struk/`) | 3 foto struk minimarket Indonesia + 7 struk CORD v2 test-split | dipakai saat memperbaiki parser — angkanya optimistis |
| **Held-out A** (`struk/heldout/`) | 10 struk CORD v2 validation, seed 42 | **terbakar**: 7 bug ditemukan darinya |
| **Held-out B** (`struk/heldout_b/`) | 10 struk, seed 7, tanpa set A | **terbakar**: 4 bug ditemukan darinya |
| **Held-out C** (`struk/heldout_c/`) | 10 struk, seed 2026, tanpa A+B | **terbakar**: 4 bug ditemukan darinya |
| **Held-out D** (`struk/heldout_d/`) | 10 struk, seed 2027, tanpa A+B+C | **bersih** — diukur sekali, tidak dipakai tuning |

Setiap kali set held-out dipakai untuk mencari bug, set itu harus diganti yang
baru. Sisa struk validation yang belum dipakai: **14**.

Set held-out tidak masuk git (masing-masing ~20 MB) karena bisa dibuat ulang
persis dari cache CORD:

```bash
python ML/draw_heldout_set.py --check   # pastikan isi disk = hasil undian
python ML/draw_heldout_set.py           # tulis ulang semua set
```

## Hasil

### Struk Indonesia asli (tiga foto sendiri)

Ini yang paling mendekati pemakaian nyata — minimarket, bukan restoran:

| Struk | Item | Nama ketemu | CER | WER | Total |
|---|---|---|---|---|---|
| Alfamart | 10/10 | 8/10 | **1,4%** | 10,0% | 154.000 ✓ |
| Indomaret | 10/10 | 7/10 | **2,9%** | 13,2% | 133.078 ✓ |
| Superindo (singkatan) | 10/10 | 8/10 | **3,8%** | 14,3% | 166.500 ✓ |

### Sebelum dan sesudah perbaikan (data yang sama)

| Set | Metrik | Sebelum | Sesudah |
|---|---|---|---|
| Dev (10) | CER | 14,2% | **12,3%** |
| Dev (10) | WER | 31,0% | **21,9%** |
| Dev (10) | item ketemu | 31/51 (60,8%) | **34/51 (66,7%)** |
| Held-out A (10) | CER | 34,3% | **25,4%** |
| Held-out A (10) | WER | 54,2% | **30,1%** |
| Held-out A (10) | item ketemu | 18/31 (58,1%) | **21/31 (67,7%)** |
| Held-out B (10) | CER | 36,9% | **34,4%** |
| Held-out B (10) | WER | 46,2% | **43,6%** |
| Held-out B (10) | item ketemu | 22/29 (75,9%) | 22/29 (75,9%) |
| Held-out C (10) | CER | 25,9% | **13,9%** |
| Held-out C (10) | WER | 50,0% | **32,9%** |
| Held-out C (10) | item ketemu | 25/31 (80,6%) | **26/31 (83,9%)** |
| Held-out C (10) | jumlah item tepat | 2/10 | **6/10** |

### Angka yang boleh dikutip (held-out D, diukur sekali)

| Metrik | Nilai |
|---|---|
| Item ketemu | 30 / 45 (66,7%) |
| Jumlah item tepat | 7 / 10 |
| Total tepat | 8 / 10 |
| **CER** | **18,2%** (99 edit / 544 karakter) |
| **WER** | **35,2%** (43 edit / 122 kata) |
| Akurasi per karakter | 81,8% |

Setiap set punya tingkat kesulitan berbeda — D lebih sulit daripada C
(CER 18,2% vs 13,9%) dan lebih mudah daripada B (34,4%). Jadi angka antar-set
**tidak** boleh dibandingkan; yang sah hanya sebelum/sesudah pada set yang sama.

## Bug yang ditemukan dari data held-out

| Ronde | Bug | Dampak | Perbaikan |
|---|---|---|---|
| A | `Pajak Resto 10%` / `P.Rest 10%` jadi item | item lebih | `resto`/`restoran`/`rest` masuk kosakata pajak |
| A | `Service charge` tidak dihitung | warning selisih | `service`/`svc` ikut komponen pajak |
| A | `CARD` / `Other` jadi item | item lebih | masuk kosakata pembayaran |
| A | `SUB TOTAL` terbaca `Sub Tota l` | subtotal tidak dikenali → total salah | regex toleran spasi + perbaikan korektor |
| A | `SOT0 MEDAN` (digit di akhir kata) | nama produk salah | substitusi digit→huruf sadar batas kata |
| A | Kolom qty menempel di nama (`1 Chicken Baked Rice`) | nama kotor, CER naik | awalan 1–2 digit dibuang |
| A | **`85G` berubah jadi `856` oleh korektor sendiri** | nama produk salah | token ukuran kemasan tidak lagi dianggap nominal |
| B | `PB1 10%` terbaca `PB  1 10` | baris pajak jadi item, pajak 0 | `pb\s*1` + korektor menggabung `PB 1` |
| B | `Kartu` jadi item | item lebih | `kartu` masuk kosakata pembayaran |
| B | `TOTAL` terbaca `TOTA.` | total jadi item | toleransi awalan 4 huruf pada label |
| B | `Tendered` / `EDC` / nama bank jadi item | item lebih, total salah | masuk kosakata pembayaran |
| C | `SUC CHG 6%` tidak dikenali | pajak tidak dihitung | `suc\s*chg` masuk kosakata pajak |
| C | `RESTO ITALIA` dianggap label pajak | **seluruh item hilang** | `resto` dipisah dari kosakata pajak "konklusif" |

Bug `85G → 856` penting: selama ini saya laporkan sebagai salah baca ML Kit,
padahal penyebabnya `_looksLikeAmount` yang men-substitusi `G` jadi `6`. Bukan
OCR-nya yang salah.

Bug `RESTO ITALIA` juga penting sebagai pelajaran: menambahkan `resto` ke
kosakata pajak sempat membuat nama restoran dianggap awal blok ringkasan,
sehingga daftar item dipotong sampai kosong. Sekarang ada dua daftar terpisah —
kata pajak biasa, dan kata pajak yang boleh menyimpulkan sebuah baris sendiri.

## Batas yang masih diketahui

Dari set D, yang **belum** diperbaiki dan sengaja tidak ditambal:

- **Kolom harga bergeser satu baris** (`valc_05`, `valc_09`, `vald_08`). Saat
  ML Kit memecah struk jadi kolom, harga bisa menempel ke baris berikutnya,
  sehingga item kehilangan harganya lalu dibuang. Ini masalah pelurusan
  geometri, bukan kosakata; menambalnya dengan heuristik berisiko merusak struk
  yang sudah benar.
- **Awalan qty yang menempel** (`1Prs Sop Sui Jiao`, `( R )1`) khas format
  struk restoran CORD, tidak muncul di struk minimarket Indonesia.
- **Awalan kode produk** (`4003-Blueberry Fuji`) dibiarkan karena kode itu
  memang tercetak di struk.
- **Nama label yang rusak berat** (`GRAD TOTAL`, `TUHAI`, `KEEALI` pada foto
  resolusi rendah) tetap lolos sebagai item.

## Batas data ini

- **Struk dev 1–3** adalah foto sendiri; ground truth dibaca manual dari foto.
- **Semua struk CORD** (dev 4–10, held-out A–D) berasal dari CORD v2 (lisensi
  CC-BY-4.0). Nama item acuannya adalah anotasi dataset, bukan audit manusia,
  dan struk CORD adalah struk restoran — domain berbeda dari minimarket yang
  jadi sasaran parser.
- Beberapa anotasi CORD adalah artefak: baris diskon (`Discount BCA 15%`)
  dilabeli sebagai item, dan kuantitas kadang ikut di nama (`KENTHIR 2`).
  Parser benar mengabaikannya, tetapi CER menghitungnya sebagai kesalahan.
- Gambar CORD beresolusi rendah (sebagian 432×648 px). Ketika OCR-nya sendiri
  keluar sampah (`SUS TBTAL`, `O15GONT`), itu masalah kualitas foto, bukan
  parser.

## Ukuran sampel untuk klaim yang lebih kuat

| Keperluan | Jumlah struk |
|---|---|
| Membandingkan dua versi kode (regresi) | 10–20 |
| Klaim "akurasi ≥95%" dengan interval kepercayaan layak | ≥100 |
| Menutup variasi merchant, cahaya, sudut | 30–50 per kondisi |

Foto struk asli yang baru cukup ditaruh di folder set terkait, ditambahkan ke
`ground_truth.json`, dan otomatis ikut terukur.
