# OCR Confidence Tie-Breaker + Multi-Variant Voting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menurunkan CER OCR dengan memakai confidence ML Kit sebagai tie-breaker retry dan voting amount antar tiga varian gambar resolusi-sama.

**Architecture:** `OcrLine` mendapat field `confidence` (nullable) yang diisi dari `TextLine.confidence`. Voting per-baris amount berjalan di file baru `lib/ocr/ocr_voting.dart` sebagai fungsi murni atas `List<OcrRawResult>`, dipanggil `OcrService` saat hasil pertama lemah. Hasil voting ikut kompetisi `scoreOf` dengan kandidat lama — tidak pernah memaksa hasil lebih buruk.

**Tech Stack:** Flutter/Dart, `google_mlkit_text_recognition` 0.14.0 (tidak dinaikkan), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-05-ocr-confidence-voting-design.md`

## Global Constraints

- `confidence` dan `angle` ML Kit **null di iOS** — semua jalur baru harus no-op di sana.
- Paket `google_mlkit_text_recognition` tetap `^0.14.0`.
- Voting hanya boleh jalan saat `_isWeak(parsed)` true — struk sehat tidak boleh lebih lambat.
- Confidence hanya tie-breaker saat `scoreOf` **sama persis**; tidak ada filter baris berdasar confidence.
- Varian voting hanya yang resolusinya identik dengan prepared image: asli, `prepareBinarized`, `prepareSharpened`. Crop/perspective dikecualikan.
- Gaya kode: komentar bahasa Inggris, doc-comment menjelaskan *kenapa*, mengikuti pola file OCR yang ada.
- Semua test berjalan tanpa device (`flutter test`).

## Review Focus

- iOS / confidence null semua baris → tie-break tidak mengubah pilihan, voting tetap jalan (voting tidak butuh confidence). Test: Task 2.
- Semua varian membaca amount berbeda (3 bacaan berbeda) → pertahankan bacaan asli, jangan pilih minoritas. Test: Task 3.
- Baris amount hanya muncul di satu varian (tidak ada pasangan posisi) → tidak ada voting untuk baris itu. Test: Task 3.
- Bounding box tidak tumpang tindih (baris baru muncul di binarisasi) → tidak dipasangkan. Test: Task 3.
- `scoreOf` hasil voting lebih rendah dari kandidat lama → kandidat lama yang menang. Test: Task 4.

---

### Task 1: Field `confidence` di `OcrLine` + `averageConfidence` di `OcrRawResult`

**Files:**
- Modify: `smart_receipt/lib/ocr/ocr_raw_text.dart`
- Modify: `smart_receipt/lib/ocr/ocr_engine.dart:62-93` (`_toRawResult`)
- Test: `smart_receipt/test/ocr_raw_text_test.dart` (buat baru)

**Interfaces:**
- Produces: `OcrLine({required String text, required double left, required double top, required double right, required double bottom, double? confidence})`
- Produces: `double? get averageConfidence` pada `OcrRawResult` — rata-rata `confidence` baris yang non-null; `null` kalau tidak ada satu pun.

- [ ] **Step 1: Write the failing test**

```dart
// test/ocr_raw_text_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/ocr/ocr_raw_text.dart';

OcrLine _line(String text, {double? confidence}) => OcrLine(
      text: text, left: 0, top: 0, right: 10, bottom: 10,
      confidence: confidence,
    );

void main() {
  test('confidence defaults to null and is preserved', () {
    expect(const OcrLine(text: 'x', left: 0, top: 0, right: 1, bottom: 1).confidence, isNull);
    expect(_line('x', confidence: 0.8).confidence, 0.8);
  });

  test('averageConfidence averages non-null line confidences', () {
    final raw = OcrRawResult(lines: [_line('a', confidence: 0.6), _line('b', confidence: 0.9)], fullText: 'a\nb');
    expect(raw.averageConfidence, closeTo(0.75, 1e-9));
  });

  test('averageConfidence is null when no line has confidence', () {
    final raw = OcrRawResult(lines: [_line('a'), _line('b')], fullText: 'a\nb');
    expect(raw.averageConfidence, isNull);
  });

  test('averageConfidence ignores null lines but keeps non-null ones', () {
    final raw = OcrRawResult(lines: [_line('a'), _line('b', confidence: 0.5)], fullText: 'a\nb');
    expect(raw.averageConfidence, 0.5);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd smart_receipt && flutter test test/ocr_raw_text_test.dart`
Expected: FAIL — `confidence` bukan parameter `OcrLine`, `averageConfidence` tidak ada.

- [ ] **Step 3: Implement**

Tambahkan parameter named opsional `this.confidence` ke `OcrLine`. Tambahkan getter `averageConfidence` ke `OcrRawResult` yang memfilter baris non-null lalu merata-rata; `null` saat daftar kosong. Di `ocr_engine.dart` `_toRawResult`, teruskan `confidence: line.confidence`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd smart_receipt && flutter test test/ocr_raw_text_test.dart`
Expected: PASS

- [ ] **Step 5: Jalankan test OCR lama untuk regresi**

Run: `cd smart_receipt && flutter test test/`
Expected: PASS semua (konstruktor lama tanpa `confidence` tetap valid karena opsional).

- [ ] **Step 6: Commit**

```bash
git add smart_receipt/lib/ocr/ocr_raw_text.dart smart_receipt/lib/ocr/ocr_engine.dart smart_receipt/test/ocr_raw_text_test.dart
git commit -m "feat(ocr): propagate ML Kit line confidence into OcrLine"
```

### Task 2: Tie-breaker confidence di pemilihan hasil retry

**Files:**
- Modify: `smart_receipt/lib/ocr/ocr_service.dart:189-288` (`_retryOcr`)
- Test: `smart_receipt/test/ocr_retry_test.dart` (buat baru)

**Interfaces:**
- Consumes: `OcrRawResult.averageConfidence` dari Task 1; `ReceiptParser.scoreOf` (sudah ada).
- Produces: logika pemilihan di `_retryOcr` — fungsi kecil statis/testable `int _pickBetter(ParsedReceipt a, double? confA, ParsedReceipt b, double? confB)` yang mengembalikan 1 kalau `a` lebih baik, 2 kalau `b` lebih baik. Aturan: `scoreOf` beda → skor menang; sama persis → confidence lebih tinggi menang; confidence sama/null → kandidat pertama (eksisting) menang.

- [ ] **Step 1: Write the failing test**

Uji `_pickBetter` lewat kelas pembungkus testable. Karena `_retryOcr` privat, ekstrak logika pemilihan ke method public statis `OcrService.pickBetterResult` (atau top-level function di `ocr_service.dart`) supaya bisa diuji tanpa device. Test-nya:

```dart
// test/ocr_retry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/ocr/ocr_service.dart';
import 'package:smart_receipt/ocr/receipt_parser.dart';

ParsedReceipt _receipt(int score) {
  // Bangun receipt dengan item sehingga scoreOf(a) != scoreOf(b) mudah;
  // untuk skor sama, dua receipt identik.
  ... // gunakan ParsedReceipt dengan items kosong / sama sesuai kebutuhan
}

void main() {
  test('higher score wins regardless of confidence', () {
    // a skor lebih tinggi, b confidence lebih tinggi -> a menang
  });
  test('equal scores: higher confidence wins', () {
    // scoreOf(a) == scoreOf(b), conf 0.9 vs 0.6 -> b menang
  });
  test('equal scores, null confidence: first (existing) wins', () {
    // confA null / confB null / keduanya null -> a menang
  });
}
```

(Sertakan nilai konkret: dua `ParsedReceipt` identik untuk skor sama; untuk skor beda, tambah satu item di salah satu.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd smart_receipt && flutter test test/ocr_retry_test.dart`
Expected: FAIL — `pickBetterResult` belum ada.

- [ ] **Step 3: Implement**

Tambahkan fungsi pemilihan (public static) di `ocr_service.dart` dengan aturan Interfaces di atas. Gunakan di `_retryOcr` pada `attempt()`: simpan `bestConf` (averageConfidence raw kandidat) bersama `best`; ganti pembanding `scoreOf(retryParsed) > scoreOf(best)` dengan `pickBetterResult`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd smart_receipt && flutter test test/ocr_retry_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add smart_receipt/lib/ocr/ocr_service.dart smart_receipt/test/ocr_retry_test.dart
git commit -m "feat(ocr): break retry ties with ML Kit confidence"
```

### Task 3: Voting amount antar varian — fungsi murni `ocr_voting.dart`

**Files:**
- Create: `smart_receipt/lib/ocr/ocr_voting.dart`
- Test: `smart_receipt/test/ocr_voting_test.dart`

**Interfaces:**
- Consumes: `OcrRawResult`, `OcrLine` dari Task 1.
- Produces: `OcrRawResult voteAmounts(List<OcrRawResult> variants)` — varian pertama dianggap bacaan utama. Ekspor juga helper testable `bool linesOverlap(OcrLine a, OcrLine b, {double threshold = 0.6})` (IoU bounding box).

Perilaku (dari spec):
- Pasangkan baris antar varian dengan IoU ≥ 0.6.
- Baris adalah *amount* kalau seluruh token-nya lolos bentuk amount (`RegExp` amount sederhana `^[\d.,]+$` setelah buang prefix `Rp` dan tanda kurung — cukup untuk voting, parser tetap yang memutuskan akhirnya).
- Untuk tiap baris amount utama: kumpulkan bacaan padannya dari varian lain; kalau ≥2 dari semua varian (termasuk utama) membaca nilai sama (bandingkan string ternormalisasi: lowercase, non-alnum dibuang) → pakai mayoritas; kalau semua berbeda → pertahankan bacaan utama.
- Baris tanpa pasangan di varian lain → tidak diubah.
- Geometri & confidence baris dipertahankan dari bacaan yang dipilih; `fullText` dihitung ulang dari baris.

- [ ] **Step 1: Write the failing test**

Kasus wajib (lihat Review Focus):

```dart
// test/ocr_voting_test.dart
void main() {
  test('2 of 3 variants agree on amount -> majority wins');
  // utama "TOTAL 29.000", binarisasi "TOTAL 29.000", sharpened "TOTAL 29.0OO"
  // -> hasil "TOTAL 29.000"

  test('all three differ -> primary reading kept');
  // "5.000" / "5.100" / "5.200" -> "5.000"

  test('line with no positional match is untouched');
  // baris hanya ada di utama -> teks sama

  test('non-overlapping new line in variant is not merged in');
  // binarisasi punya baris ekstra tanpa pasangan -> tidak muncul di hasil

  test('non-amount lines are never voted');
  // "INDOMIE GORENG" vs "INDOMIE GOREBG" -> tetap bacaan utama

  test('overlap uses IoU >= 0.6');
  // linesOverlap: kotak identik true; kotak jauh false; geser sedikit true
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd smart_receipt && flutter test test/ocr_voting_test.dart`
Expected: FAIL — file belum ada.

- [ ] **Step 3: Implement `ocr_voting.dart`**

Fungsi murni, tanpa I/O. Struktur: untuk tiap baris utama → cari pasangan per varian (IoU max satu pasangan terbaik) → jika baris amount, kumpulkan suara → tulis hasil. Tidak perlu algoritma khusus selain yang test tentukan.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd smart_receipt && flutter test test/ocr_voting_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add smart_receipt/lib/ocr/ocr_voting.dart smart_receipt/test/ocr_voting_test.dart
git commit -m "feat(ocr): per-line amount voting across same-resolution variants"
```

### Task 4: Integrasi voting + pass sharpened ke `OcrService._retryOcr`

**Files:**
- Modify: `smart_receipt/lib/ocr/ocr_service.dart` (`_retryOcr`)
- Test: `smart_receipt/test/ocr_service_voting_test.dart` (buat baru, pakai `OcrEngine` fake yang sudah ada polanya di test lama; kalau belum ada fake, buat `FakeOcrEngine` di file test)

**Interfaces:**
- Consumes: `voteAmounts` dari Task 3; `prepareSharpened`, `prepareBinarized` dari `image_quality.dart`; `pickBetterResult` dari Task 2.
- Produces: alur `_retryOcr` baru — strategi lama tetap; setelah strategi lama, jika masih `_isWeak(best)`: jalankan OCR pada `prepareSharpened` dan `prepareBinarized`, bentuk `List<OcrRawResult>` [utama, sharpened, binarisasi] (raw utama = hasil pass pertama yang sudah dikoreksi), panggil `voteAmounts`, parse hasilnya, dan masuk kompetisi `pickBetterResult` seperti kandidat lain.

- [ ] **Step 1: Write the failing test**

Fake engine mengembalikan teks berbeda per path (deteksi via nama file `sharpened`/`binarized`), preprocessor fake menulis file jpg kecil ke disk (gambar 10×10 putih via `package:image`). Test:

```dart
test('weak first pass triggers voting and majority amount is used', ...);
// pass1 amount salah "29.OOO" (korektor biarkan), sharpened & binarized benar "29.000"
// -> parsed final punya amount mayoritas; verifikasi lewat raw.lines teks atau parsed.total

test('voted result loses to existing best -> existing kept', ...);
// voting menghasilkan parse dengan scoreOf lebih rendah -> best tidak berubah

test('healthy first pass never runs extra OCR', ...);
// _isWeak false -> engine.recognize hanya dipanggil sekali (hitung panggilan)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd smart_receipt && flutter test test/ocr_service_voting_test.dart`
Expected: FAIL — voting belum dipanggil di `_retryOcr`.

- [ ] **Step 3: Implement di `_retryOcr`**

Setelah strategi 1–3 lama, tambah blok: `if (_isWeak(best))` → siapkan kedua varian (try/catch, gagal = lewati pass itu; varian gagal tidak ikut voting, voting tetap valid dengan 2 varian), OCR keduanya, `voteAmounts([bestRaw, sharpenedRaw, binarizedRaw])`, `correctOcrText` dihasilkan sebelum masuk voting (konsisten dengan jalur lama), parse, `pickBetterResult`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd smart_receipt && flutter test test/ocr_service_voting_test.dart`
Expected: PASS

- [ ] **Step 5: Jalankan seluruh unit test**

Run: `cd smart_receipt && flutter test test/`
Expected: PASS semua.

- [ ] **Step 6: Commit**

```bash
git add smart_receipt/lib/ocr/ocr_service.dart smart_receipt/test/ocr_service_voting_test.dart
git commit -m "feat(ocr): three-variant amount voting in weak-scan retry path"
```

### Task 5: Verifikasi harness on-device + catat hasil

**Files:**
- Modify: `smart_receipt/OCR_TESTING.md` (tambah baris hasil)

**Interfaces:**
- Consumes: `tool/ocr_assets.sh` (sudah ada), set dev + held-out yang ada di disk.

- [ ] **Step 1: Jalankan harness dev**

Run: `bash tool/ocr_assets.sh run dev`
Expected: ringkasan CER/WER tercetak. Catat angkanya.

- [ ] **Step 2: Jalankan satu set held-out yang tersedia di disk**

Run: `bash tool/ocr_assets.sh list` lalu `bash tool/ocr_assets.sh run <set>`
Expected: CER/WER. Kriteria sukses dari spec: CER turun atau setara, total exact tidak turun.

- [ ] **Step 3: Catat hasil sebelum/sesudah di `OCR_TESTING.md`**

Tambahkan baris di tabel "Sebelum dan sesudah" dengan label commit ini, gaya sama dengan baris yang ada.

- [ ] **Step 4: Commit**

```bash
git add smart_receipt/OCR_TESTING.md
git commit -m "docs(ocr): record voting+confidence accuracy results"
```
