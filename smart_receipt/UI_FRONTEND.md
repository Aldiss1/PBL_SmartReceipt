# Smart Receipt — Dokumentasi Frontend & UI

Dokumen ini memetakan seluruh lapisan tampilan aplikasi **Smart Receipt**: widget kustom, widget Flutter/Material yang dipakai, design system, navigasi, dan pola UI per layar. Semua nama kelas dan file mengacu pada kode di `lib/`.

---

## 1. Ringkasan

| Aspek | Keterangan |
| --- | --- |
| Framework | Flutter (Material 3, `useMaterial3: true`) |
| Bahasa UI | Indonesia (string di-hardcode, belum ada `intl`/ARB) |
| Orientasi | Mobile-first, layout satu kolom, tanpa breakpoint tablet/desktop |
| State management | `provider` (`ChangeNotifierProvider<ReceiptProvider>`) + `StatefulWidget` lokal |
| Tema | Palet statis `AppColors` (light/dark) + `ThemeController` persisten via `shared_preferences` |
| Grafik | Digambar sendiri dengan `CustomPaint` (paket `fl_chart` ada di `pubspec.yaml` tetapi tidak dipakai) |
| Font | Font bawaan platform (tidak ada `fonts:` di `pubspec.yaml`) |
| Navigasi | `Navigator` imperatif + `InstantPushPageRoute` (push instan, pop beranimasi) |
| Shell utama | Bottom navigation mengambang (`AppBottomNav`) dengan tombol Scan di tengah |

Total ada **13 file layar** di `lib/screens/` dan **3 file widget bersama** di `lib/widgets/`.

---

## 2. Peta folder UI

```
lib/
├── main.dart                     # MaterialApp, tema, provider, route awal
├── theme/
│   ├── app_colors.dart           # AppPalette (light/dark) + AppColors (akses aktif)
│   └── theme_controller.dart     # ThemeController, ThemeScope, persistensi
├── navigation/
│   ├── app_nav.dart              # navigateTab(), openScan()
│   └── app_route.dart            # InstantPushPageRoute + appRoute()
├── widgets/
│   ├── app_widgets.dart          # widget bersama (top bar, tombol, chip, bottom nav)
│   ├── charts.dart               # TrendLineChart (CustomPainter)
│   └── receipt_mock.dart         # placeholder kertas struk
└── screens/
    ├── splash_screen.dart
    ├── home_dashboard.dart
    ├── scan_receipt.dart
    ├── ocr_processing.dart
    ├── category_classification.dart
    ├── review_transaction.dart
    ├── transaction_saved.dart
    ├── transaction_history.dart
    ├── transaction_detail.dart
    ├── analysis.dart
    ├── spending_prediction.dart
    ├── settings.dart
    └── empty_state.dart
```

---

## 3. Design system

### 3.1 Palet warna

Dua palet lengkap didefinisikan sebagai konstanta di `AppPalette` (`lib/theme/app_colors.dart`):

- **Light** — disampel dari desain `01 - Home Dashboard.png`: latar `#F9F9FF`, kartu putih, navy `#131A33`, aksen oranye `#FEA619`.
- **Dark** — bergaya Instagram dark mode: kanvas hitam murni `#000000`, permukaan `#1C1C1C`, teks putih, dan gradien logo Instagram.

Widget **tidak** membaca `Theme.of(context)`. Semua warna diambil dari getter statis `AppColors`, yang menunjuk ke palet aktif.

Token yang paling sering dipakai:

| Token | Light | Dark | Kegunaan |
| --- | --- | --- | --- |
| `bg` | `#F9F9FF` | `#000000` | Latar Scaffold |
| `card` | `#FFFFFF` | `#1C1C1C` | Permukaan kartu, nav bar, sheet |
| `border` | `#EDEFF7` | `#262626` | Garis pemisah, outline |
| `textDark` | `#151C27` | `#FFFFFF` | Teks utama |
| `textLabel` | `#5B6472` | `#C7C7C7` | Teks sekunder terang |
| `textMuted` | `#8A8D97` | `#A8A8A8` | Teks tersier, hint |
| `navy` | `#131A33` | `#0095F6` | Aksen brand, progress, ikon aktif |
| `orange` | `#FEA619` | `#FA7E1E` | Aksen utama, badge, bar teratas |
| `amber` | `#8C5D10` | `#FCAF45` | Ikon/link aksi ("Lihat Semua") |
| `green` | `#009668` | `#78DE45` | Status valid/sukses |
| `red` | `#E5484D` | `#ED4956` | Aksi destruktif, error |
| `buttonBg` / `onButton` | `#131A33` / putih | `#FEA619` / `#2A1B00` | Tombol primer & chip aktif |
| `iconBox` | `#E7EEFE` | `#262626` | Latar kotak ikon |
| `track` | `#E7EEFE` | `#363636` | Track progress bar/switch |

Token pendukung lain: `lavender`, `promoBg`, `chipText`, `redSoft`, `greenSoft`, `amberSoft`, `orangeSoft`, `iconMuted`, `heroTrack`, `switchActive`, `onNavy`, dan `categoryColors` (9 warna, satu per kategori).

**Gradien** yang dipakai:

| Token | Pemakaian |
| --- | --- |
| `heroGradient` | Didefinisikan di palet tetapi belum dipakai layar mana pun |
| `viewfinderGradient` | Bingkai kamera di `scan_receipt.dart` |
| `panelGradient` | Panel preview gambar di `ocr_processing.dart` |
| `brandGradient` / `brandSolid` | Tile logo di splash screen |
| `spendBannerGradient` / `spendBanner` | Banner "Pengeluaran Bulan Ini", kartu total analisis, kartu prediksi, header detail transaksi |

`spendBannerGradient` hanya terisi di palet light; palet dark memakai `spendBanner` solid oranye. Pola pemakaiannya selalu:

```dart
color: AppColors.spendBanner,
gradient: AppColors.spendBannerGradient == null ? null : LinearGradient(...),
```

### 3.2 Warna kategori

`AppColors.palette.categoryColors` berisi 9 warna yang dipetakan berurutan ke `kAppCategories`:

| # | Kategori | Light | Dark |
| --- | --- | --- | --- |
| 1 | Makanan | `#FEA619` | `#FA7E1E` |
| 2 | Minuman | `#4C8DF6` | `#0095F6` |
| 3 | Rumah Tangga | `#8C5D10` | `#FCAF45` |
| 4 | Perawatan Diri | `#B45BCB` | `#962FBF` |
| 5 | Kesehatan | `#009668` | `#78DE45` |
| 6 | Transportasi | `#3D445C` | `#4F5BD5` |
| 7 | Elektronik | `#5B6472` | `#D62976` |
| 8 | Pakaian | `#DB6B8C` | `#ED4956` |
| 9 | Lainnya | `#8A8D97` | `#A8A8A8` |

Warna avatar memakai daftar tetap `AppColors.avatarColors` dan fungsi deterministik `avatarColor(seed)`, sehingga avatar "Rian Pratama" selalu mendapat warna yang sama di light maupun dark mode.

### 3.3 Skala radius

| Nilai | Dipakai untuk |
| --- | --- |
| 4–8 | Progress bar, chip kecil, sel matriks, divider pil |
| 10–16 | Kartu list, tombol, search field, kotak ikon |
| 18–22 | Kartu panel, banner, kartu statistik |
| 24–26 | Bingkai kamera, bottom sheet |
| 30–33 | Tile logo, pill bottom nav |
| `CircleBorder` | Avatar, tombol ikon bulat, tombol Scan |

### 3.4 Skala spacing

- Padding horizontal layar: **22** (konsisten di hampir semua screen).
- Jarak antar-blok: **12 / 14 / 16 / 18 / 20**.
- Padding bawah scroll: `24 + AppBottomNav.clearance(context)` pada layar bertab.
- Padding vertikal tombol: 14–15; padding kartu: 14–20.

### 3.5 Tipografi

Tidak ada font kustom. Skala yang benar-benar dipakai:

| Peran | Ukuran | Weight |
| --- | --- | --- |
| Nominal besar (total, prediksi) | 30–32 | `w800` |
| Judul layar | 20 | `w700` |
| Judul section | 15–16 | `w700` |
| Isi kartu / nama toko | 13.5–15 | `w600`–`w700` |
| Body / deskripsi | 12.5–13 | `w400` |
| Caption, label, hint | 10.5–12 | `w400`–`w600` |
| Mikro-label (matriks, chip dense) | 9.5–10.5 | `w500`–`w700` |

Detail kecil: wordmark splash memakai `letterSpacing: 6`, label "DASHBOARD FINANSIAL" memakai `letterSpacing: 0.6`, dan penampil OCR memakai `fontFamily: 'monospace'`.

### 3.6 Format angka & tanggal

Didefinisikan di `lib/models/models.dart`:

- `rupiah(int)` → `Rp1.420.000` (pemisah titik manual, tanpa `intl`).
- `formatDate(DateTime)` → `13 Sep 2026`.
- `formatDateTime(DateTime)` → `13 Sep 2026 • 19:14`.

### 3.7 Ikon

Seluruh ikon berasal dari `Icons.*` (Material Icons). Pemetaan kategori → ikon ada di `models.dart`:

| Kategori | Ikon |
| --- | --- |
| Makanan | `restaurant` |
| Minuman | `local_cafe_outlined` |
| Rumah Tangga | `home_outlined` |
| Perawatan Diri | `spa_outlined` |
| Kesehatan | `medical_services_outlined` |
| Transportasi | `directions_car_outlined` |
| Elektronik | `devices_other_outlined` |
| Pakaian | `checkroom_outlined` |
| Lainnya | `category_outlined` |

---

## 4. Tema dan mekanisme repaint

Alur tema:

```
themeController.load()            # baca shared_preferences sebelum runApp
        ↓
AppColors.apply(AppPalette.x)     # palet aktif disimpan sebagai static
        ↓
ThemeController.notifyListeners() # listener di main.dart & settings.dart
        ↓
ThemeScope.watch(context)         # layar mendaftar sebagai dependen
        ↓
setState → build ulang           # Scaffold diberi ValueKey<AppPalette>
```

Poin penting:

1. **`ThemeScope`** (`InheritedNotifier<ThemeController>`) bukan sumber warna; ia hanya alat agar `build()` layar ikut dijalankan ulang. Setiap layar memanggil `ThemeScope.watch(context)` di awal `build`.
2. **`ValueKey<AppPalette>(AppColors.palette)`** pada `Scaffold` memaksa subtree dibuang dan dibangun ulang saat palet berganti. Ini kompensasi karena warna dibaca dari variabel statis, bukan dari `InheritedWidget`.
3. **`ThemeMode.system` adalah default.** Pilihan eksplisit pengguna (light/dark) disimpan ke `shared_preferences` dengan key `theme_mode` dan bertahan setelah restart.
4. `SmartReceiptApp` mengimplementasikan `WidgetsBindingObserver` untuk menangkap `didChangePlatformBrightness`, sehingga mode sistem ikut berubah secara live.

---

## 5. Navigasi dan shell layar

### 5.1 `AppBottomNav`

Bottom navigation kustom yang mengambang (`lib/widgets/app_widgets.dart`), terdiri dari:

- Kontainer pil setinggi **66** dengan radius **33**, border, dan shadow.
- 5 slot: **Beranda (0), Riwayat (1), Scan (2), Analisis (3), Pengaturan (4)**.
- Slot index 2 bukan tab, melainkan tombol kamera bulat 56 px yang diletakkan di `Positioned(top: 0)` sehingga menonjol ke atas.
- Konstanta tinggi: `_padTop = 10`, `_bodyHeight = 84`, `_padBottom = 14` → `AppBottomNav.height = 108`.
- `AppBottomNav.clearance(context)` = tinggi nav + `MediaQuery.padding.bottom`, dipakai sebagai bottom padding scroll agar konten tidak tertutup.

### 5.2 `FloatingNavBody`

```dart
Stack(
  children: [
    Positioned.fill(child: child),                    // konten layar
    Positioned(left: 0, right: 0, bottom: 0, child: nav),
  ],
)
```

Konten dapat "mengalir" di belakang nav, bukan dipotong di atasnya. Dipakai oleh Beranda, Riwayat, Analisis, Pengaturan, dan Empty State.

### 5.3 `navigateTab` dan `openScan`

`lib/navigation/app_nav.dart`:

- `navigateTab(context, index)` → `Navigator.pushReplacement` ke layar tab yang dituju. Karena memakai `pushReplacement`, stack tidak menumpuk, tetapi state tab lama ikut dibuang dan tombol back tidak kembali ke tab sebelumnya.
- `openScan(context)` → `Navigator.push` ke `ScanReceiptScreen`.

### 5.4 `InstantPushPageRoute`

`appRoute()` membungkus `InstantPushPageRoute`: `transitionDuration = 0` saat push, sedangkan `reverseDuration` dikembalikan ke durasi normal agar animasi **pop** tetap terlihat. Hampir semua perpindahan layar memakai ini. Pengecualian: `ocr_processing.dart` menuju `CategoryClassificationScreen` memakai `MaterialPageRoute` biasa.

### 5.5 Route bernama

`main.dart` mendaftarkan `'/scan'`, tetapi seluruh pemanggilan scan memakai `openScan()` (route langsung). Route bernama tersebut saat ini tidak pernah dipakai.

---

## 6. Widget kustom

### 6.1 `lib/widgets/app_widgets.dart`

| Widget | Jenis | Fungsi | Dipakai di |
| --- | --- | --- | --- |
| `AppStatusBar` | `StatelessWidget` | Placeholder status bar. Saat ini **tidak menggambar apa pun** (hanya `Padding` nol); parameter `time` tidak dipakai | Semua layar kecuali Splash |
| `AppTopBar` | `StatelessWidget` | Judul + subtitle opsional, tombol back opsional, daftar `actions` di kanan | Semua layar kecuali Splash dan Transaksi Tersimpan |
| `CircleIconButton` | `StatelessWidget` | Tombol ikon bulat 40×40 dengan `Material` + `InkWell` | Back, refresh, edit, delete |
| `SectionHeader` | `StatelessWidget` | Bar aksen oranye 6×20 + judul + widget `trailing` | Analisis, Review, Detail, Klasifikasi |
| `PrimaryButton` | `StatelessWidget` | Tombol utama `Material` + `InkWell`, bisa ikon, melebar penuh, disabled otomatis jadi 40% opacity | Scan, Review, Klasifikasi, Prediksi, Detail, Saved, Empty State |
| `SecondaryButton` | `StatelessWidget` | Tombol outline dengan border `AppColors.border` | Scan, Review, OCR gagal, Saved |
| `CategoryChip` | `StatelessWidget` | Pil kategori: ikon + nama, warna 14% alpha, mode `dense` | Review, Riwayat, Klasifikasi |
| `IconBox` | `StatelessWidget` | Kotak ikon bersudut (`size * 0.27`), warna & latar dapat di-override | Review, Riwayat, Detail, Klasifikasi, Settings |
| `AppBottomNav` | `StatelessWidget` | Bottom nav mengambang + tombol Scan tengah | Beranda, Riwayat, Analisis, Pengaturan, Empty State |
| `FloatingNavBody` | `StatelessWidget` | `Stack` yang menaruh nav di atas konten full-bleed | Layar bertab |
| `_NavItem` | privat | Satu slot nav: ikon + label, status aktif | Internal `AppBottomNav` |
| `_ScanButton` | privat | Lingkaran putih 56 px berisi tombol kamera 46 px | Internal `AppBottomNav` |

Catatan implementasi:

- `AppTopBar` memakai `Expanded` untuk judul dan `maxLines: 1` + ellipsis, jadi judul panjang tidak mendorong aksi keluar layar.
- `PrimaryButton` menentukan state disabled dari `onPressed == null` (bukan parameter terpisah).
- `SectionHeader` memakai null-aware element `?trailing` (fitur Dart terbaru) agar slot kanan opsional tanpa `if`.

### 6.2 `lib/widgets/charts.dart`

| Widget | Jenis | Fungsi |
| --- | --- | --- |
| `TrendLineChart` | `StatelessWidget` | `CustomPaint` setinggi 150 (default) + baris label bulan di bawah |
| `_LinePainter` | `CustomPainter` | Menggambar 4 garis grid, area gradient di bawah kurva, garis polyline, dan titik per data |

Perilaku visual:

- Nilai maksimum diskalakan `* 1.2` agar puncak tidak menempel di tepi atas.
- Area di bawah kurva memakai gradient warna garis dari alpha 0.22 → 0.
- Titik terakhir dapat ditebalkan dan diwarnai oranye lewat `highlightLast: true`.
- `shouldRepaint` membandingkan `values`, `color`, dan `highlightLast`.
- Jika `values.length < 2`, tidak ada yang digambar.

Dipakai di `analysis.dart` (tren 6 bulan) dan `spending_prediction.dart` (aktual + prediksi).

### 6.3 `lib/widgets/receipt_mock.dart`

`ReceiptMock` — ilustrasi kertas struk dari `Container` dan bar-bar abu-abu, lengkap dengan "barcode" dari 16 garis. Dipakai sebagai placeholder di bingkai kamera (`scan_receipt.dart`) dan preview OCR saat file gambar tidak tersedia (`ocr_processing.dart`).

---

## 7. Daftar layar

| # | Layar | File | State | Peran |
| --- | --- | --- | --- | --- |
| 1 | Splash | `splash_screen.dart` | Stateful | Logo, animasi masuk, auto ke Beranda setelah 1,8 dtk |
| 2 | Beranda | `home_dashboard.dart` | Stateless | Ringkasan bulan ini, kategori, transaksi terbaru |
| 3 | Scan Struk | `scan_receipt.dart` | Stateful | Ambil foto kamera/galeri |
| 4 | Proses OCR | `ocr_processing.dart` | Stateful | Progress pipeline + hasil teks mentah |
| 5 | Klasifikasi | `category_classification.dart` | Stateful | Prediksi kategori per item + confidence |
| 6 | Review | `review_transaction.dart` | Stateful | Koreksi item/kategori lalu simpan |
| 7 | Tersimpan | `transaction_saved.dart` | Stateless | Konfirmasi sukses |
| 8 | Riwayat | `transaction_history.dart` | Stateful | Cari + filter + daftar struk |
| 9 | Detail | `transaction_detail.dart` | Stateless | Rincian item & total |
| 10 | Analisis | `analysis.dart` | Stateful | Periode, kategori, evaluasi model, tren |
| 11 | Prediksi | `spending_prediction.dart` | Stateless | Regresi linear + metrik |
| 12 | Pengaturan | `settings.dart` | Stateful | Tema, preferensi, dataset ML |
| 13 | Empty State | `empty_state.dart` | Stateless | Komponen kosong reusable + versi layar penuh |

### 7.1 Splash (`splash_screen.dart`)

- `Stack` dengan konten tengah dan footer di bawah.
- `_LogoMark`: tile 104×104, radius 30, gradient brand (light) atau solid oranye (dark), ikon `document_scanner_outlined` + titik oranye.
- `_LogoWordmark`: `Text.rich` "Smart" (putih/hitam) + "Receipt" (oranye), lalu label "ANALYZER" dengan letter spacing 6.
- Animasi: `TweenAnimationBuilder<double>` 0.8 → 1 dengan `Curves.easeOutBack`, dibungkus `Opacity`.
- Footer: `CircularProgressIndicator` 26 px + teks "Politeknik Negeri Malang • 2026".
- Navigasi: `Future.delayed(1800 ms)` → `navigateTab(context, 0)`.

### 7.2 Beranda (`home_dashboard.dart`)

Susunan `SingleChildScrollView`:

1. `_Header` — "Beranda", ikon notifikasi, avatar 40 px.
2. `_GreetingSection` — label "DASHBOARD FINANSIAL", sapaan, dan `_DateChip` (bulan/tahun + ikon kalender).
3. `_MonthlySpendCard` — tinggi tetap 158, banner gradient/solid, nominal 32 pt, ikon `center_focus_strong` di pojok, `_GrowthBadge` (persentase naik/turun vs bulan lalu).
4. `_StatsRow` — dua `_StatCard`: jumlah struk dan rata-rata per hari. Memakai `Text.rich` untuk nilai + suffix.
5. `_CategoryCard` — maksimal 4 kategori teratas; setiap `_CategoryRow` berisi titik warna, nama, persen, nominal, dan bar `Stack` + `FractionallySizedBox` + penanda titik pada kategori pertama.
6. `_RecentTransactionsHeader` — "Lihat Semua" → tab Riwayat.
7. `_TransactionCard` — ikon kategori, nama toko, chip kategori, tanggal, nominal, badge "Valid". Jika kosong → `_NoTransactionsHint`.
8. `_ScanPromoCard` — CTA scan dengan ikon `document_scanner_outlined`.

Data berasal dari `ReceiptProvider` (`recentReceipts(3)`, `totalThisMonth`, `monthOverMonthChange`, `countThisMonth`, `averagePerDayThisMonth`, `spendingByCategory`).

### 7.3 Scan Struk (`scan_receipt.dart`)

- `_Viewfinder`: `AspectRatio(0.84)` dengan gradient `viewfinderGradient`, `ReceiptMock` di tengah (di-rotate -0.02 rad), empat `_corner` oranye, `_Pill` "AUTO", dua `_RoundIcon` (flash, grid), dan teks "Posisikan struk di dalam bingkai".
- `_TipCard` + `_Tip`: tiga tips OCR dengan bullet oranye.
- Aksi: `PrimaryButton` "Ambil Foto" (kamera) dan `SecondaryButton` "Pilih dari Galeri".
- `ImagePicker` dengan batas 2400 px untuk kamera; galeri tanpa downscale.
- Error permission ditangani lewat `ScaffoldMessenger.showSnackBar` dengan pesan yang membedakan akses ditolak vs error umum.

### 7.4 Proses OCR (`ocr_processing.dart`)

- `_Preview`: tinggi 220, `ClipRRect` radius 22, menampilkan `Image.file` asli atau `ReceiptMock`, garis scan oranye (`_ScanLine`) dengan glow, dan `_Tag` "Scan".
- Progress: label + persentase, lalu `LinearProgressIndicator` yang dianimasikan `TweenAnimationBuilder` 400 ms.
- Checklist `_StepRow` untuk 3 tahap: preprocessing, OCR, parsing. Status: aktif (spinner), selesai (centang hijau), belum (ikon abu).
- `_QualityNotice` muncul bila `ImageQualityReport.hasIssue` (blur, gelap, dll).
- `_RawTextCard` menampilkan maksimal 40 baris teks OCR.
- `_FailureView` — layar error penuh: lingkaran `redSoft`, ikon `error_outline`, pesan, hint, tombol "Coba Lagi" + "Ambil Ulang Foto".

### 7.5 Klasifikasi (`category_classification.dart`)

- `_StoreSummary` — kartu toko + tanggal + metode bayar.
- `_ModelCard` — status model: TF-IDF + Naive Bayes aktif, atau fallback lexicon. Berisi `_ModelStatus` bergaris status hijau/amber.
- `_ReviewNotice` — muncul jika ada item yang perlu dikonfirmasi.
- `_ClassifyingCard` — state loading model.
- `_PredictionCard` — per item: ikon kategori, nama, `CategoryChip`, label confidence, `LinearProgressIndicator` berwarna kategori, dan persentase.
- `_NoItemsCard` — bila OCR tidak menghasilkan item.

### 7.6 Review (`review_transaction.dart`)

- `_StoreCard` — toko, tanggal, ikon edit; mengetuk kartu membuka `_StoreEditorSheet`.
- `_ParseWarnings` — daftar peringatan parser dengan latar `amberSoft`.
- `_ItemCard` — ikon kategori, nama + ikon pensil, `qty × harga`, `CategoryChip` (ketuk = ubah kategori), nominal subtotal, dan ikon hapus. Mengetuk kartu membuka `_ItemEditorSheet` dalam mode edit.
- `_TotalCard` — subtotal item, "Diskon & biaya lain" (selisih total struk vs item), divider, total struk.
- `_OcrTextViewer` — `ExpansionTile` dengan tiga mode (`Teks`, `Koordinat`, `Baris parser`), `_ModeChip`, `SelectableText` monospace, dan `IconButton` salin ke clipboard + SnackBar.
- `_CategorySheet` — `showModalBottomSheet` berisi handle, judul, dan `ListTile` untuk 9 kategori.
- `_StoreEditorSheet` — bottom sheet "Edit Nama Toko" dengan satu `_SheetField` (teks terpilih otomatis), validasi nama tidak boleh kosong, dan tombol simpan. Nilai balik `String?`.
- `_ItemEditorSheet` — bottom sheet "Tambah Item" / "Edit Item": `_SheetField` nama & harga, `_QtyStepper`, pemilih kategori (membuka `_CategorySheet`), preview subtotal. Nilai balik `TransactionItem?`.
- `_EmptyItemsNotice` — bila tidak ada item terbaca.

Item yang ditambahkan manual tidak mengubah total struk: total cetak tetap otoritatif, selisihnya muncul di baris "Diskon & biaya lain".

### 7.7 Tersimpan (`transaction_saved.dart`)

Lingkaran `greenSoft` 108 px + ikon centang 62 px, judul "Transaksi Tersimpan", kartu ringkasan (toko, tanggal, jumlah item, metode, total), lalu `PrimaryButton` "Lihat Riwayat" dan `SecondaryButton` "Kembali ke Beranda".

### 7.8 Riwayat (`transaction_history.dart`)

- `_SearchField` — `TextField` tanpa border di dalam `Container` radius 15.
- `_FilterChip` — chip horizontal `ListView.separated`; "Semua" + kategori yang benar-benar ada di data.
- `_HistoryCard` — ikon kategori, toko, tanggal, chip kategori utama + `+n` jika multi-kategori, nominal, jumlah item.
- Tiga state: loading (`CircularProgressIndicator`), kosong total (`EmptyStateView` "Belum Ada Transaksi"), tidak ada hasil (`EmptyStateView` "Transaksi Tidak Ditemukan" + reset filter).

### 7.9 Detail (`transaction_detail.dart`)

- `_ReceiptHeader` — kartu gradient dengan ikon toko, nama, tanggal, "Total Pembayaran", dan dua `_Badge` (metode bayar, jumlah item).
- `_ItemRow` — daftar item dengan `IconBox`, nama, `qty × harga • kategori`, subtotal, divider antar-baris.
- `_SummaryCard` — subtotal, diskon, jumlah kategori, total.
- Aksi `CircleIconButton` delete/edit masih **no-op** (`onTap: () {}`).

### 7.10 Analisis (`analysis.dart`)

- `_PeriodSelector` — segmented control 3 pilihan ("Bulan Ini", "3 Bulan", "Tahun Ini") memakai `AnimatedContainer` 180 ms.
- `_TotalCard` — banner gradient, nominal, rentang tanggal, badge growth.
- `_StatsRow` + `_MiniStat` — total struk dan rata-rata per hari.
- `_CategoryCard` + `_CategoryBar` — bar distribusi per kategori.
- `_ModelEvaluationCard` — metrik nyata dari `ModelEvaluator`: akurasi, precision, recall, F1, macro F1, jumlah data uji dalam `_MetricTile` (grid 3 kolom), lalu `_ConfusionMatrixView` yang bisa di-scroll horizontal dengan `_MatrixCell` (heatmap 26×26, diagonal hijau).
- `_TrendCard` — `TrendLineChart` 6 bulan, atau teks kosong bila belum ada data.
- `_PredictionCta` — kartu ajakan ke layar prediksi.

### 7.11 Prediksi (`spending_prediction.dart`)

- `_InsufficientDataCard` — bila bulan berdata < `SpendingForecaster.minMonths`.
- `_PredictionCard` — banner nominal prediksi + badge perubahan vs bulan ini.
- `_ChartCard` — `TrendLineChart` aktual + prediksi, dengan `_LegendDot`.
- `_MetricsCard` — MAE, RMSE, R² dalam tiga kotak `FittedBox`.
- `_InsightCard` — narasi tren + kualitas fit berdasarkan R².

### 7.12 Pengaturan (`settings.dart`)

- `_ProfileCard` — avatar inisial "R", nama, email, chevron.
- `_SettingsGroup` — grup berjudul yang membungkus `_LinkTile` / `_SwitchTile` dengan `_Divider` bergeser 64 px.
- Switch "Mode Gelap" terhubung langsung ke `themeController`; switch "Notifikasi" hanya state lokal.
- Baris "Kelola Dataset" dan "Latih Ulang Model" menampilkan jumlah koreksi nyata dari `CorrectionTrainingService` dan membuka bottom sheet informasi (`_showInfoSheet`).
- Baris "Keluar" bergaya danger (merah) dan belum punya aksi.

### 7.13 Empty State (`empty_state.dart`)

`EmptyStateView` reusable: ilustrasi lingkaran `iconBox` 132 px + badge oranye, judul, pesan, dan `PrimaryButton` (`expanded: false`). `EmptyStateScreen` membungkusnya dengan `AppTopBar` + `FloatingNavBody` untuk pemakaian full-screen.

---

## 8. Widget Flutter/Material yang dipakai

### Layout

| Widget | Contoh pemakaian |
| --- | --- |
| `Scaffold` | Semua layar; diberi `ValueKey<AppPalette>` |
| `SafeArea` | Semua layar (`bottom: false` pada layar bertab) |
| `Column`, `Row` | Hampir semua susunan |
| `Stack`, `Positioned` | Bottom nav, viewfinder, banner, header detail |
| `Expanded`, `Flexible`, `Spacer` | Mengisi sisa ruang / mendorong elemen |
| `SizedBox` | Jarak dan ukuran tetap |
| `Container` | Kartu, banner, ikon, chip |
| `Padding`, `Center`, `Align` | Penempatan |
| `AspectRatio` | Bingkai kamera 0.84 |
| `FractionallySizedBox` | Bar kategori |
| `FittedBox` | Metrik prediksi, `ReceiptMock` |
| `ConstrainedBox` | Batas tinggi teks OCR (180) |
| `DecoratedBox` | Titik status pada badge |
| `ClipRRect` | Preview gambar, progress bar |
| `Opacity` | Placeholder struk, animasi logo |
| `Transform.rotate` | Kemiringan `ReceiptMock` |
| `Divider` | Pemisah baris dan ringkasan |
| `Image.file` | Preview hasil kamera |

### Scroll

| Widget | Contoh pemakaian |
| --- | --- |
| `SingleChildScrollView` | Hampir semua layar (satu kolom) |
| `ListView` | Daftar kategori di bottom sheet |
| `ListView.builder` | Riwayat transaksi |
| `ListView.separated` | Filter chip horizontal |

### Material & input

| Widget | Contoh pemakaian |
| --- | --- |
| `Material` | Tombol, kartu yang bisa diketuk, `ExpansionTile` |
| `InkWell` | Ripple pada tombol, kartu, nav item |
| `GestureDetector` | Segmented control, filter chip, tombol Scan, "Lihat Semua" |
| `IconButton` | Salin teks OCR |
| `TextField` | Pencarian riwayat |
| `Switch` | Mode gelap, notifikasi |
| `ListTile` | Bottom sheet kategori |
| `ExpansionTile` | Penampil teks OCR |
| `SnackBar` / `ScaffoldMessenger` | Error kamera, koreksi tersimpan, teks disalin |
| `showModalBottomSheet` | Pilih kategori, info dataset/retrain |

### Feedback

| Widget | Contoh pemakaian |
| --- | --- |
| `CircularProgressIndicator` | Splash, loading riwayat, klasifikasi, OCR |
| `LinearProgressIndicator` | Progress OCR, confidence item |
| `TweenAnimationBuilder` | Progress OCR, animasi logo splash |
| `AnimatedContainer` | Selector periode |

### Teks

| Widget | Contoh pemakaian |
| --- | --- |
| `Text` | Seluruh label |
| `Text.rich` / `TextSpan` | Wordmark splash, nilai + suffix pada stat card |
| `SelectableText` | Teks OCR mentah (bisa diseleksi) |

### Painting & navigasi

| Widget | Contoh pemakaian |
| --- | --- |
| `CustomPaint` + `CustomPainter` | `TrendLineChart` |
| `MaterialApp` | Root, `theme`/`darkTheme`/`themeMode` |
| `Navigator` (`push`, `pushReplacement`, `pop`, `maybePop`) | Alur scan dan perpindahan tab |
| `MaterialPageRoute` | Dasar `InstantPushPageRoute` |

---

## 9. State dan pola UI

### 9.1 Sumber state

- **Global**: `ReceiptProvider` (data struk + agregat), `themeController` (tema).
- **Lokal per layar**: `_period`, `_evaluation`, `_query`, `_filter`, `_busy`, `_stage`, `_predictions`, `_view`, `_notifications`, `_correctionCount`.

### 9.2 Pola loading

| Layar | Indikator |
| --- | --- |
| Riwayat | `CircularProgressIndicator` di tengah bila `isLoading && receipts.isEmpty` |
| Klasifikasi | `_ClassifyingCard` dengan spinner + teks |
| OCR | Progress bar + checklist bertahap |
| Evaluasi model (Analisis) | Spinner kecil + "Menghitung metrik…" |
| Splash | Spinner di footer |

### 9.3 Pola kosong

Selalu berupa kartu atau `EmptyStateView`, bukan layar kosong: "Belum ada transaksi tersimpan", "Belum ada pengeluaran bulan ini", "Belum ada item tersimpan pada periode ini", "Belum ada data pengeluaran untuk digambarkan", "Data Belum Cukup" untuk prediksi.

### 9.4 Pola error

- **Error fatal OCR** → `_FailureView` satu layar dengan tombol retry.
- **Error non-fatal** → `SnackBar` (kamera, clipboard).
- **Error data** → `ReceiptProvider.error` disimpan, daftar dikosongkan, UI menampilkan empty state.
- **Model gagal dimuat** → fallback classifier lexicon, ditandai kartu amber.

### 9.5 Warna status

- Hijau: valid, selesai, model aktif.
- Amber: peringatan, perlu review, kualitas gambar.
- Merah: error, aksi destruktif.
- Oranye: aksen brand, highlight, kategori pertama.

---

## 10. Alur pengguna utama

```
Splash (1,8 s)
   └─> Beranda
         ├─> [tab] Riwayat ──> Detail Transaksi
         ├─> [tab] Analisis ──> Prediksi Pengeluaran
         ├─> [tab] Pengaturan
         └─> Scan (tombol tengah / promo card)
               └─> Scan Struk (kamera / galeri)
                     └─> Proses OCR
                           ├─ gagal ──> OCR Gagal (retry / ambil ulang)
                           └─ sukses ─> Klasifikasi Kategori
                                          └─> Review Transaksi
                                                ├─ koreksi kategori (bottom sheet)
                                                └─> Simpan
                                                      └─> Transaksi Tersimpan
                                                            ├─> Riwayat
                                                            └─> Beranda
```

Perpindahan tab memakai `pushReplacement`; alur scan memakai `push`/`pushReplacement` dengan `InstantPushPageRoute`.

---

## 11. Responsivitas dan aksesibilitas

**Yang sudah ada**

- `SafeArea` dan `MediaQuery.padding.bottom` diperhitungkan pada bottom nav.
- `Expanded`/`Flexible` + `maxLines` + `TextOverflow.ellipsis` mencegah teks panjang merusak layout.
- `FittedBox` pada angka metrik yang bisa panjang.
- Tap target utama 40–56 px (tombol ikon 40, Scan 56, nav item selebar layar / 5).
- Kontras teks mengikuti palet light/dark yang sudah dipisah.

**Keterbatasan**

- Tidak ada breakpoint (`LayoutBuilder`/`MediaQuery.size`); di tablet layout akan melebar penuh.
- Tidak ada `Semantics`/`tooltip` pada tombol ikon (`CircleIconButton`, `_RoundIcon`).
- Belum diuji dengan text scale besar; beberapa kartu memakai tinggi tetap (mis. banner 158 px) sehingga berisiko overflow.
- Beberapa `GestureDetector` tidak punya state pressed/ripple (filter chip, segmented control, tombol Scan).
- String UI belum dilokalisasi; seluruh teks berbahasa Indonesia dan ditulis langsung di widget.

---

## 12. Catatan teknis dan inkonsistensi

Hal-hal yang perlu diketahui sebelum mengubah UI:

1. **Warna hardcoded di beberapa tempat.** `_RawTextCard` (OCR), `_StoreSummary` dan `_NoItemsCard` (Klasifikasi), serta `_EmptyItemsNotice` (Review) memakai `Colors.white` sehingga tetap putih di dark mode. Beberapa warna lain juga hardcoded: `#3A2A00` (teks di atas oranye), `#C7CBD6` (teks viewfinder), `#8A93A8` (ikon langkah OCR).
2. **`AppStatusBar` tidak menggambar apa pun.** Kelas ini hanya placeholder; status bar asli ditangani OS. Parameter `time` tidak pernah dipakai.
3. **Duplikasi widget.** `_CategoryCard`/`_CategoryRow`/`_CategoryBar` ada di Beranda dan Analisis dengan kode hampir identik; `_StatCard` dan `_MiniStat` juga mirip. Belum diekstrak ke `widgets/`.
4. **Aksi yang belum berfungsi:** delete/edit di Detail Transaksi, "Keluar", "Kategori & Label", "Tentang Aplikasi", "Bantuan & Dukungan", dan switch Notifikasi (hanya state lokal).
5. **Dependensi tidak terpakai:** `fl_chart`, `intl`, dan `cupertino_icons` ada di `pubspec.yaml` tetapi tidak diimpor di `lib/`.
6. **Route `'/scan'`** terdaftar di `main.dart` tetapi tidak pernah dipakai; semua scan lewat `openScan()`.
7. **Satu transisi tidak konsisten:** OCR → Klasifikasi memakai `MaterialPageRoute`, layar lain memakai `appRoute()`.
8. **Belum ada golden/screenshot test.** `test/widget_test.dart` memastikan splash berpindah ke Beranda dan layar-layar alur OCR bisa dirender tanpa exception; `test/theme_toggle_test.dart` menguji repaint saat tema berganti. Tidak ada pengujian visual per layar.
9. **Tema dark bukan hasil `ColorScheme`.** `ThemeData` hanya memakai `ColorScheme.fromSeed` untuk komponen Material bawaan (mis. `Switch`); mayoritas warna tetap dari `AppColors`, jadi komponen Material baru bisa tampil berbeda dari desain.
10. **`Text.rich` pada `_MiniStat`** (Analisis) tidak diberi `maxLines`/`overflow`, berbeda dari `_StatCard` (Beranda) yang sudah memakai `maxLines: 1` + ellipsis. Nominal besar berisiko meluber di kartu statistik Analisis.

---

## 13. Referensi cepat

| Kebutuhan | File |
| --- | --- |
| Menambah warna/token baru | `lib/theme/app_colors.dart` |
| Mengubah perilaku tema | `lib/theme/theme_controller.dart` |
| Widget yang dipakai lintas layar | `lib/widgets/app_widgets.dart` |
| Grafik tren | `lib/widgets/charts.dart` |
| Placeholder struk | `lib/widgets/receipt_mock.dart` |
| Pola tab & buka scan | `lib/navigation/app_nav.dart` |
| Animasi transisi halaman | `lib/navigation/app_route.dart` |
| Format Rupiah/tanggal | `lib/models/models.dart` |
| Daftar kategori & ikon | `lib/models/categories.dart`, `lib/models/models.dart` |
| Data untuk UI | `lib/providers/receipt_provider.dart` |
| Desain acuan light mode | `01 - Home Dashboard.png` |
